module libs::full_math {
    use libs::constants;
    use std::u256;
    use std::u16;
    use std::debug::print;

    /// Error codes
    const ERR_OVERFLOW: u64 = 1;
    const ERR_DENOMINATOR_ZERO: u64 = 2;

    /// Represents a 512-bit unsigned integer as two 256-bit parts
    public struct U512 has copy, drop {
        // Most significant 256 bits
        hi: u256,
        // Least significant 256 bits
        lo: u256
    }

    /// @notice Calculates floor(a×b÷denominator) with full precision
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return result The 256-bit result
    public fun mul_div(a: u256, b: u256, denominator: u256): u256 {
        assert!(denominator > 0, ERR_DENOMINATOR_ZERO);

        // Get the 512-bit product
        let prod = full_mul(a, b);
        // Make sure the result will fit in 256 bits
        assert!(prod.hi < denominator, ERR_OVERFLOW);

        // Compute the quotient
        if (prod.hi == 0) {
            // If high bits are zero, we can just divide the low bits
            prod.lo / denominator
        } else {
            // Full 512-bit division
            div_512_by_256(prod, denominator)
        }
    }

    /// @notice Calculates ceil(a×b÷denominator) with full precision
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return result The 256-bit result
    public fun mul_div_rounding_up(a: u256, b: u256, denominator: u256): u256 {
        let result = mul_div(a, b, denominator);
        
        // Check if we need to round up
        let remainder = mul_mod(a, b, denominator);
        if (remainder > 0) {
            assert!(result < constants::get_max_u256(), ERR_OVERFLOW);
            result + 1
        } else {
            result
        }
    }

    /// @notice Multiplies two 256-bit numbers to produce a 512-bit result
    fun full_mul(a: u256, b: u256): U512 {
        // Split a and b into 128-bit parts
        let base = 1u256 << 128; // 2^128
        let a_lo = u256::try_as_u128(a % base).extract();
        let a_hi = u256::try_as_u128(a / base).extract();
        let b_lo = u256::try_as_u128(b % base).extract();
        let b_hi = u256::try_as_u128(b / base).extract();

        // Compute partial products
        let p0 = (a_lo as u256) * (b_lo as u256);  // Low * Low
        let p1 = (a_lo as u256) * (b_hi as u256);  // Low * High  (need *2^128)
        let p2 = (a_hi as u256) * (b_lo as u256);  // High * Low  (need *2^128)
        let p3 = (a_hi as u256) * (b_hi as u256);  // High * High (need *2^256)

        // Split p1 and p2 into high and low parts to avoid overflow when adding
        let p1_lo = u256::try_as_u128(p1 % base).extract();
        let p1_hi = u256::try_as_u128(p1 / base).extract();
        let p2_lo = u256::try_as_u128(p2 % base).extract();
        let p2_hi = u256::try_as_u128(p2 / base).extract();

        // Add the low parts of middle terms
        let mut middle_lo = (p1_lo as u256) + (p2_lo as u256);
        let middle_lo_carry = if (middle_lo >= base) { 1u256 } else { 0u256 };
        middle_lo = middle_lo % base;

        // Add the high parts of middle terms and the carry
        let middle_hi = (p1_hi as u256) + (p2_hi as u256) + middle_lo_carry;

        // Split p0 into high and low parts
        let p0_lo = u256::try_as_u128(p0 % base).extract();
        let p0_hi = u256::try_as_u128(p0 / base).extract();

        // Combine low parts: p0_lo is the lowest 128 bits
        let low_lo = (p0_lo as u256);
        
        // Middle part: p0_hi + middle_lo
        let mut low_hi = (p0_hi as u256) + middle_lo;
        let low_hi_carry = if (low_hi >= base) { 1u256 } else { 0u256 };
        low_hi = low_hi % base;

        // Combine to get low 256 bits
        let low = low_lo + (low_hi << 128);

        // High 256 bits: p3 + middle_hi + low_hi_carry
        let high = p3 + middle_hi + low_hi_carry;

        U512 { hi: high, lo: low }
    }

