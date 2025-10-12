<table>
    <tr><th></th><th></th></tr>
    <tr>
        <td><img src="./logo.png" width="250" height="250" /></td>
        <td>
            <h1>Avon Protocol Audit Report</h1>
            <h2>OrderBook and OrderBookFactory</h2>
            <p>Prepared by: alix40, Independent Security Researcher</p>
            <p>Date: 01.05.2025</p>
            <p>Commit: e3e2b6074faf68f5f2221e117f452a23061da105</p>
        </td>
    </tr>
</table>

## About **Avon**
Avon is a decentralized lending protocol that implements an orderbook-based system for matching lenders and borrowers. The core components include OrderbookFactory for creating and managing orderbooks, Orderbook for managing lending/borrowing orders using red-black trees, and Pool contracts implementing ERC-4626 for managing deposits, borrowing, and liquidations.

## About **Alix40**
Alix40 is a leading smart contract security researcher with over 200 high/medium severity findings across major DeFi protocols. Currently serving as a Lead Senior Watson at Sherlock, they have consistently ranked in the top 5 positions in 15+ competitive audit contests, specializing in lending protocols and complex financial primitives.
## Scope
Files in scope:
- src/Orderbook.sol
- src/OrderbookFactory.sol
- src/libraries/OrderbookLib.sol
- src/libraries/RedBlackTreeLib.sol

<div style="page-break-after: always;"></div>



## Summary of Findings
| ID     | Title                        | Fixed |
| ------ | ---------------------------- | ----- |
| [H-01] | Interest Rate Manipulation Attack on Limit Orders | ✓ |
| [M-01] | Pool Managers Can Block Pool Removal Through LTV Manipulation | ✓ |
| [M-02] | Incorrect Rate Casting in batchInsertOrder() Creates Rate Inconsistency | ✓ |
| [M-03] | Single Pool Manager Can Block All Borrowing | ✓ |
| [M-04] | Borrowers Could Be Locked in Very Unfavorable Loans Due to Dust Amounts | ✓ |
| [M-05] | Multiple Borrower Orders With Same Rate and LTV Can Lead to State Inconsistencies | ✓ |
| [M-06] | Suboptimal Order Matching Due to Timestamp-Based Sorting | ✓ |
| [M-07] | DOS Vector in batchInsertOrder Due to Lack of Minimum Amount Validation | ✓ |
| [M-08] | Lack of Order Uniqueness Enforcement in batchInsertOrder Can Lead to Uncleaned Orders | ✓ |
| [M-09] | Inconsistent Order Cleanup Due to External LTV Fetching | ✓ |
| [L-01] | IRM Whitelisting Not Continuously Enforced |  |
| [L-02] | Limit Orders Lack Expiration |  |
| [L-03] | No Fees for Limit Order Matching |  |
| [L-04] | Insufficient Slippage Protection in matchMarketBorrowOrder |  |
| [L-05] | Misleading Function Name _getBestLenderRate |  |
| [L-06] | Unused ltvs Parameter in batchInsertOrder |  |
| [L-07] | Inconsistent Orderbook ID Computation |  |
| [L-08] | OrderbookFactory IRM Whitelist Implementation Could Be Improved |  |
| [L-09] | Unused isLender Parameter in _matchOrder() |  |
| [L-10] | Unnecessary Complexity with borrowerTree Implementation |  |
| [L-11] | Non-Upgradeable Core Contracts May Limit Protocol Evolution |  |
| [L-12] | Potential Reentrancy in batchInsertOrder Function |  |

<div style="page-break-after: always;"></div>

## High Risk Findings

### [H-01] Interest Rate Manipulation Attack on Limit Orders

**Impact**: HIGH - Borrowers can be forced into loans with much higher interest rates than their specified limits

**Description**:
The permissionless nature of limit order matching allows attackers to manipulate interest rates and lock borrowers into unfavorable loans through flash loan attacks.

