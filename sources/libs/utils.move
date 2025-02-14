module libs::utils {
    public fun int_128_add(a: u128, a_is_positive: bool, b: u128, b_is_positive: bool): (u128, bool) { 
        if (a_is_positive == b_is_positive) {
            (a + b, a_is_positive)
        } else {
            if (a >= b) {
                (a - b, a_is_positive)
            } else {
                (b - a, b_is_positive)
            }
        }
    }

    public fun int_128_sub(a: u128, a_is_positive: bool, b: u128, b_is_positive: bool): (u128, bool) {
        if (a_is_positive != b_is_positive) {
            return int_128_add(a, a_is_positive, b, !b_is_positive)
        };
        // same sign
        if (a>=b) {
            (a - b, a_is_positive)
        } else {
            (b - a, !a_is_positive)
        }
    }

    #[test]
    fun test_int_128_add() {
        // Test case 1: positive + positive
        let (result, is_positive) = int_128_add(100, true, 50, true);
        assert!(result == 150, 0);
        assert!(is_positive == true, 1);

        // Test case 2: positive + negative, positive larger
        let (result, is_positive) = int_128_add(100, true, 50, false);
        assert!(result == 50, 2);
        assert!(is_positive == true, 3);

        // Test case 3: positive + negative, negative larger
        let (result, is_positive) = int_128_add(50, true, 100, false);
        assert!(result == 50, 4);
        assert!(is_positive == false, 5);

        // Test case 4: negative + negative
        let (result, is_positive) = int_128_add(100, false, 50, false);
        assert!(result == 150, 6);
        assert!(is_positive == false, 7);
    }

    #[test]
    fun test_int_128_sub() {
        // Test case 1: positive - positive, result positive
        let (result, is_positive) = int_128_sub(100, true, 50, true);
        assert!(result == 50, 0);
        assert!(is_positive == true, 1);

        // Test case 2: positive - positive, result negative
        let (result, is_positive) = int_128_sub(50, true, 100, true);
        assert!(result == 50, 2);
        assert!(is_positive == false, 3);

        // Test case 3: positive - negative
        let (result, is_positive) = int_128_sub(100, true, 50, false);
        assert!(result == 150, 4);
        assert!(is_positive == true, 5);

        // Test case 4: negative - negative
        let (result, is_positive) = int_128_sub(100, false, 50, false);
        assert!(result == 50, 6);
        assert!(is_positive == false, 7);
    }

    #[test]
    fun test_int_128_edge_cases() {
        // Test with zero
        let (result, is_positive) = int_128_add(0, true, 100, true);
        assert!(result == 100, 0);
        assert!(is_positive == true, 1);

        let (result, is_positive) = int_128_add(100, true, 0, false);
        assert!(result == 100, 2);
        assert!(is_positive == true, 3);

        // Test equal numbers with different signs
        let (result, is_positive) = int_128_add(100, true, 100, false);
        assert!(result == 0, 4);
        assert!(is_positive == true, 5);

        let (result, is_positive) = int_128_sub(100, true, 100, true);
        assert!(result == 0, 6);
        assert!(is_positive == true, 7);
    }
}

