#[test_only]
module libs::pool_tests {
    use libs::pool::Self;
    use libs::tick_math;
    use libs::constants;
    use sui::test_scenario;

    #[test]
    fun test_pool_initialize() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        let ctx = test_scenario::ctx(&mut scenario);

        let real_tick = 1000;
        let tick = tick_math::convert_from_real_tick(real_tick, true);

        // Create a new pool using pool module's functions
        let sqrt_price_x96 = tick_math::get_sqrt_price_at_tick(tick); // Some valid price
        let lp_fee = 3000; // 0.3%
        let pool = pool::create_test_pool(sqrt_price_x96, lp_fee, ctx);
        
        assert!(pool::get_sqrt_price_x96(&pool) == sqrt_price_x96, 0);
        assert!(pool::get_fee_protocol(&pool) == 0, 0);
        assert!(pool::get_tick(&pool) < constants::get_max_tick(), 0);
        assert!(pool::get_tick(&pool) > constants::get_min_tick(), 0);

        // Test case 2: Try to initialize again (should fail)
        // TODO: add this case ability
        // let sqrt_price_x96_2 = tick_math::get_sqrt_price_at_tick(2000);
        // let lp_fee_2 = 500;
        // let result = pool::initialize(&mut pool, sqrt_price_x96_2, lp_fee_2);
        // assert!(result == ERR_POOL_ALREADY_INITIALIZED, 0);

        // Clean up test objects
        pool::destroy_test_pool(pool);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_modify_liquidity_success() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        let ctx = test_scenario::ctx(&mut scenario);

        // Create and initialize pool
        let real_tick = 1000;
        let tick = tick_math::convert_from_real_tick(real_tick, true);
        let sqrt_price_x96 = tick_math::get_sqrt_price_at_tick(tick);
        let lp_fee = 3000;
        let mut pool = pool::create_test_pool(sqrt_price_x96, lp_fee, ctx);

        let tick_lower = tick_math::convert_from_real_tick(0, true);
        let tick_upper = tick_math::convert_from_real_tick(240, true);
        // Test case: Add liquidity with valid parameters
        let params = pool::create_test_modify_liquidity_params(
            @0x1,
            tick_lower,
            tick_upper,
            1000000,
            true,
            4,
            vector::empty()
        );

        let (amount0, amount1, fees0, fees1) = pool::modify_liquidity(&mut pool, &params);
        assert!(amount0 > 0 || amount1 > 0, 0); // At least one amount should be positive
        assert!(fees0 == 0 && fees1 == 0, 0); // No fees for first position

