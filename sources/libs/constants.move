module libs::constants {
    // Maximum values for different bit lengths
    const MAX_U8: u8 = 0xff;
    const MAX_U16: u16 = 0xffff;
    const MAX_U32: u32 = 0xffffffff;
    const MAX_U64: u64 = 0xffffffffffffffff;
    const MAX_U128: u128 = 0xffffffffffffffffffffffffffffffff;
    const MAX_U160: u256 = 0xffffffffffffffffffffffffffffffffffffffff;
    const MAX_U256: u256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    // Fixed point number constants
    /// @notice The Q96 point in binary fixed point maths
    /// @dev Used in SqrtPriceMath
    const RESOLUTION_96: u8 = 96;
    const Q96: u128 = 0x1000000000000000000000000;

    /// @notice The Q128 point in binary fixed point maths
    const RESOLUTION_128: u8 = 128;
    const Q128: u256 = 0x100000000000000000000000000000000;

    /// Constants for tick range
    const TICK_OFFSET: u32 = 887272;  // This is the offset we use to simulate negative ticks
    const MIN_TICK: u32 = 0;     // Represents -887272 in original Solidity code
    const MAX_TICK: u32 = 1774544;  // Represents 887272 in original Solidity code

    /// Constants for tick spacing
    const MIN_TICK_SPACING: u32 = 1;
    const MAX_TICK_SPACING: u32 = 32767;

    /// @notice the swap fee is represented in hundredths of a bip, so the max is 100%
    /// @dev the swap fee is the total fee on a swap, including both LP and Protocol fee
    const MAX_SWAP_FEE: u32 = 1000000; // 1e6

    /// Constants for sqrt price range
    const MIN_SQRT_PRICE: u256 = 4295128739;
    const TICK_OFFSET_SQRT_PRICE: u256 = 79228162514264337593543950336;
    const MAX_SQRT_PRICE: u256 = 1461446703485210103287273052203988822378723970342;

    public fun get_max_u8(): u8 {
        MAX_U8
    }

    public fun get_max_u16(): u16 {
        MAX_U16
    }

    public fun get_max_u32(): u32 {
        MAX_U32
    }

    public fun get_max_u128(): u128 {
        MAX_U128
    }

    public fun get_max_u160(): u256 {
        MAX_U160
    }

    public fun get_max_u256(): u256 {
        MAX_U256
    }

    public fun get_max_u64(): u64 {
        MAX_U64
    }

    public fun get_q96(): u128 {
        Q96
    }

    public fun get_resolution_96(): u8 {
        RESOLUTION_96
    }

    public fun get_q128(): u256 {
        Q128
    }

    public fun get_resolution_128(): u8 {
        RESOLUTION_128
    }

    public fun get_tick_offset(): u32 {
        TICK_OFFSET
    }

    public fun get_min_tick(): u32 {
        MIN_TICK
    }

    public fun get_max_tick(): u32 {
        MAX_TICK
    }

    public fun get_max_swap_fee(): u32 {
        MAX_SWAP_FEE
    }

    public fun get_min_sqrt_price(): u256 {
        MIN_SQRT_PRICE
    }

    public fun get_tick_0_sqrt_price(): u256 {
        TICK_OFFSET_SQRT_PRICE
    }

    public fun get_max_sqrt_price(): u256 {
        MAX_SQRT_PRICE
    }

    public fun get_min_tick_spacing(): u32 {
        MIN_TICK_SPACING
    }

    public fun get_max_tick_spacing(): u32 {
        MAX_TICK_SPACING
    }
}