**Proof of Concept**:
1. Borrower creates a limit order at 7% interest rate
2. Current market rates in Pool A are ~70%
3. Attacker executes in single transaction:
   - Takes flash loan of debt tokens
   - Deposits large amount into Pool A
   - Temporarily drops pool's borrow rate below 7%
   - Pool updates rates via `batchInsertOrder()`
   - Calls `matchLimitBorrowOrder()` on borrower's order
   - Withdraws deposit and repays flash loan

**Recommended Mitigation**:
Add permission controls to `matchLimitBorrowOrder()` 

**Review**: Fixed in `1a52c0e41997d94cccab7964ace27323e9f5a35d`

## Medium Risk Findings

### [M-01] Pool Managers Can Block Pool Removal Through LTV Manipulation

**Impact**: MEDIUM - Malicious pool managers can prevent pool removal from orderbook

**Description**:
The `removePool()` function relies on calling `pool.getLTV()` which can be manipulated by pool managers to always revert:

```solidity
function removePool(address pool) external onlyOwner {
    if (pool == address(0)) revert ErrorsLib.ZeroAddress();
    if (!isWhitelisted[pool]) revert ErrorsLib.NotWhitelisted();
    isWhitelisted[pool] = false;
    _cancelPoolOrders(pool, IPoolImplementation(pool).getLTV());
    emit EventsLib.PoolRemoved(pool);
}
```

**Recommended Mitigation**:
1. Add a `forceRemovePool()` function that accepts LTV as parameter
2. Centralize LTV configuration in the orderbook contract

**Review**: Fixed in `459aa4fd74f23109dbd6a2aec071a97ff4397cdb`

### [M-02] Incorrect Rate Casting in batchInsertOrder() Creates Rate Inconsistency

**Impact**: MEDIUM - Can lead to users being locked in very high interest rate positions

**Description**:
When casting interest rates from uint256 to uint64 in `batchInsertOrder()`, large rates can overflow leading to much lower stored rates:

```solidity
function batchInsertOrder(uint256[] calldata irs, ...) {
    ...
    lenderTree._insertOrder(true, uint64(irs[i]), uint64(ltv), amounts[i]);
    poolOrders[msg.sender].push(irs[i]);
}
```

**Recommended Mitigation**:
Change function signature to accept uint64 arrays:
```solidity
function batchInsertOrder(uint64[] calldata irs, ...)
```

**Review**: Fixed in `0fd1a547462b1a8e1c6267de963ef5af2cce5b91`

### [M-03] Single Pool Manager Can Block All Borrowing

**Impact**: MEDIUM - A malicious pool manager can DOS all borrowing operations

**Description**:
A malicious pool manager can block all borrowing by making `previewBorrow()` revert:

```solidity
function _calculateAndSetPoolCollateral(
    PoolData[] memory poolData_,
    uint256 uniquePoolCount_,
    address borrower_,
    uint256 collateralBuffer_
) internal view returns (uint256 totalCollateral_) {
    for (uint256 i = 0; i < uniquePoolCount_; i++) {
        uint256 requiredCollateral = IPoolImplementation(poolData_[i].pool).previewBorrow(
            borrower_,
            poolData_[i].amount,
            collateralBuffer_
        );
```

**Recommended Mitigation**:
Add try-catch mechanism to skip failed previewBorrow calls.

**Review**: Fixed in `49adb9f86489a804dc7174fbe8c1a27bf7cb9da3`

### [M-04] Borrowers Could Be Locked in Very Unfavorable Loans Due to Dust Amounts

**Impact**: MEDIUM - Borrowers can be forced to maintain positions with dust amounts that cost more in gas fees than the borrowed amount itself

**Description**:
The protocol does not enforce minimum amounts for loans taken from multiple pools. This can result in borrowers being locked into borrow positions with dust amounts where the gas fees for managing the position (opening/closing) exceed the borrowed amount itself.

