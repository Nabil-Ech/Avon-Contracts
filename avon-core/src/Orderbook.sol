// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {OrderbookLib} from "./libraries/OrderbookLib.sol";
import {AugmentedRedBlackTreeLib} from "./libraries/AugmentedRedBlackTreeLib.sol";
import {MathLib, WAD} from "./libraries/MathLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {IPoolFactory} from "./interface/IPoolFactory.sol";
import {IOrderbookFactory} from "./interface/IOrderbookFactory.sol";
import {IPoolImplementation} from "./interface/IPoolImplementation.sol";
import {
    MatchedOrder,
    OrderbookConfig,
    TreeState,
    PreviewMatchedOrder,
    PreviewBorrowParams,
    PoolData,
    BorrowerLimitOrder
} from "./interface/Types.sol";

/// @title OrderbookStorage
/// @author Avon Labs
/// @notice This contract is used to store the state of the orderbook
contract OrderbookStorage {
    address public ORDERBOOK_FACTORY;
    OrderbookConfig public orderbookConfig;

    /// @dev Red-black tree structure storing lender orders
    AugmentedRedBlackTreeLib.Tree internal lenderTree;

    /// @dev Red-black tree structure storing borrower orders
    AugmentedRedBlackTreeLib.Tree internal borrowerTree;

    /// @dev Maximum number of limit orders a borrower can have at once
    uint16 public constant MAX_LIMIT_ORDERS = 10;

    /// @dev Array of all whitelisted pools
    address[] public whitelistedPools;

    address public newOrderbook;

    /// @dev Address that receives matching fees
    address public feeRecipient;

    /// @dev Flat matching fee amount in loan token
    uint256 public flatMatchingFee;

    mapping(address => bool) public isWhitelisted;
    mapping(address => uint256[]) public poolOrders;
    mapping(address => BorrowerLimitOrder[]) public borrowersOrders;
}

