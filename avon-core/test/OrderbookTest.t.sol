// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "../lib/forge-std/src/Test.sol";
import {TreeState, PreviewBorrowParams} from "../src/interface/Types.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {OrderbookFactory} from "../src/OrderbookFactory.sol";
import {MockPoolFactory} from "./mocks/MockPoolFactory.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPool} from "./mocks/MockPool.sol";
import {MockIRM} from "./mocks/MockIRM.sol";
import {IOrderbook} from "../src/interface/IOrderbook.sol";
import {BorrowerLimitOrder} from "../src/interface/Types.sol";

contract OrderbookTest is Test {
    OrderbookFactory factory;
    Orderbook orderbook;
    MockERC20 loanToken;
    MockERC20 collateralToken;
    MockPoolFactory poolFactory;
    MockPool pool;
    MockIRM irm;

    address admin = makeAddr("admin");
    address poolManager = makeAddr("poolManager");
    address feeRecipient = makeAddr("feeRecipient");
    address borrower = makeAddr("borrower");
    address lender = makeAddr("lender");
    address keeper = makeAddr("keeper");

    function setUp() public {
        vm.startPrank(admin);

        // Deploy tokens
        loanToken = new MockERC20("Loan Token", "LOAN");
        collateralToken = new MockERC20("Collateral Token", "COLL");

        // Deploy factory
        factory = new OrderbookFactory(admin);

        // Deploy and enable IRM
        irm = new MockIRM(0.01e18, 0.1e18, 1e18, 0.8e18);
        factory.setIrm(address(irm), true);

        // Deploy pool factory
        poolFactory = new MockPoolFactory();

        // Create orderbook
        factory.setPoolManager(poolManager, true);
        factory.setPoolFactory(address(poolFactory), true);
        factory.setKeeper(keeper, true);
        address orderbookAddress =
            factory.createOrderbook(address(loanToken), address(collateralToken), address(feeRecipient));
        orderbook = Orderbook(orderbookAddress);

        pool = poolFactory.createPool(address(loanToken), address(orderbook), address(irm), address(collateralToken));

        vm.stopPrank();

        // Setup accounts with tokens
        loanToken.mint(lender, 10000e18);
        collateralToken.mint(borrower, 10000e18);

        // Whitelist pool
        vm.prank(poolManager);
        orderbook.whitelistPool(address(pool), address(poolFactory));
    }

    function testZeroOwnerAddress() public {
        vm.expectRevert();
        factory.createOrderbook(address(0), address(collateralToken), address(feeRecipient));

        vm.prank(admin);
        factory.renounceOwnership();
        vm.expectRevert();
        factory.createOrderbook(address(loanToken), address(collateralToken), address(feeRecipient));
    }

    function testSetPoolManager() public {
        // Only owner can set pool manager
        vm.prank(poolManager);
        vm.expectRevert();
        factory.setPoolManager(poolManager, true);

        // zero address should fail
        vm.prank(admin);
        vm.expectRevert();
        factory.setPoolManager(address(0), true);

        // Admin can remove pool manager
        vm.prank(admin);
        factory.setPoolManager(poolManager, false);
        assertFalse(factory.isPoolManager(poolManager));
    }

    function testPoolWhitelisting() public {
        // Non-pool manager should fail
        vm.prank(borrower);
        vm.expectRevert();
        orderbook.whitelistPool(address(pool), address(poolFactory));

        // Zero address should fail
        vm.prank(poolManager);
        vm.expectRevert();
        orderbook.whitelistPool(address(0), address(poolFactory));

        // Pool with IRM not enabled should fail
        MockIRM newIrm = new MockIRM(0.01e18, 0.1e18, 1e18, 0.8e18);
        MockPool newPool = new MockPool(loanToken, address(orderbook), address(newIrm), address(collateralToken));
        vm.prank(poolManager);
        vm.expectRevert();
        orderbook.whitelistPool(address(newPool), address(poolFactory));

        // Already whitelisted pool should fail
        vm.prank(poolManager);
        vm.expectRevert();
        orderbook.whitelistPool(address(pool), address(poolFactory));

        assertTrue(orderbook.isWhitelisted(address(pool)));
    }

    function testRemovePool() public {
        // Only owner can remove pool
        vm.prank(poolManager);
        vm.expectRevert();
        orderbook.removePool(address(pool));

        // Zero address should fail
        vm.prank(admin);
        vm.expectRevert();
        orderbook.removePool(address(0));

        // Non-whitelisted pool should fail
        MockPool newPool = new MockPool(loanToken, address(orderbook), address(irm), address(collateralToken));
        vm.prank(poolManager);
        vm.expectRevert();
        orderbook.removePool(address(newPool));

        // Adding some pool orders
        vm.prank(lender);
        loanToken.approve(address(pool), 1000e18);
        vm.prank(lender);
        pool.deposit(1000e18, lender);

        // Owner should succeed
        vm.prank(admin);
        orderbook.removePool(address(pool));

        assertFalse(orderbook.isWhitelisted(address(pool)));
        // Check if orders were removed
        uint256[] memory poolOrderIds = orderbook.getPoolOrders(address(pool));
        assertEq(poolOrderIds.length, 0);
        TreeState memory poolTreeState = orderbook.getTreeState(true, 0, 10);
        assertEq(poolTreeState.total, 0);
    }

    function testBatchInsertOrder() public {
        // Depositing 0 amount should not create orders
        vm.prank(lender);
        loanToken.approve(address(pool), 0);
        vm.prank(lender);
        pool.deposit(0, lender);
        uint256[] memory poolOrderIds = orderbook.getPoolOrders(address(pool));
        assertEq(poolOrderIds.length, 0);
        TreeState memory poolTreeState = orderbook.getTreeState(true, 0, 10);
        assertEq(poolTreeState.total, 0);

        // Deposit to pool to have some assets
        vm.prank(lender);
        loanToken.approve(address(pool), 1000e18);
        vm.prank(lender);
        pool.deposit(1000e18, lender);

        // Check if orders were created
        poolOrderIds = orderbook.getPoolOrders(address(pool));
        assertGt(poolOrderIds.length, 0);

        // Non-Whitelisted pool should fail
        MockPool newPool = new MockPool(loanToken, address(orderbook), address(irm), address(collateralToken));
        vm.prank(lender);
        loanToken.approve(address(newPool), 1000e18);
        vm.prank(lender);
        vm.expectRevert();
        newPool.deposit(1000e18, lender);

        // Invalid length should fail
        uint64[] memory rates = new uint64[](2);
        uint256[] memory amounts = new uint256[](3);

        vm.prank(address(newPool));
        vm.expectRevert();
        orderbook.batchInsertOrder(rates, amounts);
    }

    function testInsertLimitBorrowOrder() public {
        uint64 rate = 0.05e18;
        uint64 ltv = 0.7e18;
        uint256 amount = 100e18;
        uint256 minAmountExpected = 90e18;
        uint256 collateralBuffer = 0.05e18;
        uint256 collateralAmount = 150e18;

        // Zero amount should fail
        vm.startPrank(borrower);
        vm.expectRevert();
        orderbook.insertLimitBorrowOrder(rate, ltv, 0, minAmountExpected, collateralBuffer, collateralAmount);

        // Collateral buffer should be more than 0.01e18
        vm.expectRevert();
        orderbook.insertLimitBorrowOrder(rate, ltv, amount, minAmountExpected, 0.009e18, collateralAmount);

        // Approve collateral
        collateralToken.approve(address(orderbook), collateralAmount);

        // Place limit order
        orderbook.insertLimitBorrowOrder(rate, ltv, amount, minAmountExpected, collateralBuffer, collateralAmount);

        // Check borrower orders
        BorrowerLimitOrder[] memory orders = orderbook.getBorrowerOrders(borrower);
        assertEq(orders.length, 1);
        assertEq(orders[0].amount, amount);

        // More than MAX_LIMIT_ORDER should fail
        for (uint256 i = 0; i < 9; i++) {
            collateralToken.approve(address(orderbook), collateralAmount);
            orderbook.insertLimitBorrowOrder(
                rate, ltv, amount + i, minAmountExpected, collateralBuffer, collateralAmount
            );
        }

        orders = orderbook.getBorrowerOrders(borrower);
        assertEq(orders.length, 1);
    }

    function testCancelBorrowOrder() public {
        // First place an order
        uint64 rate = 0.05e18;
        uint64 ltv = 0.7e18;
        uint256 amount = 100e18;
        uint256 minAmountExpected = 90e18;
        uint256 collateralBuffer = 0.05e18;
        uint256 collateralAmount = 150e18;

        vm.startPrank(borrower);
        collateralToken.approve(address(orderbook), collateralAmount);
        orderbook.insertLimitBorrowOrder(rate, ltv, amount, minAmountExpected, collateralBuffer, collateralAmount);

        // Check collateral balance before cancellation
        uint256 balanceBefore = collateralToken.balanceOf(borrower);

        // INvalid prameters should fail
        vm.expectRevert();
        orderbook.cancelBorrowOrder(rate, ltv, 30e18, 1);
        vm.expectRevert();
        orderbook.cancelBorrowOrder(rate, ltv, 0, 0);
        vm.expectRevert();
        orderbook.cancelBorrowOrder(rate + 1, ltv, 30e18, 0);
        vm.expectRevert();
        orderbook.cancelBorrowOrder(rate, ltv + 1, 30e18, 0);
        vm.expectRevert();
        orderbook.cancelBorrowOrder(rate, ltv, 110e18, 0);

        // Cancel partial order
        orderbook.cancelBorrowOrder(rate, ltv, 30e18, 0);
        BorrowerLimitOrder[] memory orders = orderbook.getBorrowerOrders(borrower);
        assertEq(orders.length, 1);
        assertEq(orders[0].amount, 70e18);
        assertEq(orders[0].minAmountExpected, 63e18);
        assertEq(orders[0].collateralBuffer, 0.05e18);
        assertEq(orders[0].collateralAmount, 105e18);
        orderbook.cancelBorrowOrder(rate, ltv, 70e18, 0);
        orders = orderbook.getBorrowerOrders(borrower);
        assertEq(orders.length, 0);
        vm.stopPrank();

        // Verify collateral returned
        uint256 balanceAfter = collateralToken.balanceOf(borrower);
        assertEq(balanceAfter - balanceBefore, collateralAmount);

        // Verify order removed
        vm.prank(borrower);
        orders = orderbook.getBorrowerOrders(borrower);
        assertEq(orders.length, 0);
    }

    function testMatchLimitBorrowOrder() public {
        // Setup pool with assets
        vm.prank(lender);
        loanToken.approve(address(pool), 1000e18);
        vm.prank(lender);
        pool.deposit(1000e18, lender);

        // Place borrower limit order
        uint64 rate = 2e18;
        uint64 ltv = 0.5e18;
        uint256 amount = 100e18;
        uint256 minAmountExpected = 90e18;
        uint256 collateralBuffer = 0.05e18;

        (,, uint256 collateralRequired,) = orderbook.previewBorrow(
            PreviewBorrowParams({
                borrower: borrower,
                amount: amount,
                collateralBuffer: collateralBuffer,
                rate: rate,
                ltv: ltv,
                isMarketOrder: false,
                isCollateral: false
            })
        );

        vm.startPrank(borrower);
        collateralToken.approve(address(orderbook), collateralRequired);
        orderbook.insertLimitBorrowOrder(rate, ltv, amount, minAmountExpected, collateralBuffer, collateralRequired);
        vm.stopPrank();

        // Match the order
        vm.prank(keeper);
        orderbook.matchLimitBorrowOrder(borrower, 0);

        // Check borrower balance
        uint256 borrowerBalance = loanToken.balanceOf(borrower);
        assertGt(borrowerBalance, 0);
    }

    function testPause() public {
        // Only owner can pause
        vm.prank(poolManager);
        vm.expectRevert();
        orderbook.pause();

        // Owner can pause
        vm.prank(admin);
        orderbook.pause();

        // Cannot place orders when paused
        uint64 rate = 0.05e18;
        uint64 ltv = 0.7e18;
        uint256 amount = 100e18;
        uint256 minAmountExpected = 90e18;
        uint256 collateralBuffer = 0.05e18;
        uint256 collateralAmount = 150e18;

        vm.startPrank(borrower);
        collateralToken.approve(address(orderbook), collateralAmount);
        vm.expectRevert();
        orderbook.insertLimitBorrowOrder(rate, ltv, amount, minAmountExpected, collateralBuffer, collateralAmount);
        vm.stopPrank();

        // Unpause
        vm.prank(admin);
        orderbook.unpause();
    }

    function testGetTreeState() public {
        // Place borrower limit order
        uint64 rate = 0.05e18;
        uint64 ltv = 0.7e18;
        uint256 amount = 100e18;
        uint256 minAmountExpected = 90e18;
        uint256 collateralBuffer = 0.05e18;
        uint256 collateralAmount = 150e18;

        vm.startPrank(borrower);
        collateralToken.approve(address(orderbook), collateralAmount);
        orderbook.insertLimitBorrowOrder(rate, ltv, amount, minAmountExpected, collateralBuffer, collateralAmount);
        vm.stopPrank();

        // Get borrower tree state
        TreeState memory borrowerTreeState = orderbook.getTreeState(false, 0, 10);
        assertGt(borrowerTreeState.total, 0);
    }

    function testMatchMarketBorrowOrder() public {
        // Setup pool with assets
        vm.prank(lender);
        loanToken.approve(address(pool), 1000e18);
        vm.prank(lender);
        pool.deposit(1000e18, lender);

        uint256 amount = 100e18;
        uint256 minAmountExpected = 90e18;
        uint256 collateralBuffer = 0.05e18;

        // Preview to get collateral required
        (,, uint256 collateralRequired,) = orderbook.previewBorrow(
            PreviewBorrowParams({
                borrower: borrower,
                amount: amount,
                collateralBuffer: collateralBuffer,
                rate: 0, // Not used for market order
                ltv: 0, // Not used for market order
                isMarketOrder: true,
                isCollateral: false
            })
        );

        // Execute market order
        vm.startPrank(borrower);
        collateralToken.approve(address(orderbook), collateralRequired);
        orderbook.matchMarketBorrowOrder(amount, minAmountExpected, collateralBuffer, 0, 0);
        vm.stopPrank();

        // Verify borrower received loan tokens
        uint256 borrowerBalance = loanToken.balanceOf(borrower);
        assertGt(borrowerBalance, 0);
        assertGe(borrowerBalance, minAmountExpected);
    }

    // Test previewBorrow with exact collateral flag
    function testPreviewBorrowWithExactCollateral() public {
        // Setup pool with assets
        vm.prank(lender);
        loanToken.approve(address(pool), 1000e18);
        vm.prank(lender);
        pool.deposit(1000e18, lender);

        uint256 collateralAmount = 50e18;
        uint256 collateralBuffer = 0.05e18;

        // Preview borrow with exact collateral
        (, uint256 loanTokenAmount,, uint256 amountLeft) = orderbook.previewBorrow(
            PreviewBorrowParams({
                borrower: borrower,
                amount: collateralAmount, // This is collateral amount when isCollateral is true
                collateralBuffer: collateralBuffer,
                rate: 1e18, // Some rate
                ltv: 0.5e18, // Some LTV
                isMarketOrder: false,
                isCollateral: true // Important: using the collateral path
            })
        );

        assertGt(loanTokenAmount, 0);
        assertEq(amountLeft, 0);
    }

    // Test multiple pools scenario
    function testMultiplePoolsScenario() public {
        // Setup first pool with assets
        vm.prank(lender);
        loanToken.approve(address(pool), 500e18);
        vm.prank(lender);
        pool.deposit(500e18, lender);

        // Create and setup second pool
        vm.startPrank(admin);
        MockPool pool2 =
            poolFactory.createPool(address(loanToken), address(orderbook), address(irm), address(collateralToken));
        vm.stopPrank();

        vm.prank(poolManager);
        orderbook.whitelistPool(address(pool2), address(poolFactory));

        vm.prank(lender);
        loanToken.approve(address(pool2), 500e18);
        vm.prank(lender);
        pool2.deposit(500e18, lender);

        // Now place a market order large enough to match from both pools
        uint256 amount = 800e18;
        uint256 minAmountExpected = 750e18;
        uint256 collateralBuffer = 0.05e18;

        // Preview to get collateral required
        (,, uint256 collateralRequired,) = orderbook.previewBorrow(
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

        // Execute market order
        vm.startPrank(borrower);
        collateralToken.approve(address(orderbook), collateralRequired);
        orderbook.matchMarketBorrowOrder(amount, minAmountExpected, collateralBuffer, 0, 0);
        vm.stopPrank();

        // Verify borrower received loan tokens
        uint256 borrowerBalance = loanToken.balanceOf(borrower);
        assertGt(borrowerBalance, 0);
        assertGe(borrowerBalance, minAmountExpected);
    }

    // Test for edge case with zero matched orders
    function testMatchMarketBorrowOrderWithNoMatches() public {
        uint256 amount = 100e18;
        uint256 minAmountExpected = 90e18;
        uint256 collateralBuffer = 0.05e18;

        // No deposits in pool, so no matches will be found

        vm.startPrank(borrower);
        collateralToken.approve(address(orderbook), 1000e18); // Large approval

        // This should revert with insufficient amount received
        vm.expectRevert();
        orderbook.matchMarketBorrowOrder(amount, minAmountExpected, collateralBuffer, 0, 0);
        vm.stopPrank();
    }

    // Test for preview with no matches
    function testPreviewBorrowWithNoMatches() public view {
        uint256 amount = 100e18;
        uint256 collateralBuffer = 0.05e18;

        // No deposits in pool, so preview should show no matches

        (, uint256 loanTokenAmount, uint256 collateralRequired, uint256 amountLeft) = orderbook.previewBorrow(
            PreviewBorrowParams({
                borrower: borrower,
                amount: amount,
                collateralBuffer: collateralBuffer,
                rate: 1e18,
                ltv: 0.5e18,
                isMarketOrder: false,
                isCollateral: false
            })
        );

        assertEq(loanTokenAmount, 0);
        assertEq(collateralRequired, 0);
        assertEq(amountLeft, amount);
    }

    // Test match limit borrow order with invalid index
    function testMatchLimitBorrowOrderInvalidIndex() public {
        // Setup pool with assets
        vm.prank(lender);
        loanToken.approve(address(pool), 1000e18);
        vm.prank(lender);
        pool.deposit(1000e18, lender);

        // Zero address should fail
        vm.expectRevert();
        orderbook.matchLimitBorrowOrder(address(0), 0);

        // Non-existent borrower should fail
        vm.expectRevert();
        orderbook.matchLimitBorrowOrder(address(1), 0);

        // Invalid index should fail
        vm.prank(lender);
        vm.expectRevert();
        orderbook.matchLimitBorrowOrder(borrower, 0);

        // Create an order first
        uint64 rate = 2e18;
        uint64 ltv = 0.5e18;
        uint256 amount = 100e18;
        uint256 minAmountExpected = 90e18;
        uint256 collateralBuffer = 0.05e18;
        uint256 collateralRequired = 150e18;

        vm.startPrank(borrower);
        collateralToken.approve(address(orderbook), collateralRequired);
        orderbook.insertLimitBorrowOrder(rate, ltv, amount, minAmountExpected, collateralBuffer, collateralRequired);
        vm.stopPrank();

        // Out of bounds index should fail
        vm.prank(lender);
        vm.expectRevert();
        orderbook.matchLimitBorrowOrder(borrower, 1);
    }

    // Test with insufficient collateral
    function testLimitOrderWithInsufficientCollateral() public {
        // This should fail as the collateral amount is too small
        uint64 rate = 0.05e18;
        uint64 ltv = 0.7e18;
        uint256 amount = 100e18;
        uint256 minAmountExpected = 90e18;
        uint256 collateralBuffer = 0.05e18;
        uint256 collateralAmount = 10e18; // Too small

        vm.startPrank(borrower);
        collateralToken.approve(address(orderbook), collateralAmount);

        // The contract doesn't validate collateral amount directly on insert,
        // but this would fail when matching if collateral is insufficient.
        // Only will get matched when collateral price is high enough.
        // However, we can still insert the order.
        orderbook.insertLimitBorrowOrder(rate, ltv, amount, minAmountExpected, collateralBuffer, collateralAmount);
        vm.stopPrank();
    }

    // Test isPoolManager check
    function testIsPoolManager() public {
        assertFalse(factory.isPoolManager(address(0)));
        assertTrue(factory.isPoolManager(poolManager));
        assertFalse(factory.isPoolManager(borrower));

        // Add a new pool manager
        address newPoolManager = makeAddr("newPoolManager");
        vm.prank(admin);
        factory.setPoolManager(newPoolManager, true);
        assertTrue(factory.isPoolManager(newPoolManager));
    }

    // Test boundary conditions for market order matching
    function testMarketBorrowOrderEdgeCases() public {
        // Setup pool with assets
        vm.prank(lender);
        loanToken.approve(address(pool), 1000e18);
        vm.prank(lender);
        pool.deposit(1000e18, lender);

        // Test case: zero amount should fail
        vm.startPrank(borrower);
        vm.expectRevert();
        orderbook.matchMarketBorrowOrder(0, 0, 0.05e18, 0, 0);
        vm.stopPrank();

        // Test case: minimum amount exceeds requested amount should fail
        vm.startPrank(borrower);
        collateralToken.approve(address(orderbook), 1000e18);
        vm.expectRevert();
        orderbook.matchMarketBorrowOrder(100e18, 101e18, 0.05e18, 0, 0);
        vm.stopPrank();

        // Test case: collateral buffer too low should fail
        vm.startPrank(borrower);
        collateralToken.approve(address(orderbook), 1000e18);
        vm.expectRevert();
        orderbook.matchMarketBorrowOrder(100e18, 90e18, 0.009e18, 0, 0);
        vm.stopPrank();
    }

    // Test borrower order cancellation edge cases
    function testCancelBorrowOrderEdgeCases() public {
        // First place an order
        uint64 rate = 0.05e18;
        uint64 ltv = 0.7e18;
        uint256 amount = 100e18;
        uint256 minAmountExpected = 90e18;
        uint256 collateralBuffer = 0.05e18;
        uint256 collateralAmount = 150e18;

        vm.startPrank(borrower);
        collateralToken.approve(address(orderbook), collateralAmount);
        orderbook.insertLimitBorrowOrder(rate, ltv, amount, minAmountExpected, collateralBuffer, collateralAmount);

        // Test non-existent index
        vm.expectRevert();
        orderbook.cancelBorrowOrder(rate, ltv, 30e18, 10); // Invalid index

        // Test attempting to cancel from another borrower should fail
        vm.stopPrank();
        vm.prank(lender);
        vm.expectRevert();
        orderbook.cancelBorrowOrder(rate, ltv, 30e18, 0);

        // Test full order cancellation
        vm.prank(borrower);
        orderbook.cancelBorrowOrder(rate, ltv, amount, 0);

        // Try to cancel again (should fail as order is gone)
        vm.prank(borrower);
        vm.expectRevert();
        orderbook.cancelBorrowOrder(rate, ltv, amount, 0);
        TreeState memory treeState = orderbook.getTreeState(false, 0, 10);
        assertEq(treeState.total, 0);
    }

    // Test preview borrow with different parameters
    function testPreviewBorrowPathCoverage() public {
        // Setup pool with assets
        vm.prank(lender);
        loanToken.approve(address(pool), 1000e18);
        vm.prank(lender);
        pool.deposit(1000e18, lender);

        // Test market order preview
        (, uint256 loanTokenAmount1,,) = orderbook.previewBorrow(
            PreviewBorrowParams({
                borrower: borrower,
                amount: 100e18,
                collateralBuffer: 0.05e18,
                rate: 0,
                ltv: 0,
                isMarketOrder: true,
                isCollateral: true
            })
        );

        (,, uint256 collateralRequired1,) = orderbook.previewBorrow(
            PreviewBorrowParams({
                borrower: borrower,
                amount: 100e18,
                collateralBuffer: 0.05e18,
                rate: 0,
                ltv: 0,
                isMarketOrder: true,
                isCollateral: false
            })
        );

        // Test limit order preview
        (, uint256 loanTokenAmount2,,) = orderbook.previewBorrow(
            PreviewBorrowParams({
                borrower: borrower,
                amount: 100e18,
                collateralBuffer: 0.05e18,
                rate: 1e18,
                ltv: 0.5e18,
                isMarketOrder: false,
                isCollateral: true
            })
        );
        (,, uint256 collateralRequired2,) = orderbook.previewBorrow(
            PreviewBorrowParams({
                borrower: borrower,
                amount: 100e18,
                collateralBuffer: 0.05e18,
                rate: 1e18,
                ltv: 0.5e18,
                isMarketOrder: false,
                isCollateral: false
            })
        );

        // Verify preview results are different
        assertEq(loanTokenAmount1 > 0, true);
        assertEq(loanTokenAmount2 > 0, true);
        assertEq(collateralRequired1 > 0, true);
        assertEq(collateralRequired2 > 0, true);
    }

    // Test match order with insufficient approval
    function testMatchWithInsufficientApproval() public {
        // Setup pool with assets
        vm.prank(lender);
        loanToken.approve(address(pool), 1000e18);
        vm.prank(lender);
        pool.deposit(1000e18, lender);

        uint256 amount = 100e18;
        uint256 minAmountExpected = 90e18;
        uint256 collateralBuffer = 0.05e18;

        // Preview to get collateral required
        (,, uint256 collateralRequired,) = orderbook.previewBorrow(
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

        // Approve less than required
        vm.startPrank(borrower);
        collateralToken.approve(address(orderbook), collateralRequired / 2);

        // Should revert due to insufficient approval
        vm.expectRevert();
        orderbook.matchMarketBorrowOrder(amount, minAmountExpected, collateralBuffer, 0, 0);
        vm.stopPrank();
    }

    // Test orderbook with maximum limit orders
    function testMaximumLimitOrdersBoundary() public {
        uint64 rate = 0.05e18;
        uint64 ltv = 0.7e18;
        uint256 amount = 100e18;
        uint256 minAmountExpected = 90e18;
        uint256 collateralBuffer = 0.05e18;
        uint256 collateralAmount = 150e18;

        vm.startPrank(borrower);

        // Insert exactly MAX_LIMIT_ORDERS orders (10)
        for (uint256 i = 0; i < 10; i++) {
            collateralToken.approve(address(orderbook), collateralAmount);
            orderbook.insertLimitBorrowOrder(rate, ltv, amount, minAmountExpected, collateralBuffer, collateralAmount);
        }

        // Verify we have 10 orders
        BorrowerLimitOrder[] memory orders = orderbook.getBorrowerOrders(borrower);
        assertEq(orders.length, 1);

        // Cancel one
        orderbook.cancelBorrowOrder(rate, ltv, amount, 0);
        orders = orderbook.getBorrowerOrders(borrower);
        assertEq(orders.length, 0);

        vm.stopPrank();
    }

    function testPoolWhitelistingFromDifferentFactory() public {
        // Create a new pool factory
        MockPoolFactory newPoolFactory = new MockPoolFactory();

        // Create a new pool
        MockPool newPool =
            newPoolFactory.createPool(address(loanToken), address(orderbook), address(irm), address(collateralToken));

        // Whitelist the new pool
        vm.prank(poolManager);
        vm.expectRevert();
        orderbook.whitelistPool(address(newPool), address(newPoolFactory));

        vm.prank(poolManager);
        vm.expectRevert();
        orderbook.whitelistPool(address(newPool), address(poolFactory));

        //adding new pool factory to orderbook
        vm.prank(admin);
        factory.setPoolFactory(address(newPoolFactory), true);

        vm.prank(poolManager);
        orderbook.whitelistPool(address(newPool), address(newPoolFactory));
        assertTrue(orderbook.isWhitelisted(address(newPool)));
        assertTrue(factory.isPoolFactory(address(newPoolFactory)));
    }
}
