module libs::pool {
    use sui::table::{Self, Table};
    use libs::tick_bitmap;
    use libs::position::{Self, PositionManager};
    use libs::tick_math;
    use libs::sqrt_price_math;
    use libs::swap_math;
    use libs::liquidity_math;
    use libs::constants;
    use libs::utils;
    use std::u256;
    use std::debug::print;

    // Error codes
    const ERR_TICKS_MISORDERED: u64 = 1;
    const ERR_TICK_LOWER_OUT_OF_BOUNDS: u64 = 2;
    const ERR_TICK_UPPER_OUT_OF_BOUNDS: u64 = 3;
    const ERR_TICK_LIQUIDITY_OVERFLOW: u64 = 4;
    const ERR_POOL_ALREADY_INITIALIZED: u64 = 5;
    const ERR_POOL_NOT_INITIALIZED: u64 = 6;
    const ERR_PRICE_LIMIT_ALREADY_EXCEEDED: u64 = 7;
    const ERR_PRICE_LIMIT_OUT_OF_BOUNDS: u64 = 8;
    // const ERR_NO_LIQUIDITY_TO_RECEIVE_FEES: u64 = 9;
    // const ERR_INVALID_FEE_FOR_EXACT_OUT: u64 = 10;
    const EINVALID_FOR_EXACT_OUTPUT: u64 = 11;

    public struct LiquidityNet has store, copy, drop {
        liquidity_net: u128,
        is_positive: bool
    }

    /// Info stored for each initialized individual tick
    public struct TickInfo has store, copy, drop {
        // the total position liquidity that references this tick
        liquidity_gross: u128,
        // amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left)
        liquidity_net: LiquidityNet,
        // fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
        fee_growth_outside_0_x128: u256,
        fee_growth_outside_1_x128: u256
    }

    /// The state of a pool
    public struct Pool has store {
        /// Current price and tick
        sqrt_price_x96: u256,
        /// Current tick index, represents the current price in tick space
        tick: u32,
        /// Fee parameters
        fee_protocol: u8,
        lp_fee: u32,
        /// Global fee growth
        fee_growth_global_0_x128: u256,
        fee_growth_global_1_x128: u256,
        /// Current liquidity
        liquidity: u128,
        /// Tick data: maps tick index (u32) to TickInfo
        /// A tick represents a discrete point in price space where liquidity can be provided
        /// key is tick
        ticks: Table<u32, TickInfo>,
        /// Tick bitmap: maps word position (u32) to bitmap (u256)
        /// Each bit in the bitmap represents whether a tick at a specific index is initialized
        /// word_pos = tick_index >> 8 (tick index divided by 256)
        /// key is word_pos
        tick_bitmap: Table<u32, u256>,
        /// Position management
        positions: PositionManager
    }

    /// Parameters for modifying liquidity
    public struct ModifyLiquidityParams has drop {
        // the address that owns the position
        owner: address,
        // the lower and upper tick of the position
        tick_lower: u32,
        tick_upper: u32,
        // any change in liquidity
        abs_liquidity_delta: u128,
        liquidity_delta_is_positive: bool,
        // the spacing between ticks
        tick_spacing: u32,
        // used to distinguish positions of the same owner, at the same tick range
        salt: vector<u8>
    }

    /// Tracks state changes when modifying liquidity
    public struct ModifyLiquidityState has drop {
        // whether the lower tick was flipped from initialized to uninitialized, or vice versa
        flipped_lower: bool,
        // the amount of liquidity at the lower tick after the modification
        liquidity_gross_after_lower: u128,
        // whether the upper tick was flipped from initialized to uninitialized, or vice versa
        flipped_upper: bool,
        // the amount of liquidity at the upper tick after the modification
        liquidity_gross_after_upper: u128
    }

    /// Parameters for swap
    public struct SwapParams has drop {
        /// the exact amount of tokens the user wants to send to or receive from the pool.
        amount_specified: u128,
        /// exact_output is true represents exact output, otherwise exact input.
        exact_output: bool,
        tick_spacing: u32,
        zero_for_one: bool,
        sqrt_price_limit_x96: u256,
        lp_fee_override: u32
    }

