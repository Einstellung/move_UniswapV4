module libs::currency_delta {
    use sui::table::{Self, Table};
    use sui::address;
    use sui::hash;
    use libs::utils;

    /// Cannot destroy CurrencyDelta with non-zero deltas
    const ENONZERO_DELTAS_EXIST: u64 = 1;

    /// Represents a delta entry for a specific currency and account
    public struct DeltaEntry has store, drop {
        amount: u128,
        /// entry amount sign, true for positive, false for negative
        is_positive: bool
    }

    /// The main structure to track currency deltas
    public struct CurrencyDelta has store {
        /// Maps hash(currency_address + target_address) to DeltaEntry
        deltas: Table<vector<u8>, DeltaEntry>,
        /// Tracks the number of non-zero delta entries.
        /// This counter is:
        /// - Incremented when a new non-zero delta is created
        /// - Decremented when a non-zero delta becomes zero
        /// - Used to ensure all deltas are properly settled before destroying the CurrencyDelta
        /// - Must be zero before the CurrencyDelta can be destroyed
        nonzero_count: u64
    }

    /// Create a new CurrencyDelta tracker
    public fun new(ctx: &mut TxContext): CurrencyDelta {
        CurrencyDelta {
            deltas: table::new(ctx),
            nonzero_count: 0
        }
    }

    /// Compute the slot (hash) for storing delta
    public fun compute_slot(target: address, currency: address): vector<u8> {
        let mut bytes = vector::empty();
        vector::append(&mut bytes, address::to_bytes(target));
        vector::append(&mut bytes, address::to_bytes(currency));
        hash::keccak256(&bytes)
    }

    /// Get the current delta for a currency and target
    /// Returns the amount and the sign of the delta
    public fun get_delta(
        currency_delta: &CurrencyDelta,
        currency: address,
        target: address
    ): (u128, bool) {
        let slot = compute_slot(target, currency);
        
        if (table::contains(&currency_delta.deltas, slot)) {
            let entry = table::borrow(&currency_delta.deltas, slot);
            (entry.amount, entry.is_positive)
        } else {
            (0, true)
        }
    }

    /// Apply a new delta for a currency and target
    /// Returns the previous and next values
    public fun apply_delta(
        currency_delta: &mut CurrencyDelta,
        currency: address,
        target: address,
        amount: u128,
        amount_is_positive: bool
    ): (u128, bool, u128, bool) {
        let slot = compute_slot(target, currency);
        
        let (prev_amount, prev_is_positive) = if (table::contains(&currency_delta.deltas, slot)) {
            let entry = table::borrow(&currency_delta.deltas, slot);
            (entry.amount, entry.is_positive)
        } else {
            (0, true)
        };

        // Calculate new amount using utils::int_128_add
        let (new_amount, new_is_positive) = utils::int_128_add(prev_amount, prev_is_positive, amount, amount_is_positive);

        // Update nonzero count
        if (prev_amount == 0 && new_amount > 0) {
            currency_delta.nonzero_count = currency_delta.nonzero_count + 1;
        } else if (prev_amount > 0 && new_amount == 0) {
            currency_delta.nonzero_count = currency_delta.nonzero_count - 1;
        };

        // Store new value
        if (new_amount == 0) {
            if (table::contains(&currency_delta.deltas, slot)) {
                table::remove(&mut currency_delta.deltas, slot);
            }
        } else {
            let entry = DeltaEntry {
                amount: new_amount,
                is_positive: new_is_positive
            };
            if (table::contains(&currency_delta.deltas, slot)) {
                table::remove(&mut currency_delta.deltas, slot);
            };
            table::add(&mut currency_delta.deltas, slot, entry);
        };

        (prev_amount, prev_is_positive, new_amount, new_is_positive)
    }

    /// Get the count of non-zero deltas
    public fun get_nonzero_count(currency_delta: &CurrencyDelta): u64 {
        currency_delta.nonzero_count
    }

    /// Destroy the CurrencyDelta and its resources
    /// Aborts if there are any non-zero deltas remaining (nonzero_count > 0)
    public fun destroy(currency_delta: CurrencyDelta) {
        assert!(currency_delta.nonzero_count == 0, ENONZERO_DELTAS_EXIST);
        let CurrencyDelta { deltas, nonzero_count: _ } = currency_delta;
        table::destroy_empty(deltas);
    }

    #[test]
    fun test_basic_operations() {
        use sui::test_scenario;
        
        let mut scenario = test_scenario::begin(@0x1);
        let ctx = test_scenario::ctx(&mut scenario);
        
        // Create new CurrencyDelta
        let mut currency_delta = new(ctx);
        assert!(get_nonzero_count(&currency_delta) == 0, 0);

        // Test apply_delta with new entry
        let (prev_amount, prev_is_positive, new_amount, new_is_positive) = 
            apply_delta(&mut currency_delta, @0x2, @0x3, 100, true);
        
        assert!(prev_amount == 0, 1);
        assert!(prev_is_positive == true, 2);
        assert!(new_amount == 100, 3);
        assert!(new_is_positive == true, 4);
        assert!(get_nonzero_count(&currency_delta) == 1, 5);

        // Test get_delta
        let (amount, is_positive) = get_delta(&currency_delta, @0x2, @0x3);
        assert!(amount == 100, 6);
        assert!(is_positive == true, 7);

        // Clear delta before destroying
        apply_delta(&mut currency_delta, @0x2, @0x3, 100, false);
        assert!(get_nonzero_count(&currency_delta) == 0, 8);

        // Clean up
        destroy(currency_delta);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_add_sub_operations() {
        use sui::test_scenario;
        
        let mut scenario = test_scenario::begin(@0x1);
        let ctx = test_scenario::ctx(&mut scenario);
        
        let mut currency_delta = new(ctx);

        // Add positive delta
        let (_, _, amount, is_positive) = apply_delta(&mut currency_delta, @0x2, @0x3, 100, true);
        assert!(amount == 100, 0);
        assert!(is_positive == true, 1);

        // Add another positive delta
        let (_, _, amount, is_positive) = apply_delta(&mut currency_delta, @0x2, @0x3, 50, true);
        assert!(amount == 150, 2);
        assert!(is_positive == true, 3);

        // Add negative delta
        let (_, _, amount, is_positive) = apply_delta(&mut currency_delta, @0x2, @0x3, 30, false);
        assert!(amount == 120, 4);
        assert!(is_positive == true, 5);

        // Add larger negative delta
        let (_, _, amount, is_positive) = apply_delta(&mut currency_delta, @0x2, @0x3, 200, false);
        assert!(amount == 80, 6);
        assert!(is_positive == false, 7);

        // Clear delta before destroying
        apply_delta(&mut currency_delta, @0x2, @0x3, 80, true);
        assert!(get_nonzero_count(&currency_delta) == 0, 8);

        destroy(currency_delta);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_nonzero_count() {
        use sui::test_scenario;
        
        let mut scenario = test_scenario::begin(@0x1);
        let ctx = test_scenario::ctx(&mut scenario);
        
        let mut currency_delta = new(ctx);
        assert!(get_nonzero_count(&currency_delta) == 0, 0);

        // Add entry for (@0x2, @0x3)
        apply_delta(&mut currency_delta, @0x2, @0x3, 100, true);
        assert!(get_nonzero_count(&currency_delta) == 1, 1);

        // Add entry for (@0x2, @0x4)
        apply_delta(&mut currency_delta, @0x2, @0x4, 100, true);
        assert!(get_nonzero_count(&currency_delta) == 2, 2);

        // Cancel out first entry
        apply_delta(&mut currency_delta, @0x2, @0x3, 100, false);
        assert!(get_nonzero_count(&currency_delta) == 1, 3);

        // Clear remaining delta
        apply_delta(&mut currency_delta, @0x2, @0x4, 100, false);
        assert!(get_nonzero_count(&currency_delta) == 0, 4);

        destroy(currency_delta);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ENONZERO_DELTAS_EXIST)]
    fun test_destroy_with_nonzero_delta() {
        use sui::test_scenario;
        
        let mut scenario = test_scenario::begin(@0x1);
        let ctx = test_scenario::ctx(&mut scenario);
        
        let mut currency_delta = new(ctx);
        
        // Add non-zero delta
        apply_delta(&mut currency_delta, @0x2, @0x3, 100, true);
        
        // This should fail
        destroy(currency_delta);
        test_scenario::end(scenario);
    }
}