**Proof of Concept**:
```solidity
function testPoc6() public {
    // Setup pool with assets
    vm.startPrank(lender);
    loanToken.approve(address(pool), 500e18);
    loanToken.approve(address(pool2), 500e18);
    pool.deposit(100e18, lender);
    pool2.setBaseRate(1e18 + 2e17);
    pool2.deposit(100e18, lender);
    vm.stopPrank();

    uint256 amount = 100e18 + 1;
    uint256 minAmountExpected = 100e18;
    uint256 collateralBuffer = 0.05e18;
    
    // Preview and execute borrow
    (, , uint256 collateralRequired, ) = orderbook.previewBorrow(
        PreviewBorrowParams({
            borrower: borrower,
            amount: amount,
            collateralBuffer: collateralBuffer,
            rate: 0,
            ltv: 0,
            isMarketOrder: true,
            isCollateral: false
        })
    );

    vm.startPrank(borrower);
    collateralToken.approve(address(orderbook), collateralRequired);
    orderbook.matchMarketBorrowOrder(
        amount,
        minAmountExpected,
        collateralBuffer
    );
    vm.stopPrank();
}
```
Results show borrower taking 100e18 from pool1 and just 1 wei from pool2:
```log
Logs:
  Pool1 initial balance: 100000000000000000000
  Pool2 initial balance: 100000000000000000000
  Pool1 balance After: 0
  Pool2 balance After: 99999999999999999999
```
**Recommended Mitigation**:
Add a minimum amount check in `_processPoolMatches`:
```diff
function _processPoolMatches(
    PoolData[] memory pools,
    uint256 poolCount,
    address borrower,
    uint256 minAmountExpected
) internal returns (uint256 amountReceived) {
    IERC20 collateralToken = IERC20(orderbookConfig.collateral_token);

    for (uint256 i; i < poolCount; i++) {
        (address pool, uint256 poolAmount, uint256 collateral) =
            (pools[i].pool, pools[i].amount, pools[i].collateral);
+       if (pools[i].amount < DUST_AMOUNT) continue;
        // Approve and interact with pool
        collateralToken.safeIncreaseAllowance(pool, collateral);
        IPoolImplementation(pool).supplyCollateral(collateral, borrower);
        (uint256 assets,) = IPoolImplementation(pool).borrow(poolAmount, 0, borrower, borrower, 0);
        amountReceived += assets;
    }

    if (amountReceived < minAmountExpected) revert ErrorsLib.InsufficientAmountReceived();
    return amountReceived;
}
```

The suggested fix would skip any pool matches where the amount is below a defined dust threshold, preventing users from being locked into unfavorable micro-positions

**Review**: Acknowledged, but other fixes already mitigate this.

### [M-05] Multiple Borrower Orders With Same Rate and LTV Can Lead to State Inconsistencies

**Impact**: MEDIUM - Breaks a protocol invariant + leads dos in certain conditions

**Description**:
The protocol does not enforce uniqueness of rate and LTV combinations per borrower in `insertLimitBorrowOrder()`. This allows borrowers to submit multiple orders with the same parameters, which can lead to state inconsistencies in the borrower tree and incorrect amount tracking.

**Proof of Concept**:
```solidity
function testPoCinsertborrowerorderSameKey() public {
    // First place an order
    uint64 rate = 0.05e18;
    uint64 ltv = 0.7e18;
    uint256 amount = 100e18;
    uint256 minAmountExpected = 90e18;
    uint256 collateralBuffer = 0.05e18;
    uint256 collateralAmount = 150e18;
    
    vm.startPrank(borrower);
    collateralToken.approve(address(orderbook), collateralAmount);
    orderbook.insertLimitBorrowOrder(
        rate,
        ltv,
        amount,
        minAmountExpected,
        collateralBuffer,
        collateralAmount
    );

    // Can submit another order with same rate and LTV
    collateralToken.approve(address(orderbook), collateralAmount/3);
    orderbook.insertLimitBorrowOrder(
        rate,
        ltv,
        amount,
        minAmountExpected,
        collateralBuffer,
        collateralAmount/3
    );
    
    // Multiple orders exist with same parameters
    BorrowerLimitOrder[] memory borrowersOrders = orderbook.getBorrowerOrders(borrower);
    assertEq(borrowersOrders.length, 2);
}
```

