module libs::position {
    use sui::hash::keccak256;
    use sui::address;
    use sui::bcs;
    use sui::table::{Self, Table};
    use libs::liquidity_math;
    use libs::constants;

    /// Position represents an owner address' liquidity between a lower and upper tick boundary
    public struct Position has store, copy, drop {
        // the amount of liquidity owned by this position
        liquidity: u128,
        // fee growth per unit of liquidity as of the last update to liquidity or fees owed
        fee_growth_inside_0_last_x128: u256,
        fee_growth_inside_1_last_x128: u256,
    }

    /// PositionManager stores all positions
    public struct PositionManager has store {
        positions: Table<vector<u8>, Position>
    }

    const CANNOT_UPDATE_EMPTY_POSITION: u64 = 1;

    /// Create a new PositionManager
    public fun new(ctx: &mut TxContext): PositionManager {
        PositionManager {
            positions: table::new(ctx)
        }
    }

    /// Returns the position key for a given owner and position boundaries
    public fun calculate_position_key(owner: address, tick_lower: u32, tick_upper: u32, salt: vector<u8>): vector<u8> {
        let mut key = vector::empty<u8>();
        vector::append(&mut key, address::to_bytes(owner));
        vector::append(&mut key, bcs::to_bytes(&tick_lower));
        vector::append(&mut key, bcs::to_bytes(&tick_upper));
        vector::append(&mut key, salt);
        keccak256(&key)
    }

    /// Get position information for a given owner and position boundaries
    public fun get(
        position_manager: &PositionManager,
        owner: address,
        tick_lower: u32,
        tick_upper: u32,
        salt: vector<u8>
    ): &Position {
        let position_key = calculate_position_key(owner, tick_lower, tick_upper, salt);
        table::borrow(&position_manager.positions, position_key)
    }

    /// Get mutable position information for a given owner and position boundaries
    public fun get_mut(
        position_manager: &mut PositionManager,
        owner: address,
        tick_lower: u32,
        tick_upper: u32,
        salt: vector<u8>
    ): &mut Position {
        let position_key = calculate_position_key(owner, tick_lower, tick_upper, salt);
        // check if the position exists
        if (!table::contains(&position_manager.positions, position_key)) {
            // create a new position
            table::add(&mut position_manager.positions, position_key, Position {
                liquidity: 0,
                fee_growth_inside_0_last_x128: 0,
                fee_growth_inside_1_last_x128: 0
            });
        };

        table::borrow_mut(&mut position_manager.positions, position_key)
    }

    /// Updates position state and returns fees owed
    /// fee_growth_inside_x128 use Q128 fixed point format, which means actuall fee*2^128, so when return fees, we need to divide by 2^128
    public fun update(
        position: &mut Position,
        abs_liquidity_delta: u128,
        liquidity_delta_is_positive: bool,
        fee_growth_inside_0_x128: u256,
        fee_growth_inside_1_x128: u256
    ): (u256, u256) {
        let liquidity = position.liquidity;

        if (abs_liquidity_delta == 0) {
            assert!(liquidity != 0, CANNOT_UPDATE_EMPTY_POSITION);
        } else {
            position.liquidity = liquidity_math::add_delta(liquidity, abs_liquidity_delta, !liquidity_delta_is_positive);
        };

        // calculate accumulated fees
        let fees_owed_0 = 
            (fee_growth_inside_0_x128 - position.fee_growth_inside_0_last_x128) * (liquidity as u256) / constants::get_q128();

        let fees_owed_1 = (fee_growth_inside_1_x128 - position.fee_growth_inside_1_last_x128) * (liquidity as u256) / constants::get_q128();

        // update the position
        position.fee_growth_inside_0_last_x128 = fee_growth_inside_0_x128;
        position.fee_growth_inside_1_last_x128 = fee_growth_inside_1_x128;

        (fees_owed_0, fees_owed_1)
    }

