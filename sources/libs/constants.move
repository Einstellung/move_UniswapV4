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
}
