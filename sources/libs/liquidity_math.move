module libs::liquidity_math {
    use libs::constants::get_max_u128;

    /// @notice Add a signed liquidity delta to liquidity and revert if it overflows or underflows
    /// @param x The liquidity before change
    /// @param y The delta by which liquidity should be changed
    /// @param is_negative Whether the delta is negative
    /// @return The liquidity after change
    /// Unlike Solidity, Move have a built-in way to handle overflow and underflow. So their is no need to use assert to check by yourself.
    public fun add_delta(x: u128, y: u128, is_negative: bool): u128 {
        if (!is_negative) {
            // If y is positive, we need to check for overflow
            // assert!(x <= get_max_u128() - y, ERR_OVERFLOW);
            x + y
        } else {
            // If y is negative, we need to handle underflow
            // assert!(x >= y, ERR_UNDERFLOW);
            x - y
        }
    }

    #[test]
    fun test_add_delta() {
        // Test positive delta
        assert!(add_delta(100, 50, false) == 150, 0);
        
        // Test negative delta
        assert!(add_delta(100, 30, true) == 70, 1);
        
        // Test zero delta
        assert!(add_delta(100, 0, false) == 100, 2);
    }

    #[test]
    #[expected_failure]
    fun test_add_delta_overflow() {
        add_delta(get_max_u128(), 1, false);
    }

    #[test]
    #[expected_failure]
    fun test_add_delta_underflow() {
        add_delta(10, 11, true);
    }
}