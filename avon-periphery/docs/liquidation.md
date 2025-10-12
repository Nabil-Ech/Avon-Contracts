Avon lets pool managers set liquidation bonus, soft range, and soft seize cap at the time of pool creation. These liquidation parameters need to be within protocol-defined bounds if they've to be updated, defined [here.](../src/pool/utils/PoolConstants.sol)

- These bounds can be set at the time of pool factory deployment. They're constant so can't be changed after that.

- Soft Range: If the health score is only slightly below the threshold, a flat bonus is applied, and the amount of collateral that can be seized is capped.

- Hard Range: If the health score is far below the threshold, the bonus increases quadratically, and the full collateral can be seized.

- Liquidation bonus in soft range can be set to any value between `MIN_LIQ_BONUS` and `MAX_SOFT_RANGE_LIQ_BONUS`.

- Liquidation bonus in hard range will remain between `MIN_LIQ_BONUS` and `MAX_LIQ_BONUS`. We use a smooth quadratic scaling for the bonus factor calculation in hard range.


# Liquidation Params

| Param Name                | Value         | Human Readable Value | Purpose                                                         |
|---------------------------|--------------|-----------------------|-----------------------------------------------------------------|
| MIN_LIQ_BONUS             | 1.03e18      | 3%                    | Minimum liquidation bonus allowed for pool managers             |
| MAX_SOFT_RANGE_LIQ_BONUS  | 1.1e18       | 10%                   | Maximum bonus for liquidations within the soft range            |
| MAX_LIQ_BONUS             | 1.15e18      | 15%                   | Maximum liquidation bonus allowed                               |
| MIN_SOFT_RANGE            | 0.03e18      | 3% underwater         | Minimum soft range threshold for liquidations                   |
| MAX_SOFT_RANGE            | 0.07e18      | 7%                    | Maximum soft range threshold for liquidations                   |
| MIN_SOFT_SEIZE_CAP        | 0.1e18       | 10%                   | Minimum cap on assets seized in soft liquidations               |
| MAX_SOFT_SEIZE_CAP        | 0.5e18       | 50%                   | Maximum cap on assets seized in soft liquidations               |

Notes

- All values use WAD (1e18) fixed-point scaling.
- Examples: `1.03e18` corresponds to a 3% liquidation bonus, and `0.03e18` corresponds to a 3% soft range.

# Liquidation Auctions
- Avon strategy managers have the ability to integrate auction services to determine auction-driven liquidation bonuses in real-time.
- Auction-driven liquidation bonuses are effective immediately but persist only for a single transaction. Due to the transient nature of auction-driven liquidation bonus updates, positions can be liquidated at any-time outside of auction transactions at the current persistent liquidation bonus; preserving a non-auction liquidation path that cannot be affected by the auction.

From a high-level this mechanism is replacing gas-price priority for Avon liquidations with a new ordering rule where liquidators are ordered by lowest liquidation bonus bid first. Example ordering of liquidators within a single auction transaction:

1. Liquidator A: 1% bonus.
2. Liquidator C: 1.5% bonus.
3. Liquidator B: 2% bonus.

Liquidators place bids off-chain in the form of the liquidation bonus that would be acceptable to them. These bids are then gathered by the off-chain auctioneer, and ordered by lowest liquidation bonus bids first. The <auction_contract> on-chain then executes each liquidator in that pre-defined order; and prior to each liquidator executing, the <auction_contract> modifies the liquidation bonus within the Avon Pool to that given liquidators bid. Every liquidator included in the auction transaction will have a chance to execute. If one of the liquidator’s execution fails, the smart contract catches this failure and executes the next liquidator.

The off-chain auctioneer infrastructure will constantly host auctions on a defined cadence such as once per block. If a new oracle update exists for that block, that oracle update will be auctioned off. If an oracle update for that block does not exist, the auction will be hosted without an oracle update to allow for interest-triggered liquidations to be captured.

## Auction Priority Mechanisms
1. Atomically executing liquidations in the same transaction as oracle updates before non-auction liquidators can act on the oracle update. This priority mechanism must live externally, and is implemented by the oracle whitelisting the <auction_contract> as a valid updater of the given data feed referenced by the AvonPool. 
2. An early liquidation threshold provided to auction-based liquidations (maximum of 10bps) over non-auction liquidations. This priority only applies to SOFT_RANGE liquidations.

