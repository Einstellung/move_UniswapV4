module libs::sqrt_price_math {
    use std::u256;
    use libs::constants;

    // Error codes
    const EINVALID_PRICE_OR_LIQUIDITY: u64 = 1;
    const EINVALID_PRICE: u64 = 2;
    const ENOT_ENOUGH_LIQUIDITY: u64 = 3;
    const EAMOUNT_OVERFLOW: u64 = 4;

    /// @notice Gets the next sqrt price given a delta of currency0
    /// @dev Always rounds up
    /// \delta x(amount0) = L * (sqrt(pb) - sqrt(pa)/sqrt(pb)*sqrt(pa))
    /// new_sqrtPX96(pb) = liquidity * sqrtPX96(pa) / (liquidity +- amount * sqrtPX96(pa)),
    public fun get_next_sqrt_price_from_amount0_rounding_up(
        sqrt_px96: u256,
        liquidity: u128,
        amount: u256,
        add: bool
    ): u256 {
        if (amount == 0) {
            return sqrt_px96
        };

        // sqrtPX86 multiply by 2^96 so liquidity also needs to multiply by 2^96
        let liquidity_96 = (liquidity as u256) << constants::get_resolution_96();

        if (add) {
            // Round-up ensures that when token0 is added, the new sqrt_price is computed to be at least high enough
            // to fully account for the token0 amount. In other words, even though adding token0 naturally tends to
            // push the price in one direction (e.g., a downward or "rightward" shift in the price curve), rounding up
            // nudges the computed sqrt_price slightly in the opposite direction. This conservative approach guarantees
            // that the price moves sufficiently to cover the intended token0 input.
            return u256::divide_and_round_up(liquidity_96 * sqrt_px96, liquidity_96 + amount * sqrt_px96)
        } else {
            let product = amount * sqrt_px96;
            assert!(
                liquidity_96 > product,
                ENOT_ENOUGH_LIQUIDITY
            );
            
            // Round-down ensures that when token1 is involved, the new sqrt_price is computed to be no higher than necessary,
            // preventing an overestimation of the price change. In effect, although subtracting token1 might tend to shift the
            // price in one direction (e.g., an upward or "leftward" shift), rounding down nudges the computed sqrt_price slightly
            // in the opposite direction. This conservative approach protects against moving the price too far, thereby avoiding
            // an excessive token1 change.
            let denominator = liquidity_96 - product;
            return (liquidity_96 * sqrt_px96) / denominator
        }
    }

    /// @notice Gets the next sqrt price given a delta of currency1
    /// @dev Always rounds down
    /// \delta y(amount1) = L * (sqrt(pb) - sqrt(pa))
    /// new_sqrtPX96(pb) = sqrtPX96(pa) +- ((amount / liquidity) * x96)
    public fun get_next_sqrt_price_from_amount1_rounding_down(
        sqrt_px96: u256,
        liquidity: u128,
        amount: u256,
        add: bool
    ): u256 {
        // Early check for amount overflow
        assert!(amount <= constants::get_max_u160(), EAMOUNT_OVERFLOW);

        if (add) {
            let quotient = (amount << constants::get_resolution_96()) / (liquidity as u256);
            return sqrt_px96 + quotient
        } else {
            let quotient = u256::divide_and_round_up(amount << constants::get_resolution_96(), (liquidity as u256));
            assert!(sqrt_px96 > quotient, ENOT_ENOUGH_LIQUIDITY);
            return sqrt_px96 - quotient
        }
    }

    /// @notice Gets the next sqrt price given an input amount of currency0 or currency1
    public fun get_next_sqrt_price_from_input(
        sqrt_px96: u256,
        liquidity: u128,
        amount_in: u256,
        zero_for_one: bool
    ): u256 {
        assert!(sqrt_px96 != 0 && liquidity != 0, EINVALID_PRICE_OR_LIQUIDITY);

        if (zero_for_one) {
            get_next_sqrt_price_from_amount0_rounding_up(sqrt_px96, liquidity, amount_in, true)
        } else {
            get_next_sqrt_price_from_amount1_rounding_down(sqrt_px96, liquidity, amount_in, true)
        }
    }

    /// @notice Gets the next sqrt price given an output amount of currency0 or currency1
    public fun get_next_sqrt_price_from_output(
        sqrt_px96: u256,
        liquidity: u128,
        amount_out: u256,
        zero_for_one: bool
    ): u256 {
        assert!(sqrt_px96 != 0 && liquidity != 0, EINVALID_PRICE_OR_LIQUIDITY);

        if (zero_for_one) {
            get_next_sqrt_price_from_amount1_rounding_down(sqrt_px96, liquidity, amount_out, false)
        } else {
            get_next_sqrt_price_from_amount0_rounding_up(sqrt_px96, liquidity, amount_out, false)
        }
    }

    /// @notice Gets the amount0 delta between two prices
    /// \delta x = liquidity * (sqrt(upper) - sqrt(lower)) / (sqrt(upper) * sqrt(lower))
    public fun get_amount0_delta(
        sqrt_price_ax96: u256,
        sqrt_price_bx96: u256,
        liquidity: u128,
        round_up: bool
    ): u256 {
        let (sqrt_price_ax96, sqrt_price_bx96) = if (sqrt_price_ax96 > sqrt_price_bx96) {
            (sqrt_price_bx96, sqrt_price_ax96)
        } else {
            (sqrt_price_ax96, sqrt_price_bx96)
        };

        assert!(sqrt_price_ax96 > 0, EINVALID_PRICE);

        let liquidity_96 = (liquidity as u256) << constants::get_resolution_96();
        let numerator2 = sqrt_price_bx96 - sqrt_price_ax96;

        if (round_up) {
            u256::divide_and_round_up(
                ((liquidity_96 * numerator2) / sqrt_price_bx96),
                sqrt_price_ax96
            )
        } else {
            (liquidity_96 * numerator2 / sqrt_price_bx96) / sqrt_price_ax96
        }
    }

    /// @notice Gets the amount1 delta between two prices
    /// \delta y(amount1) = L * (sqrt(pb) - sqrt(pa))
    public fun get_amount1_delta(
        sqrt_price_ax96: u256,
        sqrt_price_bx96: u256,
        liquidity: u128,
        round_up: bool
    ): u256 {
        let numerator = if (sqrt_price_ax96 >= sqrt_price_bx96) {
            sqrt_price_ax96 - sqrt_price_bx96
        } else {
            sqrt_price_bx96 - sqrt_price_ax96
        };

        let mut_amount = ((liquidity as u256) * numerator) / (constants::get_q96() as u256);
        if (round_up && (((liquidity as u256) * numerator) % (constants::get_q96() as u256)) > 0) {
            mut_amount + 1
        } else {
            mut_amount
        }
    }

    /// @notice Helper that gets signed currency0 delta
    public fun get_amount0_delta_signed(
        sqrt_price_ax96: u256,
        sqrt_price_bx96: u256,
        liquidity: u128,
        liquidity_is_positive: bool
    ): u256 {
        if (!liquidity_is_positive) {
            get_amount0_delta(sqrt_price_ax96, sqrt_price_bx96, liquidity, false)
        } else {
            get_amount0_delta(sqrt_price_ax96, sqrt_price_bx96, liquidity, true)
        }
    }

    /// @notice Helper that gets signed currency1 delta
    public fun get_amount1_delta_signed(
        sqrt_price_ax96: u256,
        sqrt_price_bx96: u256,
        liquidity: u128,
        liquidity_is_positive: bool
    ): u256 {
        if (!liquidity_is_positive) {
            get_amount1_delta(sqrt_price_ax96, sqrt_price_bx96, liquidity, false)
        } else {
            get_amount1_delta(sqrt_price_ax96, sqrt_price_bx96, liquidity, true)
        }
    }

    #[test]
    fun test_get_next_sqrt_price_basic() {
        let sqrt_price = 1 << 96; // Q96
        let liquidity = 1000000;
        let amount = 1000;
        
        // Test amount0 calculations
        let next_price = get_next_sqrt_price_from_amount0_rounding_up(sqrt_price, liquidity, amount, true);
        assert!(next_price < sqrt_price, 0);
        
        let next_price = get_next_sqrt_price_from_amount0_rounding_up(sqrt_price, liquidity, amount, false);
        assert!(next_price > sqrt_price, 1);
        
        // Test amount1 calculations
        let next_price = get_next_sqrt_price_from_amount1_rounding_down(sqrt_price, liquidity, amount, true);
        assert!(next_price > sqrt_price, 2);
        
        let next_price = get_next_sqrt_price_from_amount1_rounding_down(sqrt_price, liquidity, amount, false);
        assert!(next_price < sqrt_price, 3);
    }

    #[test]
    fun test_get_next_sqrt_price_edge_cases() {
        let sqrt_price = 1 << 96; // Q96
        let liquidity = 1000000;
        
        // Test with zero amount
        let next_price = get_next_sqrt_price_from_amount0_rounding_up(sqrt_price, liquidity, 0, true);
        assert!(next_price == sqrt_price, 0);
        
        let next_price = get_next_sqrt_price_from_amount1_rounding_down(sqrt_price, liquidity, 0, true);
        assert!(next_price == sqrt_price, 1);
        
        // Test with large amounts
        let large_amount = (constants::get_max_u128() as u256) - 1000;
        let next_price = get_next_sqrt_price_from_amount1_rounding_down(sqrt_price, liquidity, large_amount, true);
        assert!(next_price > sqrt_price, 2);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_PRICE_OR_LIQUIDITY)]
    fun test_get_next_sqrt_price_invalid_price() {
        let liquidity = 1000000;
        let amount = 1000;
        
        // Should fail with zero price
        get_next_sqrt_price_from_input(0, liquidity, amount, true);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_PRICE_OR_LIQUIDITY)]
    fun test_get_next_sqrt_price_invalid_liquidity() {
        let sqrt_price = 1 << 96;
        let amount = 1000;
        
        // Should fail with zero liquidity
        get_next_sqrt_price_from_input(sqrt_price, 0, amount, true);
    }

    #[test]
    fun test_get_amount_deltas() {
        let sqrt_price_a = 1 << 96; // Q96
        let sqrt_price_b = 2 << 96; // 2 * Q96
        let liquidity = 1000000;
        
        // Test amount0 delta
        let amount0 = get_amount0_delta(sqrt_price_a, sqrt_price_b, liquidity, true);
        let amount0_down = get_amount0_delta(sqrt_price_a, sqrt_price_b, liquidity, false);
        assert!(amount0 >= amount0_down, 0);
        
        // Test amount1 delta
        let amount1 = get_amount1_delta(sqrt_price_a, sqrt_price_b, liquidity, true);
        let amount1_down = get_amount1_delta(sqrt_price_a, sqrt_price_b, liquidity, false);
        assert!(amount1 >= amount1_down, 1);
        
        // Test price order doesn't matter
        let amount1_reverse = get_amount1_delta(sqrt_price_b, sqrt_price_a, liquidity, true);
        assert!(amount1 == amount1_reverse, 2);
    }

    #[test]
    fun test_signed_amount_deltas() {
        let sqrt_price_a = 1 << 96; // Q96
        let sqrt_price_b = 2 << 96; // 2 * Q96
        let liquidity = 1000000;
        
        // Test positive liquidity
        let amount0_positive = get_amount0_delta_signed(sqrt_price_a, sqrt_price_b, liquidity, true);
        let amount1_positive = get_amount1_delta_signed(sqrt_price_a, sqrt_price_b, liquidity, true);
        
        // Test negative liquidity
        let amount0_negative = get_amount0_delta_signed(sqrt_price_a, sqrt_price_b, liquidity, false);
        let amount1_negative = get_amount1_delta_signed(sqrt_price_a, sqrt_price_b, liquidity, false);
        
        // Verify that positive and negative results are consistent
        assert!(amount0_positive == get_amount0_delta(sqrt_price_a, sqrt_price_b, liquidity, true), 0);
        assert!(amount0_negative == get_amount0_delta(sqrt_price_a, sqrt_price_b, liquidity, false), 1);
        assert!(amount1_positive == get_amount1_delta(sqrt_price_a, sqrt_price_b, liquidity, true), 2);
        assert!(amount1_negative == get_amount1_delta(sqrt_price_a, sqrt_price_b, liquidity, false), 3);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_PRICE)]
    fun test_amount0_delta_invalid_price() {
        let sqrt_price_b = 2 << 96;
        let liquidity = 1000000;
        
        // Should fail with zero price
        get_amount0_delta(0, sqrt_price_b, liquidity, true);
    }
}