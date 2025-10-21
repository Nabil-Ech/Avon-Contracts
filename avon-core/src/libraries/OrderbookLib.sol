// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {TreeState, MatchedOrder, PreviewMatchedOrder} from "../interface/Types.sol";
import {IPoolImplementation} from "../interface/IPoolImplementation.sol";
import {AugmentedRedBlackTreeLib} from "./AugmentedRedBlackTreeLib.sol";
import {ErrorsLib} from "./ErrorsLib.sol";
import {EventsLib} from "./EventsLib.sol";

/// @notice Main orderbook contract for managing lender and borrower orders
/// @dev Uses AugmentedRedBlackTreeLib for efficient order storage and matching
/// @dev Inherits from AugmentedRedBlackTreeLib for core tree operations
library OrderbookLib {
    using AugmentedRedBlackTreeLib for AugmentedRedBlackTreeLib.Tree;

    ///@dev The maximum safe Loan-to-Value (LTV) ratio, represented as a fixed-point number with 18 decimals.
    ///This value is set to 99%, meaning that the loan amount should not exceed 99% of the collateral value.
    uint64 public constant MAX_SAFE_LTV = 0.99e18;

    ///@dev The minimum Loan-to-Value (LTV) ratio, represented as a fixed-point number with 18 decimals.
    ///This value is set to 50%, meaning that the loan amount should be at least 50% of the collateral value.
    uint64 public constant MIN_LTV = 0.5e18;

    /// @dev Maximum number of matched orders to record in detail arrays
    uint256 private constant MAX_MATCH_DETAILS = 30;

    /// @dev Minimum gas required to continue matching loop
    uint256 private constant MIN_REMAINING_GAS = 5000;

    /**
     * @notice Insert a new order into the order book
     * @dev Orders are stored in separate red-black trees for lenders and borrowers:
     *      - Lender orders: Sorted by lowest interest rate first, then highest LTV
     *      - Borrower orders: Sorted by highest interest rate first, then lowest LTV
     * @param tree The red-black tree where the order will be inserted
     * @param isLender Boolean indicating if the order is from a lender (true) or borrower (false).
     *                Determines sorting order: lenders sorted by lowest rate first, borrowers by highest.
     * @param rate The interest rate of the order
     * @param ltv The loan-to-value ratio of the order
     * @param amount The amount of the order
     */
    function _insertOrder(
        AugmentedRedBlackTreeLib.Tree storage tree,
        bool isLender,
        uint64 rate,
        uint64 ltv,
        uint256 amount
    ) internal {
        if (msg.sender == address(0)) revert ErrorsLib.InvalidInput();
        if (amount == 0 || rate == 0 || ltv < MIN_LTV || ltv > MAX_SAFE_LTV) revert ErrorsLib.InvalidInput();

        (uint64 keyRate, uint64 keyLTV) = _convertToTreeKeys(isLender, rate, ltv);

        tree.insert(keyRate, keyLTV, amount, msg.sender, block.timestamp);

        emit EventsLib.OrderInserted(isLender, msg.sender, rate, ltv, amount);
    }

    /**
     * @dev Matches an order from the order book.
     * @param tree The red-black tree containing the orders.
     * @param isLender Boolean indicating if the order is from a lender.
     * @param rate The rate of the order to match.
     * @param ltv The loan-to-value ratio of the order to match.
     * @param amount The amount of the order to match.
     * @return matchedOrders A struct containing details of the matched orders.
     *
     * This function attempts to match an order from the order book based on the provided parameters.
     * It iterates through the orders in the tree, checking for matches and filling the order until
     * the requested amount is matched or there are no more matching orders.
     */
    function _matchOrder(
        AugmentedRedBlackTreeLib.Tree storage tree,
        bool isLender,
        uint64 rate,
        uint64 ltv,
        uint256 amount
    ) internal returns (MatchedOrder memory matchedOrders) {
        if (amount == 0) revert ErrorsLib.InvalidInput();

        matchedOrders.counterParty = new address[](MAX_MATCH_DETAILS);
        matchedOrders.amounts = new uint256[](MAX_MATCH_DETAILS);
        uint256 matchedCount = 0;
        uint256 remaining = amount;
        bool recordDetails = matchedCount < MAX_MATCH_DETAILS;

        bytes32 currentPtr = tree.first();
        while (remaining > 0 && currentPtr != bytes32(0) && recordDetails) {
            if (gasleft() < MIN_REMAINING_GAS) break;

            bytes32 nextPtr = AugmentedRedBlackTreeLib.next(currentPtr);

            uint256 originalKey = AugmentedRedBlackTreeLib.value(currentPtr);
            bool nodeRemoved = false;

            if (_isMatchingOrder(currentPtr, rate, ltv, isLender)) {
                uint256 compositeKey = AugmentedRedBlackTreeLib.value(currentPtr);
                uint256 entriesCount = tree.getEntryCount(compositeKey);

                uint256 i = 0;
                while (i < entriesCount && remaining > 0) {
                    AugmentedRedBlackTreeLib.Entry storage entry = tree.getEntryAt(compositeKey, i);
                    uint256 fill = entry.amount > remaining ? remaining : entry.amount;

                    if (recordDetails) {
                        matchedOrders.counterParty[matchedCount] = entry.account;
                        matchedOrders.amounts[matchedCount] = fill;
                        matchedCount++;
                        matchedOrders.totalCount++;
                        recordDetails = matchedCount < MAX_MATCH_DETAILS;
                    }
                    // something weird with this,
                    ///@audit: if we surpass MAX_MATCH_DETAILS, 
                    //why modifying entry values yet not includ them as conterparties?
                    matchedOrders.totalMatched += fill;
                    remaining -= fill;

                    emit EventsLib.OrderMatched(
                        isLender ? msg.sender : entry.account, isLender ? entry.account : msg.sender, rate, ltv, fill
                    );

                    entry.amount = entry.amount - fill;

                    if (entry.amount == 0) {
                        tree.removeEntry(compositeKey, i);
                        // why reducing the number here ?
                        entriesCount--;

                        if (entriesCount == 0) {
                            nodeRemoved = true;
                            break;
                        }
                    } else {
                        tree._heapifyDown(compositeKey, i);
                        i++;
                    }
                }
            }

            if (nodeRemoved) {
                currentPtr = AugmentedRedBlackTreeLib.nearestAfter(tree, originalKey);
            } else {
                currentPtr = nextPtr;
            }
        }
    }

    /**
     * @dev Cancels an order in the AugmentedRedBlackTreeLib.
     * @param tree The AugmentedRedBlackTreeLib storage.
     * @param isLender Boolean indicating if the order is from a lender.
     * @param compositeKey The composite key of the order.
     * @param entryIndex The index of the entry to cancel in the heap of entries.
     */
    function _cancelOrder(
        AugmentedRedBlackTreeLib.Tree storage tree,
        bool isLender,
        uint256 compositeKey,
        uint256 entryIndex
    ) internal {
        (uint64 rate, uint64 ltv) = _convertFromTreeKeys(isLender, compositeKey);

        uint256 entryCount = AugmentedRedBlackTreeLib.getEntryCount(tree, compositeKey);
        if (entryIndex >= entryCount) revert ErrorsLib.InvalidInput();

        AugmentedRedBlackTreeLib.Entry storage entry =
            AugmentedRedBlackTreeLib.getEntryAt(tree, compositeKey, entryIndex);

        uint256 amount = entry.amount;
        tree.removeEntry(compositeKey, entryIndex);

        emit EventsLib.OrderCanceled(isLender, msg.sender, rate, ltv, amount);
    }

    /**
     * @dev Retrieves the state of a Red-Black Tree within a specified range.
     * @param tree The Red-Black Tree to retrieve the state from.
     * @param isLender A boolean indicating if the tree is a lender's tree or the borrower's.
     * @param offset The starting index from which to retrieve the tree state.
     * @param limit The maximum number of nodes to retrieve.
     * @return state A TreeState struct containing the state of the tree.
     */
    function _getTreeState(AugmentedRedBlackTreeLib.Tree storage tree, bool isLender, uint256 offset, uint256 limit)
        internal
        view
        returns (TreeState memory state)
    {
        // Get total nodes
        uint256 totalNodes = tree.size();
        state.total = totalNodes;

        // Calculate actual limit based on remaining nodes
        uint256 actualLimit = offset >= totalNodes ? 0 : (totalNodes - offset < limit ? totalNodes - offset : limit);

        // Initialize arrays
        state.ptrs = new bytes32[](actualLimit);
        state.irs = new uint256[](actualLimit);
        state.ltvs = new uint256[](actualLimit);
        state.entryCounts = new uint256[](actualLimit);
        state.totalAmounts = new uint256[](actualLimit);
        state.entries = new AugmentedRedBlackTreeLib.Entry[][](actualLimit);

        // Skip to offset
        bytes32 currentPtr = tree.first();
        for (uint256 i = 0; i < offset; i++) {
            currentPtr = AugmentedRedBlackTreeLib.next(currentPtr);
        }

        // Fill arrays for limit items
        for (uint256 i = 0; i < actualLimit; i++) {
            state.ptrs[i] = currentPtr;

            uint256 compositeKey = AugmentedRedBlackTreeLib.value(currentPtr);
            (uint64 rate, uint64 ltv) = _convertFromTreeKeys(isLender, compositeKey);
            state.irs[i] = rate;
            state.ltvs[i] = ltv;

            // Get entry count
            uint256 entryCount = AugmentedRedBlackTreeLib.getEntryCount(tree, compositeKey);

            // Create memory array for entries
            AugmentedRedBlackTreeLib.Entry[] memory nodeEntries = new AugmentedRedBlackTreeLib.Entry[](entryCount);
            state.totalAmounts[i] = 0;

            for (uint256 j = 0; j < entryCount; j++) {
                nodeEntries[j] = AugmentedRedBlackTreeLib.getEntryAt(tree, compositeKey, j);
                state.totalAmounts[i] += nodeEntries[j].amount;
            }

            state.entries[i] = nodeEntries;
            state.entryCounts[i] = entryCount;

            currentPtr = AugmentedRedBlackTreeLib.next(currentPtr);
        }

        return state;
    }

    /**
     * @dev Returns the best available lender rate in the orderbook
     * @param tree The Red-Black Tree to search
     * @return rate The best interest rate available
     * @return ltv The corresponding LTV for the best rate
     */
    function _getBestLenderRate(AugmentedRedBlackTreeLib.Tree storage tree)
        internal
        view
        returns (uint64 rate, uint64 ltv)
    {
        bytes32 currentPtr = tree.last();
        if (currentPtr == bytes32(0)) revert ErrorsLib.NoMatch();

        uint256 compositeKey = AugmentedRedBlackTreeLib.value(currentPtr);
        (rate, ltv) = _convertFromTreeKeys(true, compositeKey);
    }

    function _previewMatchBorrow(AugmentedRedBlackTreeLib.Tree storage tree, uint64 rate, uint64 ltv, uint256 amount)
        internal
        view
        returns (PreviewMatchedOrder memory previewMatchedOrders)
    {
        if (amount == 0) revert ErrorsLib.InvalidInput();

        previewMatchedOrders.counterParty = new address[](MAX_MATCH_DETAILS);
        previewMatchedOrders.amounts = new uint256[](MAX_MATCH_DETAILS);
        previewMatchedOrders.irs = new uint256[](MAX_MATCH_DETAILS);
        previewMatchedOrders.ltvs = new uint256[](MAX_MATCH_DETAILS);
        uint256 matchedCount = 0;
        uint256 totalMatchCount = 0;
        uint256 remaining = amount;
        bool recordDetails = matchedCount < MAX_MATCH_DETAILS;

        bytes32 currentPtr = tree.first();
        while (remaining > 0 && currentPtr != bytes32(0) && recordDetails) {
            if (gasleft() < MIN_REMAINING_GAS) break;

            bytes32 nextPtr = AugmentedRedBlackTreeLib.next(currentPtr);

            uint256 originalKey = AugmentedRedBlackTreeLib.value(currentPtr);
            bool nodeRemoved = false;

            if (_isMatchingOrder(currentPtr, rate, ltv, false)) {
                uint256 compositeKey = AugmentedRedBlackTreeLib.value(currentPtr);
                uint256 entriesCount = tree.getEntryCount(compositeKey);

                uint256 i = 0;
                while (i < entriesCount && remaining > 0) {
                    AugmentedRedBlackTreeLib.Entry memory entry = tree.getEntryAt(compositeKey, i);
                    uint256 fill = entry.amount > remaining ? remaining : entry.amount;

                    if (recordDetails) {
                        (uint64 displayRate, uint64 displayLtv) = _convertFromTreeKeys(true, compositeKey);
                        previewMatchedOrders.counterParty[matchedCount] = entry.account;
                        previewMatchedOrders.amounts[matchedCount] = fill;
                        previewMatchedOrders.irs[matchedCount] = displayRate;
                        previewMatchedOrders.ltvs[matchedCount] = displayLtv;
                        matchedCount++;
                        recordDetails = matchedCount < MAX_MATCH_DETAILS;
                    }

                    previewMatchedOrders.totalMatched += fill;
                    remaining -= fill;
                    totalMatchCount++;

                    entry.amount = entry.amount - fill;

                    if (entry.amount == 0) {
                        i++;

                        if (entriesCount == 0) {
                            nodeRemoved = true;
                            break;
                        }
                    }
                }
            }

            if (nodeRemoved) {
                currentPtr = AugmentedRedBlackTreeLib.nearestAfter(tree, originalKey);
            } else {
                currentPtr = nextPtr;
            }
        }

        previewMatchedOrders.totalCount = totalMatchCount;
    }

    function _previewMatchBorrowWithExactCollateral(
        AugmentedRedBlackTreeLib.Tree storage tree,
        address borrower,
        uint64 rate,
        uint64 ltv,
        uint256 collateralAmount,
        uint256 collateralBuffer
    ) internal view returns (PreviewMatchedOrder memory previewMatchedOrders) {
        if (collateralAmount == 0) revert ErrorsLib.InvalidInput();

        previewMatchedOrders.counterParty = new address[](MAX_MATCH_DETAILS);
        previewMatchedOrders.amounts = new uint256[](MAX_MATCH_DETAILS);
        previewMatchedOrders.irs = new uint256[](MAX_MATCH_DETAILS);
        previewMatchedOrders.ltvs = new uint256[](MAX_MATCH_DETAILS);
        uint256 matchedCount = 0;
        uint256 totalMatchCount = 0;
        uint256 remaining = collateralAmount;
        bool recordDetails = matchedCount < MAX_MATCH_DETAILS;

        bytes32 currentPtr = tree.first();
        while (remaining > 0 && currentPtr != bytes32(0) && recordDetails) {
            if (gasleft() < MIN_REMAINING_GAS) break;

            bytes32 nextPtr = AugmentedRedBlackTreeLib.next(currentPtr);

            uint256 originalKey = AugmentedRedBlackTreeLib.value(currentPtr);
            bool nodeRemoved = false;

            if (_isMatchingOrder(currentPtr, rate, ltv, false)) {
                uint256 compositeKey = AugmentedRedBlackTreeLib.value(currentPtr);
                uint256 entriesCount = tree.getEntryCount(compositeKey);

                uint256 i = 0;
                while (i < entriesCount && remaining > 0) {
                    AugmentedRedBlackTreeLib.Entry memory entry = tree.getEntryAt(compositeKey, i);
                    uint256 totalCollateralRequired =
                        IPoolImplementation(entry.account).previewBorrow(borrower, entry.amount, collateralBuffer);

                    if (totalCollateralRequired == 0) {
                        i++;
                        continue;
                    }

                    uint256 fill = totalCollateralRequired > remaining
                        ? IPoolImplementation(entry.account).previewBorrowWithExactCollateral(
                            borrower, remaining, collateralBuffer
                        )
                        : entry.amount;
                    uint256 collateralFilled = totalCollateralRequired > remaining ? remaining : totalCollateralRequired;

                    if (recordDetails) {
                        (uint64 displayRate, uint64 displayLtv) = _convertFromTreeKeys(true, compositeKey);
                        previewMatchedOrders.counterParty[matchedCount] = entry.account;
                        previewMatchedOrders.amounts[matchedCount] = fill;
                        previewMatchedOrders.irs[matchedCount] = displayRate;
                        previewMatchedOrders.ltvs[matchedCount] = displayLtv;
                        matchedCount++;
                        recordDetails = matchedCount < MAX_MATCH_DETAILS;
                    }

                    previewMatchedOrders.totalMatched += collateralFilled;
                    remaining -= collateralFilled;
                    totalMatchCount++;

                    entry.amount = entry.amount - fill;

                    if (entry.amount == 0) {
                        i++;

                        if (entriesCount == 0) {
                            nodeRemoved = true;
                            break;
                        }
                    }
                }
            }

            if (nodeRemoved) {
                currentPtr = AugmentedRedBlackTreeLib.nearestAfter(tree, originalKey);
            } else {
                currentPtr = nextPtr;
            }
        }

        previewMatchedOrders.totalCount = totalMatchCount;
    }

    /**
     * @dev Checks if an order matches the search criteria
     * @param ptr Pointer to the order in the tree
     * @param searchRate The rate to match against
     * @param searchLTV The LTV to match against
     * @param isLender Whether the search is in lender context
     * @return True if order matches criteria, false otherwise
     */
    function _isMatchingOrder(bytes32 ptr, uint256 searchRate, uint256 searchLTV, bool isLender)
        private
        view
        returns (bool)
    {
        (uint256 nodeRate, uint256 nodeLTV) =
            AugmentedRedBlackTreeLib._unpackCompositeKey(AugmentedRedBlackTreeLib.value(ptr));

        return isLender
            ? type(uint64).max - uint64(nodeRate) >= searchRate && uint64(nodeLTV) <= searchLTV
            : uint64(nodeRate) <= searchRate && type(uint64).max - uint64(nodeLTV) >= searchLTV;
    }

    /**
     * @dev Converts user-facing rate and LTV to tree storage format
     * @param isLender Whether the conversion is for lender context
     * @param rate The interest rate to convert
     * @param ltv The LTV to convert
     * @return keyRate Rate as stored in the tree
     * @return keyLTV LTV as stored in the tree
     */
    function _convertToTreeKeys(bool isLender, uint64 rate, uint64 ltv)
        private
        pure
        returns (uint64 keyRate, uint64 keyLTV)
    {
        if (isLender) {
            keyRate = rate;
            keyLTV = uint64(type(uint64).max - ltv);
        } else {
            keyRate = uint64(type(uint64).max - rate);
            keyLTV = ltv;
        }
    }

    /**
     * @dev Converts tree storage format back to user-facing rate and LTV
     * @param isLender Whether the conversion is for lender context
     * @param compositeKey The composite key from the tree
     * @return rate The user-facing interest rate
     * @return ltv The user-facing LTV
     */
    function _convertFromTreeKeys(bool isLender, uint256 compositeKey) private pure returns (uint64 rate, uint64 ltv) {
        (uint256 rawRate, uint256 rawLTV) = AugmentedRedBlackTreeLib._unpackCompositeKey(compositeKey);

        if (isLender) {
            rate = uint64(rawRate);
            ltv = uint64(type(uint64).max - uint64(rawLTV));
        } else {
            rate = uint64(type(uint64).max - uint64(rawRate));
            ltv = uint64(rawLTV);
        }
    }
}