**Recommended Mitigation**:
Enforce uniqueness of rate and LTV combinations per borrower in `insertLimitBorrowOrder()`.

**Review**: Fixed in `d1193c8ad0f98a66094de10149fc87c17d43b666`

### [M-06] Suboptimal Order Matching Due to Timestamp-Based Sorting

**Impact**: MEDIUM - Users can be forced into unfavorable interest rates due to inefficient liquidity matching

**Description**:
The `_heapifyUp` and `_heapifyDown` functions sort lending orders with the same composite key (same LTV and interest rate) based on timestamp instead of available liquidity. This can lead to suboptimal matching where smaller liquidity pools are matched first, potentially resulting in:
- Higher interest rate volatility
- Less efficient capital utilization
- Users being locked into unfavorable rates

**Proof of Concept**:
Consider a scenario with two pools sharing the same rate and LTV:
- Pool1: 5,000 USDC available liquidity
- Pool2: 50 USDC available liquidity

Current implementation matches based on timestamp, potentially leading to:
1. Pool2's small liquidity being matched first
2. Higher interest rate impact due to borrowing from smaller liquidity pools
3. Less efficient capital utilization across the protocol

For example, borrowing 1,000 USDC from:
- A 2M USDC pool: minimal interest rate impact
- A 20K USDC pool: significant interest rate impact

**Recommended Mitigation**:
Implement a max-heap based on order amount instead of timestamp:
- Sort lending orders primarily by available liquidity
- Prioritize matching with larger liquidity pools
- Reduce interest rate volatility during matching
- Improve capital efficiency across the protocol

**Review**: Fixed in `3706ead9a7b976869e810579e53a53d447e7c139`

### [M-07] DOS Vector in batchInsertOrder Due to Lack of Minimum Amount Validation and max order count

**Impact**: MEDIUM - Malicious pools can effectively block all borrowing operations through dust amount orders

**Description**:
The `batchInsertOrder()` function lacks minimum amount validation and maximum order count checks. This allows malicious pools to create multiple lending orders with dust amounts, which can be used to grief borrowers and effectively block borrowing operations due to the `MAX_MATCH_DETAILS` (30) limit.

**Proof of Concept**:
Attack scenario:
1. Malicious pool creates `MAX_MATCH_DETAILS` (30) lending orders with:
   - Amount = 1 wei each
   - Very low interest rates
   - High LTV (99%)
2. These orders will be matched first due to favorable rates
3. When a borrower attempts to borrow:
   - The `MAX_MATCH_DETAILS` limit is reached
   - The borrowed amount remains unfulfilled due to dust amounts
   - The borrowing transaction fails (or only borrows 30 wei)
4. If the pool reinserts these orders again after each `borrow()`, this creates a persistent DOS condition

**Recommended Mitigation**:
1. Implement minimum amount validation in `batchInsertOrder()`
2. Add maximum order count per pool
3. Consider implementing dust amount checks relative to the token decimals
```diff
    function batchInsertOrder(uint256[] calldata irs, uint256[] calldata ltvs, uint256[] calldata amounts)
        external
        whenNotPaused
    {
        uint256 length = irs.length;
        if (length != ltvs.length || length != amounts.length) revert ErrorsLib.InvalidInput();
        if (!isWhitelisted[msg.sender]) revert ErrorsLib.NotWhitelisted();
+        if (length > 10) revert ErrorsLib.MaxLengthError();
        uint256 ltv = IPoolImplementation(msg.sender).getLTV();
        _cancelPoolOrders(msg.sender, ltv);
        for (uint256 i; i < length; ++i) {
-            if (amounts[i] == 0) break;
+            if (amounts[i] < DUST) break;

            lenderTree._insertOrder(true, uint64(irs[i]), uint64(ltv), amounts[i]);
            poolOrders[msg.sender].push(irs[i]);
        }
    }
```
**Review**: Fixed in `49adb9f86489a804dc7174fbe8c1a27bf7cb9da3`
### [M-08] Lack of Order Uniqueness Enforcement in batchInsertOrder Can Lead to Uncleaned Orders