    /// Tracks the state of a pool throughout a swap, and returns these values at the end of the swap
    public struct SwapResult has drop {
        /// the current sqrt price of the pool
        sqrt_price_x96: u256,
        /// the current tick of the pool
        tick: u32,
        /// the current liquidity of the pool
        liquidity: u128
    }

    // public struct SwapDelta has drop {
    //     amount_in: u128,
    //     amount_in_to_pool: bool,
    //     amount_out: u128,
    //     amount_out_to_user: bool
    // }

    /// Tracks computation steps during a swap
    public struct StepComputations has drop {
        /// the price at the beginning of the step
        sqrt_price_start_x96: u256,
        /// the next tick to swap to from the current tick in the swap direction
        tick_next: u32,
        /// whether tickNext is initialized or not
        initialized: bool,
        /// sqrt(price) for the next tick
        sqrt_price_next_x96: u256,
        /// how much is being swapped in in this step
        amount_in: u256,
        /// how much is being swapped out
        amount_out: u256,
        /// how much fee is being paid in
        fee_amount: u256,
        /// the global fee growth(per unit of liquidity) of the input token. updated in storage at the end of swap
        fee_growth_global_x128: u256
    }

    /// Check if ticks are valid
    fun check_ticks(tick_lower: u32, tick_upper: u32) {
        assert!(tick_lower < tick_upper, ERR_TICKS_MISORDERED);
        assert!(tick_lower >= constants::get_min_tick(), ERR_TICK_LOWER_OUT_OF_BOUNDS);
        assert!(tick_upper <= constants::get_max_tick(), ERR_TICK_UPPER_OUT_OF_BOUNDS);
    }

    /// Initialize a new pool
    public fun initialize(
        pool: &mut Pool,
        sqrt_price_x96: u256,
        lp_fee: u32,
    ): u32 {
        // Check if pool is already initialized
        assert!(pool.sqrt_price_x96 == 0, ERR_POOL_ALREADY_INITIALIZED);

        let tick = tick_math::get_tick_at_sqrt_price(sqrt_price_x96);
        
        pool.sqrt_price_x96 = sqrt_price_x96;
        pool.tick = tick;
        pool.lp_fee = lp_fee;
        // protocol_fee is initially 0 so no need to set it

        // initialize the TickInfo
        table::add(&mut pool.ticks, tick, TickInfo {
            liquidity_gross: 0,
            liquidity_net: LiquidityNet {
                liquidity_net: 0,
                is_positive: true
            },
            fee_growth_outside_0_x128: 0,
            fee_growth_outside_1_x128: 0
        });

        tick
    }

    fun checkPoolInitialized(pool: &Pool) {
        assert!(pool.sqrt_price_x96 != 0, ERR_POOL_NOT_INITIALIZED);
    }

    /// Set protocol fee
    /// @notice Only protocol manager may update the protocol fee.
    /// TODO: Security check
    public fun set_protocol_fee(pool: &mut Pool, protocol_fee: u8) {
        Self::checkPoolInitialized(pool);
        pool.fee_protocol = protocol_fee;
    }

    /// Set LP fee
    /// @notice Only dynamic fee pools may update the lp fee.
    /// TODO: Security check
    public fun set_lp_fee(pool: &mut Pool, lp_fee: u32) {
        Self::checkPoolInitialized(pool);
        pool.lp_fee = lp_fee;
    }

