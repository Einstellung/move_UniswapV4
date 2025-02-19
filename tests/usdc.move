#[test_only]
module move_v4::usdc {
    use sui::coin::{Self, TreasuryCap};
    use sui::test_scenario::{Self, Scenario};

    /// One-time witness for the USDC currency
    public struct USDC has drop {}

    const ADMIN: address = @0xABCD;
    const USER: address = @0x1234;
    const INITIAL_AMOUNT: u64 = 1000000000;

    fun init(witness: USDC, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness,
            6,
            b"USDC",
            b"USD Coin",
            b"Stablecoin for testing",
            option::none(),
            ctx
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury_cap, ADMIN);
    }

    #[test_only]
    public fun mint_test_coins(scenario: &mut Scenario) {
        let mut treasury_cap = test_scenario::take_from_address<TreasuryCap<USDC>>(scenario, ADMIN);
        let ctx = test_scenario::ctx(scenario);
        
        // Mint coins for ADMIN
        let admin_coins = coin::mint<USDC>(&mut treasury_cap, INITIAL_AMOUNT, ctx);
        transfer::public_transfer(admin_coins, ADMIN);

        // Mint coins for USER
        let user_coins = coin::mint<USDC>(&mut treasury_cap, INITIAL_AMOUNT, ctx);
        transfer::public_transfer(user_coins, USER);

        test_scenario::return_to_address(ADMIN, treasury_cap);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(USDC {}, ctx);
    }
}
