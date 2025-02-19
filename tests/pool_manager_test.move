#[test_only]
module move_v4::pool_manager_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use move_v4::pool_manager::{Self, PoolManager, PoolKey};
    use move_v4::usdc;
    use move_v4::eth;
    use libs::currency_delta::{Self};
    use libs::constants;
    use libs::tick_math;
    use std::debug::print;

    // Test coins with one-time witness
    public struct USDC has drop {}
    public struct ETH has drop {}


    const ADMIN: address = @0xABCD;
    const USER: address = @0x1234;

    // Use constants for price and ticks
    const LIQUIDITY_AMOUNT: u128 = 1000000;
    const SWAP_AMOUNT: u128 = 1000000;
    const DEFAULT_FEE_TIER: u32 = 3000;    // 0.3% fee tier
    const DEFAULT_TICK_SPACING: u32 = 2;


    fun setup_test_coins(scenario: &mut Scenario) {
        // Initialize currencies
        // we should init the currencies before minting the test coins
        // initialize and mint coin cannot happen at the same transaction
        ts::next_tx(scenario, ADMIN);
        {
            usdc::init_for_testing(ts::ctx(scenario));
            eth::init_for_testing(ts::ctx(scenario));

        };
        // Mint test coins
        ts::next_tx(scenario, ADMIN);
        {
            usdc::mint_test_coins(scenario);
            eth::mint_test_coins(scenario);
        };
    }


    fun test_scenario(): Scenario {
        ts::begin(ADMIN)
    }

    fun create_test_pool_key(): PoolKey {
        pool_manager::create_pool_key(
            @0x1, // USDC address
            @0x2, // ETH address
            DEFAULT_FEE_TIER,
            DEFAULT_TICK_SPACING
        )
    }

    #[test]
    fun test_pool_initialization() {
        let mut scenario = test_scenario();
        
        // Setup test environment
        setup_test_coins(&mut scenario);

        // Create pool manager
        ts::next_tx(&mut scenario, ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let mut pool_manager = pool_manager::new<usdc::USDC, eth::ETH>(ctx);
            
            // Initialize pool with initial sqrt price
            let key = create_test_pool_key();
            let initial_sqrt_price_x96 = constants::get_tick_0_sqrt_price();
            
            let tick = pool_manager::initialize(&mut pool_manager, key, initial_sqrt_price_x96, ctx);
            let (real_tick, real_tick_signal) = tick_math::convert_to_real_tick(tick);
            assert!(real_tick == constants::get_min_tick(), 0);
            assert!(real_tick_signal == true, 1);

            transfer::public_share_object(pool_manager);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_add_liquidity() {
        let mut scenario = test_scenario();
        
        // Setup test environment
        setup_test_coins(&mut scenario);

        // Create and initialize pool manager
        ts::next_tx(&mut scenario, ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let mut pool_manager = pool_manager::new<usdc::USDC, eth::ETH>(ctx);
            let key = create_test_pool_key();
            let initial_sqrt_price_x96 = constants::get_tick_0_sqrt_price();
            pool_manager::initialize(&mut pool_manager, key, initial_sqrt_price_x96, ctx);
            transfer::public_share_object(pool_manager);
        };

        // Get initial pool reserves
        ts::next_tx(&mut scenario, USER);
        {

            // later we will use mut scenario, once mut scenario is been used we cannot borrow scenario anymore, so before we use mut scenario, we should borrow scenario at first.
            let mut coin_usdc = ts::take_from_address<Coin<usdc::USDC>>(&scenario, USER);
            let mut coin_eth = ts::take_from_address<Coin<eth::ETH>>(&scenario, USER);
            

            // Add liquidity
            let mut pool_manager = ts::take_shared<PoolManager<usdc::USDC, eth::ETH>>(&scenario);
            let key = create_test_pool_key();
            let pool_id = pool_manager::key_to_id(&key);
            let reserves = pool_manager::get_pool_reserves(&pool_manager, pool_id);
            let initial_balance0 = pool_manager::get_reserve_balance0(reserves);
            let initial_balance1 = pool_manager::get_reserve_balance1(reserves);


            let ctx = ts::ctx(&mut scenario);
            
            let mut currency_delta = currency_delta::new(ctx);

            let tick_lower = tick_math::convert_from_real_tick(0, true);
            let tick_upper = tick_math::convert_from_real_tick(240, true);

            let (amount0, amount1, fees0, fees1) = pool_manager::modify_liquidity(
                &mut pool_manager,
                &key,
                tx_context::sender(ctx),
                tick_lower,
                tick_upper,
                LIQUIDITY_AMOUNT,
                true,
                b"test",
                &mut currency_delta
            );

            // Verify amounts
            assert!(amount0 > 0 || amount1 > 0, 0); // At least one amount should be positive
            assert!(fees0 == 0 && fees1 == 0, 0); // No fees for first position

            // Split the required amounts
            let mut split_coin_usdc = if (amount0 > 0) {
                coin::split(&mut coin_usdc, (amount0 as u64), ctx)
            } else {
                coin::zero<usdc::USDC>(ctx)
            };

            let mut split_coin_eth = if (amount1 > 0) {
                coin::split(&mut coin_eth, (amount1 as u64), ctx)
            } else {
                coin::zero<eth::ETH>(ctx)
            };

            // Settle tokens to pool
            pool_manager::settle(
                &mut pool_manager,
                &key,
                &mut split_coin_usdc,
                &mut split_coin_eth,
                &mut currency_delta,
                ctx
            );

            // Get final pool reserves and verify balances
            let reserves = pool_manager::get_pool_reserves(&pool_manager, pool_id);
            let final_balance0 = pool_manager::get_reserve_balance0(reserves);
            let final_balance1 = pool_manager::get_reserve_balance1(reserves);

            // Verify that the balance changes match the amounts
            assert!(final_balance0 == initial_balance0 + (amount0 as u64), 0);
            assert!(final_balance1 == initial_balance1 + (amount1 as u64), 0);

            // Return remaining coins to user
            transfer::public_transfer(coin_usdc, USER);
            transfer::public_transfer(coin_eth, USER);

            // Clean up split coins
            coin::burn_for_testing(split_coin_usdc);
            coin::burn_for_testing(split_coin_eth);

            ts::return_shared(pool_manager);
            currency_delta::destroy(currency_delta);
        };

        ts::end(scenario);
    }

    // #[test]
    // fun test_swap() {
    //     let mut scenario = test_scenario();
        
    //     // Setup test environment
    //     setup_test_coins(&mut scenario);

    //     // Create and initialize pool manager with liquidity
    //     ts::next_tx(&mut scenario, ADMIN);
    //     {
    //         let mut coin_usdc = ts::take_from_address<Coin<usdc::USDC>>(&scenario, USER);
    //         let mut coin_eth = ts::take_from_address<Coin<eth::ETH>>(&scenario, USER);

    //         let ctx = ts::ctx(&mut scenario);
    //         let mut pool_manager = pool_manager::new<usdc::USDC, eth::ETH>(ctx);
    //         let key = create_test_pool_key();
    //         let initial_sqrt_price_x96 = constants::get_tick_0_sqrt_price();
    //         pool_manager::initialize(&mut pool_manager, key, initial_sqrt_price_x96, ctx);

    //         let tick_lower = tick_math::convert_from_real_tick(0, true);
    //         let tick_upper = tick_math::convert_from_real_tick(240, true);

    //         // Add initial liquidity
    //         let mut currency_delta = currency_delta::new(ctx);
    //         let (amount0, amount1, fees0, fees1) =pool_manager::modify_liquidity(
    //             &mut pool_manager,
    //             &key,
    //             tx_context::sender(ctx),
    //             tick_lower,
    //             tick_upper,
    //             LIQUIDITY_AMOUNT,
    //             true,
    //             b"test",
    //             &mut currency_delta
    //         );


    //         // Split the required amounts
    //         let mut split_coin_usdc = if (amount0 > 0) {
    //             coin::split(&mut coin_usdc, (amount0 as u64), ctx)
    //         } else {
    //             coin::zero<usdc::USDC>(ctx)
    //         };

    //         let mut split_coin_eth = if (amount1 > 0) {
    //             coin::split(&mut coin_eth, (amount1 as u64), ctx)
    //         } else {
    //             coin::zero<eth::ETH>(ctx)
    //         };

    //         // Settle tokens to pool
    //         pool_manager::settle(
    //             &mut pool_manager,
    //             &key,
    //             &mut split_coin_usdc,
    //             &mut split_coin_eth,
    //             &mut currency_delta,
    //             ctx
    //         );

    //         // Return remaining coins to user
    //         transfer::public_transfer(coin_usdc, USER);
    //         transfer::public_transfer(coin_eth, USER);

    //         // Clean up split coins
    //         coin::burn_for_testing(split_coin_usdc);
    //         coin::burn_for_testing(split_coin_eth);

    //         transfer::public_share_object(pool_manager);
    //         currency_delta::destroy(currency_delta);
    //     };

    //     // Perform swap
    //     ts::next_tx(&mut scenario, USER);
    //     {
    //         let mut pool_manager = ts::take_shared<PoolManager<usdc::USDC, eth::ETH>>(&scenario);
    //         let ctx = ts::ctx(&mut scenario);
            
    //         let key = create_test_pool_key();
    //         let mut currency_delta = currency_delta::new(ctx);
    //         let limit_tick = tick_math::convert_from_real_tick(2, false);

    //         let (amount0, amount1, amount_calculated) = pool_manager::swap(
    //             &mut pool_manager,
    //             &key,
    //             10,
    //             false,      // exact input
    //             true,       // zero for one (USDC -> ETH)
    //             tick_math::get_sqrt_price_at_tick(limit_tick),
    //             ctx,
    //             &mut currency_delta
    //         );


    //         // Verify swap results
    //         assert!(amount0 > 0, 0);
    //         assert!(amount1 > 0, 0);

    //         ts::return_shared(pool_manager);
    //         currency_delta::destroy(currency_delta);
    //     };

    //     ts::end(scenario);
    // }

    #[test]
    fun test_take_and_settle() {
        let mut scenario = test_scenario();
        
        // Setup test environment
        setup_test_coins(&mut scenario);

        // Create and initialize pool manager
        ts::next_tx(&mut scenario, ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let mut pool_manager = pool_manager::new<usdc::USDC, eth::ETH>(ctx);
            let key = create_test_pool_key();
            let initial_sqrt_price_x96 = constants::get_tick_0_sqrt_price();
            pool_manager::initialize(&mut pool_manager, key, initial_sqrt_price_x96, ctx);
            transfer::public_share_object(pool_manager);
        };

        // Test take and settle
        ts::next_tx(&mut scenario, USER);
        {
            let mut pool_manager = ts::take_shared<PoolManager<usdc::USDC, eth::ETH>>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            
            let key = create_test_pool_key();
            let mut currency_delta = currency_delta::new(ctx);

            // Create test coins
            let mut coin_usdc = coin::mint_for_testing<usdc::USDC>(1000000, ctx);
            let mut coin_eth = coin::mint_for_testing<eth::ETH>(1000000, ctx);

            // Settle tokens to pool
            pool_manager::settle(
                &mut pool_manager,
                &key,
                &mut coin_usdc,
                &mut coin_eth,
                &mut currency_delta,
                ctx
            );

            // Take tokens from pool
            pool_manager::take(
                &mut pool_manager,
                &key,
                &mut currency_delta,
                ctx
            );

            // Clean up
            coin::burn_for_testing(coin_usdc);
            coin::burn_for_testing(coin_eth);

            ts::return_shared(pool_manager);
            currency_delta::destroy(currency_delta);
        };

        ts::end(scenario);
    }
}