    /// @notice Retrieves fee growth data
    /// @param pool The Pool state struct
    /// @param tick_lower The lower tick boundary of the position
    /// @param tick_upper The upper tick boundary of the position
    /// @return (fee_growth_inside_0_x128, fee_growth_inside_1_x128) The all-time fee growth in token0 and token1, per unit of liquidity, inside the position's tick boundaries
    fun get_fee_growth_inside(
        pool_ticks: &Table<u32, TickInfo>,
        pool_tick: u32,
        pool_fee_growth_global_0_x128: u256,
        pool_fee_growth_global_1_x128: u256,
        tick_lower: u32,
        tick_upper: u32
    ): (u256, u256) {
        let lower = table::borrow(pool_ticks, tick_lower);
        let upper = table::borrow(pool_ticks, tick_upper);
        let tick_current = pool_tick;

        let fee_growth_inside_0_x128: u256;
        let fee_growth_inside_1_x128: u256;

        if (tick_current < tick_lower) {
            fee_growth_inside_0_x128 = lower.fee_growth_outside_0_x128 - upper.fee_growth_outside_0_x128;
            fee_growth_inside_1_x128 = lower.fee_growth_outside_1_x128 - upper.fee_growth_outside_1_x128;
        } else if (tick_current >= tick_upper) {
            fee_growth_inside_0_x128 = upper.fee_growth_outside_0_x128 - lower.fee_growth_outside_0_x128;
            fee_growth_inside_1_x128 = upper.fee_growth_outside_1_x128 - lower.fee_growth_outside_1_x128;
        } else {
            fee_growth_inside_0_x128 = pool_fee_growth_global_0_x128 - lower.fee_growth_outside_0_x128 - upper.fee_growth_outside_0_x128;
            fee_growth_inside_1_x128 = pool_fee_growth_global_1_x128 - lower.fee_growth_outside_1_x128 - upper.fee_growth_outside_1_x128;
        };

        (fee_growth_inside_0_x128, fee_growth_inside_1_x128)
    }

    /// @notice Updates a tick and returns true if the tick was flipped from initialized to uninitialized, or vice versa
    /// @param pool The mapping containing all tick information for initialized ticks
    /// @param tick The tick that will be updated
    /// @param liquidity_delta A new amount of liquidity to be added (subtracted) when tick is crossed from left to right (right to left)
    /// @param upper true for updating a position's upper tick, or false for updating a position's lower tick
    /// @return (flipped, liquidity_gross_after) Whether the tick was flipped and the total amount of liquidity after the update
    fun update_tick(
        pool: &mut Pool,
        tick: u32,
        liquidity_delta: u128,
        liquidity_delta_is_positive: bool,
        upper: bool,
    ): (bool, u128) {
        // check whether the tick is initialized
        if(!table::contains(&pool.ticks, tick)) {
            // initialize the tick
            table::add(&mut pool.ticks, tick, TickInfo {
                liquidity_gross: 0,
                liquidity_net: LiquidityNet {
                    liquidity_net: 0,
                    is_positive: true
                },
                fee_growth_outside_0_x128: 0,
                fee_growth_outside_1_x128: 0
            });
        };

        let info = table::borrow_mut(&mut pool.ticks, tick);
        let liquidity_gross_before = info.liquidity_gross;
        let liquidity_net_before = info.liquidity_net;

        let liquidity_gross_after = liquidity_math::add_delta(liquidity_gross_before, liquidity_delta, !liquidity_delta_is_positive);

        let flipped = (liquidity_gross_after == 0) != (liquidity_gross_before == 0);

        if (liquidity_gross_before == 0) {
            // by convention, we assume that all growth before a tick was initialized happened _below_ the tick
            if (tick <= pool.tick) {
                info.fee_growth_outside_0_x128 = pool.fee_growth_global_0_x128;
                info.fee_growth_outside_1_x128 = pool.fee_growth_global_1_x128;
            }
        };

        // when the lower (upper) tick is crossed left to right, liquidity must be added (removed)
        // when the lower (upper) tick is crossed right to left, liquidity must be removed (added)
        info.liquidity_net = if (upper) {
            let (liquidity_net, is_positive) = utils::int_128_sub(liquidity_net_before.liquidity_net, liquidity_net_before.is_positive, liquidity_delta, liquidity_delta_is_positive);
            LiquidityNet {
                liquidity_net: liquidity_net,
                is_positive: is_positive
            }
        } 
        else {
            let (liquidity_net, is_positive) = utils::int_128_add(liquidity_net_before.liquidity_net, liquidity_net_before.is_positive, liquidity_delta, liquidity_delta_is_positive);
            LiquidityNet {
                liquidity_net: liquidity_net,
                is_positive: is_positive
            }
        };
        info.liquidity_gross = liquidity_gross_after;

        (flipped, liquidity_gross_after)
    }

    /// @notice Clears tick data
    /// @param pool The mapping containing all initialized tick information for initialized ticks
    /// @param tick The tick that will be cleared
    fun clear_tick(pool: &mut Pool, tick: u32) {
        table::remove(&mut pool.ticks, tick);
    }

