module libs::swap_math {
    use std::u256;
    use libs::sqrt_price_math;
    use libs::constants;

    // Error codes
    const EINVALID_SWAP_FEE: u64 = 1;
    // const EINVALID_AMOUNT: u64 = 2;

    /// @notice Computes the sqrt price target for the next swap step
    /// @param zero_for_one The direction of the swap, true for currency0 to currency1, false for currency1 to currency0
    /// @param sqrt_price_next_x96 The Q64.96 sqrt price for the next initialized tick
    /// @param sqrt_price_limit_x96 The Q64.96 sqrt price limit. If zero for one, the price cannot be less than this value
    /// after the swap. If one for zero, the price cannot be greater than this value after the swap
    /// @return sqrt_price_target_x96 The price target for the next swap step
    public fun get_sqrt_price_target(
        zero_for_one: bool,
        sqrt_price_next_x96: u256,
        sqrt_price_limit_x96: u256
    ): u256 {
        // zero for one will cause the price to move down(input currency0 to the pool and output currency1 from the pool)
        if (zero_for_one) {
            if (sqrt_price_next_x96 < sqrt_price_limit_x96) {
                sqrt_price_limit_x96
            } else {
                sqrt_price_next_x96
            }
            // one for zero will cause the price to move up(input currency1 to the pool and output currency0 from the pool)
        } else {
            if (sqrt_price_next_x96 > sqrt_price_limit_x96) {
                sqrt_price_limit_x96
            } else {
                sqrt_price_next_x96
            }
        }
    }

    /// @notice Computes the result of swapping some amount in, or amount out, given the parameters of the swap
    /// @dev If the swap's amountSpecified is positive, it represents the exact input amount for the swap.
    /// If negative, it represents the exact output amount requested.
    /// @param sqrt_price_current_x96 The current sqrt price of the pool
    /// @param sqrt_price_target_x96 The price that cannot be exceeded, from which the direction of the swap is inferred
    /// @param liquidity The usable liquidity
    /// @param amount_remaining How much input or output amount is remaining to be swapped in/out in current step
    /// @param exact_in Whether exact input (true) or exact output (false)
    /// @param fee_pips The fee taken from the input amount, expressed in hundredths of a bip
    /// @return (sqrt_price_next_x96, amount_in, amount_out, fee_amount) where:
    /// - sqrt_price_next_x96 The price after swapping the amount in/out, not to exceed the price target
    /// - amount_in The amount to be swapped in, of either currency0 or currency1, based on the direction of the swap
    /// - amount_out The amount to be received, of either currency0 or currency1, based on the direction of the swap
    /// - fee_amount The amount of input that will be taken as a fee
    public fun compute_swap_step(
        sqrt_price_current_x96: u256,
        sqrt_price_target_x96: u256,
        liquidity: u128,
        amount_remaining: u256,
        exact_in: bool,
        fee_pips: u32
    ): (u256, u256, u256, u256) {
        assert!(fee_pips <= constants::get_max_swap_fee(), EINVALID_SWAP_FEE);

        let zero_for_one = sqrt_price_current_x96 >= sqrt_price_target_x96;

        let sqrt_price_next_x96: u256;
        let mut amount_in: u256;
        let mut amount_out: u256;
        let fee_amount: u256;

        if (exact_in) {
            // after deducting the fee, the remaining amount is less than the original amount. amount_remaining_less_fee is the actual amount to be swapped
            let amount_remaining_less_fee = (amount_remaining * ((constants::get_max_swap_fee() - fee_pips) as u256)) / (constants::get_max_swap_fee() as u256);
            
            amount_in = if (zero_for_one) {
                sqrt_price_math::get_amount0_delta(
                    sqrt_price_target_x96,
                    sqrt_price_current_x96,
                    liquidity,
                    true
                )
            } else {
                sqrt_price_math::get_amount1_delta(
                    sqrt_price_current_x96,
                    sqrt_price_target_x96,
                    liquidity,
                    true
                )
            };

            // Whether the remaining amount is enough to push the price to the target
            // fee percentage is a ratio of fee_pips/MAX_SWAP_FEE for exmaple 3000 / 1e6 = 0.3%
            // fee_amount comes from A-a(A is total amount, a is effictive swap amount)
            if (amount_remaining_less_fee >= amount_in) {
                sqrt_price_next_x96 = sqrt_price_target_x96;
                fee_amount = if (fee_pips == constants::get_max_swap_fee()) {
                    amount_in
                } else {
                    // a + A*(fee_pips/MAX_SWAP_FEE) = A, A=a*(MAX_SWAP_FEE/(MAX_SWAP_FEE-fee_pips))
                    // fee_amount=A-a= a*(fee_pips/(MAX_SWAP_FEE-fee_pips))
                    let denominator = constants::get_max_swap_fee() - fee_pips;
                    u256::divide_and_round_up(amount_in * (fee_pips as u256), (denominator as u256))
                };
            } else {
                sqrt_price_next_x96 = sqrt_price_math::get_next_sqrt_price_from_input(
                    sqrt_price_current_x96,
                    liquidity,
                    amount_remaining_less_fee,
                    zero_for_one
                );
                amount_in = amount_remaining_less_fee;
                // we didn't reach the target, so take the remainder of the maximum input as fee
                fee_amount = amount_remaining - amount_remaining_less_fee;
            };

            amount_out = if (zero_for_one) {
                sqrt_price_math::get_amount1_delta(
                    sqrt_price_next_x96,
                    sqrt_price_current_x96,
                    liquidity,
                    false
                )
            } else {
                sqrt_price_math::get_amount0_delta(
                    sqrt_price_current_x96,
                    sqrt_price_next_x96,
                    liquidity,
                    false
                )
            };
        } 
        
        else {
            amount_out = if (zero_for_one) {
                sqrt_price_math::get_amount1_delta(
                    sqrt_price_target_x96,
                    sqrt_price_current_x96,
                    liquidity,
                    false
                )
            } else {
                sqrt_price_math::get_amount0_delta(
                    sqrt_price_current_x96,
                    sqrt_price_target_x96,
                    liquidity,
                    false
                )
            };

            if (amount_remaining >= amount_out) {
                sqrt_price_next_x96 = sqrt_price_target_x96;
            } else {
                sqrt_price_next_x96 = sqrt_price_math::get_next_sqrt_price_from_output(
                    sqrt_price_current_x96,
                    liquidity,
                    amount_remaining,
                    zero_for_one
                );
                amount_out = amount_remaining;
            };

            amount_in = if (zero_for_one) {
                sqrt_price_math::get_amount0_delta(
                    sqrt_price_next_x96,
                    sqrt_price_current_x96,
                    liquidity,
                    true
                )
            } else {
                sqrt_price_math::get_amount1_delta(
                    sqrt_price_current_x96,
                    sqrt_price_next_x96,
                    liquidity,
                    true
                )
            };

            // fee_pips cannot be MAX_SWAP_FEE for exact out
            assert!(fee_pips < constants::get_max_swap_fee(), EINVALID_SWAP_FEE);
            let denominator = constants::get_max_swap_fee() - fee_pips;
            fee_amount = u256::divide_and_round_up(amount_in * (fee_pips as u256), (denominator as u256));
        };

        (sqrt_price_next_x96, amount_in, amount_out, fee_amount)
    }