        // Clean up test objects
        pool::destroy_test_pool(pool);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure] // 这里的 abort_code 需要根据你的实际错误码来设置
    fun test_modify_liquidity_invalid_ticks() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        let ctx = test_scenario::ctx(&mut scenario);

        // Create and initialize pool
        let real_tick = 1000;
        let tick = tick_math::convert_from_real_tick(real_tick, true);
        let sqrt_price_x96 = tick_math::get_sqrt_price_at_tick(tick);
        let lp_fee = 3000;
        let mut pool = pool::create_test_pool(sqrt_price_x96, lp_fee, ctx);

        let tick_lower = tick_math::convert_from_real_tick(240, true);
        let tick_upper = tick_math::convert_from_real_tick(0, true);

        // Test case: Try to add liquidity with invalid ticks (should fail)
        let invalid_params = pool::create_test_modify_liquidity_params(
            @0x1,
            tick_lower,
            tick_upper, // Upper < Lower
            1000000,
            true,
            4,
            vector::empty()
        );

        // This should abort with the expected error code
        let (_amount0, _amount1, _fees0, _fees1) = pool::modify_liquidity(&mut pool, &invalid_params);

        // Clean up test objects (这里其实不会执行到，因为上面会 abort)
        pool::destroy_test_pool(pool);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_success() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        let ctx = test_scenario::ctx(&mut scenario);

        // Create and initialize pool
        let real_tick = 100; // current tick
        let tick = tick_math::convert_from_real_tick(real_tick, true);
        let sqrt_price_x96 = tick_math::get_sqrt_price_at_tick(tick);
        let lp_fee = 3000;
        let mut pool = pool::create_test_pool(sqrt_price_x96, lp_fee, ctx);
        let tick_lower = tick_math::convert_from_real_tick(10, true);
        let tick_upper = tick_math::convert_from_real_tick(240, true);

        // Add initial liquidity
        let liquidity_params = pool::create_test_modify_liquidity_params(
            @0x1,
            tick_lower,
            tick_upper,
            1000000,
            true,
            2,
            vector::empty()
        );

        let (_amount0, _amount1, _fees0, _fees1) = pool::modify_liquidity(&mut pool, &liquidity_params);

        ///////////////////////
        // Verify swap results: First swap(exact input, zero for one)
        ///////////////////////
        let limit_tick = tick_math::convert_from_real_tick(2, true);
        // Perform a valid swap
        let swap_params = pool::create_test_swap_params(
            10,
            false,
            2,
            true,
            tick_math::get_sqrt_price_at_tick(limit_tick),
            0
        );
        let (amount0, amount1, _, result) = pool::swap(&mut pool, &swap_params);

        if (swap_params.get_swap_params_exact_output()) {
            assert!(amount0 > 0, 0);
            assert!(amount1 == swap_params.get_swap_params_amount_specified(), 0);
        } else {
            assert!(amount0 == swap_params.get_swap_params_amount_specified(), 0);
            assert!(amount1 > 0, 0);
        };
        assert!(pool::get_swap_result_sqrt_price_x96(&result) >= pool::get_swap_params_sqrt_price_limit_x96(&swap_params), 0); // Price should respect limit
        assert!(pool::get_swap_result_sqrt_price_x96(&result) < sqrt_price_x96, 0); // price should be updated, new price should be lower than before price
        ///////////////////////

        ///////////////////////
        // Perform a valid swap: Second swap(exact output, zero for one)
        ///////////////////////
        let swap_params_2 = pool::create_test_swap_params(
            5,
            true,
            2,
            true,
            tick_math::get_sqrt_price_at_tick(limit_tick),
            0
        );
        let (amount_2_0, amount_2_1, _, result_2) = pool::swap(&mut pool, &swap_params_2);
        // Verify swap results
        if (swap_params_2.get_swap_params_exact_output()) {
            assert!(amount_2_0 > 0, 0);
            assert!(amount_2_1 == swap_params_2.get_swap_params_amount_specified(), 0);
        } else {
            assert!(amount_2_0 == swap_params_2.get_swap_params_amount_specified(), 0);
            assert!(amount_2_1 > 0, 0);
        };
        assert!(pool::get_swap_result_sqrt_price_x96(&result_2) >= pool::get_swap_params_sqrt_price_limit_x96(&swap_params_2), 0); // Price should respect limit
        assert!(pool::get_swap_result_sqrt_price_x96(&result_2) < pool::get_swap_result_sqrt_price_x96(&result), 0); // price should be updated, new price should be lower than before price


        ///////////////////////
        // Perform a valid swap: Third swap(exact output, one for zero)
        // one for zero will cause flip exact output direction
        ///////////////////////
        let limit_tick = tick_math::convert_from_real_tick(101, true);
        let swap_params_3 = pool::create_test_swap_params(
            10,
            true,
            2,
            false,
            tick_math::get_sqrt_price_at_tick(limit_tick),
            0
        );
        let (amount_3_0, amount_3_1, _, result_3) = pool::swap(&mut pool, &swap_params_3);
        // Verify swap results
        if (swap_params_3.get_swap_params_exact_output()) {
            assert!(amount_3_0 == swap_params_3.get_swap_params_amount_specified(), 0);
            assert!(amount_3_1 > 0, 0);
        } else {
            assert!(amount_3_0 > 0, 0);
            assert!(amount_3_1 == swap_params_3.get_swap_params_amount_specified(), 0);
        };
        assert!(pool::get_swap_result_sqrt_price_x96(&result_3) <= pool::get_swap_params_sqrt_price_limit_x96(&swap_params_3), 0); // Price should respect limit
        assert!(pool::get_swap_result_sqrt_price_x96(&result_3) > pool::get_swap_result_sqrt_price_x96(&result_2), 0); // price should be updated, new price should be upper than before price
        ///////////////////////
        

        ///////////////////////
        // Perform a valid swap: Third swap(exact input, one for zero)
        // one for zero will cause flip exact input direction
        ///////////////////////
        let limit_tick = tick_math::convert_from_real_tick(101, true);
        let swap_params_4 = pool::create_test_swap_params(
            10,
            false,
            2,
            false,
            tick_math::get_sqrt_price_at_tick(limit_tick),
            0
        );
        let (amount_4_0, amount_4_1, _, result_4) = pool::swap(&mut pool, &swap_params_4);
        // Verify swap results
        if (swap_params_4.get_swap_params_exact_output()) {
            assert!(amount_4_0 == swap_params_4.get_swap_params_amount_specified(), 0);
            assert!(amount_4_1 > 0, 0);
        } else {
            assert!(amount_4_0 > 0, 0);
            assert!(amount_4_1 == swap_params_4.get_swap_params_amount_specified(), 0);
        };
        assert!(pool::get_swap_result_sqrt_price_x96(&result_4) <= pool::get_swap_params_sqrt_price_limit_x96(&swap_params_4), 0); // Price should respect limit
        assert!(pool::get_swap_result_sqrt_price_x96(&result_4) > pool::get_swap_result_sqrt_price_x96(&result_3), 0); // price should be updated, new price should be upper than before price
        ///////////////////////

        // Clean up test objects
        pool::destroy_test_pool(pool);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_tick_spacing_to_max_liquidity_per_tick() {
        // Test with different tick spacings
        let tick_spacing_1 = 1;
        let max_liquidity_1 = pool::tick_spacing_to_max_liquidity_per_tick(tick_spacing_1);
        assert!(max_liquidity_1 > 0, 0);

        let tick_spacing_60 = 60;
        let max_liquidity_60 = pool::tick_spacing_to_max_liquidity_per_tick(tick_spacing_60);
        assert!(max_liquidity_60 > max_liquidity_1, 0); // Larger spacing should allow more liquidity per tick
    }
} 