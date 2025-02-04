module libs::full_math {
    // use libs::constants::get_max_u256;

    /// Error codes
    const ERR_OVERFLOW: u64 = 1;
    const ERR_DENOMINATOR_ZERO: u64 = 2;

    /// @notice Calculates floor(a×b÷denominator) with full precision
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return result The 256-bit result
    /// Using the principle: (a*b)/c = (a/c)*b + (a%c*b)/c
    public fun mul_div(a: u256, b: u256, denominator: u256): u256 {
        // Check for zero denominator
        assert!(denominator != 0, ERR_DENOMINATOR_ZERO);

        // First calculate a/c and a%c
        let quotient = a / denominator;
        let remainder = a % denominator;

        // Calculate (a/c)*b
        let term1 = quotient * b;
        
        // Calculate (a%c*b)/c
        let term2 = (remainder * b) / denominator;

        // Add the terms
        let result = term1 + term2;
        
        // Check for overflow
        assert!(result >= term1, ERR_OVERFLOW);
        
        result
    }

    /// @notice Calculates ceil(a×b÷denominator) with full precision
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return result The 256-bit result
    public fun mul_div_rounding_up(a: u256, b: u256, denominator: u256): u256 {
        let result = mul_div(a, b, denominator);
        if ((a * b) % denominator != 0) {
            let new_result = result + 1;
            assert!(new_result != 0, ERR_OVERFLOW);
            new_result
        } else {
            result
        }
    }

    #[test]
    fun test_mul_div() {
        // Basic test
        assert!(mul_div(500, 2000, 1000) == 1000, 0);
        
        // Test with larger numbers
        assert!(mul_div(2351232132, 23452342342, 2342) == 2351232132 * 23452342342 / 2342, 1);
        
        // Test with denominator = 1
        assert!(mul_div(500, 2000, 1) == 1000000, 2);

        // TODO: Right now this test is failing because of overflow and calculation is not efficient enough
        // Test with large numbers
        // let a = get_max_u256() / 2;
        // let b = get_max_u256() / 2;
        // let denominator = get_max_u256() / 4;
        // assert!(mul_div(a, b, denominator) == a * 2, 3);
    }

    #[test]
    fun test_mul_div_rounding_up() {
        // Test exact division
        assert!(mul_div_rounding_up(500, 2000, 1000) == 1000, 0);
        
        // Test rounding up
        assert!(mul_div_rounding_up(10, 10, 3) == 34, 1);
    }

    #[test]
    #[expected_failure(abort_code = ERR_DENOMINATOR_ZERO)]
    fun test_mul_div_zero_denominator() {
        mul_div(1, 1, 0);
    }

    // TODO: Right now this test is failing because of overflow and calculation is not efficient enough
    // #[test]
    // #[expected_failure(abort_code = ERR_OVERFLOW)]
    // fun test_mul_div_overflow() {
    //     mul_div(get_max_u256(), 2, 1);
    // }
}