    /// @notice Derives max liquidity per tick from given tick spacing
    /// @dev Executed when adding liquidity
    /// @param tick_spacing The amount of required tick separation
    /// @return The max liquidity per tick
    public fun tick_spacing_to_max_liquidity_per_tick(tick_spacing: u32): u128 {
        let min_tick = constants::get_min_tick();
        let max_tick = constants::get_max_tick();
        
        let min_tick_div = min_tick / tick_spacing;
        let min_tick_rem = min_tick % tick_spacing;
        let min_tick_adjusted = if (min_tick_rem != 0) {
            min_tick_div - 1
        } else {
            min_tick_div
        };
        
        let max_tick_div = max_tick / tick_spacing;
        let num_ticks = (max_tick_div - min_tick_adjusted) + 1;
        
        constants::get_max_u128() / (num_ticks as u128)
    }

    /// @notice Effect changes to a position in a pool
    /// @param pool The Pool state struct
    /// @param params The position details and the change to the position's liquidity to effect
    /// @return amount0 The amount of token0 that was locked or released
    /// @return amount1 The amount of token1 that was locked or released
    /// @return fees_owed_0 The amount of token0 that was collected as fees
    /// @return fees_owed_1 The amount of token1 that was collected as fees
    public fun modify_liquidity(
        pool: &mut Pool,
        params: &ModifyLiquidityParams
    ): (u128, u128, u128, u128) {
        check_ticks(params.tick_lower, params.tick_upper);

        let mut state = ModifyLiquidityState {
            flipped_lower: false,
            liquidity_gross_after_lower: 0,
            flipped_upper: false,
            liquidity_gross_after_upper: 0
        };

        // Update ticks if needed
        if (params.abs_liquidity_delta != 0) {
            let liquidity_delta_is_positive = params.liquidity_delta_is_positive;
            
            // Update lower tick
            let (flipped_lower, liquidity_gross_after_lower) = 
                update_tick(pool, params.tick_lower, params.abs_liquidity_delta, liquidity_delta_is_positive, false, );
            // Update upper tick
            let (flipped_upper, liquidity_gross_after_upper) = 
                update_tick(pool, params.tick_upper, params.abs_liquidity_delta, liquidity_delta_is_positive, true, );

            state = ModifyLiquidityState {
                flipped_lower,
                liquidity_gross_after_lower,
                flipped_upper,
                liquidity_gross_after_upper
            };

            // Check if we exceed the max liquidity per tick
            if (liquidity_delta_is_positive) {
                let max_liquidity_per_tick = tick_spacing_to_max_liquidity_per_tick(params.tick_spacing);
                assert!(state.liquidity_gross_after_lower <= max_liquidity_per_tick, ERR_TICK_LIQUIDITY_OVERFLOW);
                assert!(state.liquidity_gross_after_upper <= max_liquidity_per_tick, ERR_TICK_LIQUIDITY_OVERFLOW);
            };

            // Update tick bitmap if needed
            if (state.flipped_lower) {
                tick_bitmap::flip_tick(&mut pool.tick_bitmap, params.tick_lower, params.tick_spacing);
            };
            if (state.flipped_upper) {
                tick_bitmap::flip_tick(&mut pool.tick_bitmap, params.tick_upper, params.tick_spacing);
            };
        };

        ///////////////////////////////
        // Record the position update //
        ///////////////////////////////
        // Get the position
        let position = position::get_mut(&mut pool.positions, params.owner, params.tick_lower, params.tick_upper, params.salt);

        let (fee_growth_inside_0_x128, fee_growth_inside_1_x128) = 
            get_fee_growth_inside(
                &pool.ticks,
                pool.tick,
                pool.fee_growth_global_0_x128,
                pool.fee_growth_global_1_x128,
                params.tick_lower,
                params.tick_upper
            );

        let (fees_owed_0, fees_owed_1) = position::update(
            position,
            params.abs_liquidity_delta,
            params.liquidity_delta_is_positive,
            fee_growth_inside_0_x128,
            fee_growth_inside_1_x128
        );
        ///////////////////////////////

        // clear any tick data that is no longer needed
        if (!params.liquidity_delta_is_positive) {
            if (state.flipped_lower) {
                clear_tick(pool, params.tick_lower);
            };
            if (state.flipped_upper) {
                clear_tick(pool, params.tick_upper);
            };
        };

        // Calculate the amounts of token0 and token1 that need to be locked/released
        let mut amount0 = 0;
        let mut amount1 = 0;

        if (params.abs_liquidity_delta != 0) {
            if (pool.tick < params.tick_lower) {
                // current tick is below the passed range; liquidity can only become in range by crossing from left to right,
                // when we'll need _more_ token0 (it's becoming more valuable) so user must provide it
                amount0 = sqrt_price_math::get_amount0_delta_signed(
                    tick_math::get_sqrt_price_at_tick(params.tick_lower),
                    tick_math::get_sqrt_price_at_tick(params.tick_upper),
                    params.abs_liquidity_delta,
                    params.liquidity_delta_is_positive
                );
            } else if (pool.tick < params.tick_upper) {
                // current tick is inside the passed range
                amount0 = sqrt_price_math::get_amount0_delta_signed(
                    pool.sqrt_price_x96,
                    tick_math::get_sqrt_price_at_tick(params.tick_upper),
                    params.abs_liquidity_delta,
                    params.liquidity_delta_is_positive
                );
                amount1 = sqrt_price_math::get_amount1_delta_signed(
                    tick_math::get_sqrt_price_at_tick(params.tick_lower),
                    pool.sqrt_price_x96,
                    params.abs_liquidity_delta,
                    params.liquidity_delta_is_positive
                );

                pool.liquidity = liquidity_math::add_delta(pool.liquidity, params.abs_liquidity_delta, !params.liquidity_delta_is_positive);
            } else {
                // current tick is above the passed range; liquidity can only become in range by crossing from right to left,
                // when we'll need _more_ token1 (it's becoming more valuable) so user must provide it
                amount1 = sqrt_price_math::get_amount1_delta_signed(
                    tick_math::get_sqrt_price_at_tick(params.tick_lower),
                    tick_math::get_sqrt_price_at_tick(params.tick_upper),
                    params.abs_liquidity_delta,
                    params.liquidity_delta_is_positive
                );
            }
        };

        (
            u256::try_as_u128(amount0).extract(), 
            u256::try_as_u128(amount1).extract(), 
            u256::try_as_u128(fees_owed_0).extract(), 
            u256::try_as_u128(fees_owed_1).extract()
        )
    }