## Auction Role
Responsibility: The sole ability for `AUCTION_ROLE` holders within Avon is to update the transient liquidation bonus.

### Role Management
Pool managers can control which addresses have permission to perform transient liquidation bonus updates through the `AUCTION_ROLE`.

- `AUCTION_ROLE` should be given to an immutable <auction_contract>.
- The `PROPOSER_ROLE` is set as the admin for the `AUCTION_ROLE` via `_setRoleAdmin(AUCTION_ROLE, PROPOSER_ROLE)` being called in the `AvonPool` constructor. The `PROPOSER_ROLE` will only be held by the orderbook owner and the `AvonPool` itself. 
- Pool managers and `PROPOSER_ROLE` control the `AUCTION_ROLE` without timelocks using wrapper functions within `AvonPool`:
  - `grantAuctionRole(address account)` - Grant auction permissions to an address.
  - `revokeAuctionRole(address account)` - Remove auction permissions from an address.
- Multiple addresses may hold the `AUCTION_ROLE`.

## Auction Priority Window (Early Liquidation Threshold Mechanism)
`uint256 auctionPriorityWindow` (WAD-scaled basis points) offers strategy managers the ability to provide auction-based liquidations with a maximum of a 10 basis points earlier liquidation threshold than default (non-auction) liquidations. It's functionality is to:
1. Determine if the given AvonPool should provide an auction service with priority access to liquidations via a liquidation threshold earlier than non-auction liquidations (setting any non-zero value for `auctionPriorityWindow` provides priority).
2. Determine the exact priority given to auction liquidations based on the value `auctionPriorityWindow` is set to (a maximum of 10 basis points).

If auctionPriorityWindow is set to 0, both auctions and non-auction liquidations have the same liquidation threshold.
When auctionPriorityWindow is > 0, only auction liquidations are allowed while the position’s health score is in (1.0 - auctionPriorityWindow, 1.0). At or below 1.0 - auctionPriorityWindow, regular (non-auction) liquidations proceed as normal.

- An "auction liquidation" is any liquidation occurring within a transaction where `updateTransientLiquidationBonus()` has set a non-zero transient bonus for the given pool (the transient bonus is per-transaction and must be set in the same transaction as the liquidation by an address with `AUCTION_ROLE`).
- `MAX_AUCTION_PRIORITY_WINDOW` in `PoolConstants` is set to 10 basis points WAD-scaled (0.001e18) and is used as the maximum `auctionPriorityWindow` that can be awarded to auction liquidations over non-auction liquidations. `auctionPriorityWindow` values are validated to be less than or equal to `MAX_AUCTION_PRIORITY_WINDOW` at both pool deployment time, and whenever the variable is re-configured.
- The Pool Manager can modify the `auctionPriorityWindow` variable without timelocks using `configureAuctionPriorityWindow`. This mirrors the ability for Pool Manager to grant or revoke `AUCTION_ROLE` without timelocks, and enables the auction mechanism to be quickly disabled if any issues are detected (by setting `auctionPriorityWindow` to 0).
- The cap (10 basis points) is intentionally small relative to realistic interest accrual dynamics across common IRMs, so it prioritizes interest-triggered liquidations without materially affecting price-move liquidations. Strategy managers should size `auctionPriorityWindow` conservatively for their IRM.
- The window is strictly less than the soft band, so the mechanism does not change liquidation economics, only priority within that thin health score region.

### Priority Window Enforcement
- Window Size: Restricted interval is (1.0 − `auctionPriorityWindow`, 1.0)” and “lower boundary inclusive via `diff <= auctionPriorityWindow`; 1.0 excluded by `HealthyPosition`.
- Enforcement: Regular (non-auction) liquidations are reverted within this window only when `s.auctionPriorityWindow > 0`. As soon as the position health score falls outside of this window, regular liquidations are possible at the persistent bonus.

Implementation Notes
All of the following validations occur within this LOC in the _liquidate() function:

```
if (s.auctionPriorityWindow > 0 && transientBonus == 0 && diff <= s.auctionPriorityWindow) {
            revert PoolErrors.NonAuctionLiquidationWithinAuctionPriorityWindow();
}
```
1. `s.auctionPriorityWindow > 0` is the first validation. If false, this LOC is bypassed and the liquidation flow works as normal where everyone has access to the same liquidation threshold.
2. `transientBonus == 0` is the second validation and is used as a way to determine whether the liquidation is a part of a valid auction transaction. If this returns true, this is not a valid auction transaction as it means no one has called updateTransientLiquidationBonus() with valid inputs during this transaction.
3. The window size is enforced by reusing the diff variable (which measures distance from healthy threshold) that is used to determine soft vs. hard range.

## Transient Liquidation Bonus Updates
- `updateTransientLiquidationBonus()` stores the new liquidation bonus in transient storage to ensure it cannot persist past the scope of a single transaction.
- `updateTransientLiquidationBonus()` is gated only to `AUCTION_ROLE`.
- The transient storage slot lives within `PoolStorage`, and uses internal helper functions in `PoolStorage` (`getTransientLiquidationBonus()` and `setTransientLiquidationBonus()`) to set and get this transient value. Using transient storage enables the EVM to natively guarantee that the dynamic liquidation bonus will revert to the application default as soon as the auction transaction has completed. This prevents the <auction_contract> from leaving the liquidation bonus at a low value and this persisting, impacting non-auction liquidations. This ensures that any transaction outside of an <auction_contract> transaction will be offered the default liquidation bonus, and that the auction system cannot permanently affect pool liquidation economics.
- Calls to `updateTransientLiquidationBonus()` are not timelocked.
- `updateTransientLiquidationBonus()` enforces the following:
1. The new transient bonus must be greater than WAD (1e18).
2. The new transient bonus must be less than the current persistent bonus.
3. The new transient bonus must be greater than or equal to the previous transient bonus if one exists.

## Use of Transient Liquidation Bonuses

The `_liquidate()` function will now retrieve the transient liquidation bonus prior to calculating the offered liquidation bonus.
- If `PoolStorage.getTransientLiquidationBonus()` returns 0, this indicates to the pool that this is not an auction transaction, and the pool should offer default liquidation bonus values using `s.liquidationBonus`.
- If `PoolStorage.getTransientLiquidationBonus()` returns a non-zero value, this indicates to the pool that this is a valid auction transaction, and the pool should use the transient liquidation bonus value for both soft and hard range calculations.

- By changing the parameters between calls, the <auction_contract> can enforce an application-defined priority order. Example ordering of liquidators within a single transaction (values are WAD (1e18 = 100%)):
updateTransientLiquidationBonus(1.01) → Liquidator A executes.
updateTransientLiquidationBonus(1.02) → Liquidator B executes.
updateTransientLiquidationBonus(1.025) → Liquidator C executes.

Notes

In the hard range, since the transient bonus must be strictly less than `s.liquidationBonus`, auction liquidations can only reduce and in the deep-hard limit, at most match the effective liquidation bonus for the same position state; they can never exceed the regular liquidation bonus.

## Data Feed Requirements

This service can build seamlessly on existing oracle data feeds implementations by providing each `AvonPool` with it’s own unique data feed. Each `AvonPool` must only read from their own unique data feed. Each `AvonPool` will also require a unique <auction_contract> that will be authorized as an updater only for this unique data feed, and only added as an authorized updater of the liquidation bonus for the given `AvonPool` associated with the data feed. This results in successfully isolating auctions triggered by an ETH/USD feed that cause liquidations on both an ETH/USDC pool and an ETH/BTC pool; or isolating auctions between an ETH/USD pool operated by Curator A and an ETH/USD pool operated by Curator B.

## Full Flow Example

**---------- OFF-CHAIN--------------**

