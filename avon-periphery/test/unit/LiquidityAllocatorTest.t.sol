// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../BasePoolTest.t.sol";
import {PoolStorage} from "../../src/pool/PoolStorage.sol";
import {PoolConstants} from "../../src/pool/utils/PoolConstants.sol";
import {TestAvonPool} from "../TestHelper.t.sol";
import {LiquidityAllocator} from "../../src/libraries/LiquidityAllocator.sol";
import {MockPoolFactory} from "../mock/MockPoolFactory.sol";

contract LiquidityAllocatorTest is BasePoolTest {
    TestAvonPool testPool;

    function setUp() public override {
        super.setUp();
        vm.startPrank(owner);
        MockPoolFactory mockPoolFactory = new MockPoolFactory();
        PoolStorage.PoolConfig memory cfg = PoolStorage.PoolConfig({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(oracle),
            irm: address(irm),
            lltv: 0.8e18 // 80% LTV
        });
        address[] memory proposers = new address[](2);
        address[] memory executors = new address[](2);
        proposers[0] = manager; // Pool manager
        proposers[1] = owner; // Owner of the orderbook
        executors[0] = manager; // Pool manager
        executors[1] = owner; // Owner of the orderbook

        testPool = new TestAvonPool(
            cfg,
            manager,
            address(orderbook),
            address(orderbookFactory),
            MANAGER_FEE,
            1.03e18,
            0.03e18,
            0.25e18,
            0.001e18,
            0, // No deposit cap
            0, // No borrow cap
            proposers,
            executors,
            owner
        );
        mockPoolFactory.mockSetValidPool(address(testPool), true);
        orderbookFactory.mockSetPoolFactory(address(mockPoolFactory), true);
        vm.stopPrank();

        vm.prank(manager);
        orderbook.mockWhitelistPool(address(testPool), address(mockPoolFactory));
    }

    function testGetQuoteSuggestionsWithSmallTickCount() public {
        // Setup a basic pool state with lending and borrowing
        _setupTestBorrowingPosition(borrower, DEFAULT_BORROW_AMOUNT, 1e18);

        // Call getQuoteSuggestions with small tick count
        uint16 tickCount = 5;
        (uint64[] memory rates, uint256[] memory liquidity) =
            testPool.exposed_getQuoteSuggestions(tickCount, DEFAULT_DEPOSIT_AMOUNT - DEFAULT_BORROW_AMOUNT);

        // Verify results
        assertEq(rates.length, tickCount, "Should return array of size tickCount");
        assertEq(liquidity.length, tickCount, "Should return array of size tickCount");

        // Verify that each rate is calculated and liquidity is allocated
        for (uint256 i = 0; i < rates.length; i++) {
            if (i == 0) {
                assertGt(rates[i], 0, "First rate should be > 0");
                assertGt(liquidity[i], 0, "First liquidity should be > 0");
            }
        }
    }

    function testGetQuoteSuggestionsWithLargeTickCount() public {
        // Setup a basic pool state with lending and borrowing
        _setupTestBorrowingPosition(borrower, DEFAULT_BORROW_AMOUNT, 1e18);

        // Call getQuoteSuggestions with large tick count
        uint16 tickCount = 20;
        (uint64[] memory rates, uint256[] memory liquidity) =
            testPool.exposed_getQuoteSuggestions(tickCount, DEFAULT_DEPOSIT_AMOUNT - DEFAULT_BORROW_AMOUNT);

        // Verify results use PoolConstants.QUOTE_SUGGESTIONS since tickCount > 10
        assertEq(rates.length, PoolConstants.QUOTE_SUGGESTIONS, "Should return array of size QUOTE_SUGGESTIONS");
        assertEq(liquidity.length, PoolConstants.QUOTE_SUGGESTIONS, "Should return array of size QUOTE_SUGGESTIONS");
    }

    function testGetQuoteSuggestionsWithHighUtilization() public {
        // Setup high utilization scenario (90%)
        _setupTestBorrowingPosition(borrower, DEFAULT_DEPOSIT_AMOUNT * 9 / 10, 2e18);

        // Call getQuoteSuggestions
        uint16 tickCount = 5;
        (uint64[] memory rates,) =
            testPool.exposed_getQuoteSuggestions(tickCount, DEFAULT_DEPOSIT_AMOUNT - (DEFAULT_DEPOSIT_AMOUNT * 9 / 10));

        // Verify that rates reflect high utilization
        uint256 ratePerSecond = uint256(0.01e18) / 31536000;
        assertGt(rates[0], ratePerSecond, "First rate should be higher at high utilization");
    }

    function testGetQuoteSuggestionsWithZeroLiquidity() public {
        // Setup a basic pool state
        _setupTestBorrowingPosition(borrower, DEFAULT_DEPOSIT_AMOUNT, 2e18);

        // Call getQuoteSuggestions with zero available liquidity
        uint16 tickCount = 5;
        (uint64[] memory rates, uint256[] memory liquidity) = testPool.exposed_getQuoteSuggestions(tickCount, 0);

        // Verify results
        assertEq(rates.length, tickCount, "Should return array of size tickCount");

        // All liquidity values should be 0
        for (uint256 i = 0; i < liquidity.length; i++) {
            assertEq(liquidity[i], 0, "Liquidity should be 0 when available liquidity is 0");
        }
    }

    // Helper function to setup a lending position
    function _setupTestLendingPosition(address user, uint256 amount) internal {
        vm.startPrank(user);
        loanToken.approve(address(testPool), amount);
        testPool.deposit(amount, user);
        vm.stopPrank();
    }

    // Helper function to setup a borrowing position
    function _setupTestBorrowingPosition(address user, uint256 borrowAmount, uint256 collateralAmount)
        internal
        returns (uint256 assets, uint256 shares)
    {
        // First ensure there's liquidity in the pool
        _setupTestLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Now setup the borrowing position
        vm.startPrank(user);

        // Deposit collateral
        collateralToken.approve(address(testPool), collateralAmount);
        testPool.depositCollateral(collateralAmount, user);

        // Borrow
        (assets, shares) = testPool.borrow(borrowAmount, 0, user, user, borrowAmount);

        vm.stopPrank();
        return (assets, shares);
    }
}