    /// @notice Divides a 512-bit number by a 256-bit number using long division algorithm
    /// @dev Implements schoolbook long division algorithm, processing 128 bits at a time
    /// @param num The 512-bit dividend
    /// @param denominator The 256-bit divisor
    /// @return The quotient of the division
    /// X = num.hi * 2^256 + num.lo
    /// q = X / denominator = (num.hi * 2^256 + num.lo) / denominator
    fun div_512_by_256(num: U512, denominator: u256): u256 {
        // Early return if high bits are zero
        if (num.hi == 0) {
            return num.lo / denominator
        };
        
        // Check if denominator is zero
        assert!(denominator > 0, ERR_DENOMINATOR_ZERO);
        assert!(denominator < constants::get_max_u256(), ERR_OVERFLOW);
        assert!(num.hi * 2 >= 0, ERR_OVERFLOW);
        // if num.hi >= denominator, num.hi / denominator >= 1, *2^256 will cause overflow
        assert!(num.hi < denominator, ERR_OVERFLOW);
        
        // initialize remainder and quotient for num.hi
        let mut r = num.hi;
        print(&b"check reminder value".to_string());
        print(&r);
        let mut q = 0u256; // initialize as 0
        let mut i = 0u16;  // counter for bits

        while (i < 256) {
            r = r * 2;
            let shift_amount = 255u16 - i;
            let bit = (num.lo >> u16::try_as_u8(shift_amount).extract()) & 1u256;  // process from most significant bit to least
            r = r + bit;

            q = q << 1;
            // print(&r);
            if (r >= denominator) {
                print(&b"I am here!!".to_string());
                r = r - denominator;
                q = q + 1;
            };
            i = i + 1;
        };

        q
    }

    /// @notice Calculates (a * b) mod m
    /// This is needed because direct multiplication might overflow
    /// X = a * b = hi * 2^256 + lo
    /// X mod m = (hi * 2^256 + lo) mod m = ((hi mod m) * (2^256 mod m) + (lo mod m)) mod m
    /// 2^256 mod m = ((2^256-1) % m + 1) % m
    fun mul_mod(a: u256, b: u256, m: u256): u256 {
        let a_mod = a % m;
        let b_mod = b % m;

        let product = full_mul(a_mod, b_mod);
        let two256_mod_m = ((constants::get_max_u256() % m) + 1) % m;

        let hi_mod = product.hi % m;
        let lo_mod = product.lo % m;

        let result = ((hi_mod * two256_mod_m) % m + lo_mod) % m;
        result
    }

    #[test]
    fun test_mul_div() {
        // Basic test
        // assert!(mul_div(500, 2000, 1000) == 1000, 0);
        
        
        // // Test with denominator = 1
        // assert!(mul_div(500, 2000, 1) == 1000000, 1);

        // Test with large numbers
        let a = 1; // Large 128-bit number
        let b = constants::get_max_u256() - 1; // Large 128-bit number
        let denominator = constants::get_max_u256() - 1; // Same large number
        print(&333333333);
        print(&mul_div(a, b, denominator));
        assert!(mul_div(a, b, denominator) == a, 3); // Should equal a
    }

    #[test]
    fun test_mul_div_rounding_up() {
        // Test exact division
        assert!(mul_div_rounding_up(500, 2000, 1000) == 1000, 0);
        
        // Test rounding up
        assert!(mul_div_rounding_up(10, 10, 3) == 34, 1);

        // Test with large numbers
        let a = 8; // Large 128-bit number
        let b = constants::get_max_u256() - 1; // Large 128-bit number
        let denominator = constants::get_max_u256() - 1; // Same large number
        // print(&mul_div_rounding_up(a, b, denominator));
        assert!(mul_div_rounding_up(a, b, denominator) == a, 2); // Should equal a
    }

    #[test]
    #[expected_failure(abort_code = ERR_DENOMINATOR_ZERO)]
    fun test_mul_div_zero_denominator() {
        mul_div(1, 1, 0);
    }

    #[test]
    #[expected_failure(abort_code = ERR_OVERFLOW)]
    fun test_mul_div_overflow() {
        let max = constants::get_max_u256();
        mul_div(max, 2, 1);
    }

    #[test]
    fun test_div_512_by_256_analysis() {
        let num_hi = 115792089237316195423570985008687907853269403128392408138763188592324256989184u256;
        let denominator = constants::get_max_u256() - 1;
        
        // Test the initial comparison
        print(&b"Initial values:".to_string());
        print(&b"num_hi:".to_string());
        print(&num_hi);
        print(&b"denominator:".to_string());
        print(&denominator);
        print(&b"num_hi < denominator:".to_string());
        print(&(num_hi < denominator));
        
        // Test left shift behavior
        print(&b"Left shift test:".to_string());
        let mut shifted = num_hi;
        let mut i = 0;
        while (i < 5) {
            print(&shifted);
            shifted = shifted << 1;
            i = i + 1;
        };
    }
}