    /// @notice Performs a swap
    /// @param pool The Pool state struct
    /// @param params The swap parameters
    /// @return amount0 The amount of token0 that was swapped
    /// @return amount1 The amount of token1 that was swapped
    /// @return amount_calculated The amount calculated
    /// @return result The swap result
    public fun swap(
        pool: &mut Pool,
        params: &SwapParams
    ): (u128, u128, u256, SwapResult) {
        let zero_for_one = params.zero_for_one;

        // Get protocol fee
        // TODO: here need some more detail process
        let protocol_fee = if (zero_for_one) {
            pool.fee_protocol
        } else {
            pool.fee_protocol
        };

        // Initialize state
        let mut amount_specified_remaining = params.amount_specified;
        let mut amount_calculated = 0u256;
        // current tick and price
        let mut result = SwapResult {
            sqrt_price_x96: pool.sqrt_price_x96,
            tick: pool.tick,
            liquidity: pool.liquidity
        };
        // let mut amount_to_protocol = 0u256;

        // Calculate swap fee
        // TODO: here need some more detail process
        let lp_fee = if (params.lp_fee_override > 0) {
            params.lp_fee_override
        } else {
            pool.lp_fee
        };
        let swap_fee = if (protocol_fee == 0) {
            lp_fee
        } else {
            lp_fee
        };

        // a swap fee totaling MAX_SWAP_FEE (100%) makes exact output swaps impossible since the input is entirely consumed by the fee
        if (swap_fee > constants::get_max_swap_fee()) {
            // if exactOutput
            assert!(params.amount_specified == 0, EINVALID_FOR_EXACT_OUTPUT);
        };

        // swapFee is the pool's fee in pips (LP fee + protocol fee)
        // when the amount swapped is 0, there is no protocolFee applied and the fee amount paid to the protocol is set to 0
        // TODO: I will implement this in the future
        // if (params.amountSpecified == 0) return (BalanceDeltaLibrary.ZERO_DELTA, 0, swapFee, result);

        // Validate price limit, zero for one will cause the price decline
        if (zero_for_one) {
            assert!(params.sqrt_price_limit_x96 < result.sqrt_price_x96, ERR_PRICE_LIMIT_ALREADY_EXCEEDED);
            assert!(params.sqrt_price_limit_x96 > constants::get_min_sqrt_price(), ERR_PRICE_LIMIT_OUT_OF_BOUNDS);
        } else {
            assert!(params.sqrt_price_limit_x96 > result.sqrt_price_x96, ERR_PRICE_LIMIT_ALREADY_EXCEEDED);
            assert!(params.sqrt_price_limit_x96 < constants::get_max_sqrt_price(), ERR_PRICE_LIMIT_OUT_OF_BOUNDS);
        };

        let mut step = StepComputations {
            sqrt_price_start_x96: 0,
            tick_next: 0,
            initialized: false,
            sqrt_price_next_x96: 0,
            amount_in: 0,
            amount_out: 0,
            fee_amount: 0,
            fee_growth_global_x128: if (zero_for_one) {
                pool.fee_growth_global_0_x128
            } else {
                pool.fee_growth_global_1_x128
            }
        };

        // Continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
        while (amount_specified_remaining != 0 && result.sqrt_price_x96 != params.sqrt_price_limit_x96) {
            step.sqrt_price_start_x96 = result.sqrt_price_x96;

            // Get next initialized tick
            let (_tick_next, _initialized) = tick_bitmap::next_initialized_tick_within_one_word(
                &pool.tick_bitmap,
                result.tick,
                params.tick_spacing,
                zero_for_one
            );
            step.tick_next = _tick_next;
            step.initialized = _initialized;

            // Ensure we don't overshoot the min/max tick
            if (step.tick_next <= constants::get_min_tick()) {
                step.tick_next = constants::get_min_tick();
            };
            if (step.tick_next >= constants::get_max_tick()) {
                step.tick_next = constants::get_max_tick();
            };

            // Get the price for the next tick
            step.sqrt_price_next_x96 = tick_math::get_sqrt_price_at_tick(step.tick_next);

            // Get target price for this step
            let _sqrt_price_target_x96 = swap_math::get_sqrt_price_target(
                zero_for_one,
                step.sqrt_price_next_x96,
                params.sqrt_price_limit_x96
            );

            // Compute values for this step
            let (_sqrt_price_after, _amount_in, _amount_out, _fee_amount) = swap_math::compute_swap_step(
                result.sqrt_price_x96,
                _sqrt_price_target_x96,
                result.liquidity,
                amount_specified_remaining as u256,
                !params.exact_output,
                swap_fee
            );

            result.sqrt_price_x96 = _sqrt_price_after;
            step.amount_in = _amount_in;
            step.amount_out = _amount_out;
            step.fee_amount = _fee_amount;

            // if exactOutput
            if (params.exact_output) {
                amount_specified_remaining = amount_specified_remaining - u256::try_as_u128(step.amount_out).extract();
                // if exact output, amount_calculated represents the amount of token that user need to send to the pool(because we already know the pool output to the user amount)
                amount_calculated = amount_calculated + (step.amount_in + step.fee_amount);
            } else {
                // safe because we test that amountSpecified > amountIn + feeAmount in SwapMath
                amount_specified_remaining = amount_specified_remaining - u256::try_as_u128(step.amount_in + step.fee_amount).extract();
                // In this case, amount_calculated represents the amount of tokens the pool will return to the user.
                amount_calculated = amount_calculated + step.amount_out;
            };

            // if the protocol fee is on, calculate how much is owed, decrement feeAmount, and increment protocolFee
            if (protocol_fee > 0) {
                // TODO: Temporarily skip protocol fee design
            };

            // update global fee tracker
            if (result.liquidity > 0) {
                // FullMath.mulDiv isn't needed as the numerator can't overflow uint256 since tokens have a max supply of type(uint128).max
                step.fee_growth_global_x128 = step.fee_growth_global_x128 + 
                    (step.fee_amount * constants::get_q128() / (result.liquidity as u256));
            };

            // current price is the same as the next tick price, which means the tick is crossed
            if (result.sqrt_price_x96 == step.sqrt_price_next_x96) {
                // if the tick is initialized, run the tick transition
                if (step.initialized) {
                    let (_fee_growth_global_0_x128, _fee_growth_global_1_x128) = if (zero_for_one) {
                        (step.fee_growth_global_x128, pool.fee_growth_global_1_x128)
                    } else {
                        (pool.fee_growth_global_0_x128, step.fee_growth_global_x128)
                    };

                    let liquidity_net = cross_tick(
                        pool,
                        step.tick_next,
                        _fee_growth_global_0_x128,
                        _fee_growth_global_1_x128
                    );
 
                    // Update liquidity
                    result.liquidity = if (zero_for_one) {
                        // if we're moving leftward, we interpret liquidityNet as the opposite sign
                        // safe because liquidityNet cannot be type(int128).min
                        // if zeroForOne then liquidity_net is negative value(liquidityNet = -liquidityNet) 
                        liquidity_math::add_delta(result.liquidity, liquidity_net.liquidity_net, !!liquidity_net.is_positive)
                    } else {
                        liquidity_math::add_delta(result.liquidity, liquidity_net.liquidity_net, !liquidity_net.is_positive)
                    };
                };

                result.tick = if (zero_for_one) {
                    step.tick_next - 1
                } else {
                    step.tick_next
                };
            } else if (result.sqrt_price_x96 != step.sqrt_price_start_x96) {
                // if the current price is different from the step start price
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                result.tick = tick_math::get_tick_at_sqrt_price(result.sqrt_price_x96);
            };
        };

        // Update pool state
        pool.sqrt_price_x96 = result.sqrt_price_x96;
        pool.tick = result.tick;

        pool.liquidity = result.liquidity;

        // update fee growth global
        if (zero_for_one) {
            pool.fee_growth_global_0_x128 = step.fee_growth_global_x128;
        } else {
            pool.fee_growth_global_1_x128 = step.fee_growth_global_x128;
        };

        // exact input
        let (swap_delta0, swap_delta1) = if (zero_for_one != (!params.exact_output)) {
            // swaps token0 for token1 with an exact output
            (
                u256::try_as_u128(amount_calculated).extract(), 
                params.amount_specified - amount_specified_remaining
            )
        } else {
            // swaps token1 for token0 with an exact input
            (
                params.amount_specified - amount_specified_remaining, 
                u256::try_as_u128(amount_calculated).extract()
            )
        };

        (swap_delta0, swap_delta1, amount_calculated, result)
    }

