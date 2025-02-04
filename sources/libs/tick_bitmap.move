module libs::tick_bitmap {
    use sui::table::{Self, Table};
    use libs::bit_math;
    use libs::constants;

    /// Error codes
    const ERR_TICK_MISALIGNED: u64 = 1;

    /// Constants
    const WORD_SIZE: u32 = 256;        // Number of bits per word

    /// @notice Computes the position in the mapping where the initialized bit for a tick lives
    /// @param tick The tick for which to compute the position
    /// @return wordPos The key in the mapping containing the word in which the bit is stored
    /// @return bitPos The bit position in the word where the flag is stored
    fun position(tick: u32): (u32, u8) {
        let word_pos = tick / WORD_SIZE;
        let bit_pos = ((tick % WORD_SIZE) as u8);
        (word_pos, bit_pos)
    }

    /// @notice Helper function to get word from bitmap table, returns 0 if not found
    fun try_get_tick_word(
        self: &Table<u32, u256>,
        word_pos: u32
    ): u256 {
        if (!table::contains(self, word_pos)) {
            0
        } else {
            *table::borrow(self, word_pos)
        }
    }

    /// @notice Helper function to get or create word in bitmap table
    fun try_borrow_mut_tick_word(
        self: &mut Table<u32, u256>,
        word_pos: u32
    ): &mut u256 {
        if (!table::contains(self, word_pos)) {
            table::add(self, word_pos, 0);
        };
        table::borrow_mut(self, word_pos)
    }

    /// @notice Creates a new tick bitmap table
    public fun new(ctx: &mut TxContext): Table<u32, u256> {
        table::new(ctx)
    }

    /// @notice Flips the initialized state for a given tick from false to true, or vice versa
    /// @param self The mapping in which to flip the tick
    /// @param tick The tick to flip
    /// @param tick_spacing The spacing between usable ticks
    public fun flip_tick(self: &mut Table<u32, u256>, tick: u32, tick_spacing: u32) {
        assert!(tick % tick_spacing == 0, ERR_TICK_MISALIGNED);

        let (word_pos, bit_pos) = position(tick / tick_spacing);
        let mask = 1u256 << bit_pos;
        let word = try_borrow_mut_tick_word(self, word_pos);
        // XOR the mask with the word to flip the bit
        // XOR rule is 0 won't change, 1 will flip
        *word = *word ^ mask;
    }

    /// @notice Returns the next initialized tick contained in the same word (or adjacent word) as the tick that is either
    /// to the left (less than or equal to) or right (greater than) of the given tick
    /// @param self The mapping in which to compute the next initialized tick
    /// @param tick The starting tick
    /// @param tick_spacing The spacing between usable ticks
    /// @param lte Whether to search for the next initialized tick to the left (less than or equal to the starting tick)
    /// @return next The next initialized or uninitialized tick up to 256 ticks away from the current tick
    /// @return initialized Whether the next tick is initialized, as the function only searches within up to 256 ticks
    public fun next_initialized_tick_within_one_word(
        self: &Table<u32, u256>,
        tick: u32,
        tick_spacing: u32,
        lte: bool
    ): (u32, bool) {
        let compressed = tick / tick_spacing;

        if (lte) {
            let (word_pos, bit_pos) = position(compressed);
            //  bit_pos and smaller than bit_pos will all be 1
            // In binary representation, the digits on the left have higher value and those on the right have lower value.
            // By using a mask that sets the lower bits to 1 (and higher bits to 0), we isolate the portion of the number that represents values less than or equal to a given threshold.
            let mask = (1u256 << bit_pos) - 1 + (1u256 << bit_pos);
            let masked = try_get_tick_word(self, word_pos) & mask;

            let initialized = masked != 0;

            let next = if (initialized) {
                // the most significant bit is the closest to the current word_pos
                let msb = bit_math::get_most_significant_bit(masked);
                (word_pos * WORD_SIZE + (msb as u32)) * tick_spacing
            } else {
                // if not initialized, the next initialized tick is the current tick
                (word_pos * WORD_SIZE + (bit_pos as u32)) * tick_spacing
            };

            (next, initialized)
        } else {
            let (word_pos, bit_pos) = position(compressed + 1);
            // We need to find bigger than current bit_pos tick point
            let mask = ((1u256 << bit_pos) - 1) ^ constants::get_max_u256();
            let masked = try_get_tick_word(self, word_pos) & mask;

            let initialized = masked != 0;

            let next = if (initialized) {
                // the least significant bit is the closest to the current word_pos
                let lsb = bit_math::get_least_significant_bit(masked);
                (word_pos * WORD_SIZE + (lsb as u32)) * tick_spacing
            } else {
                ((word_pos + 1) * WORD_SIZE) * tick_spacing
            };

            (next, initialized)
        }
    }

    #[test_only]
    public fun is_initialized(
        tick_bitmap: &Table<u32, u256>,
        tick: u32
    ): bool {
        let (next, initialized) = next_initialized_tick_within_one_word(tick_bitmap, tick, 1, true);
        if (next == tick) {
            initialized
        } else {
            false
        }
    }

    #[test]
    fun test_position() {
        // Test basic positions
        let (word_pos, bit_pos) = position(0);
        assert!(word_pos == 0, 0);
        assert!(bit_pos == 0, 1);

        let (word_pos, bit_pos) = position(1);
        assert!(word_pos == 0, 2);
        assert!(bit_pos == 1, 3);

        // Test word boundary
        let (word_pos, bit_pos) = position(255);
        assert!(word_pos == 0, 4);
        assert!(bit_pos == 255, 5);

        let (word_pos, bit_pos) = position(256);
        assert!(word_pos == 1, 6);
        assert!(bit_pos == 0, 7);

        // Test large numbers
        let (word_pos, bit_pos) = position(1000);
        assert!(word_pos == 3, 8);  // 1000 / 256 = 3
        assert!(bit_pos == 232, 9); // 1000 % 256 = 232
    }

    #[test]
    fun test_flip_tick() {
        
        let mut tick_bitmap = table::new<u32, u256>(&mut tx_context::dummy());

        // Test single flip
        let (word_pos, bit_pos) = position(0);
        assert!(try_get_tick_word(&tick_bitmap, word_pos) & (1u256 << bit_pos) == 0, 0);
        flip_tick(&mut tick_bitmap, 0, 1);
        assert!(try_get_tick_word(&tick_bitmap, word_pos) & (1u256 << bit_pos) != 0, 1);

        // Test double flip (should cancel out)
        flip_tick(&mut tick_bitmap, 0, 1);
        assert!(try_get_tick_word(&tick_bitmap, word_pos) & (1u256 << bit_pos) == 0, 2);

        // Test multiple ticks in same word
        flip_tick(&mut tick_bitmap, 1, 1);
        flip_tick(&mut tick_bitmap, 2, 1);
        // check second bit of word 0
        assert!(try_get_tick_word(&tick_bitmap, 0) & (1u256 << 1) != 0, 3);
        // check third bit of word 0
        assert!(try_get_tick_word(&tick_bitmap, 0) & (1u256 << 2) != 0, 4);

        // Test ticks in different words
        flip_tick(&mut tick_bitmap, 256, 1);  // This should be in word 1
        // check first bit of word 1
        assert!(try_get_tick_word(&tick_bitmap, 1) & 1u256 != 0, 5);
        // Previous flips should remain unchanged
        assert!(try_get_tick_word(&tick_bitmap, 0) & (1u256 << 1) != 0, 6);
        assert!(try_get_tick_word(&tick_bitmap, 0) & (1u256 << 2) != 0, 7);

        table::drop(tick_bitmap);
    }

    #[test]
    fun test_next_initialized_tick_within_one_word() {
        
        let mut tick_bitmap = table::new<u32, u256>(&mut tx_context::dummy());

        // Initialize some ticks
        flip_tick(&mut tick_bitmap, 2, 1);
        flip_tick(&mut tick_bitmap, 8, 1);
        flip_tick(&mut tick_bitmap, 16, 1);

        // Test searching right
        let (next, initialized) = next_initialized_tick_within_one_word(&tick_bitmap, 1, 1, false);
        assert!(next == 2 && initialized, 0);

        // Test searching left
        let (next, initialized) = next_initialized_tick_within_one_word(&tick_bitmap, 9, 1, true);
        assert!(next == 8 && initialized, 1);

        // Test boundary cases
        let (next, initialized) = next_initialized_tick_within_one_word(&tick_bitmap, 255, 1, false);
        assert!(next == 512 && !initialized, 2);

        table::drop(tick_bitmap);
    }

    #[test]
    #[expected_failure(abort_code = ERR_TICK_MISALIGNED)]
    fun test_flip_tick_misaligned() {
        
        let mut tick_bitmap = table::new<u32, u256>(&mut tx_context::dummy());
        // tick must be multiple of tick_spacing
        flip_tick(&mut tick_bitmap, 1, 2); // tick 1 is not aligned with spacing 2
        table::drop(tick_bitmap);
    }
}