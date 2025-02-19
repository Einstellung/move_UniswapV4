module move_v4::pool_manager {
    use sui::table::{Self, Table};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::hash;
    use sui::bcs;
    use sui::address;
    use libs::pool::{Self, Pool};
    use libs::constants;
    use libs::currency_delta::{Self, CurrencyDelta};
    use sui::balance::{Self, Balance};

    /// Errors
    const EINVALID_TOKEN_ORDER: u64 = 1;
    const ETICK_SPACING_TOO_LARGE: u64 = 2;
    const ETICK_SPACING_TOO_SMALL: u64 = 3;
    const EPOOL_ALREADY_EXISTS: u64 = 4;
    const EPOOL_NOT_FOUND: u64 = 5;
    const EUNAUTHORIZED: u64 = 6;

    /// Represents a unique identifier for a pool
    public struct PoolId has store, copy, drop {
        id: vector<u8>  // This will store the keccak256 hash
    }

    /// Key for a specific pool, containing all the parameters that make it unique
    public struct PoolKey has store, copy, drop {
        token0: address,
        token1: address,
        fee: u32,
        tick_spacing: u32,
    }

    /// Stores the token reserves for a pool
    public struct PoolReserves<phantom T0, phantom T1> has store {
        token0: Balance<T0>,
        token1: Balance<T1>
    }

    /// The main pool manager object that holds all pools
    public struct PoolManager<phantom T0, phantom T1> has key, store {
        id: UID,
        /// Maps PoolId to Pool
        pools: Table<PoolId, Pool>,
        /// Maps PoolId to token reserves
        token_reserves: Table<PoolId, PoolReserves<T0, T1>>,
        /// Protocol fee configuration
        protocol_fee_controller: address,
    }

    /// Events
    public struct InitializeEvent has copy, drop {
        pool_id: PoolId,
        token0: address,
        token1: address,
        fee: u32,
        tick_spacing: u32,
        sqrt_price_x96: u256,
        tick: u32
    }

    public struct ModifyLiquidityEvent has copy, drop {
        pool_id: PoolId,
        owner: address,
        tick_lower: u32,
        tick_upper: u32,
        liquidity_delta: u128,
        liquidity_delta_is_positive: bool,
        salt: vector<u8>
    }

    public struct SwapEvent has copy, drop {
        pool_id: PoolId,
        sender: address,
        amount0: u128,
        amount1: u128,
        sqrt_price_x96: u256,
        liquidity: u128,
        tick: u32,
        fee: u32
    }

    public struct ProtocolFeeUpdateEvent has copy, drop {
        pool_id: PoolId,
        new_protocol_fee: u8
    }

    /// Create a new pool manager
    public fun new<T0, T1>(ctx: &mut TxContext): PoolManager<T0, T1> {
        PoolManager {
            id: object::new(ctx),
            pools: table::new(ctx),
            token_reserves: table::new(ctx),
            protocol_fee_controller: tx_context::sender(ctx)
        }
    }

    /// Convert a PoolKey to a PoolId
    public fun key_to_id(key: &PoolKey): PoolId {
        // Serialize the PoolKey into bytes
        let mut bytes = vector::empty();
        
        // Append all fields in order
        vector::append(&mut bytes, address::to_bytes(key.token0));
        vector::append(&mut bytes, address::to_bytes(key.token1));
        vector::append(&mut bytes, bcs::to_bytes(&key.fee));
        vector::append(&mut bytes, bcs::to_bytes(&key.tick_spacing));

        // Create hash
        PoolId {
            id: hash::keccak256(&bytes)
        }
    }

    /// Initialize a new pool
    public fun initialize<T0, T1>(
        pool_manager: &mut PoolManager<T0, T1>,
        key: PoolKey,
        sqrt_price_x96: u256,
        ctx: &mut TxContext
    ): u32 {
        // Validate tick spacing
        assert!(key.tick_spacing <= constants::get_max_tick_spacing(), ETICK_SPACING_TOO_LARGE);
        assert!(key.tick_spacing >= constants::get_min_tick_spacing(), ETICK_SPACING_TOO_SMALL);

        // Validate token order, the reason for require order is to avoid establish two pools with same coins pare like ETH/USDC and USDC/ETH
        assert!(address::to_u256(key.token0) < address::to_u256(key.token1), EINVALID_TOKEN_ORDER);

        let pool_id = key_to_id(&key);
        assert!(!table::contains(&pool_manager.pools, pool_id), EPOOL_ALREADY_EXISTS);

        // Create and initialize the pool
        // TODO: I should remove create_test_pool and use create_pool instead
        let pool = pool::create_test_pool(sqrt_price_x96, key.fee, ctx);
        let tick = pool::get_tick(&pool);

        // Store the new pool
        table::add(&mut pool_manager.pools, pool_id, pool);

        // Initialize token reserves for the pool
        let reserves = PoolReserves {
            token0: balance::zero(),
            token1: balance::zero()
        };
        table::add(&mut pool_manager.token_reserves, pool_id, reserves);

        // Emit initialize event
        event::emit(InitializeEvent {
            pool_id,
            token0: key.token0,
            token1: key.token1,
            fee: key.fee,
            tick_spacing: key.tick_spacing,
            sqrt_price_x96,
            tick
        });

        tick
    }

    /// Modify liquidity in a pool
    public fun modify_liquidity<T0, T1>(
        pool_manager: &mut PoolManager<T0, T1>,
        key: &PoolKey,
        owner: address,
        tick_lower: u32,
        tick_upper: u32,
        liquidity_delta: u128,
        liquidity_delta_is_positive: bool,
        salt: vector<u8>,
        currency_delta: &mut CurrencyDelta
    ): (u128, u128, u128, u128) {
        let pool_id = key_to_id(key);
        assert!(table::contains(&pool_manager.pools, pool_id), EPOOL_NOT_FOUND);

        let pool = table::borrow_mut(&mut pool_manager.pools, pool_id);
        
        // TODO: I should remove create_test_modify_liquidity_params and use create_modify_liquidity_params instead
        let params = pool::create_test_modify_liquidity_params(
            owner,
            tick_lower,
            tick_upper,
            liquidity_delta,
            liquidity_delta_is_positive,
            key.tick_spacing,
            salt
        );

        let (amount0, amount1, fees0, fees1) = pool::modify_liquidity(pool, &params);

        // Emit modify liquidity event
        event::emit(ModifyLiquidityEvent {
            pool_id,
            owner,
            tick_lower,
            tick_upper,
            liquidity_delta,
            liquidity_delta_is_positive,
            salt
        });

        // stand from the pool's perspective, if the liquidity_delta_is_positive, it means we will add amounts to the pool, otherwise we will take amounts from the pool
        let amount_direction = if (liquidity_delta_is_positive) {
            true
        } else {
            false
        };

        account_pool_balance_delta(currency_delta, key.token0, amount0, amount_direction, owner);
        account_pool_balance_delta(currency_delta, key.token1, amount1, amount_direction, owner);

        // TODO: In the future, I can use liquidity_delta_is_positive to know whether take amount from the pool or add amount to the pool
        // If take from the pool I should add principle amount and the fee amount
        (amount0, amount1, fees0, fees1)
    }

    /// Perform a swap in the pool
    public fun swap<T0, T1>(
        pool_manager: &mut PoolManager<T0, T1>,
        key: &PoolKey,
        amount_specified: u128,
        exact_output: bool,
        zero_for_one: bool,
        sqrt_price_limit_x96: u256,
        ctx: &mut TxContext,
        currency_delta: &mut CurrencyDelta
    ): (u128, u128, u256) {
        let pool_id = key_to_id(key);
        assert!(table::contains(&pool_manager.pools, pool_id), EPOOL_NOT_FOUND);

        let pool = table::borrow_mut(&mut pool_manager.pools, pool_id);
        
        let params = pool::create_test_swap_params(
            amount_specified,
            exact_output,
            key.tick_spacing,
            zero_for_one,
            sqrt_price_limit_x96,
            0 // No LP fee override
        );

        let (amount0, amount1, amount_calculated, result) = pool::swap(pool, &params);

        let sender = tx_context::sender(ctx);

        // Emit swap event
        event::emit(SwapEvent {
            pool_id,
            sender: sender,
            amount0,
            amount1,
            sqrt_price_x96: pool::get_swap_result_sqrt_price_x96(&result),
            liquidity: pool::get_swap_result_liquidity(&result),
            tick: pool::get_swap_result_tick(&result),
            fee: key.fee
        });

        account_pool_balance_delta(currency_delta, key.token0, amount0, zero_for_one, sender);
        account_pool_balance_delta(currency_delta, key.token1, amount1, !zero_for_one, sender);

        (amount0, amount1, amount_calculated)
    }

    /// Account for balance changes in the pool
    /// @param currency_delta The currency delta tracker
    /// @param key The pool key containing token addresses
    /// @param amount The amount to account for
    /// @param amount_is_positive Whether the amount is being added (true) or removed (false)
    /// @param target The address to account the delta for
    fun account_pool_balance_delta(
        currency_delta: &mut CurrencyDelta,
        currency_address: address,
        amount: u128,
        amount_is_positive: bool,
        target: address
    ) {
        if (amount == 0) return;

        currency_delta::apply_delta(
                currency_delta,
                currency_address,
                target,
                amount,
                amount_is_positive
            );
    }

    /// Set protocol fee for a pool
    public fun set_protocol_fee<T0, T1>(
        pool_manager: &mut PoolManager<T0, T1>,
        key: &PoolKey,
        new_protocol_fee: u8,
        ctx: &mut TxContext
    ) {
        // Only protocol fee controller can update fees
        assert!(tx_context::sender(ctx) == pool_manager.protocol_fee_controller, EUNAUTHORIZED);
        
        let pool_id = key_to_id(key);
        assert!(table::contains(&pool_manager.pools, pool_id), EPOOL_NOT_FOUND);
        
        let pool = table::borrow_mut(&mut pool_manager.pools, pool_id);
        
        // Update protocol fee
        pool::set_protocol_fee(pool, new_protocol_fee);

        // Emit protocol fee update event
        event::emit(ProtocolFeeUpdateEvent {
            pool_id,
            new_protocol_fee
        });
    }

    /// Update protocol fee controller
    public fun set_protocol_fee_controller<T0, T1>(
        pool_manager: &mut PoolManager<T0, T1>,
        new_controller: address,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == pool_manager.protocol_fee_controller, EUNAUTHORIZED);
        pool_manager.protocol_fee_controller = new_controller;
    }

    /// Get protocol fee controller
    public fun get_protocol_fee_controller<T0, T1>(pool_manager: &PoolManager<T0, T1>   ): address {
        pool_manager.protocol_fee_controller
    }

    /// Get pool by id
    public fun get_pool<T0, T1>(pool_manager: &PoolManager<T0, T1>, pool_id: PoolId): &Pool {
        assert!(table::contains(&pool_manager.pools, pool_id), EPOOL_NOT_FOUND);
        table::borrow(&pool_manager.pools, pool_id)
    }

    /// Get mutable pool by id
    public fun get_pool_mut<T0, T1>(pool_manager: &mut PoolManager<T0, T1>, pool_id: PoolId): &mut Pool {
        assert!(table::contains(&pool_manager.pools, pool_id), EPOOL_NOT_FOUND);
        table::borrow_mut(&mut pool_manager.pools, pool_id)
    }

    /// Take tokens from the pool based on the currency delta
    public fun take<T0, T1>(
        pool_manager: &mut PoolManager<T0, T1>,
        key: &PoolKey,
        currency_delta: &mut CurrencyDelta,
        ctx: &mut TxContext
    ) {
        let pool_id = key_to_id(key);
        assert!(table::contains(&pool_manager.pools, pool_id), EPOOL_NOT_FOUND);
        
        let sender = tx_context::sender(ctx);
        
        // Get deltas for both tokens
        let (amount0, amount0_is_positive) = currency_delta::get_delta(currency_delta, key.token0, sender);
        let (amount1, amount1_is_positive) = currency_delta::get_delta(currency_delta, key.token1, sender);

        // Get pool reserves
        let reserves = table::borrow_mut(&mut pool_manager.token_reserves, pool_id);
        
        if (!amount0_is_positive) {
            let balance0 = balance::split(&mut reserves.token0, (amount0 as u64));
            let refund0 = coin::from_balance(balance0, ctx);
            transfer::public_transfer(refund0, sender);
            // update currency delta
            currency_delta::apply_delta(
                currency_delta,
                key.token0,
                sender,
                amount0,
                true
            );
        };
        
        if (!amount1_is_positive) {
            let balance1 = balance::split(&mut reserves.token1, (amount1 as u64));
            let refund1 = coin::from_balance(balance1, ctx);
            transfer::public_transfer(refund1, sender);
            // update currency delta
            currency_delta::apply_delta(
                currency_delta,
                key.token1,
                sender,
                amount1,
                true
            );
        };
    }

    // settle token to the pool
    public fun settle<T0, T1>(
        pool_manager: &mut PoolManager<T0, T1>,
        key: &PoolKey,
        coin0: &mut Coin<T0>,
        coin1: &mut Coin<T1>,
        currency_delta: &mut CurrencyDelta,
        ctx: &mut TxContext
    ) {
        let pool_id = key_to_id(key);
        assert!(table::contains(&pool_manager.pools, pool_id), EPOOL_NOT_FOUND);
        
        let sender = tx_context::sender(ctx);
        
        // Get deltas for both tokens
        let (amount0, amount0_is_positive) = currency_delta::get_delta(currency_delta, key.token0, sender);
        let (amount1, amount1_is_positive) = currency_delta::get_delta(currency_delta, key.token1, sender);

        // Get pool reserves
        let reserves = table::borrow_mut(&mut pool_manager.token_reserves, pool_id);
        
        if (amount0_is_positive) {
            let deposit0 = coin::split(coin0, (amount0 as u64), ctx);
            let balance0 = coin::into_balance(deposit0);
            balance::join(&mut reserves.token0, balance0);
            // update currency delta
            currency_delta::apply_delta(
                currency_delta,
                key.token0,
                sender,
                amount0,
                false
            );
        };
        
        if (amount1_is_positive) {
            let deposit1 = coin::split(coin1, (amount1 as u64), ctx);
            let balance1 = coin::into_balance(deposit1);
            balance::join(&mut reserves.token1, balance1);
            // update currency delta
            currency_delta::apply_delta(
                currency_delta,
                key.token1,
                sender,
                amount1,
                false
            );
        };
    }

    /// Create a new pool key
    public fun create_pool_key(
        token0: address,
        token1: address,
        fee: u32,
        tick_spacing: u32
    ): PoolKey {
        PoolKey {
            token0,
            token1,
            fee,
            tick_spacing
        }
    }

    /// Get pool reserves by pool id
    public fun get_pool_reserves<T0, T1>(pool_manager: &PoolManager<T0, T1>, pool_id: PoolId): &PoolReserves<T0, T1> {
        assert!(table::contains(&pool_manager.token_reserves, pool_id), EPOOL_NOT_FOUND);
        table::borrow(&pool_manager.token_reserves, pool_id)
    }

    /// Get balance of token0 from pool reserves
    public fun get_reserve_balance0<T0, T1>(reserves: &PoolReserves<T0, T1>): u64 {
        balance::value(&reserves.token0)
    }

    /// Get balance of token1 from pool reserves
    public fun get_reserve_balance1<T0, T1>(reserves: &PoolReserves<T0, T1>): u64 {
        balance::value(&reserves.token1)
    }
}