    /// @notice Transitions to next tick as needed by price movement
    /// @param pool The Pool state struct
    /// @param tick The destination tick of the transition
    /// @param fee_growth_global_0_x128 The all-time global fee growth, per unit of liquidity, in token0
    /// @param fee_growth_global_1_x128 The all-time global fee growth, per unit of liquidity, in token1
    /// @return liquidity_net The amount of liquidity added (subtracted) when tick is crossed from left to right (right to left)
    fun cross_tick(
        pool: &mut Pool,
        tick: u32,
        fee_growth_global_0_x128: u256,
        fee_growth_global_1_x128: u256
    ): LiquidityNet {
        let info = table::borrow_mut(&mut pool.ticks, tick);
        info.fee_growth_outside_0_x128 = fee_growth_global_0_x128 - info.fee_growth_outside_0_x128;
        info.fee_growth_outside_1_x128 = fee_growth_global_1_x128 - info.fee_growth_outside_1_x128;
        info.liquidity_net
    }

    #[test_only]
    public fun create_test_pool(sqrt_price_x96: u256, lp_fee: u32, ctx: &mut TxContext): Pool {
        let mut pool = Pool {
            sqrt_price_x96: 0,
            tick: 0,
            fee_protocol: 0,
            lp_fee: 0,
            fee_growth_global_0_x128: 0,
            fee_growth_global_1_x128: 0,
            liquidity: 0,
            ticks: table::new<u32, TickInfo>(ctx),
            tick_bitmap: table::new<u32, u256>(ctx),
            positions: position::new(ctx)
        };
        let _ = initialize(&mut pool, sqrt_price_x96, lp_fee);
        pool
    }