    #[test]
    fun test_calculate_position_key() {
        let owner = @0xABCD;
        let tick_lower = 10u32;
        let tick_upper = 20u32;
        let salt = x"1234";

        let key = calculate_position_key(owner, tick_lower, tick_upper, salt);
        
        // Verify the key is generated correctly by checking its components
        let mut expected_key = vector::empty<u8>();
        vector::append(&mut expected_key, address::to_bytes(owner));
        vector::append(&mut expected_key, bcs::to_bytes(&tick_lower));
        vector::append(&mut expected_key, bcs::to_bytes(&tick_upper));
        vector::append(&mut expected_key, salt);
        let expected_key = keccak256(&expected_key);

        assert!(key == expected_key, 0);
    }

    #[test]
    fun test_position_get() {
        use sui::test_scenario;

        let admin = @0xABCD;
        let mut scenario = test_scenario::begin(admin);
        let ctx = test_scenario::ctx(&mut scenario);
        
        // Create a new position manager
        let mut position_manager = new(ctx);
        let position = Position {
            liquidity: 1000,
            fee_growth_inside_0_last_x128: 0,
            fee_growth_inside_1_last_x128: 0
        };

        // Add position to the table
        let owner = @0xABCD;
        let tick_lower = 10u32;
        let tick_upper = 20u32;
        let salt = x"1234";
        let position_key = calculate_position_key(owner, tick_lower, tick_upper, salt);
        table::add(&mut position_manager.positions, position_key, position);

        // Test get function
        let stored_position = get(&position_manager, owner, tick_lower, tick_upper, salt);
        assert!(stored_position.liquidity == 1000, 0);
        assert!(stored_position.fee_growth_inside_0_last_x128 == 0, 1);
        assert!(stored_position.fee_growth_inside_1_last_x128 == 0, 2);

        // Clean up test objects
        let PositionManager { positions } = position_manager;
        table::drop(positions);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = CANNOT_UPDATE_EMPTY_POSITION)]
    fun test_update_empty_position() {
        let mut position = Position {
            liquidity: 0,
            fee_growth_inside_0_last_x128: 0,
            fee_growth_inside_1_last_x128: 0
        };

        update(
            &mut position,
            0,  // liquidity_delta = 0
            true,
            1000,
            2000
        );
    }

    #[test]
    fun test_update_with_liquidity_delta_positive() {
        let mut position = Position {
            liquidity: 1000,
            fee_growth_inside_0_last_x128: 0,
            fee_growth_inside_1_last_x128: 0
        };

        let liquidity_delta = 500u128;
        let fee_growth_inside_0_x128 = 1000 << 128;
        let fee_growth_inside_1_x128 = 2000 << 128;

        let (fees_0, fees_1) = update(
            &mut position,
            liquidity_delta,
            true,
            fee_growth_inside_0_x128,
            fee_growth_inside_1_x128
        );

        // Verify liquidity update
        assert!(position.liquidity == 1500, 0); // 1000 + 500

        // Verify fee growth updates
        assert!(position.fee_growth_inside_0_last_x128 == fee_growth_inside_0_x128, 1);
        assert!(position.fee_growth_inside_1_last_x128 == fee_growth_inside_1_x128, 2);

        // Verify fees calculation
        assert!(fees_0 > 0, 3);
        assert!(fees_1 > 0, 4);
    }

        #[test]
    fun test_update_with_liquidity_delta_negative() {
        let mut position = Position {
            liquidity: 1000,
            fee_growth_inside_0_last_x128: 0,
            fee_growth_inside_1_last_x128: 0
        };

        let liquidity_delta = 500u128;
        let fee_growth_inside_0_x128 = 1000 << 128;
        let fee_growth_inside_1_x128 = 2000 << 128;

        let (fees_0, fees_1) = update(
            &mut position,
            liquidity_delta,
            false,
            fee_growth_inside_0_x128,
            fee_growth_inside_1_x128
        );

        // Verify liquidity update
        assert!(position.liquidity == 500, 0); // 1000 - 500

        // Verify fee growth updates
        assert!(position.fee_growth_inside_0_last_x128 == fee_growth_inside_0_x128, 1);
        assert!(position.fee_growth_inside_1_last_x128 == fee_growth_inside_1_x128, 2);

        // Verify fees calculation
        assert!(fees_0 > 0, 3);
        assert!(fees_1 > 0, 4);
    }

    #[test_only]
    public fun destroy_test_position_manager(position_manager: PositionManager) {
        let PositionManager { positions } = position_manager;
        table::drop(positions);
    }
}
