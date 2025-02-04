module libs::tick_math {
    use libs::bit_math;
    use libs::constants::get_max_u256;

    /// Error codes
    const ERR_INVALID_TICK: u64 = 1;
    const ERR_INVALID_SQRT_PRICE: u64 = 2;

    /// Constants for tick range
    const TICK_OFFSET: u32 = 887272;  // This is the offset we use to simulate negative ticks
    const MIN_TICK: u32 = 0;     // Represents -887272 in original Solidity code
    const MAX_TICK: u32 = 1774544;  // Represents 887272 in original Solidity code

    /// Constants for tick spacing
    const MIN_TICK_SPACING: u32 = 1;
    const MAX_TICK_SPACING: u32 = 32767;

    /// Constants for sqrt price range
    const MIN_SQRT_PRICE: u256 = 4295128739;
    const TICK_0_SQRT_PRICE: u256 = 79228162514264337593543950336;
    const MAX_SQRT_PRICE: u256 = 1461446703485210103287273052203988822378723970342;

    // Constants for price calculation
    const PRICE_CONST_1: u256 = 0xfffcb933bd6fad37aa2d162d1a594001u256;
    const PRICE_CONST_2: u256 = 0xfff97272373d413259a46990580e213au256;
    const PRICE_CONST_3: u256 = 0xfff2e50f5f656932ef12357cf3c7fdccu256;
    const PRICE_CONST_4: u256 = 0xffe5caca7e10e4e61c3624eaa0941cd0u256;
    const PRICE_CONST_5: u256 = 0xffcb9843d60f6159c9db58835c926644u256;
    const PRICE_CONST_6: u256 = 0xff973b41fa98c081472e6896dfb254c0u256;
    const PRICE_CONST_7: u256 = 0xff2ea16466c96a3843ec78b326b52861u256;
    const PRICE_CONST_8: u256 = 0xfe5dee046a99a2a811c461f1969c3053u256;
    const PRICE_CONST_9: u256 = 0xfcbe86c7900a88aedcffc83b479aa3a4u256;
    const PRICE_CONST_10: u256 = 0xf987a7253ac413176f2b074cf7815e54u256;
    const PRICE_CONST_11: u256 = 0xf3392b0822b70005940c7a398e4b70f3u256;
    const PRICE_CONST_12: u256 = 0xe7159475a2c29b7443b29c7fa6e889d9u256;
    const PRICE_CONST_13: u256 = 0xd097f3bdfd2022b8845ad8f792aa5825u256;
    const PRICE_CONST_14: u256 = 0xa9f746462d870fdf8a65dc1f90e061e5u256;
    const PRICE_CONST_15: u256 = 0x70d869a156d2a1b890bb3df62baf32f7u256;
    const PRICE_CONST_16: u256 = 0x31be135f97d08fd981231505542fcfa6u256;
    const PRICE_CONST_17: u256 = 0x9aa508b5b7a84e1c677de54f3e99bc9u256;
    const PRICE_CONST_18: u256 = 0x5d6af8dedb81196699c329225ee604u256;
    const PRICE_CONST_19: u256 = 0x2216e584f5fa1ea926041bedfe98u256;
    const PRICE_CONST_20: u256 = 0x48a170391f7dc42444e8fa2u256;

    /// @notice Given a tickSpacing, compute the maximum usable tick
    public(package) fun max_usable_tick(tick_spacing: u32): u32 {
        (MAX_TICK / tick_spacing) * tick_spacing
    }

    /// @notice Given a tickSpacing, compute the minimum usable tick
    public(package) fun min_usable_tick(tick_spacing: u32): u32 {
        (MIN_TICK / tick_spacing) * tick_spacing
    }

    /// Convert an offset tick to a real tick
    /// @param tick The offset tick to convert
    /// @return (abs_real_tick, real_tick_signal) where:
    /// - abs_real_tick is the absolute value of the real tick
    /// - real_tick_signal is true for positive tick, false for negative tick
    public(package) fun convert_to_real_tick(tick: u32): (u32, bool) {
        if (tick >= TICK_OFFSET) {
            (tick - TICK_OFFSET, true)  // Positive tick
        } else {
            (TICK_OFFSET - tick, false)  // Negative tick
        }
    }

    /// Convert a real tick to an offset tick (add offset)
    public(package) fun convert_from_real_tick(abs_real_tick: u32, real_tick_signal: bool): u32 {
        if (real_tick_signal) {
            abs_real_tick + TICK_OFFSET
        } else {
            TICK_OFFSET - abs_real_tick
        }
    }

    /// @notice Calculates sqrt(1.0001^tick) * 2^96
    /// @dev Throws if tick > max tick
    /// @param tick The input tick for the above formula
    /// @return sqrtPriceX96 A Fixed point Q64.96 number representing the sqrt of the price
    public fun get_sqrt_price_at_tick(tick: u32): u256 {
        assert!(tick <= MAX_TICK, ERR_INVALID_TICK);
        
        // Convert the offset tick to real tick for calculation
        let (abs_real_tick, real_tick_signal) = convert_to_real_tick(tick);

        // Use bit operations to calculate price, calculate sqrt(1.0001^abs_real_tick) first
        // use Binary Exponentiation method. https://oi-wiki.org/math/binary-exponentiation/
        let mut price = if (abs_real_tick & 0x1 != 0) {
            PRICE_CONST_1
        } else {
            1u256 << 128
        };
        // from math viewpoint, the price currenty is 2^128 / sqrt(1.0001^abs_real_tick)
        // use this form can avoid overflow problem
        if (abs_real_tick & 0x2 != 0) price = ((price * PRICE_CONST_2) >> 128);
        if (abs_real_tick & 0x4 != 0) price = ((price * PRICE_CONST_3) >> 128);
        if (abs_real_tick & 0x8 != 0) price = ((price * PRICE_CONST_4) >> 128);
        if (abs_real_tick & 0x10 != 0) price = ((price * PRICE_CONST_5) >> 128);
        if (abs_real_tick & 0x20 != 0) price = ((price * PRICE_CONST_6) >> 128);
        if (abs_real_tick & 0x40 != 0) price = ((price * PRICE_CONST_7) >> 128);
        if (abs_real_tick & 0x80 != 0) price = ((price * PRICE_CONST_8) >> 128);
        if (abs_real_tick & 0x100 != 0) price = ((price * PRICE_CONST_9) >> 128);
        if (abs_real_tick & 0x200 != 0) price = ((price * PRICE_CONST_10) >> 128);
        if (abs_real_tick & 0x400 != 0) price = ((price * PRICE_CONST_11) >> 128);
        if (abs_real_tick & 0x800 != 0) price = ((price * PRICE_CONST_12) >> 128);
        if (abs_real_tick & 0x1000 != 0) price = ((price * PRICE_CONST_13) >> 128);
        if (abs_real_tick & 0x2000 != 0) price = ((price * PRICE_CONST_14) >> 128);
        if (abs_real_tick & 0x4000 != 0) price = ((price * PRICE_CONST_15) >> 128);
        if (abs_real_tick & 0x8000 != 0) price = ((price * PRICE_CONST_16) >> 128);
        if (abs_real_tick & 0x10000 != 0) price = ((price * PRICE_CONST_17) >> 128);
        if (abs_real_tick & 0x20000 != 0) price = ((price * PRICE_CONST_18) >> 128);
        if (abs_real_tick & 0x40000 != 0) price = ((price * PRICE_CONST_19) >> 128);
        if (abs_real_tick & 0x80000 != 0) price = ((price * PRICE_CONST_20) >> 128);

        // If the tick is positive, we need to invert the price
        // after revert the positive tick is 2^128 * sqrt(1.0001^abs_real_tick)
        let final_price = if (real_tick_signal) {
            get_max_u256() / price
        } else {
            price
        };

        // We want to divide by 1<<32 rounding up, so we add 2^32 - 1 before shifting
        // Rounding up may cause the final value to be slightly larger than the theoretical value, but this design ensures that near boundary values, the truncation of the decimal part does not lead to an underestimation of the price. This, in turn, prevents off-by-one errors when converting in the reverse direction (from price to tick). As long as both forward and reverse conversions adopt the same rounding strategy, the overall mapping remains monotonic, consistent, and secure, thereby enhancing the stability and robustness of the system in real-world financial operations
        // If truncation (rounding down) is applied directly, the calculated price may be slightly lower than the theoretical value. As a result, when converting back to a tick, the derived tick value might be lower than expected, leading the system to mistakenly determine that the price has crossed a certain boundary. In real-world applications, this could lead to the following issues:
        // •	Boundary misjudgment: For example, near a tick boundary, the system may incorrectly assume that the next liquidity range has been reached due to rounding errors caused by truncation. This could result in an off-by-one tick calculation, mistakenly placing the price in the next liquidity range.
        // •	Liquidity management issues: This off-by-one error might cause the system to assume that a liquidity range has been exhausted when, in reality, it still has available liquidity. This misjudgment could trigger unnecessary adjustments or incorrect capital allocations.
        // finally we get Q64.96 format for price
        ((final_price + ((1u256 << 32) - 1)) >> 32)
    }

    /// @notice Calculates the greatest tick value such that getSqrtPriceAtTick(tick) <= sqrtPriceX96: sqrt(1.0001^tick) * 2^96
    /// @param sqrtPriceX96 The sqrt price for which to compute the tick as a Q64.96
    /// @return tick The greatest tick for which the getSqrtPriceAtTick(tick) is less than or equal to the input sqrtPriceX96
    public fun get_tick_at_sqrt_price(sqrtPriceX96: u256): u32 {
        // Validate the price is within bounds
        assert!(
            sqrtPriceX96 >= MIN_SQRT_PRICE && sqrtPriceX96 < MAX_SQRT_PRICE,
            ERR_INVALID_SQRT_PRICE
        );

        // Determine the sign of the real tick.
        // If sqrtPriceX96 is greater than price_at_zero, the tick is positive
        // Otherwise, the tick is negative
        let real_tick_signal = sqrtPriceX96 >= TICK_0_SQRT_PRICE;

        // orignal sqrtPriceX96 is Q64.96 format (u160), we need to enhace it's precision (especially the decimal part). Now, we let 64 bit for integer part, and 96+32 bit for decimal part
        let price = sqrtPriceX96 << 32;
        // price = 2^E * f (E is integer(msb), f is mantissa around [1, 2))
        // log_2(price) = E + log_2(f), f from [1, 2) so log_2(f) from [0, 1)
        // price / 2^128 = 2^(E-128) * f, so log_2(price/2^128) = E-128 + log_2(f)
        // log_2 is integer part = E-128 (this may be negative so we use abs_log_2)
        // r is f*2^127 because we want to enhance the precision of the mantissa part to [2^127, 2^128)

        let mut r = price;
        let msb = bit_math::get_most_significant_bit(r); // price is around 2^mbs

        let mut abs_log_2: u256;
        if (msb >= 128) {
            // price / 2^(mbs-127) = 2^mbs * f / 2^(mbs-127) = f * 2^127
            r = price >> (msb - 127);
            // (E-128) * 2^64
            abs_log_2 = ((msb as u256) - 128) << 64;
        } else {
            // 2^E * f * 2^(127-msb) = 2^127 * f
            r = price << (127 - msb);
            // (128-E) * 2^64
            abs_log_2 = ((128 - msb) as u256) << 64;
        };

        // 2^127 * f^2
        r = (r * r) >> 127;
        // f^2 / 2
        //  f \in [1,2) so f^2 \in [1,4), for normalization, we need to use f^2 / 2
        // if f^2 >= 2 indicates f >= sqrt(2), indicates log_2(f) >= 0.5, the toppest decimal of log_2(f) is 1
        // x = 0.b_1b_2b_3...  b_1 represent 1/2 b_2 represent 1/4...
        let mut f = r >> 128;
        // f^2/2 \in [0.5, 2) u256 just can store integer part and decimal part will be round down.
        // we store the toppest decimal of log_2(f) in abs_log_2
        abs_log_2 = abs_log_2 | (f << 63);
        // let r always in range of [2^127, 2^128)
        r = r >> (f as u8);

        r = (r * r) >> 127;
        // new f^4, log_2(f) >= 1/4 ?
        f = r >> 128;
        abs_log_2 = abs_log_2 | (f << 62);
        r = r >> (f as u8);

        r = (r * r) >> 127;
        f = r >> 128;
        abs_log_2 = abs_log_2 | (f << 61);
        r = r >> (f as u8);

        r = (r * r) >> 127;
        f = r >> 128;
        abs_log_2 = abs_log_2 | (f << 60);
        r = r >> (f as u8);

        r = (r * r) >> 127;
        f = r >> 128;
        abs_log_2 = abs_log_2 | (f << 59);
        r = r >> (f as u8);

        r = (r * r) >> 127;
        f = r >> 128;
        abs_log_2 = abs_log_2 | (f << 58);
        r = r >> (f as u8);

        r = (r * r) >> 127;
        f = r >> 128;
        abs_log_2 = abs_log_2 | (f << 57);
        r = r >> (f as u8);

        r = (r * r) >> 127;
        f = r >> 128;
        abs_log_2 = abs_log_2 | (f << 56);
        r = r >> (f as u8);

        r = (r * r) >> 127;
        f = r >> 128;
        abs_log_2 = abs_log_2 | (f << 55);
        r = r >> (f as u8);

        r = (r * r) >> 127;
        f = r >> 128;
        abs_log_2 = abs_log_2 | (f << 54);
        r = r >> (f as u8);

        r = (r * r) >> 127;
        f = r >> 128;
        abs_log_2 = abs_log_2 | (f << 53);
        r = r >> (f as u8);

        r = (r * r) >> 127;
        f = r >> 128;
        abs_log_2 = abs_log_2 | (f << 52);
        r = r >> (f as u8);

        r = (r * r) >> 127;
        f = r >> 128;
        abs_log_2 = abs_log_2 | (f << 51);
        r = r >> (f as u8);

        // 14 decimal places of precision are already sufficient
        r = (r * r) >> 127;
        f = r >> 128;
        abs_log_2 = abs_log_2 | (f << 50);

        // tick = log_2(price) / log_2(1.0001), factor(2) / log_2(1.0001) = 255738958999603826347141
        let log_sqrt10001_abs = abs_log_2 * 255738958999603826347141; // Q22.128 number

        // magic1: represents the upper bound of the maximum possible error in logarithmic calculations, used to downward adjust log_sqrt10001 to compute a conservative lower bound tickLow
        // magic2: represents the error range on the other end, used to upward adjust log_sqrt10001 to compute a conservative upper bound tickHigh
        // tickLow = (log_sqrt10001 - magic1) / 2^128
        // tickHigh = (log_sqrt10001 + magic2) / 2^128
        let magic1 = 3402992956809132418596140100660247210u256;
        let magic2 = 291339464771989622907027621153398088495u256;

        let abs_tick_low: u32;
        let abs_tick_high: u32;

        if (real_tick_signal) {
            abs_tick_high = ((log_sqrt10001_abs + magic2) >> 128).try_as_u32().extract();
            abs_tick_low = if (log_sqrt10001_abs >= magic1) {
                ((log_sqrt10001_abs - magic1) >> 128).try_as_u32().extract()
            } else {
                ((magic1 - log_sqrt10001_abs) >> 128).try_as_u32().extract()
            };
        } else {
            abs_tick_high = if (log_sqrt10001_abs >= magic2) {
                ((log_sqrt10001_abs - magic2) >> 128).try_as_u32().extract()
            } else {
                ((magic2 - log_sqrt10001_abs) >> 128).try_as_u32().extract()
            };
            abs_tick_low = ((log_sqrt10001_abs + magic1) >> 128).try_as_u32().extract();
        };

        let abs_choose_tick = if (get_sqrt_price_at_tick(abs_tick_high) <= sqrtPriceX96) {
            abs_tick_high
        } else {
            abs_tick_low
        };
        
        let tick = if (real_tick_signal) {
            abs_choose_tick + TICK_OFFSET
        } else {
            TICK_OFFSET - abs_choose_tick
        };
        tick
    }

    /// Helper function to check if a tick is valid for a given tick spacing
    public fun is_valid_tick(tick: u32, tick_spacing: u32): bool {
        let in_range = tick >= MIN_TICK && tick <= MAX_TICK;
        in_range && (tick % tick_spacing == 0)
    }

    #[test]
    fun test_get_sqrt_price_at_tick() {
        // Test minimum tick (equivalent to -887272)
        let price = get_sqrt_price_at_tick(MIN_TICK);
        assert!(price == MIN_SQRT_PRICE, 0);

        // Test maximum tick (equivalent to 887272)
        let price = get_sqrt_price_at_tick(MAX_TICK);
        assert!(price == MAX_SQRT_PRICE, 1);

        // Test zero tick (equivalent to original tick 0)
        let price = get_sqrt_price_at_tick(TICK_OFFSET);
        assert!(price > MIN_SQRT_PRICE && price < MAX_SQRT_PRICE, 2);

        // Test negative tick
        let price = get_sqrt_price_at_tick(TICK_OFFSET - 100);
        let price2 = get_sqrt_price_at_tick(TICK_OFFSET + 100);
        assert!(price < price2, 3); // Negative tick should give smaller price
    }

    #[test]
    #[expected_failure(abort_code = ERR_INVALID_TICK)]
    fun test_get_sqrt_price_at_tick_invalid() {
        get_sqrt_price_at_tick(MAX_TICK + 1);
    }

    #[test]
    fun test_get_tick_at_sqrt_price() {
        // Test minimum price
        let tick = get_tick_at_sqrt_price(MIN_SQRT_PRICE);
        assert!(tick == MIN_TICK, 0);

        // // Test maximum price
        let tick = get_tick_at_sqrt_price(MAX_SQRT_PRICE - 1);
        assert!(tick == MAX_TICK, 1);

        // Test middle price (around tick 0)
        let tick = get_tick_at_sqrt_price(TICK_0_SQRT_PRICE);
        assert!(tick == TICK_OFFSET, 2);
    }

    #[test]
    #[expected_failure(abort_code = ERR_INVALID_SQRT_PRICE)]
    fun test_get_tick_at_sqrt_price_invalid() {
        get_tick_at_sqrt_price(MAX_SQRT_PRICE);
    }

    #[test]
    fun test_is_valid_tick() {
        assert!(is_valid_tick(0, 1), 0);
        assert!(is_valid_tick(MAX_TICK, 1), 1);
        assert!(!is_valid_tick(MAX_TICK + 1, 1), 2);
        assert!(is_valid_tick(TICK_OFFSET, 1), 3); // Test tick 0
        assert!(!is_valid_tick(TICK_OFFSET + 100, 10), 4); // Test positive tick
        assert!(!is_valid_tick(TICK_OFFSET - 100, 10), 5); // Test negative tick
        assert!(is_valid_tick(TICK_OFFSET, 2), 5);
    }

    #[test]
    fun test_convert_to_real_tick() {
        // Test positive tick
        let (abs_tick, is_positive) = convert_to_real_tick(TICK_OFFSET + 100);
        assert!(abs_tick == 100, 0);
        assert!(is_positive == true, 1);

        // Test negative tick
        let (abs_tick, is_positive) = convert_to_real_tick(TICK_OFFSET - 100);
        assert!(abs_tick == 100, 2);
        assert!(is_positive == false, 3);

        // Test zero tick
        let (abs_tick, is_positive) = convert_to_real_tick(TICK_OFFSET);
        assert!(abs_tick == 0, 4);
        assert!(is_positive == true, 5);
    }

    #[test]
    fun test_convert_from_real_tick() {
        // Test positive tick
        let offset_tick = convert_from_real_tick(100, true);
        assert!(offset_tick == TICK_OFFSET + 100, 0);

        // Test negative tick
        let offset_tick = convert_from_real_tick(100, false);
        assert!(offset_tick == TICK_OFFSET - 100, 1);

        // Test zero tick
        let offset_tick = convert_from_real_tick(0, true);
        assert!(offset_tick == TICK_OFFSET, 2);
    }
}