    public fun get_sqrt_price_x96(pool: &Pool): u256 {
        pool.sqrt_price_x96
    }

    public fun get_fee_protocol(pool: &Pool): u8 {
        pool.fee_protocol
    }

    public fun get_tick(pool: &Pool): u32 {
        pool.tick
    }

    public fun get_lp_fee(pool: &Pool): u32 {
        pool.lp_fee
    }

    public fun get_liquidity(pool: &Pool): u128 {
        pool.liquidity
    }

    #[test_only]
    public fun get_swap_result_sqrt_price_x96(result: &SwapResult): u256 {
        result.sqrt_price_x96
    }

    #[test_only]
    public fun get_swap_result_tick(result: &SwapResult): u32 {
        result.tick
    }

    #[test_only]
    public fun get_swap_result_liquidity(result: &SwapResult): u128 {
        result.liquidity
    }

    // Test helper functions
    #[test_only]
    public fun create_test_modify_liquidity_params(
        owner: address,
        tick_lower: u32,
        tick_upper: u32,
        abs_liquidity_delta: u128,
        liquidity_delta_is_positive: bool,
        tick_spacing: u32,
        salt: vector<u8>
    ): ModifyLiquidityParams {
        ModifyLiquidityParams {
            owner,
            tick_lower,
            tick_upper,
            abs_liquidity_delta,
            liquidity_delta_is_positive,
            tick_spacing,
            salt
        }
    }

