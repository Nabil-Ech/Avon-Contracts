// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../BasePoolTest.t.sol";
import {PoolStorage} from "../../src/pool/PoolStorage.sol";
import {PoolConstants} from "../../src/pool/utils/PoolConstants.sol";
import {PoolErrors} from "../../src/pool/utils/PoolErrors.sol";
import {PoolEvents} from "../../src/pool/utils/PoolEvents.sol";
import {PoolGetter} from "../../src/pool/utils/PoolGetter.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AtomicExecutor} from "../utils/AtomicExecutor.sol";

/// @title TransientLiquidationBonusTest
contract TransientLiquidationBonusTest is BasePoolTest {
    uint256 constant TRANSIENT_LIQUIDATION_BONUS = 1.02e18; // 2%
    uint256 constant HIGHER_LIQUIDATION_BONUS = 1.021e18; // 2.1%
    uint256 constant STANDARD_REPAID_SHARES = 100e6;
    uint256 constant LARGE_REPAID_SHARES = 1000e6;
    uint256 constant SMALL_REPAID_SHARES = 50e6;
    uint256 constant HEALTH_TOLERANCE = 1e10; // Minimum tolerance for health score assertions

    function setUp() public override {
        super.setUp();
        vm.label(owner, "Owner");
        vm.label(manager, "Manager");
        vm.label(lender1, "Lender1");
        vm.label(lender2, "Lender2");
        vm.label(borrower, "Borrower");
        vm.label(liquidator, "Liquidator");
        vm.label(feeRecipient, "FeeRecipient");
        vm.label(random, "Random");
        vm.label(address(pool), "Pool");
        vm.label(address(loanToken), "LoanToken");
        vm.label(address(collateralToken), "CollateralToken");
    }

    /// @notice Test updateTransientLiquidationBonus function edge cases and error conditions
    function testTransientBonus_EdgeCasesAndValidation() public {
        // Initially should return 0
        assertEq(pool.getTransientLiquidationBonus(), 0, "Should initially return 0");

        // Grant AUCTION_ROLE to an auction service
        address auctionService = makeAddr("auctionService");
        vm.startPrank(manager);
        pool.grantAuctionRole(auctionService);
        vm.stopPrank();

        vm.startPrank(auctionService);

        // Test 1: Update to zero should revert (must be > WAD)
        vm.expectRevert(PoolErrors.InvalidInput.selector);
        pool.updateTransientLiquidationBonus(0);

        // Test 2: Update to exactly WAD should revert (must be > WAD, not >= WAD)
        vm.expectRevert(PoolErrors.InvalidInput.selector);
        pool.updateTransientLiquidationBonus(1e18);

        // Test 3: Successful update with valid bonus
        vm.expectEmit(true, true, false, true, address(pool));
        emit PoolEvents.TransientLiquidationBonusSet(address(pool), auctionService, 0, TRANSIENT_LIQUIDATION_BONUS);
        pool.updateTransientLiquidationBonus(TRANSIENT_LIQUIDATION_BONUS);
        assertEq(pool.getTransientLiquidationBonus(), TRANSIENT_LIQUIDATION_BONUS, "Should return set transient bonus");

        // Test 4: Update to value >= persistent liquidation bonus should revert
        vm.expectRevert(PoolErrors.InvalidInput.selector);
        pool.updateTransientLiquidationBonus(1.03e18);

        // Test 5: Update to value just below persistent liquidation bonus should succeed
        uint256 validBonus = 1.029e18; // Just below 1.03e18
        vm.expectEmit(true, true, false, true, address(pool));
        emit PoolEvents.TransientLiquidationBonusSet(
            address(pool), auctionService, TRANSIENT_LIQUIDATION_BONUS, validBonus
        );
        pool.updateTransientLiquidationBonus(validBonus);
        assertEq(pool.getTransientLiquidationBonus(), validBonus, "Should return updated transient bonus");

        // Test 6: Update to lower value should revert (must be >= previous transient bonus)
        vm.expectRevert(PoolErrors.InvalidInput.selector);
        pool.updateTransientLiquidationBonus(1.01e18); // Lower than current 1.029e18

        // Test 7: Update to maximum valid value (just below persistent liquidation bonus)
        uint256 maxValidBonus = 1.03e18 - 1; // Largest valid value
        vm.expectEmit(true, true, false, true, address(pool));
        emit PoolEvents.TransientLiquidationBonusSet(address(pool), auctionService, validBonus, maxValidBonus);
        pool.updateTransientLiquidationBonus(maxValidBonus);
        assertEq(pool.getTransientLiquidationBonus(), maxValidBonus, "Should return max valid transient bonus");

        // Test 8: Setting to same value is allowed
        vm.expectEmit(true, true, false, true, address(pool));
        emit PoolEvents.TransientLiquidationBonusSet(address(pool), auctionService, maxValidBonus, maxValidBonus);
        pool.updateTransientLiquidationBonus(maxValidBonus);
        assertEq(pool.getTransientLiquidationBonus(), maxValidBonus, "Should still return same transient bonus");

        vm.stopPrank();
    }

    /// @notice Test access control for transient liquidation bonus update
    function testTransientBonus_AccessControl() public {
        address unauthorizedUser = makeAddr("unauthorizedUser");
        vm.startPrank(unauthorizedUser);

        // Should revert when caller lacks AUCTION_ROLE
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorizedUser, pool.AUCTION_ROLE()
            )
        );
        pool.updateTransientLiquidationBonus(TRANSIENT_LIQUIDATION_BONUS);

        vm.stopPrank();
        address auctionService = makeAddr("auctionService");
        vm.startPrank(manager);
        pool.grantAuctionRole(auctionService);
        vm.stopPrank();
        vm.startPrank(auctionService);

        // Should succeed with AUCTION_ROLE
        vm.expectEmit(true, true, false, true, address(pool));
        emit PoolEvents.TransientLiquidationBonusSet(address(pool), auctionService, 0, TRANSIENT_LIQUIDATION_BONUS);
        pool.updateTransientLiquidationBonus(TRANSIENT_LIQUIDATION_BONUS);
        assertEq(pool.getTransientLiquidationBonus(), TRANSIENT_LIQUIDATION_BONUS, "Transient bonus should be set");

        vm.stopPrank();
        vm.startPrank(manager);
        pool.revokeAuctionRole(auctionService);
        vm.stopPrank();
        vm.startPrank(auctionService);

        // Should revert again after revoke
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, auctionService, pool.AUCTION_ROLE()
            )
        );
        pool.updateTransientLiquidationBonus(TRANSIENT_LIQUIDATION_BONUS);
        vm.stopPrank();
    }

    /// @notice Test that different transient bonus amounts result in proportionally different seized collateral
    function testTransientBonus_AmountsAffectSeizedCollateral() public {
        // Setup AtomicExecutor
        AtomicExecutor exec = new AtomicExecutor();

        vm.startPrank(manager);
        pool.grantAuctionRole(address(exec));
        vm.stopPrank();

        // Fund the executor with loan tokens
        vm.prank(owner);
        loanToken.mint(address(exec), 1_000_000e6);

        // Approve pool from the executor
        vm.prank(address(exec));
        loanToken.approve(address(pool), type(uint256).max);

        // Setup sufficient liquidity for both positions
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT * 2);

        // Create two identical borrowing positions
        address borrower1 = makeAddr("borrower1");
        address borrower2 = makeAddr("borrower2");

        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = pool.previewBorrow(borrower1, borrowAmount, DEFAULT_COLLATERAL_BUFFER);

        // Setup identical positions for both borrowers
        vm.startPrank(owner);
        collateralToken.mint(borrower1, collateralAmount);
        collateralToken.mint(borrower2, collateralAmount);
        vm.stopPrank();

        // Borrower 1 setup
        vm.startPrank(borrower1);
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower1);
        pool.borrow(borrowAmount, 0, borrower1, borrower1, borrowAmount);
        vm.stopPrank();

        // Borrower 2 setup (identical)
        vm.startPrank(borrower2);
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower2);
        pool.borrow(borrowAmount, 0, borrower2, borrower2, borrowAmount);
        vm.stopPrank();

        // Make both positions liquidatable
        _makePositionUnsafe();

        // Step 1: Liquidate first position with standard bonus

        uint256 before1 = collateralToken.balanceOf(address(exec));
        exec.setBonusAndLiquidate(
            address(pool), TRANSIENT_LIQUIDATION_BONUS, borrower1, 0, LARGE_REPAID_SHARES, 0, type(uint256).max
        );
        uint256 seizedLow = collateralToken.balanceOf(address(exec)) - before1;

        // Step 2: Liquidate second position with higher bonus
        uint256 before2 = collateralToken.balanceOf(address(exec));
        exec.setBonusAndLiquidate(
            address(pool), HIGHER_LIQUIDATION_BONUS, borrower2, 0, LARGE_REPAID_SHARES, 0, type(uint256).max
        );
        uint256 seizedHigh = collateralToken.balanceOf(address(exec)) - before2;

        // Verify higher bonus results in more seized collateral
        assertGt(seizedHigh, seizedLow, "Higher bonus should result in more seized collateral");
    }

    /// @notice Test configureAuctionPriorityWindow function
    function testAuctionWindow_Configuration() public {
        vm.startPrank(manager);

        // Test disabling auction priority window (set to 0)
        uint256 prevWindow = pool.getAuctionPriorityWindow();
        vm.expectEmit(true, true, false, true, address(pool));
        emit PoolEvents.AuctionPriorityWindowUpdated(address(pool), manager, prevWindow, 0);
        pool.configureAuctionPriorityWindow(0);
        assertEq(pool.getAuctionPriorityWindow(), 0, "Auction priority window should be disabled");

        // Test AlreadySet validation - try to set to same value (0)
        vm.expectRevert(PoolErrors.AlreadySet.selector);
        pool.configureAuctionPriorityWindow(0);

        // Test enabling auction priority window with 5bps
        prevWindow = pool.getAuctionPriorityWindow();
        vm.expectEmit(true, true, false, true, address(pool));
        emit PoolEvents.AuctionPriorityWindowUpdated(address(pool), manager, prevWindow, 0.0005e18);
        pool.configureAuctionPriorityWindow(0.0005e18);
        assertEq(pool.getAuctionPriorityWindow(), 0.0005e18, "Auction priority window should be 5bps");

        // Test AlreadySet validation again - try to set to same value (5bps)
        vm.expectRevert(PoolErrors.AlreadySet.selector);
        pool.configureAuctionPriorityWindow(0.0005e18);

        // Test setting to max 10bps
        prevWindow = pool.getAuctionPriorityWindow();
        vm.expectEmit(true, true, false, true, address(pool));
        emit PoolEvents.AuctionPriorityWindowUpdated(address(pool), manager, prevWindow, 0.001e18);
        pool.configureAuctionPriorityWindow(0.001e18);
        assertEq(pool.getAuctionPriorityWindow(), 0.001e18, "Auction priority window should be 10bps");

        vm.stopPrank();

        // Test unauthorized access
        vm.startPrank(lender1);
        vm.expectRevert(PoolErrors.Unauthorized.selector);
        pool.configureAuctionPriorityWindow(0);
        vm.stopPrank();

        // Test setting above max
        vm.startPrank(manager);
        vm.expectRevert(PoolErrors.InvalidInput.selector);
        pool.configureAuctionPriorityWindow(0.002e18); // 20bps > 10bps max
        vm.stopPrank();
    }

    /// @notice Test access control and functionality of grantAuctionRole and revokeAuctionRole functions
    function testAuctionRole_GrantRevokeAccessControl() public {
        address auctionService = makeAddr("auctionService");
        address unauthorizedUser = makeAddr("unauthorizedUser");

        // Test 1: Unauthorized user cannot grant auction role
        vm.startPrank(unauthorizedUser);
        vm.expectRevert(PoolErrors.Unauthorized.selector);
        pool.grantAuctionRole(auctionService);
        vm.stopPrank();

        // Test 2: Unauthorized user cannot revoke auction role
        vm.startPrank(unauthorizedUser);
        vm.expectRevert(PoolErrors.Unauthorized.selector);
        pool.revokeAuctionRole(auctionService);
        vm.stopPrank();

        // Test 3: Manager can grant auction role
        vm.startPrank(manager);

        // Should emit AuctionRoleGranted event
        vm.expectEmit(true, true, true, true, address(pool));
        emit PoolEvents.AuctionRoleGranted(address(pool), manager, auctionService);

        pool.grantAuctionRole(auctionService);

        // Verify role was granted
        assertTrue(pool.hasRole(pool.AUCTION_ROLE(), auctionService), "Auction role should be granted");
        vm.stopPrank();

        // Test 4: Manager can revoke auction role
        vm.startPrank(manager);

        // Should emit AuctionRoleRevoked event
        vm.expectEmit(true, true, true, true, address(pool));
        emit PoolEvents.AuctionRoleRevoked(address(pool), manager, auctionService);

        pool.revokeAuctionRole(auctionService);

        // Verify role was revoked
        assertFalse(pool.hasRole(pool.AUCTION_ROLE(), auctionService), "Auction role should be revoked");
        vm.stopPrank();

        // Test 5: Zero address validation for grant
        vm.startPrank(manager);
        vm.expectRevert(PoolErrors.InvalidInput.selector);
        pool.grantAuctionRole(address(0));
        vm.stopPrank();

        // Test 6: Zero address validation for revoke
        vm.startPrank(manager);
        vm.expectRevert(PoolErrors.InvalidInput.selector);
        pool.revokeAuctionRole(address(0));
        vm.stopPrank();

        // Test 7: Verify auction service can use granted role
        vm.startPrank(manager);

        // Should emit AuctionRoleGranted event
        vm.expectEmit(true, true, true, true, address(pool));
        emit PoolEvents.AuctionRoleGranted(address(pool), manager, auctionService);

        pool.grantAuctionRole(auctionService);
        vm.stopPrank();

        vm.startPrank(auctionService);
        // Should succeed - auction service has the role
        pool.updateTransientLiquidationBonus(TRANSIENT_LIQUIDATION_BONUS);
        vm.stopPrank();

        // Test 8: Verify auction service cannot use revoked role
        vm.startPrank(manager);

        // Should emit AuctionRoleRevoked event
        vm.expectEmit(true, true, true, true, address(pool));
        emit PoolEvents.AuctionRoleRevoked(address(pool), manager, auctionService);

        pool.revokeAuctionRole(auctionService);
        vm.stopPrank();

        vm.startPrank(auctionService);
        // Should fail - auction service no longer has the role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, auctionService, pool.AUCTION_ROLE()
            )
        );
        pool.updateTransientLiquidationBonus(TRANSIENT_LIQUIDATION_BONUS);
        vm.stopPrank();
    }

    /// @notice Comprehensive test for auction role management edge cases and admin verification
    function testAuctionRole_ComprehensiveEdgeCases() public {
        address auctionService1 = makeAddr("auctionService1");
        address auctionService2 = makeAddr("auctionService2");

        // Test 1: Verify PROPOSER_ROLE is admin for AUCTION_ROLE
        bytes32 auctionRoleAdmin = pool.getRoleAdmin(pool.AUCTION_ROLE());
        assertEq(auctionRoleAdmin, pool.PROPOSER_ROLE(), "PROPOSER_ROLE should be admin for AUCTION_ROLE");

        // Test 2: Verify pool contract has PROPOSER_ROLE
        assertTrue(pool.hasRole(pool.PROPOSER_ROLE(), address(pool)), "Pool should have PROPOSER_ROLE");

        // Test 3: Grant same role twice (should not revert, but second grant should be no-op)
        vm.startPrank(manager);

        // First grant - should emit both OpenZeppelin and custom events
        vm.expectEmit(true, true, true, true, address(pool));
        emit PoolEvents.AuctionRoleGranted(address(pool), manager, auctionService1);

        pool.grantAuctionRole(auctionService1);
        assertTrue(pool.hasRole(pool.AUCTION_ROLE(), auctionService1), "First grant should succeed");

        // Second grant to same address - should still emit custom event but OpenZeppelin event won't fire
        vm.expectEmit(true, true, true, true, address(pool));
        emit PoolEvents.AuctionRoleGranted(address(pool), manager, auctionService1);

        pool.grantAuctionRole(auctionService1);
        assertTrue(pool.hasRole(pool.AUCTION_ROLE(), auctionService1), "Second grant should not break anything");

        vm.stopPrank();

        // Test 4: Multiple role holders can coexist
        vm.startPrank(manager);

        vm.expectEmit(true, true, true, true, address(pool));
        emit PoolEvents.AuctionRoleGranted(address(pool), manager, auctionService2);

        pool.grantAuctionRole(auctionService2);

        // Both should have the role
        assertTrue(pool.hasRole(pool.AUCTION_ROLE(), auctionService1), "Service1 should still have role");
        assertTrue(pool.hasRole(pool.AUCTION_ROLE(), auctionService2), "Service2 should have role");

        vm.stopPrank();

        // Test 5: Both services can use auction functions
        vm.startPrank(auctionService1);
        pool.updateTransientLiquidationBonus(TRANSIENT_LIQUIDATION_BONUS);
        assertEq(pool.getTransientLiquidationBonus(), TRANSIENT_LIQUIDATION_BONUS, "Service1 should set bonus");
        vm.stopPrank();

        vm.startPrank(auctionService2);
        pool.updateTransientLiquidationBonus(HIGHER_LIQUIDATION_BONUS);
        assertEq(pool.getTransientLiquidationBonus(), HIGHER_LIQUIDATION_BONUS, "Service2 should update bonus");
        vm.stopPrank();

        // Test 6: Revoke from non-holder (should not revert)
        address nonHolder = makeAddr("nonHolder");
        vm.startPrank(manager);

        vm.expectEmit(true, true, true, true, address(pool));
        emit PoolEvents.AuctionRoleRevoked(address(pool), manager, nonHolder);

        pool.revokeAuctionRole(nonHolder); // Should not revert even if they don't have the role
        vm.stopPrank();

        // Test 7: Revoke one, other should still work
        vm.startPrank(manager);

        vm.expectEmit(true, true, true, true, address(pool));
        emit PoolEvents.AuctionRoleRevoked(address(pool), manager, auctionService1);

        pool.revokeAuctionRole(auctionService1);
        vm.stopPrank();

        // Service1 should no longer work
        vm.startPrank(auctionService1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, auctionService1, pool.AUCTION_ROLE()
            )
        );
        pool.updateTransientLiquidationBonus(TRANSIENT_LIQUIDATION_BONUS);
        vm.stopPrank();

        // Service2 should still work
        vm.startPrank(auctionService2);
        pool.updateTransientLiquidationBonus(HIGHER_LIQUIDATION_BONUS);
        vm.stopPrank();
    }

    /// @notice Test that auction priority window blocks non-auction liquidations and allows auction liquidations
    function testAuctionWindow_BlocksNonAuctionLiquidations() public {
        // Setup AtomicExecutor
        AtomicExecutor exec = new AtomicExecutor();

        vm.startPrank(manager);
        pool.grantAuctionRole(address(exec));
        vm.stopPrank();

        // Fund the executor with loan tokens
        vm.prank(owner);
        loanToken.mint(address(exec), 1_000_000e6);

        // Approve pool from the executor
        vm.prank(address(exec));
        loanToken.approve(address(pool), type(uint256).max);

        // Setup sufficient liquidity
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Create borrowing position
        address borrower1 = makeAddr("borrower1");

        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = pool.previewBorrow(borrower1, borrowAmount, DEFAULT_COLLATERAL_BUFFER);

        // Setup position for borrower
        vm.startPrank(owner);
        collateralToken.mint(borrower1, collateralAmount);
        vm.stopPrank();

        // Borrower setup
        vm.startPrank(borrower1);
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower1);
        pool.borrow(borrowAmount, 0, borrower1, borrower1, borrowAmount);
        vm.stopPrank();

        // Get current position data to calculate exact price needed
        PoolGetter.BorrowPosition memory pos = pool.getPosition(borrower1);

        // Calculate price for 99.95% health (within priority window)
        uint256 ltv = pool.getLTV();
        uint256 targetPrice = _calculatePriceForHealth(9995e14, pos.collateral, pos.borrowAssets, ltv);

        vm.prank(owner);
        oracle.setPrice(targetPrice);

        // Verify the health score is actually 99.95% as intended
        uint256 actualHealth = _calculateHealthScore(pos.collateral, pos.borrowAssets, targetPrice, ltv);
        assertApproxEqAbs(actualHealth, 9995e14, HEALTH_TOLERANCE, "Health should be approximately 99.95%");

        // Fund random user for regular liquidations
        vm.prank(owner);
        loanToken.mint(random, 1_000_000e6);
        vm.prank(random);
        loanToken.approve(address(pool), type(uint256).max);

        // Step 1: Verify non-auction liquidation fails within priority window
        vm.prank(random);
        vm.expectRevert(PoolErrors.NonAuctionLiquidationWithinAuctionPriorityWindow.selector);
        pool.liquidate(borrower1, 0, LARGE_REPAID_SHARES, 0, type(uint256).max, "");

        // Step 2: Verify auction liquidation succeeds within priority window
        uint256 before = collateralToken.balanceOf(address(exec));
        exec.setBonusAndLiquidate(
            address(pool), TRANSIENT_LIQUIDATION_BONUS, borrower1, 0, LARGE_REPAID_SHARES, 0, type(uint256).max
        );
        uint256 seized = collateralToken.balanceOf(address(exec)) - before;

        assertGt(seized, 0, "Auction liquidation should succeed within priority window");
    }

    /// @notice Test that liquidation bypasses priority window when auction priority window is disabled
    function testAuctionWindow_BypassWhenDisabled() public {
        // Setup AtomicExecutor
        AtomicExecutor exec = new AtomicExecutor();

        vm.startPrank(manager);
        pool.grantAuctionRole(address(exec));
        pool.configureAuctionPriorityWindow(0);
        vm.stopPrank();

        // Fund the executor with loan tokens
        vm.prank(owner);
        loanToken.mint(address(exec), 1_000_000e6);

        // Approve pool from the executor
        vm.prank(address(exec));
        loanToken.approve(address(pool), type(uint256).max);

        // Setup sufficient liquidity
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Create borrowing position
        address borrower1 = makeAddr("borrower1");

        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = pool.previewBorrow(borrower1, borrowAmount, DEFAULT_COLLATERAL_BUFFER);

        // Setup position for borrower
        vm.startPrank(owner);
        collateralToken.mint(borrower1, collateralAmount);
        vm.stopPrank();

        // Borrower setup
        vm.startPrank(borrower1);
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower1);
        pool.borrow(borrowAmount, 0, borrower1, borrower1, borrowAmount);
        vm.stopPrank();

        // Get current position data to calculate exact price needed
        PoolGetter.BorrowPosition memory pos = pool.getPosition(borrower1);

        // Calculate price for 99.95% health (within priority window)
        uint256 ltv = pool.getLTV();
        uint256 targetPrice = _calculatePriceForHealth(9995e14, pos.collateral, pos.borrowAssets, ltv);

        vm.prank(owner);
        oracle.setPrice(targetPrice);

        // Verify the health score is actually 99.95% as intended
        uint256 actualHealth = _calculateHealthScore(pos.collateral, pos.borrowAssets, targetPrice, ltv);
        assertApproxEqAbs(actualHealth, 9995e14, HEALTH_TOLERANCE, "Health should be approximately 99.95%");

        // Step 1: Verify regular liquidation succeeds when priority window is disabled
        uint256 before = collateralToken.balanceOf(address(exec));
        vm.prank(address(exec));
        pool.liquidate(borrower1, 0, LARGE_REPAID_SHARES, 0, type(uint256).max, "");
        uint256 seized = collateralToken.balanceOf(address(exec)) - before;

        assertGt(seized, 0, "Regular liquidation should succeed when priority window is disabled");
    }

    /// @notice Test priority window boundary conditions
    function testAuctionWindow_BoundaryConditions() public {
        // Setup AtomicExecutor
        AtomicExecutor exec = new AtomicExecutor();

        vm.startPrank(manager);
        pool.grantAuctionRole(address(exec));
        vm.stopPrank();

        // Fund the executor
        vm.prank(owner);
        loanToken.mint(address(exec), 1_000_000e6);

        vm.prank(address(exec));
        loanToken.approve(address(pool), type(uint256).max);

        // Setup sufficient liquidity
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT * 3);

        // Create three borrowing positions for different test scenarios
        address borrowerHealthy = makeAddr("borrowerHealthy");
        address borrowerBelowWindow = makeAddr("borrowerBelowWindow");
        address borrowerWithinWindow = makeAddr("borrowerWithinWindow");

        uint256 borrowAmount = 300e6;
        uint256 collateralAmount = pool.previewBorrow(borrowerHealthy, borrowAmount, DEFAULT_COLLATERAL_BUFFER);

        // Setup identical positions
        address[3] memory borrowers = [borrowerHealthy, borrowerBelowWindow, borrowerWithinWindow];
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(owner);
            collateralToken.mint(borrowers[i], collateralAmount);

            vm.startPrank(borrowers[i]);
            collateralToken.approve(address(pool), collateralAmount);
            pool.depositCollateral(collateralAmount, borrowers[i]);
            pool.borrow(borrowAmount, 0, borrowers[i], borrowers[i], borrowAmount);
            vm.stopPrank();
        }

        // Get position data for calculations
        PoolGetter.BorrowPosition memory pos = pool.getPosition(borrowerHealthy);
        uint256 ltv = pool.getLTV();

        // Set prices for different health levels

        uint256 auctionWindow = pool.getAuctionPriorityWindow();

        // Test healthy position - should not be liquidatable at all
        // Adjust price to ensure position is definitely healthy (e.g., 100.5% health)
        uint256 priceHealthy = _calculatePriceForHealth(1005e15, pos.collateral, pos.borrowAssets, ltv);
        vm.prank(owner);
        oracle.setPrice(priceHealthy);

        // Verify position is actually healthy
        PoolGetter.BorrowPosition memory posHealthy = pool.getPosition(borrowerHealthy);
        uint256 healthAbove = _calculateHealthScore(posHealthy.collateral, posHealthy.borrowAssets, priceHealthy, ltv);
        assertGt(healthAbove, 1e18, "Position should be healthy");

        vm.prank(address(exec));
        vm.expectRevert(PoolErrors.HealthyPosition.selector);
        pool.liquidate(borrowerHealthy, 0, SMALL_REPAID_SHARES, 0, type(uint256).max, "");

        // Test position below priority window - should allow regular liquidation
        // Priority window is 99.9% to 100%, so use 99.8% health (clearly outside window)
        uint256 priceBelowWindow = _calculatePriceForHealth(998e15, pos.collateral, pos.borrowAssets, ltv);
        vm.prank(owner);
        oracle.setPrice(priceBelowWindow);

        // Verify position is below priority window
        PoolGetter.BorrowPosition memory posBelowWindow = pool.getPosition(borrowerBelowWindow);
        uint256 healthBelowWindow =
            _calculateHealthScore(posBelowWindow.collateral, posBelowWindow.borrowAssets, priceBelowWindow, ltv);
        assertApproxEqAbs(healthBelowWindow, 998e15, HEALTH_TOLERANCE, "Health should be approximately 99.8%");
        assertLt(healthBelowWindow, 1e18 - auctionWindow, "Position should be below priority window");

        // Fund random user for regular liquidations
        vm.prank(owner);
        loanToken.mint(random, 1_000_000e6);
        vm.prank(random);
        loanToken.approve(address(pool), type(uint256).max);

        uint256 beforeBelowWindow = collateralToken.balanceOf(random);
        vm.prank(random);
        pool.liquidate(borrowerBelowWindow, 0, SMALL_REPAID_SHARES, 0, type(uint256).max, "");
        uint256 seizedBelowWindow = collateralToken.balanceOf(random) - beforeBelowWindow;

        assertGt(seizedBelowWindow, 0, "Liquidation should succeed below priority window");

        // Test position within priority window - should require auction role
        // Set to 99.95% health (within priority window)
        uint256 priceWithinWindow = _calculatePriceForHealth(9995e14, pos.collateral, pos.borrowAssets, ltv);
        vm.prank(owner);
        oracle.setPrice(priceWithinWindow);

        // Verify position is within priority window
        PoolGetter.BorrowPosition memory posWithinWindow = pool.getPosition(borrowerWithinWindow);
        uint256 healthWithinWindow =
            _calculateHealthScore(posWithinWindow.collateral, posWithinWindow.borrowAssets, priceWithinWindow, ltv);
        assertApproxEqAbs(healthWithinWindow, 9995e14, HEALTH_TOLERANCE, "Health should be approximately 99.95%");
        assertGt(healthWithinWindow, 1e18 - auctionWindow, "Position should be within priority window");

        vm.prank(address(exec));
        vm.expectRevert(PoolErrors.NonAuctionLiquidationWithinAuctionPriorityWindow.selector);
        pool.liquidate(borrowerWithinWindow, 0, SMALL_REPAID_SHARES, 0, type(uint256).max, "");

        // But auction liquidation should work
        uint256 beforeWithinWindow = collateralToken.balanceOf(address(exec));
        exec.setBonusAndLiquidate(
            address(pool),
            TRANSIENT_LIQUIDATION_BONUS,
            borrowerWithinWindow,
            0,
            SMALL_REPAID_SHARES,
            0,
            type(uint256).max
        );
        uint256 seizedWithinWindow = collateralToken.balanceOf(address(exec)) - beforeWithinWindow;

        assertGt(seizedWithinWindow, 0, "Auction liquidation should succeed within priority window");
    }

    /// @notice Test toggling priority window
    function testAuctionWindow_TogglingDuringLiquidations() public {
        // Setup AtomicExecutor
        AtomicExecutor exec = new AtomicExecutor();

        vm.startPrank(manager);
        pool.grantAuctionRole(address(exec));
        vm.stopPrank();

        // Fund the executor
        vm.prank(owner);
        loanToken.mint(address(exec), 1_000_000e6);

        vm.prank(address(exec));
        loanToken.approve(address(pool), type(uint256).max);

        // Setup sufficient liquidity
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT * 2);

        // Create two borrowing positions
        address borrower1 = makeAddr("borrower1");
        address borrower2 = makeAddr("borrower2");

        uint256 borrowAmount = 400e6;
        uint256 collateralAmount = pool.previewBorrow(borrower1, borrowAmount, DEFAULT_COLLATERAL_BUFFER);

        // Setup positions
        address[2] memory borrowers = [borrower1, borrower2];
        for (uint256 i = 0; i < 2; i++) {
            vm.prank(owner);
            collateralToken.mint(borrowers[i], collateralAmount);

            vm.startPrank(borrowers[i]);
            collateralToken.approve(address(pool), collateralAmount);
            pool.depositCollateral(collateralAmount, borrowers[i]);
            pool.borrow(borrowAmount, 0, borrowers[i], borrowers[i], borrowAmount);
            vm.stopPrank();
        }

        // Get position data for calculations
        PoolGetter.BorrowPosition memory pos = pool.getPosition(borrower1);

        // Set price within priority window (99.95% health)
        uint256 ltv = pool.getLTV();
        uint256 targetPrice = _calculatePriceForHealth(9995e14, pos.collateral, pos.borrowAssets, ltv);
        vm.prank(owner);
        oracle.setPrice(targetPrice);

        // Step 1: Verify regular liquidation fails within priority window
        vm.prank(address(exec));
        vm.expectRevert(PoolErrors.NonAuctionLiquidationWithinAuctionPriorityWindow.selector);
        pool.liquidate(borrower1, 0, STANDARD_REPAID_SHARES, 0, type(uint256).max, "");

        // Step 2: Verify auction liquidation succeeds for same position
        uint256 before1 = collateralToken.balanceOf(address(exec));
        exec.setBonusAndLiquidate(
            address(pool), TRANSIENT_LIQUIDATION_BONUS, borrower1, 0, STANDARD_REPAID_SHARES, 0, type(uint256).max
        );
        uint256 seized1 = collateralToken.balanceOf(address(exec)) - before1;
        assertGt(seized1, 0, "Auction liquidation should succeed within priority window");

        // Step 3: Disable priority window and verify regular liquidation succeeds
        vm.prank(manager);
        pool.configureAuctionPriorityWindow(0);

        uint256 before2 = collateralToken.balanceOf(address(exec));
        vm.prank(address(exec));
        pool.liquidate(borrower2, 0, STANDARD_REPAID_SHARES, 0, type(uint256).max, "");
        uint256 seized2 = collateralToken.balanceOf(address(exec)) - before2;
        assertGt(seized2, 0, "Regular liquidation should succeed when priority window is disabled");
    }

    /// @notice Helper to calculate current health score of a position
    function _calculateHealthScore(uint256 collateral, uint256 borrowAssets, uint256 oraclePrice, uint256 ltv)
        internal
        pure
        returns (uint256)
    {
        // health = ((collateral * price) / SCALE) * ltv / WAD / borrowAssets
        uint256 colVal = Math.mulDiv(collateral, oraclePrice, PoolConstants.ORACLE_PRICE_SCALE);
        uint256 tmp = Math.mulDiv(colVal, ltv, PoolConstants.WAD);
        return Math.mulDiv(tmp, PoolConstants.WAD, borrowAssets);
    }

    /// @notice Helper to calculate exact oracle price for target health score
    function _calculatePriceForHealth(uint256 targetHealth, uint256 collateral, uint256 borrowAssets, uint256 ltv)
        internal
        pure
        returns (uint256)
    {
        // price = targetHealth * borrowAssets * SCALE / (collateral * ltv)
        // Scale down early by WAD to keep numbers small.
        uint256 num = Math.mulDiv(targetHealth, borrowAssets, PoolConstants.WAD);
        num = Math.mulDiv(num, PoolConstants.ORACLE_PRICE_SCALE, 1);
        uint256 den = Math.mulDiv(collateral, ltv, PoolConstants.WAD);
        return Math.mulDiv(num, 1, den);
    }
}