**Impact**: MEDIUM - Orders with duplicate rates may not be properly cleaned up, leading to state inconsistencies and potential fund locks

**Description**:
The `batchInsertOrder()` function doesn't enforce uniqueness among lending orders with the same rate. This creates an issue in `_cancelPoolOrders()` which assumes a single order per rate and breaks after finding the first match, potentially leaving duplicate orders uncleaned.

```solidity
function _cancelPoolOrders(address pool, uint256 ltv) internal {
    // ... 
    for (uint256 j; j < entryCount; ++j) {
        RedBlackTreeLib.Entry storage entry = RedBlackTreeLib.getEntryAt(lenderTree, compositeKey, j);
        if (entry.account == pool) {
            lenderTree._cancelOrder(true, compositeKey, j);
            break; //As for a particular ir and ltv the pool can have only one order
        }
    }
}
```

The break statement assumes there can only be one order per interest rate and LTV combination, but this isn't enforced in `batchInsertOrder()`.

**Proof of Concept**:
1. Pool creates multiple orders with same interest rate via `batchInsertOrder()`
2. When `_cancelPoolOrders()` is called, it only cancels the first matching order
3. Remaining duplicate orders are left in the system, creating state inconsistencies

**Recommended Mitigation**:
Enforce order uniqueness in `batchInsertOrder()` by requiring ascending rate order:
```diff
function batchInsertOrder(uint256[] calldata irs, uint256[] calldata ltvs, uint256[] calldata amounts)
    external
    whenNotPaused
{
    uint256 length = irs.length;
    if (length != ltvs.length || length != amounts.length) revert ErrorsLib.InvalidInput();
    if (!isWhitelisted[msg.sender]) revert ErrorsLib.NotWhitelisted();
    uint256 ltv = IPoolImplementation(msg.sender).getLTV();
    _cancelPoolOrders(msg.sender, ltv);
    for (uint256 i; i < length; ++i) {
        if (amounts[i] == 0) break;
+       if (length > i+1 && irs[i+1] <= irs[i]) revert OrdersNotOrdered();
        lenderTree._insertOrder(true, uint64(irs[i]), uint64(ltv), amounts[i]);
        poolOrders[msg.sender].push(irs[i]);
    }
}
```

**Review**: Fixed in `191688adef40e6d95fa07c9fadbf45c9937a0748`

### [M-09] Inconsistent Order Cleanup Due to External LTV Fetching

**Impact**: MEDIUM - Inconsistent lenderTree state and leftover lending orders after pool removal due to LTV changes

**Description**:
The Orderbook contract fetches LTV values directly from pools when removing or inserting new lending order batches, rather than tracking them internally. If a pool changes its LTV and had existing lending orders, some orders might not be properly cleaned up during `_cancelPoolOrders()` execution.

```solidity
function removePool(address pool) external onlyOwner {
    if (pool == address(0)) revert ErrorsLib.ZeroAddress();
    if (!isWhitelisted[pool]) revert ErrorsLib.NotWhitelisted();
    isWhitelisted[pool] = false;
    // @audit fetches LTV directly from pool
    _cancelPoolOrders(pool, IPoolImplementation(pool).getLTV());
    emit EventsLib.PoolRemoved(pool);
}
```

This creates a risk where:
1. Pool creates lending orders with LTV1
2. Pool changes its LTV to LTV2
3. When removing the pool or inserting new orders, the cleanup uses LTV2
4. Orders created with LTV1 remain in the system

**Recommended Mitigation**:
Track the last used LTV internally for each pool:

```diff
+ mapping(address => uint64) public lastUsedLtvs;

function removePool(address pool) external onlyOwner {
    if (pool == address(0)) revert ErrorsLib.ZeroAddress();
    if (!isWhitelisted[pool]) revert ErrorsLib.NotWhitelisted();
    isWhitelisted[pool] = false;
-   _cancelPoolOrders(pool, IPoolImplementation(pool).getLTV());
+   _cancelPoolOrders(pool, lastUsedLtvs[pool]);
    emit EventsLib.PoolRemoved(pool);
}
function removePool(address pool) external onlyOwner {
        if (pool == address(0)) revert ErrorsLib.ZeroAddress();
        if (!isWhitelisted[pool]) revert ErrorsLib.NotWhitelisted();

        isWhitelisted[pool] = false;

-        _cancelPoolOrders(pool, IPoolImplementation(pool).getLTV());
+   _cancelPoolOrders(pool, lastUsedLtvs[pool]);

        emit EventsLib.PoolRemoved(pool);
    }

```

This ensures order cleanup uses the same LTV value that was used when creating the orders, maintaining system consistency.

**Review**: Fixed in `49adb9f86489a804dc7174fbe8c1a27bf7cb9da3`

## QA Findings

### [L-01] IRM Whitelisting Not Continuously Enforced

**Description**:
IRM validation only occurs during pool whitelisting. This allows pools to potentially change to non-whitelisted IRMs after the initial validation, bypassing the intended security checks.

**Recommended Mitigation**:
Add continuous IRM validation checks during key operations or implement a mechanism to prevent pools from changing to non-whitelisted IRMs.


### [L-02] Limit Orders Lack Expiration

**Description**:
`insertLimitBorrowOrder()` and `matchMarketBorrowOrder()` don't include expiration timestamps. This could lead to stale orders being executed, particularly problematic in cases of:
- Sequencer downtime
- Stalled transactions in mempool
- Network congestion

**Recommended Mitigation**:
Add a deadline parameter to both functions:
- `insertLimitBorrowOrder()`
- `matchMarketBorrowOrder()`

This would allow orders to automatically expire if not executed within a specified timeframe, protecting users from unfavorable market conditions during network issues.

### [L-03] No Fees for Limit Order Matching

**Description**:
The protocol doesn't implement any fee mechanism for actors (likely bots) responsible for matching limit orders. This could lead to DOS vectors where malicious actors create multiple small limit orders, passing the cost burden to the protocol.

**Recommended Mitigation**:
- Add a small fee in gas tokens for limit order matching operations
- Implement minimum order size requirements to prevent spam
- Consider incentive mechanisms to ensure efficient order matching
  
### [L-04] Insufficient Slippage Protection in matchMarketBorrowOrder

**Description**:
The `matchMarketBorrowOrder` function's slippage protection parameters are incomplete:
```solidity
function matchMarketBorrowOrder(
    uint256 amount, 
    uint256 minAmountExpected, 
    uint256 collateralBuffer
)
```
While it includes `minAmountExpected`, it lacks crucial parameters like maximum collateral amount or minimum LTV, which could lead to unfavorable trade execution in volatile market conditions.

**Recommended Mitigation**:
Add additional slippage protection parameters (1 of the two bellow):
- `maxCollateralAmount`: Upper bound for required collateral
- `minLTV`: Minimum acceptable LTV ratio

### [L-05] Misleading Function Name _getBestLenderRate

**Description**:
The function `_getBestLenderRate` actually returns the highest (worst) lending rate rather than the best rate for lenders, making the name misleading and potentially confusing for developers.

**Recommended Mitigation**:
Rename the function to `_getHighestLenderRate()` to better reflect its actual functionality.

### [L-06] Unused ltvs Parameter in batchInsertOrder

**Description**:
The `ltvs` parameter in `batchInsertOrder()` is required in the function signature but is never used in the function implementation, creating unnecessary complexity.

**Recommended Mitigation**:
Remove the unused `ltvs` parameter from the function signature or implement its intended functionality if it was meant to be used.

### [L-07] Inconsistent Orderbook ID Computation