    #[test]
    fun test_get_sqrt_price_target() {
        let sqrt_price_next = 2000000 << 96;
        let sqrt_price_limit = 1000000 << 96;

        // Test zero_for_one = true
        let target = get_sqrt_price_target(true, sqrt_price_next, sqrt_price_limit);
        assert!(target == sqrt_price_next, 0);

        // Test zero_for_one = false
        let target = get_sqrt_price_target(false, sqrt_price_next, sqrt_price_limit);
        assert!(target == sqrt_price_limit, 1);
    }

    #[test]
    fun test_compute_swap_step_exact_in() {
        let sqrt_price_current = 1000000 << 96;
        let sqrt_price_target = 2000000 << 96;
        let liquidity = 1000000 << 20;
        let amount_remaining = 1000000 << 20;
        let fee_pips = 3000; // 0.3%

        let (_, amount_in, amount_out, fee_amount) = compute_swap_step(
            sqrt_price_current,
            sqrt_price_target,
            liquidity,
            amount_remaining,
            true, // exact input
            fee_pips
        );

        assert!(amount_in > 0, 1);
        assert!(amount_out > 0, 2);
        assert!(fee_amount > 0, 3);
    }

        #[test]
    fun test_compute_swap_step_exact_in_one_for_zero() {
        let sqrt_price_current = 2000000 << 96;
        let sqrt_price_target = 1000000 << 96;
        let liquidity = 1000000 << 20;
        let amount_remaining = 1000000 << 20;
        let fee_pips = 3000; // 0.3%

        let (_, amount_in, amount_out, fee_amount) = compute_swap_step(
            sqrt_price_current,
            sqrt_price_target,
            liquidity,
            amount_remaining,
            true, // exact input
            fee_pips
        );

        assert!(amount_in > 0, 1);
        assert!(amount_out > 0, 2);
        assert!(fee_amount > 0, 3);
    }