1. The oracle generates a new price update, signs this price update in a tamper-proof way, and sends it to the off-chain auctioneer.
2. Off-chain auctioneer packs this price update into a `UserOperation`, and broadcasts the price of the data feed update to all liquidators connected to the websocket.
3. Liquidators respond with signed `SolverOperations` which contain: the bonus bid, the contract the liquidator wishes Atlas to delegateCall, and the necessary calldata with which to delegateCall the provided contract.
Liquidator A responds with a signed bid of .5% bonus.
Liquidator B responds with a signed bid of .7% bonus.
Liquidator C responds with a signed bid of .2% bonus.
4. Off-chain auctioneer orders the liquidators by lowest bonus first, and signs this ordering in a `DappOperation` using the auctioneer private key such that the ordering cannot change.
**Ordering**:
1. Liquidator C.
2. Liquidator A.
3. Liquidator B.
5. The off-chain auctioneer now takes the `UserOperation`, the `DappOperation`, and all three liquidators `SolverOperations`; and uses them to build a single Atlas transaction to be used by the `AuctionContract` to finally settle the auction on-chain.
6. The off-chain auctioneer then propagates this Atlas transaction to the chain.

**---------- ON-CHAIN--------------**

The following all happens in the single Auction transaction:

1. `UserOperation Hook`: `AuctionContract` performs data feed update.

---------Now for each liquidator, both a `PreSolver` and `SolverOp` hook are executed-------
**Liquidator C:**

1. `PreSolver` Hook: <auction_contract> sets the transient bonus on the pool to Liquidator Cs bid (.2%).
2. `SolverOp` Hook: <auction_contract> delegate calls out to Liquidator C contract using the calldata they provided. Lets imagine for some reason Liquidator C fails to liquidate.

**Liquidator A:**

1. `PreSolver` Hook: <auction_contract> sets the transient bonus on the pool to Liquidator As bid (.5%).
2. `SolverOp` Hook: <auction_contract> delegate calls out to Liquidator A using the calldata they provided. Lets imagine Liquidator A liquidates all unhealthy positions on the pool.

**Liquidator B:**

1. `PreSolver` Hook: <auction_contract> sets the transient bonus on the pool to Liquidator Bs bid (.7%).
2. `SolverOp` Hook: <auction_contract> delegate calls out to Liquidator B using the calldata they provided. In this case Liquidator B will simply revert early once they detect no liquidations are available.

**---------- Post-Auction-Transaction--------------**

1. Transaction concludes, transient bonus resets to 0, anyone may now call liquidate and access the persistent liquidation bonus.

## Auction Integration Steps

**Auction Operator Responsibilities**

The Auction Operator will perform the following when a strategy manager chooses to integrate the service.

1. Supply a unique data feed for the given `AvonPool` to utilize. This will result in totally independent auctions per `AvonPool`.
2. Deploy a unique <auction_contract> for the given pool that is authorized as an updater for this pool's unique data feed. 

**Strategy Manager Responsibilities**

The Strategy Manager must then do the following only once the above tasks are completed by the auction operator:

1. Utilize the provided unique data feed for the given `AvonPool`.
2. Provide the <auction_contract> with  `AUCTION_ROLE` for the given `AvonPool`. 
3. Choose one of the two configurations of the service using the `grantAuctionRole(address account)` and `configureAuctionPriorityWindow()` functions available to `PROPOSER_ROLE`:
- Grant `AUCTION_ROLE` with `auctionPriorityWindow = 0`: Auctions have priority to oracle triggered liquidations but not interest triggered liquidations.
- Grant `AUCTION_ROLE` with `auctionPriorityWindow > 0`: Auctions have priority to both oracle triggered liquidations and interest triggered liquidations.

## Guide for Strategy Managers

- The strategy manager should only grant an `AUCTION_ROLE` to an `<auction_contract>` that has already been whitelisted as an updater of the data feed referenced by the `AvonPool`.
- The strategy manager should NEVER set `auctionPriorityWindow > 0` when no party holds the `AUCTION_ROLE`.
- To disable auctions, the `PROPOSER_ROLE` holder can revoke the role via `revokeAuctionRole(address account)`.
- If the auction system suffers downtime, strategy managers can act quickly by setting `auctionPriorityWindow` to 0 without any timelock.
- `configureAuctionPriorityWindow()` should only be called rarely such as emergencies with auction operation, or when the IRM is modified.

# Further Information On Auction System
More information on the auction contract and system itself can be found in [atlas-auctions.md](./atlas-auctions.md)