    #[test_only]
    public fun create_test_swap_params(
        amount_specified: u128,
        exact_output: bool,
        tick_spacing: u32,
        zero_for_one: bool,
        sqrt_price_limit_x96: u256,
        lp_fee_override: u32
    ): SwapParams {
        SwapParams {
            amount_specified,
            exact_output,
            tick_spacing,
            zero_for_one,
            sqrt_price_limit_x96,
            lp_fee_override
        }
    }

    #[test_only]
    public fun destroy_test_pool(pool: Pool) {
        let Pool { 
            sqrt_price_x96: _,
            tick: _,
            fee_protocol: _,
            lp_fee: _,
            fee_growth_global_0_x128: _,
            fee_growth_global_1_x128: _,
            liquidity: _,
            ticks,
            tick_bitmap,
            positions
        } = pool;
        table::drop(ticks);
        table::drop(tick_bitmap);
        position::destroy_test_position_manager(positions);
    }

    #[test_only]
    public fun get_swap_params_sqrt_price_limit_x96(params: &SwapParams): u256 {
        params.sqrt_price_limit_x96
    }

    #[test_only]
    public fun get_swap_params_amount_specified(params: &SwapParams): u128 {
        params.amount_specified
    }

    #[test_only]
    public fun get_swap_params_exact_output(params: &SwapParams): bool {
        params.exact_output
    }

    #[test_only]
    public fun get_swap_params_tick_spacing(params: &SwapParams): u32 {
        params.tick_spacing
    }

    #[test_only]
    public fun get_swap_params_zero_for_one(params: &SwapParams): bool {
        params.zero_for_one
    }

    #[test_only]
    public fun get_swap_params_lp_fee_override(params: &SwapParams): u32 {
        params.lp_fee_override
    }

    #[test_only]
    public fun get_modify_liquidity_params_owner(params: &ModifyLiquidityParams): address {
        params.owner
    }

    #[test_only]
    public fun get_modify_liquidity_params_tick_lower(params: &ModifyLiquidityParams): u32 {
        params.tick_lower
    }

    #[test_only]
    public fun get_modify_liquidity_params_tick_upper(params: &ModifyLiquidityParams): u32 {
        params.tick_upper
    }

    #[test_only]
    public fun get_modify_liquidity_params_abs_liquidity_delta(params: &ModifyLiquidityParams): u128 {
        params.abs_liquidity_delta
    }

    #[test_only]
    public fun get_modify_liquidity_params_liquidity_delta_is_positive(params: &ModifyLiquidityParams): bool {
        params.liquidity_delta_is_positive
    }

    #[test_only]
    public fun get_modify_liquidity_params_tick_spacing(params: &ModifyLiquidityParams): u32 {
        params.tick_spacing
    }

    #[test_only]
    public fun get_modify_liquidity_params_salt(params: &ModifyLiquidityParams): vector<u8> {
        params.salt
    }
}