**Description**:
The `createOrderbook` function computes the orderbook ID directly instead of using the existing `_getOrderbookId()` function, creating inconsistency in ID computation across the codebase.

**Recommended Mitigation**:
Use the dedicated `_getOrderbookId()` function for consistency:
```diff
function createOrderbook(address _loanToken, address _collateralToken, address[] calldata _poolMakers)
--  bytes32 orderbookId = keccak256(abi.encode(_loanToken, _collateralToken));
++  bytes32 orderbookId = _getOrderbookId(_loanToken, _collateralToken);
```

### [L-08] OrderbookFactory IRM Whitelist Implementation Could Be Improved

**Description**:
The OrderbookFactory uses a simple mapping for IRM whitelist management:
```solidity
mapping(address => bool) public isIRMEnabled;
```
Given that the contract is not upgradeable, this implementation limits the ability to efficiently track and manage whitelisted IRMs.

**Recommended Mitigation**:
Use OpenZeppelin's EnumerableSet library.

### [L-09] Unused isLender Parameter in _matchOrder()

**Description**:
The `_matchOrder()` function includes an `isLender` parameter, but throughout the codebase, this parameter is only ever called with `false`. For example:
```solidity
MatchedOrder memory matchedOrder = lenderTree._matchOrder(false, rate, ltv, amount);
```
Having unused code paths increases codebase complexity 

**Recommended Mitigation**:
Remove the `isLender` parameter from the `_matchOrder()` function and simplify the implementation to only handle the actually used case.

### [L-10] Unnecessary Complexity with borrowerTree Implementation

**Description**:
The borrower tree data structure, unlike the lender tree, is not utilized in any matching logic. Storing limit borrower orders in a tree structure adds unnecessary complexity to the codebase when a simpler solution would suffice.

**Recommended Mitigation**:
Simplify the implementation by:
- Remove the borrower tree data structure
- Store borrow orders in a simple mapping
- Use off-chain infrastructure for sorting and managing borrow limit orders

This would reduce code complexity and gas costs while maintaining the same functionality.

### [L-11] Non-Upgradeable Core Contracts May Limit Protocol Evolution

**Description**:
Both user-facing contracts in Avon (`Orderbook` and `OrderbookFactory`) are not upgradeable. Any required changes or improvements to these core contracts would necessitate deploying new instances of both contracts, which could lead to:
- Protocol fragmentation
- Migration complexity
- User coordination challenges
- Potential liquidity fragmentation

**Recommended Mitigation**:
Consider implementing upgrade mechanisms. 

### [L-12] Potential Reentrancy in batchInsertOrder Function

**Description**:
The `batchInsertOrder()` function lacks reentrancy protection. While it's designed to be called by pools after borrow operations, this creates a potential reentrancy vector through the `getLTV()` call:

```solidity
function batchInsertOrder(uint256[] calldata irs, uint256[] calldata ltvs, uint256[] calldata amounts)
    external
    whenNotPaused
{
    uint256 length = irs.length;
    if (length != ltvs.length || length != amounts.length) revert ErrorsLib.InvalidInput();
    if (!isWhitelisted[msg.sender]) revert ErrorsLib.NotWhitelisted();
    // @audit reentrancy possible here
@>>    uint256 ltv = IPoolImplementation(msg.sender).getLTV();
    _cancelPoolOrders(msg.sender, ltv);
}
```

While no significant exploits have been identified (hence the low severity), adding reentrancy protection would follow best practices for security.

**Recommended Mitigation**:
Add a dedicated reentrancy guard for this function:

```diff
+   modifier isBatchOrderInserted() {
+       if (batchOrderInserted) revert Reentrancy();
+       batchOrderInserted = true;
+       _;
+       batchOrderInserted = false;
+   }

    function batchInsertOrder(uint256[] calldata irs, uint256[] calldata ltvs, uint256[] calldata amounts)
        external
        whenNotPaused
+       isBatchOrderInserted
    {
        // ... existing implementation
    }
```