    #[test]
    fun test_compute_swap_step_exact_out() {

        let sqrt_price_current = 1000000 << 96;
        let sqrt_price_target = 2000000 << 96;
        let liquidity = 1000000 << 10;
        let amount_remaining = 1000000;
        let fee_pips = 3000; // 0.3%

        let (sqrt_price_next_x96, amount_in, amount_out, fee_amount) = compute_swap_step(
            sqrt_price_current,
            sqrt_price_target,
            liquidity,
            amount_remaining,
            false, // exact output
            fee_pips
        );

        assert!(sqrt_price_next_x96 > sqrt_price_current, 0);
        assert!(amount_in > 0, 1);
        assert!(amount_out > 0, 2);
        assert!(fee_amount > 0, 3);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_SWAP_FEE)]
    fun test_invalid_fee_pips() {
        let sqrt_price_current = 1000000 << 96;
        let sqrt_price_target = 2000000 << 96;
        let liquidity = 1000000;
        let amount_remaining = 1000000;
        let fee_pips = constants::get_max_swap_fee() + 1;

        compute_swap_step(
            sqrt_price_current,
            sqrt_price_target,
            liquidity,
            amount_remaining,
            true,
            fee_pips
        );
    }

    #[test]
    fun test_compute_swap_step_exact_in_one_for_zero_capped_at_price_target() {
        let price = 1 << 96;  // SQRT_PRICE_1_1
        let price_target = (101 * (1 << 96)) / 100;  // SQRT_PRICE_101_100
        let liquidity = 2000000000000000000;  // 2 ether
        let amount_remaining = 1000000000000000000;  // 1 ether
        let fee_pips = 600;  // 0.06%
        
        let (sqrtQ, amount_in, amount_out, fee_amount) = compute_swap_step(
            price,
            price_target,
            (liquidity as u128),
            amount_remaining,
            true,
            fee_pips
        );
        
        assert!(amount_in > 0, 0);
        assert!(amount_out > 0, 1);
        assert!(fee_amount > 0, 2);
        assert!(sqrtQ == price_target, 3);
    }

    #[test]
    fun test_compute_swap_step_exact_out_zero_for_one_capped_at_price_target() {
        let price = 1 << 96;  // SQRT_PRICE_1_1
        let price_target = (99 * (1 << 96)) / 100;  // SQRT_PRICE_99_100
        let liquidity = 2000000000000000000;  // 2 ether
        let amount_remaining = 1000000000000000000;  // 1 ether
        let fee_pips = 600;  // 0.06%
        
        let (sqrtQ, amount_in, amount_out, fee_amount) = compute_swap_step(
            price,
            price_target,
            (liquidity as u128),
            amount_remaining,
            false,
            fee_pips
        );
        
        assert!(amount_in > 0, 0);
        assert!(amount_out > 0, 1);
        assert!(fee_amount > 0, 2);
        assert!(sqrtQ == price_target, 3);
    }

    #[test]
    fun test_compute_swap_step_exact_in_fully_spent() {
        let price = 1 << 96;  // SQRT_PRICE_1_1
        let price_target = (1000 * (1 << 96)) / 100;  // SQRT_PRICE_1000_100
        let liquidity = 2000000000000000000;  // 2 ether
        let amount_remaining = 1000000000000000000;  // 1 ether
        let fee_pips = 600;  // 0.06%
        
        let (sqrtQ, amount_in, amount_out, fee_amount) = compute_swap_step(
            price,
            price_target,
            (liquidity as u128),
            amount_remaining,
            true,
            fee_pips
        );
        
        assert!(amount_in > 0, 0);
        assert!(amount_out > 0, 1);
        assert!(fee_amount > 0, 2);
        assert!(sqrtQ < price_target, 3);  // Didn't reach target
        assert!(amount_in + fee_amount == amount_remaining, 4);  // Full amount used
    }

    // TODO: price change more than 100 rates will cause error
    #[test]
    fun test_compute_swap_step_exact_out_fully_received() {
        let price = 1 << 96;  // SQRT_PRICE_1_1
        // let price_target = (10000 * (1 << 96)) / 100;  // SQRT_PRICE_10000_100
        let price_target = (10000 * (1 << 96)) / 1000;  // SQRT_PRICE_10000_100
        let liquidity = 2000000000000000000;  // 2 ether
        let amount_remaining = 1000000000000000000;  // 1 ether
        let fee_pips = 600;  // 0.06%
        
        let (sqrtQ, amount_in, amount_out, fee_amount) = compute_swap_step(
            price,
            price_target,
            (liquidity as u128),
            amount_remaining,
            false,
            fee_pips
        );
        
        assert!(amount_in > 0, 0);
        assert!(amount_out == amount_remaining, 1);  // Exact output achieved
        assert!(fee_amount > 0, 2);
        assert!(sqrtQ < price_target, 3);  // Didn't reach target
    }
}