/// @title Orderbook
/// @author Avon Labs
/// @notice This is the core contract for the orderbook
contract Orderbook is OrderbookStorage, Ownable2Step, Pausable, ReentrancyGuard {
    using OrderbookLib for AugmentedRedBlackTreeLib.Tree;
    using SafeERC20 for IERC20;
    using MathLib for uint256;

    constructor(address _loanToken, address _collateralToken, address _owner, address _feeRecipient) Ownable(_owner) {
        if (
            _owner == address(0) || _loanToken == address(0) || _collateralToken == address(0)
                || _feeRecipient == address(0)
        ) {
            revert ErrorsLib.ZeroAddress();
        }

        orderbookConfig.loan_token = _loanToken;
        orderbookConfig.collateral_token = _collateralToken;
        feeRecipient = _feeRecipient;
        ORDERBOOK_FACTORY = msg.sender;

        orderbookConfig.creationNonce++;
    }

    /// @notice Sets the fee recipient address
    /// @param _feeRecipient The address that will receive matching fees
    /// @dev Only the owner can set the fee recipient address
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) revert ErrorsLib.ZeroAddress();
        feeRecipient = _feeRecipient;
        emit EventsLib.FeeRecipientSet(_feeRecipient);
    }

    /// @notice Sets the flat matching fee amount
    /// @param _flatMatchingFee The flat fee amount in collateral token
    /// @dev Only the owner can set the flat matching fee
    function setFlatMatchingFee(uint256 _flatMatchingFee) external onlyOwner {
        flatMatchingFee = _flatMatchingFee;
        emit EventsLib.FlatMatchingFeeSet(_flatMatchingFee);
    }

    /// @notice Sets the new orderbook address
    /// @param _newOrderbook The address of the new orderbook
    /// @dev Only the owner can set the new orderbook address
    /// This is used to update the orderbook address so that pools can migrate to a new orderbook
    function setNewOrderbook(address _newOrderbook) external onlyOwner {
        newOrderbook = _newOrderbook;
        emit EventsLib.NewOrderbookSet(_newOrderbook);
    }

    /// @notice Whitelists a pool for orderbook operations
    /// @param pool The address of the pool to whitelist
    /// @param poolFactory The address of the pool factory that created the pool
    /// @dev Pool manager can whitelist their pools for the orderbook
    /// Pools must use an enabled IRM
    function whitelistPool(address pool, address poolFactory) external {
        if (pool == address(0)) revert ErrorsLib.ZeroAddress();
        if (!IOrderbookFactory(ORDERBOOK_FACTORY).isPoolManager(msg.sender)) revert ErrorsLib.NotPoolManager();

        if (!IOrderbookFactory(ORDERBOOK_FACTORY).isIRMEnabled(IPoolImplementation(pool).getIRM())) {
            revert ErrorsLib.IRMNotEnabled();
        }

        if (!IOrderbookFactory(ORDERBOOK_FACTORY).isPoolFactory(poolFactory)) revert ErrorsLib.NotPoolFactory();
        if (!IPoolFactory(poolFactory).isValidPool(pool)) revert ErrorsLib.NotValidPool();

        if (isWhitelisted[pool]) revert ErrorsLib.AlreadySet();

        isWhitelisted[pool] = true;
        whitelistedPools.push(pool);

        emit EventsLib.PoolWhitelisted(pool);
    }

    /// @notice Removes a pool from the whitelist
    /// @param pool The address of the pool to remove from the whitelist
    /// @dev Only owner can remove pools from the whitelist
    /// This is used to prevent malicious pools from breaking the orderbook functionality
    /// @dev This function also cancels all orders associated with the pool
    function removePool(address pool) external onlyOwner {
        if (pool == address(0)) revert ErrorsLib.ZeroAddress();
        if (!isWhitelisted[pool]) revert ErrorsLib.NotWhitelisted();

        isWhitelisted[pool] = false;
        _removePoolFromArray(pool);

        _cancelPoolOrders(pool, IPoolImplementation(pool).getLTV());

        emit EventsLib.PoolRemoved(pool);
    }

    /// @notice Forcefully removes a pool from the whitelist
    /// @param pool The address of the pool to remove from the whitelist
    /// @param ltv The pool's current LTV, used to locate and cancel its orders
    /// @dev Only owner can remove pools from the whitelist
    function forceRemovePool(address pool, uint64 ltv) external onlyOwner {
        if (pool == address(0)) revert ErrorsLib.ZeroAddress();
        if (!isWhitelisted[pool]) revert ErrorsLib.NotWhitelisted();

        isWhitelisted[pool] = false;
        _removePoolFromArray(pool);

        _cancelPoolOrders(pool, ltv);
        emit EventsLib.PoolRemoved(pool);
    }

    /// @notice Batch insert lenders(pools) orders into the orderbook
    /// @param irs Array of interest rates for each order (in yearly rate per second)
    /// @param amounts Array of token amounts for each order
    /// @dev This function allows whitelisted pools to insert their orders in the orderbook
    /// @dev The function will cancel all previous orders for the pool because as the liquidity changes the orders will be
    /// Updated by the pool and the previous orders will become invalid
    function batchInsertOrder(uint64[] calldata irs, uint256[] calldata amounts) external whenNotPaused {
        uint256 length = irs.length;
        if (length != amounts.length) revert ErrorsLib.InvalidInput();

        if (!isWhitelisted[msg.sender]) revert ErrorsLib.NotWhitelisted();

        //Max LTV for pool can be 99% or 0.99e18
        uint256 ltv = IPoolImplementation(msg.sender).getLTV();
        _cancelPoolOrders(msg.sender, ltv);

        for (uint256 i; i < length; ++i) {
            if (amounts[i] == 0) break;
            // there is a possibility where rs[i + 1] = irs[i]
            if (length > i + 1 && irs[i + 1] <= irs[i]) revert ErrorsLib.OrdersNotOrdered();
            lenderTree._insertOrder(true, irs[i], uint64(ltv), amounts[i]);
            poolOrders[msg.sender].push(irs[i]);
        }
    }

    /// @notice Creates a Limit Order for borrowing at a higher collateral price
    /// @param rate The interest rate for the order (in yearly rate per second)
    /// @param ltv The LTV ratio for the order (1e18 = 100%)
    /// @param amount The amount to borrow
    /// @param minAmountExpected The minimum amount expected to be received
    /// @param collateralBuffer The collateral buffer for the order (> 0.01e18)
    /// @param collateralAmount The calculated amount of collateral need to fill the order when collateral is at desired higher price
    function insertLimitBorrowOrder(
        uint64 rate,
        uint64 ltv,
        uint256 amount,
        uint256 minAmountExpected,
        uint256 collateralBuffer,
        uint256 collateralAmount
    ) external nonReentrant whenNotPaused {
        if (amount == 0) revert ErrorsLib.ZeroAssets();
        if (collateralBuffer < 0.01e18) revert ErrorsLib.InvalidInput();

        BorrowerLimitOrder[] storage orders = borrowersOrders[msg.sender];

        IERC20(orderbookConfig.collateral_token).safeTransferFrom(msg.sender, address(this), collateralAmount);

        uint256 refundAmount;
        for (uint256 i; i < orders.length; ++i) {
            if (orders[i].rate == rate && orders[i].ltv == ltv) {
                refundAmount = orders[i].collateralAmount;
                _cancelBorrowerOrder(msg.sender, rate, ltv, orders[i].amount, i);
                break;
            }
        }

        // Insert new order
        borrowerTree._insertOrder(false, rate, ltv, amount);
        orders.push(BorrowerLimitOrder(rate, ltv, amount, minAmountExpected, collateralBuffer, collateralAmount));

        // Refund collateral from canceled order if any
        if (refundAmount > 0) {
            IERC20(orderbookConfig.collateral_token).safeTransfer(msg.sender, refundAmount);
        }

        if (orders.length > MAX_LIMIT_ORDERS) revert ErrorsLib.MaxOrdersLimit();

        emit EventsLib.BorrowOrderPlaced(msg.sender, rate, ltv, amount, minAmountExpected);
    }

    /// @notice Matches a market borrow order with the best available lenders
    /// @param amount The amount to borrow
    /// @param minAmountExpected The minimum amount expected to be received
    /// @param collateralBuffer The collateral buffer for the order (> 0.01e18)
    /// @param ltv Optional LTV to use; if set to 0, the minimum allowed LTV is used
    /// @param rate Optional rate to use; if set to 0, the best available lender rate is used
    /// @dev This function matches the borrow order with the best available lenders (pools) and creates borrow positions
    /// Maximum amount that can be matched is the total quoted liquidity from all pools; up to 30 pools are recorded in details
    function matchMarketBorrowOrder(
        uint256 amount,
        uint256 minAmountExpected,
        uint256 collateralBuffer,
        uint64 ltv,
        uint64 rate
    ) external nonReentrant whenNotPaused {
        if (amount == 0) revert ErrorsLib.ZeroAssets();
        if (collateralBuffer < 0.01e18) revert ErrorsLib.InvalidInput();

        if (rate == 0) {
            (rate,) = lenderTree._getBestLenderRate();
        }

        if (ltv == 0) {
            ltv = OrderbookLib.MIN_LTV;
        }
        // we need to test this, its unfair for the other pool outside the first 300 see line 122
        MatchedOrder memory matchedOrder = lenderTree._matchOrder(false, rate, ltv, amount);

        uint256 amountReceived;
        if (matchedOrder.totalMatched > 0) {
            uint256 matchedOrderCount = matchedOrder.totalCount;

            // Memory structure for pool aggregation
            PoolData[] memory poolData = new PoolData[](matchedOrderCount);
            uint256 uniquePoolCount;
            uint256 totalCollateral;

            // 1. Aggregate amounts by pool (O(n^2) but acceptable for small n)
            (poolData, uniquePoolCount) = _aggregatePoolData(matchedOrder); // returns list of unique pools that will supply the loan


            // 2. Update collateral fields in poolData using the helper function
            totalCollateral = _calculateAndSetPoolCollateral(poolData, uniquePoolCount, msg.sender, collateralBuffer);

            // 3. Single collateral transfer
            IERC20 collateralToken = IERC20(orderbookConfig.collateral_token);
            collateralToken.safeTransferFrom(msg.sender, address(this), totalCollateral);

            // 4. Collect matching fee
            if (flatMatchingFee > 0 && feeRecipient != address(0)) {
                collateralToken.safeTransferFrom(msg.sender, feeRecipient, flatMatchingFee);
                emit EventsLib.MatchingFeeCollected(msg.sender, feeRecipient, flatMatchingFee);
            }

            // 5. Process all pools
            amountReceived = _processPoolMatches(poolData, uniquePoolCount, msg.sender, minAmountExpected);
        }
    }

    /// @notice Matches a limit borrow order with the best available lenders
    /// @param borrower The address of the borrower
    /// @param index The index of the order in the borrower's order list
    /// @dev This function matches the borrow order with the best available lenders(pools) and create borrow positions
    /// This will also cancel the order in the orderbook, refund excess collateral and removes the order from the borrower's list
    function matchLimitBorrowOrder(address borrower, uint256 index) external nonReentrant whenNotPaused {
        if (!IOrderbookFactory(ORDERBOOK_FACTORY).isKeeper(msg.sender)) revert ErrorsLib.NotKeeper();
        if (borrower == address(0)) revert ErrorsLib.ZeroAddress();
        if (borrowersOrders[borrower].length == 0) revert ErrorsLib.NoOrders();
        if (index >= borrowersOrders[borrower].length) revert ErrorsLib.InvalidInput();
        BorrowerLimitOrder storage order = borrowersOrders[borrower][index];

        uint64 rate = uint64(order.rate);
        uint64 ltv = uint64(order.ltv);
        uint256 amount = order.amount;
        uint256 minAmountExpected = order.minAmountExpected;
        uint256 collateralBuffer = order.collateralBuffer;
        uint256 collateralAmount = order.collateralAmount;

        MatchedOrder memory matchedOrder = lenderTree._matchOrder(false, rate, ltv, amount);

        uint256 amountReceived;
        if (matchedOrder.totalMatched > 0) {
            uint256 matchedOrderCount = matchedOrder.totalCount;

            // Memory structure for pool aggregation
            PoolData[] memory poolData = new PoolData[](matchedOrderCount);
            uint256 uniquePoolCount;
            uint256 totalCollateral;

            // 1. Aggregate amounts by pool (O(n^2) but acceptable for small n)
            (poolData, uniquePoolCount) = _aggregatePoolData(matchedOrder);

            // 2. Update collateral fields in poolData using the helper function
            totalCollateral = _calculateAndSetPoolCollateral(poolData, uniquePoolCount, borrower, collateralBuffer);

            // This check is to ensure that the borrower's supplied collateral is sufficient
            // This will only happen when collateral is at a higher price
            if (totalCollateral + flatMatchingFee > collateralAmount) revert ErrorsLib.OrderCollateralExceedsAmount();

            // 3. Canceling the order
            _cancelBorrowerOrder(borrower, rate, ltv, amount, index);

            // 4. Refund excess collateral
            uint256 excessCollateral = collateralAmount - totalCollateral - flatMatchingFee;
            if (excessCollateral > 0) {
                IERC20(orderbookConfig.collateral_token).safeTransfer(borrower, excessCollateral);
            }

            // 5. Collect matching fee
            if (flatMatchingFee > 0 && feeRecipient != address(0)) {
                IERC20(orderbookConfig.collateral_token).safeTransfer(feeRecipient, flatMatchingFee);
                emit EventsLib.MatchingFeeCollected(borrower, feeRecipient, flatMatchingFee);
            }

            // 6. Process all pools
            amountReceived = _processPoolMatches(poolData, uniquePoolCount, borrower, minAmountExpected);
        }
    }

    /// @notice Cancels a borrower's limit order fully or partially and refunds corresponding collateral
    /// @param rate The interest rate of the order being cancelled
    /// @param ltv The LTV of the order being cancelled
    /// @param amount The amount of the order to cancel (can be partial)
    /// @param index The index of the order in the borrower's order list
    /// @dev Cancels a borrow order, refunds excess collateral, and removes the order from the borrower's list
    /// This is also used to cancel partial orders
    function cancelBorrowOrder(uint256 rate, uint256 ltv, uint256 amount, uint256 index) external nonReentrant {
        if (amount == 0) revert ErrorsLib.ZeroAssets();
        BorrowerLimitOrder memory order = borrowersOrders[msg.sender][index];
        uint256 collateralAmount = order.collateralAmount.mulDivDown(amount, order.amount);

        _cancelBorrowerOrder(msg.sender, rate, ltv, amount, index);

        IERC20(orderbookConfig.collateral_token).safeTransfer(msg.sender, collateralAmount);
        emit EventsLib.BorrowOrderCanceled(msg.sender, rate, ltv, amount);
    }

    /// @notice Pauses state-changing functions in the orderbook
    /// @dev Only callable by the owner
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses state-changing functions in the orderbook
    /// @dev Only callable by the owner
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Returns all active limit orders for a borrower
    /// @param borrower The borrower address to query
    /// @return Array of BorrowerLimitOrder structs
    function getBorrowerOrders(address borrower) external view returns (BorrowerLimitOrder[] memory) {
        return borrowersOrders[borrower];
    }

    /// @notice Returns the list of IRs for the given pool's currently quoted orders
    /// @param pool The pool address to query
    /// @return Array of interest rates (IRs) for the pool's orders
    function getPoolOrders(address pool) external view returns (uint256[] memory) {
        return poolOrders[pool];
    }

    /// @notice Returns a paginated snapshot of the orderbook tree
    /// @param isLender True for the lender tree; false for the borrower tree
    /// @param offset Number of nodes to skip from the start
    /// @param limit Maximum number of nodes to return
    /// @return state Aggregated node and entry data for the selected tree
    function getTreeState(bool isLender, uint256 offset, uint256 limit)
        external
        view
        returns (TreeState memory state)
    {
        return (isLender ? lenderTree : borrowerTree)._getTreeState(isLender, offset, limit);
    }

    /// @notice Simulates the result of a borrow operation without executing it
    /// @dev Can be used for both market orders and limit orders with specified parameters
    /// @param previewBorrowParams Struct containing all parameters for the borrow simulation
    /// @return previewMatchedOrders Details of the orders that would be matched
    /// @return loanTokenAmount The total amount of loan tokens that would be received
    /// @return collateralRequired The total collateral that would be required
    /// @return amountLeft The portion of the requested amount that couldn't be matched
    function previewBorrow(PreviewBorrowParams memory previewBorrowParams)
        external
        view
        returns (
            PreviewMatchedOrder memory previewMatchedOrders,
            uint256 loanTokenAmount,
            uint256 collateralRequired,
            uint256 amountLeft
        )
    {
        if (previewBorrowParams.isMarketOrder) {
            (previewBorrowParams.rate,) = lenderTree._getBestLenderRate();
            previewBorrowParams.ltv = OrderbookLib.MIN_LTV;
        }

        if (previewBorrowParams.isCollateral && flatMatchingFee > 0) {
            if (previewBorrowParams.amount <= flatMatchingFee) revert ErrorsLib.NotEnoughCollateral();
        }

        previewMatchedOrders = previewBorrowParams.isCollateral
            ? lenderTree._previewMatchBorrowWithExactCollateral(
                previewBorrowParams.borrower,
                previewBorrowParams.rate,
                previewBorrowParams.ltv,
                previewBorrowParams.amount - flatMatchingFee,
                previewBorrowParams.collateralBuffer
            )
            : lenderTree._previewMatchBorrow(previewBorrowParams.rate, previewBorrowParams.ltv, previewBorrowParams.amount);

        if ((previewBorrowParams.amount - previewMatchedOrders.totalMatched) > 0) {
            amountLeft = previewBorrowParams.isCollateral
                ? previewBorrowParams.amount - previewMatchedOrders.totalMatched - flatMatchingFee
                : previewBorrowParams.amount - previewMatchedOrders.totalMatched;
        }

        if (previewMatchedOrders.totalMatched > 0) {
            uint256 matchedOrderCount = previewMatchedOrders.totalCount;
            for (uint256 i; i < matchedOrderCount; i++) {
                previewBorrowParams.isCollateral
                    ? loanTokenAmount += previewMatchedOrders.amounts[i]
                    : collateralRequired += IPoolImplementation(previewMatchedOrders.counterParty[i]).previewBorrow(
                        previewBorrowParams.borrower, previewMatchedOrders.amounts[i], previewBorrowParams.collateralBuffer
                    );
            }
            if (flatMatchingFee > 0 && !previewBorrowParams.isCollateral) {
                collateralRequired += flatMatchingFee;
            }
        }
    }

    function _cancelPoolOrders(address pool, uint256 ltv) internal {
        uint256[] memory orders = poolOrders[pool];
        uint256 ordersLength = orders.length;

        if (ordersLength > 0) {
            for (uint256 i; i < ordersLength; ++i) {
                uint256 currentIR = orders[i];
                uint256 currentLTV = type(uint64).max - ltv;

                uint256 compositeKey = AugmentedRedBlackTreeLib._packCompositeKey(currentIR, currentLTV);
                uint256 entryCount = AugmentedRedBlackTreeLib.getEntryCount(lenderTree, compositeKey);

                for (uint256 j; j < entryCount; ++j) {
                    AugmentedRedBlackTreeLib.Entry storage entry =
                        AugmentedRedBlackTreeLib.getEntryAt(lenderTree, compositeKey, j);
                    if (entry.account == pool) {
                        lenderTree._cancelOrder(true, compositeKey, j);
                        break; //As for a particular ir and ltv the pool can have only one order
                    }
                }
            }
            delete poolOrders[pool];
        }
    }

    function _cancelBorrowerOrder(address borrower, uint256 rate, uint256 ltv, uint256 amount, uint256 index)
        internal
    {
        BorrowerLimitOrder[] storage orders = borrowersOrders[borrower];
        uint256 ordersLength = orders.length;
        if (ordersLength == 0) revert ErrorsLib.NoOrders();
        if (index >= ordersLength) revert ErrorsLib.InvalidInput();

        BorrowerLimitOrder storage order = orders[index];
        if (order.rate != rate || order.ltv != ltv) revert ErrorsLib.InvalidInput();

        uint256 orderAmount = order.amount;
        if (orderAmount < amount) revert ErrorsLib.InvalidInput();

        uint256 collateralAmount = order.collateralAmount.mulDivDown(amount, orderAmount);
        uint256 minExpected = order.minAmountExpected.mulDivDown(amount, orderAmount);

        uint256 compositeKey = AugmentedRedBlackTreeLib._packCompositeKey(type(uint64).max - rate, ltv);
        uint256 entryCount = AugmentedRedBlackTreeLib.getEntryCount(borrowerTree, compositeKey);

        bool found;

        for (uint256 i; i < entryCount; ++i) {
            AugmentedRedBlackTreeLib.Entry storage entry =
                AugmentedRedBlackTreeLib.getEntryAt(borrowerTree, compositeKey, i);
            if (entry.account == borrower) {
                borrowerTree._cancelOrder(false, compositeKey, i);
                if (orderAmount - amount != 0) {
                    borrowerTree._insertOrder(false, uint64(rate), uint64(ltv), orderAmount - amount);
                    order.amount -= amount;
                    order.collateralAmount -= collateralAmount;
                    order.minAmountExpected -= minExpected;
                } else {
                    if (index != ordersLength - 1) {
                        orders[index] = orders[ordersLength - 1];
                    }
                    orders.pop();
                }
                found = true;
                break; //As for a particular ir and ltv the pool can have only one order
            }
        }
        if (!found) revert ErrorsLib.OrderNotFound();
    }

    /// @dev Internal helper for processing matched pool orders
    /// @param pools Array of PoolData structs containing pool info
    /// @param poolCount Number of unique pools to process
    /// @param borrower Address of the borrower
    /// @param minAmountExpected Minimum amount the borrower expects to receive
    /// @return amountReceived Total amount received from all pools
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

            // Approve and interact with pool
            collateralToken.safeIncreaseAllowance(pool, collateral);
            IPoolImplementation(pool).depositCollateral(collateral, borrower);
            (uint256 assets,) = IPoolImplementation(pool).borrow(poolAmount, 0, borrower, borrower, 0);
            amountReceived += assets;
        }

        if (amountReceived < minAmountExpected) revert ErrorsLib.InsufficientAmountReceived();

        return amountReceived;
    }

    /// @dev Helper for calculating collateral needed
    /// @param poolData_ Array of PoolData structs containing pool info
    /// @param uniquePoolCount_ Number of unique pools to process
    /// @param borrower_ Address of the borrower
    /// @param collateralBuffer_ Collateral buffer for the borrow operation
    function _calculateAndSetPoolCollateral(
        PoolData[] memory poolData_,
        uint256 uniquePoolCount_,
        address borrower_,
        uint256 collateralBuffer_
    ) internal view returns (uint256 totalCollateral_) {
        for (uint256 i = 0; i < uniquePoolCount_; i++) {
            uint256 requiredCollateral =
                IPoolImplementation(poolData_[i].pool).previewBorrow(borrower_, poolData_[i].amount, collateralBuffer_);
            poolData_[i].collateral = requiredCollateral;
            totalCollateral_ += requiredCollateral;
        }
    }

    /// @dev Aggregates amounts from matched orders into unique pool data entries.
    /// @param matchedOrder_ The matched order details from the tree.
    /// @return poolData_ Array of aggregated pool data.
    /// @return uniquePoolCount_ The number of unique pools found.
    function _aggregatePoolData(MatchedOrder memory matchedOrder_)
        internal
        view
        returns (PoolData[] memory poolData_, uint256 uniquePoolCount_)
    {
        // only withing first 30 pools
        uint256 matchedOrderCount_ = matchedOrder_.totalCount;
        poolData_ = new PoolData[](matchedOrderCount_);

        for (uint256 i = 0; i < matchedOrderCount_; i++) {
            address pool = matchedOrder_.counterParty[i];
            uint256 poolAmount = matchedOrder_.amounts[i];
            bool exists;

            if (IPoolImplementation(pool).paused()) continue;

            for (uint256 j = 0; j < uniquePoolCount_; j++) {
                if (poolData_[j].pool == pool) {
                    poolData_[j].amount += poolAmount;
                    exists = true;
                    break;
                }
            }

            if (!exists) {
                poolData_[uniquePoolCount_] = PoolData(pool, poolAmount, 0);
                uniquePoolCount_++;
            }
        }
    }

    /// @notice Returns all whitelisted pools
    /// @return Array of all whitelisted pool addresses
    function getAllPools() external view returns (address[] memory) {
        return whitelistedPools;
    }

    /// @dev Removes a pool from the whitelistedPools array
    /// @param pool The address of the pool to remove
    function _removePoolFromArray(address pool) internal {
        uint256 length = whitelistedPools.length;
        for (uint256 i = 0; i < length; i++) {
            if (whitelistedPools[i] == pool) {
                // Swap with the last element and pop
                whitelistedPools[i] = whitelistedPools[length - 1];
                whitelistedPools.pop();
                break;
            }
        }
    }
}
