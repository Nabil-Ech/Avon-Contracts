// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/libraries/AugmentedRedBlackTreeLib.sol";

contract AugmentedRedBlackTreeLibTest is Test {
    using AugmentedRedBlackTreeLib for AugmentedRedBlackTreeLib.Tree;

    AugmentedRedBlackTreeLib.Tree private tree;

    function setUp() public {}

    function testValueFunction() public {
        uint256 ir = 500;
        uint256 ltv = 7000;
        uint256 amount = 1 ether;
        address account = address(this);
        uint256 timestamp = block.timestamp;

        tree.insert(ir, ltv, amount, account, timestamp);
        uint256 compositeKey = (ir << 160) | (ltv << 96);

        bytes32 ptr = tree.find(compositeKey);

        uint256 retrievedValue = AugmentedRedBlackTreeLib.value(ptr);

        uint256 retrievedIR = (retrievedValue >> 160) & type(uint64).max;
        uint256 retrievedLTV = (retrievedValue >> 96) & type(uint64).max;

        assertEq(retrievedIR, ir, "Interest rate mismatch");
        assertEq(retrievedLTV, ltv, "LTV mismatch");
    }

    function testValueFunctionWithEmptyPointer() public view {
        bytes32 emptyPtr = bytes32(0);
        uint256 value = AugmentedRedBlackTreeLib.value(emptyPtr);
        assertEq(value, 0, "Empty pointer should return 0");
    }

    function testValueFunctionWithMultipleEntries() public {
        uint256[] memory irs = new uint256[](3);
        uint256[] memory ltvs = new uint256[](3);

        irs[0] = 500;
        irs[1] = 600;
        irs[2] = 700;

        ltvs[0] = 7000;
        ltvs[1] = 8000;
        ltvs[2] = 9000;

        for (uint256 i = 0; i < 3; i++) {
            uint256 compositeKey = (irs[i] << 160) | (ltvs[i] << 96);

            tree.insert(irs[i], ltvs[i], 1 ether, address(this), block.timestamp);

            bytes32 ptr = tree.find(compositeKey);
            uint256 retrievedValue = AugmentedRedBlackTreeLib.value(ptr);

            uint256 retrievedIR = (retrievedValue >> 160) & type(uint64).max;
            uint256 retrievedLTV = (retrievedValue >> 96) & type(uint64).max;

            assertEq(retrievedIR, irs[i], "Interest rate mismatch at index");
            assertEq(retrievedLTV, ltvs[i], "LTV mismatch at index");
        }
    }

    function testValueFunctionMaxValues() public {
        uint256 maxIR = type(uint64).max;
        uint256 maxLTV = type(uint64).max;

        uint256 compositeKey = (maxIR << 160) | (maxLTV << 96);

        tree.insert(maxIR, maxLTV, 1 ether, address(this), block.timestamp);

        bytes32 ptr = tree.find(compositeKey);
        uint256 retrievedValue = AugmentedRedBlackTreeLib.value(ptr);

        uint256 retrievedIR = (retrievedValue >> 160) & type(uint64).max;
        uint256 retrievedLTV = (retrievedValue >> 96) & type(uint64).max;

        assertEq(retrievedIR, maxIR, "Max IR mismatch");
        assertEq(retrievedLTV, maxLTV, "Max LTV mismatch");
    }

    function testInsertAndDelete() public {
        uint256 ir = 500;
        uint256 ltv = 7000;
        uint256 compositeKey = (ir << 160) | (ltv << 96);

        tree.insert(ir, ltv, 1 ether, address(this), block.timestamp);

        assertTrue(tree.exists(compositeKey), "Value should exist after insertion");

        tree.remove(compositeKey);

        assertFalse(tree.exists(compositeKey), "Value should not exist after deletion");
    }

    function testMinMax() public {
        uint256[] memory irs = new uint256[](3);
        uint256[] memory ltvs = new uint256[](3);

        irs[0] = 700;
        irs[1] = 500;
        irs[2] = 900;

        ltvs[0] = 7500;
        ltvs[1] = 6000;
        ltvs[2] = 8500;

        for (uint256 i = 0; i < 3; i++) {
            tree.insert(irs[i], ltvs[i], 1 ether, address(this), block.timestamp);
        }

        bytes32 minPtr = tree.first();
        uint256 minValue = AugmentedRedBlackTreeLib.value(minPtr);
        uint256 minIR = (minValue >> 160) & type(uint64).max;
        uint256 minLTV = (minValue >> 96) & type(uint64).max;

        assertEq(minIR, 500, "Minimum IR should be 500");
        assertEq(minLTV, 6000, "Minimum LTV should be 6000");

        bytes32 maxPtr = tree.last();
        uint256 maxValue = AugmentedRedBlackTreeLib.value(maxPtr);
        uint256 maxIR = (maxValue >> 160) & type(uint64).max;
        uint256 maxLTV = (maxValue >> 96) & type(uint64).max;

        assertEq(maxIR, 900, "Maximum IR should be 900");
        assertEq(maxLTV, 8500, "Maximum LTV should be 8500");
    }

    function testNextPrev() public {
        uint256[] memory irs = new uint256[](3);
        uint256[] memory ltvs = new uint256[](3);

        irs[0] = 500;
        irs[1] = 700;
        irs[2] = 900;

        ltvs[0] = 6000;
        ltvs[1] = 7500;
        ltvs[2] = 8500;

        bytes32[] memory ptrs = new bytes32[](3);

        for (uint256 i = 0; i < 3; i++) {
            tree.insert(irs[i], ltvs[i], 1 ether, address(this), block.timestamp);
            uint256 compositeKey = (irs[i] << 160) | (ltvs[i] << 96);
            ptrs[i] = tree.find(compositeKey);
        }

        bytes32 nextPtr = AugmentedRedBlackTreeLib.next(ptrs[0]);
        uint256 nextValue = AugmentedRedBlackTreeLib.value(nextPtr);
        uint256 nextIR = (nextValue >> 160) & type(uint64).max;
        uint256 nextLTV = (nextValue >> 96) & type(uint64).max;

        assertEq(nextIR, 700, "Next IR should be 700");
        assertEq(nextLTV, 7500, "Next LTV should be 7500");

        bytes32 prevPtr = AugmentedRedBlackTreeLib.prev(ptrs[1]);
        uint256 prevValue = AugmentedRedBlackTreeLib.value(prevPtr);
        uint256 prevIR = (prevValue >> 160) & type(uint64).max;
        uint256 prevLTV = (prevValue >> 96) & type(uint64).max;

        assertEq(prevIR, 500, "Previous IR should be 500");
        assertEq(prevLTV, 6000, "Previous LTV should be 6000");
    }

    function testEmptyTreeOperations() public view {
        bytes32 emptyFirst = tree.first();
        bytes32 emptyLast = tree.last();

        assertEq(uint256(emptyFirst), 0, "First of empty tree should be 0");
        assertEq(uint256(emptyLast), 0, "Last of empty tree should be 0");

        uint256 compositeKey = (500 << 160) | (7000 << 96);
        assertFalse(tree.exists(compositeKey), "Empty tree should not contain any values");
    }

    function testTreeTraversal() public {
        uint256[] memory irs = new uint256[](5);
        uint256[] memory ltvs = new uint256[](5);

        irs[0] = 500;
        irs[1] = 600;
        irs[2] = 700;
        irs[3] = 800;
        irs[4] = 900;

        ltvs[0] = 6000;
        ltvs[1] = 7000;
        ltvs[2] = 7500;
        ltvs[3] = 8000;
        ltvs[4] = 8500;

        for (uint256 i = 0; i < 5; i++) {
            tree.insert(irs[i], ltvs[i], 1 ether, address(this), block.timestamp);
        }

        bytes32 current = tree.first();
        uint256 count = 0;

        while (current != bytes32(0)) {
            uint256 value = AugmentedRedBlackTreeLib.value(current);
            uint256 currentIR = (value >> 160) & type(uint64).max;
            uint256 currentLTV = (value >> 96) & type(uint64).max;

            assertEq(currentIR, irs[count], "IR mismatch in traversal");
            assertEq(currentLTV, ltvs[count], "LTV mismatch in traversal");

            current = AugmentedRedBlackTreeLib.next(current);
            count++;
        }

        assertEq(count, 5, "Should have traversed all nodes");
    }

    function testRemoveLastEntry() public {
        uint256 ir = 500;
        uint256 ltv = 7000;
        uint256 compositeKey = (ir << 160) | (ltv << 96);

        tree.insert(ir, ltv, 1 ether, address(this), block.timestamp);

        tree.remove(compositeKey);

        assertFalse(tree.exists(compositeKey), "Node should be removed when last entry is removed");
    }

    function testNearestOperations() public {
        uint256[] memory irs = new uint256[](3);
        uint256[] memory ltvs = new uint256[](3);

        irs[0] = 500;
        irs[1] = 700;
        irs[2] = 900;

        ltvs[0] = 6000;
        ltvs[1] = 7500;
        ltvs[2] = 8500;

        for (uint256 i = 0; i < 3; i++) {
            tree.insert(irs[i], ltvs[i], 1 ether, address(this), block.timestamp);
        }

        uint256 searchKey = (800 << 160) | (8000 << 96);
        bytes32 beforePtr = tree.nearestBefore(searchKey);
        uint256 beforeValue = AugmentedRedBlackTreeLib.value(beforePtr);
        uint256 beforeIR = (beforeValue >> 160) & type(uint64).max;

        assertEq(beforeIR, 700, "NearestBefore should return 700");

        bytes32 afterPtr = tree.nearestAfter(searchKey);
        uint256 afterValue = AugmentedRedBlackTreeLib.value(afterPtr);
        uint256 afterIR = (afterValue >> 160) & type(uint64).max;

        assertEq(afterIR, 900, "NearestAfter should return 900");

        uint256 lowKey = (400 << 160) | (5000 << 96);
        uint256 highKey = (1000 << 160) | (9000 << 96);

        bytes32 lowBeforePtr = tree.nearestBefore(lowKey);
        assertEq(uint256(lowBeforePtr), 0, "NearestBefore should return 0 for too low value");

        bytes32 highAfterPtr = tree.nearestAfter(highKey);
        assertEq(uint256(highAfterPtr), 0, "NearestAfter should return 0 for too high value");
    }
}
