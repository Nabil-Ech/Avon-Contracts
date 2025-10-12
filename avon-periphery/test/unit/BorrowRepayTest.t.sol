// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../BasePoolTest.t.sol";

contract BorrowRepayTest is BasePoolTest {
    function setUp() public override {
        super.setUp();
        // Add liquidity to the pool for borrowing tests
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);
    }

    function testBorrowWithExactAssets() public {
        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);

        vm.startPrank(borrower);

        // Deposit collateral
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower);

        // Borrow
        uint256 balanceBefore = loanToken.balanceOf(borrower);
        (uint256 assets, uint256 shares) = pool.borrow(borrowAmount, 0, borrower, borrower, borrowAmount);

        // Verify results
        assertEq(assets, borrowAmount, "Should receive requested borrow amount");
        assertGt(shares, 0, "Should receive borrow shares");
        assertEq(loanToken.balanceOf(borrower), balanceBefore + borrowAmount, "Loan token balance should increase");

        // Verify position
        _verifyPosition(borrower, borrowAmount, collateralAmount);
        vm.stopPrank();
    }

    function testBorrowWithExactShares() public {
        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);

        vm.startPrank(borrower);

        // Deposit collateral
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower);

        // First borrow to get share rate
        (, uint256 firstShares) = pool.borrow(borrowAmount / 2, 0, borrower, borrower, borrowAmount / 2);

        uint256 sharesToBorrow = firstShares;
        uint256 balanceBefore = loanToken.balanceOf(borrower);

        // Borrow with exact shares
        (uint256 secondAssets, uint256 secondShares) = pool.borrow(
            0,
            sharesToBorrow,
            borrower,
            borrower,
            1 // Minimum expected
        );

        // Verify results
        assertGt(secondAssets, 0, "Should receive assets");
        assertEq(secondShares, sharesToBorrow, "Should use exact shares requested");
        assertEq(loanToken.balanceOf(borrower), balanceBefore + secondAssets, "Loan token balance should increase");
        vm.stopPrank();
    }

    function testRepayWithExactAssets() public {
        // Setup borrow position
        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = 1e18;
        (, uint256 shares) = _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        // Repay
        vm.startPrank(borrower);
        loanToken.approve(address(pool), borrowAmount);
        uint256 balanceBefore = loanToken.balanceOf(borrower);
        (uint256 repaidAssets, uint256 repaidShares) = pool.repay(borrowAmount, 0, borrower);

        // Verify results
        assertEq(repaidAssets, borrowAmount, "Should repay requested amount");
        assertEq(repaidShares, shares, "Should repay all shares");
        assertEq(loanToken.balanceOf(borrower), balanceBefore - borrowAmount, "Loan token balance should decrease");

        // Verify position is cleared
        _verifyPosition(borrower, 0, collateralAmount);
        vm.stopPrank();
    }

    function testRepayWithExactShares() public {
        // Setup borrow position
        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = 1e18;
        (, uint256 shares) = _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        // Repay with shares
        vm.startPrank(borrower);
        loanToken.approve(address(pool), borrowAmount);
        uint256 balanceBefore = loanToken.balanceOf(borrower);
        (uint256 repaidAssets, uint256 repaidShares) = pool.repay(0, shares, borrower);

        // Verify results
        assertGt(repaidAssets, 0, "Should repay some assets");
        assertEq(repaidShares, shares, "Should repay requested shares");
        assertEq(loanToken.balanceOf(borrower), balanceBefore - repaidAssets, "Loan token balance should decrease");

        // Verify position is cleared
        _verifyPosition(borrower, 0, collateralAmount);
        vm.stopPrank();
    }

    function testPartialRepay() public {
        // Setup borrow position
        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = 1e18;
        (, uint256 shares) = _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        uint256 repayAmount = borrowAmount / 2;

        // Repay
        vm.startPrank(borrower);
        loanToken.approve(address(pool), repayAmount);
        (uint256 repaidAssets, uint256 repaidShares) = pool.repay(repayAmount, 0, borrower);

        // Verify partial repayment
        assertEq(repaidAssets, repayAmount, "Should repay requested amount");
        assertGt(repaidShares, 0, "Should repay some shares");
        assertLt(repaidShares, shares, "Should repay less than all shares");

        // Verify position still has debt
        _verifyPosition(borrower, borrowAmount - repayAmount, collateralAmount);
        vm.stopPrank();
    }

    function testBorrowWithInsufficientCollateral() public {
        uint256 borrowAmount = 500e6;
        uint256 insufficientCollateral = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER) / 2;

        vm.startPrank(borrower);

        // Deposit insufficient collateral
        collateralToken.approve(address(pool), insufficientCollateral);
        pool.depositCollateral(insufficientCollateral, borrower);

        // Try to borrow (should fail)
        vm.expectRevert(); // InsufficientCollateral
        pool.borrow(borrowAmount, 0, borrower, borrower, borrowAmount);

        vm.stopPrank();
    }

    function testBorrowWithInsufficientLiquidity() public {
        uint256 excessive = DEFAULT_DEPOSIT_AMOUNT * 2;
        uint256 collateralAmount = pool.previewBorrow(borrower, excessive, DEFAULT_COLLATERAL_BUFFER);
        assertEq(collateralAmount, 0, "Collateral amount should be zero for excessive borrow");

        vm.startPrank(borrower);

        // Deposit collateral
        collateralToken.approve(address(pool), 1e18);
        pool.depositCollateral(1e18, borrower);

        // Try to borrow more than pool has (should fail)
        vm.expectRevert(); // InsufficientLiquidity
        pool.borrow(excessive, 0, borrower, borrower, excessive);

        vm.stopPrank();
    }

    function testBorrowAsOtherWithoutPermission() public {
        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);

        // Setup collateral for borrower
        vm.startPrank(borrower);
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower);
        vm.stopPrank();

        // Try to borrow as borrower from another account (should fail)
        vm.startPrank(lender2);
        vm.expectRevert(); // Unauthorized
        pool.borrow(borrowAmount, 0, borrower, lender2, borrowAmount);
        vm.stopPrank();
    }

    function testBorrowAsOtherWithPermission() public {
        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);

        // Setup collateral for borrower
        vm.startPrank(borrower);
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower);

        // Give permission to lender2
        pool.setAuthorization(lender2, true);
        vm.stopPrank();

        // Borrow as borrower from lender2 account (should succeed now)
        vm.startPrank(lender2);
        (uint256 assets, uint256 shares) = pool.borrow(borrowAmount, 0, borrower, lender2, borrowAmount);

        // Verify borrow succeeded
        assertEq(assets, borrowAmount, "Should receive requested borrow amount");
        assertGt(shares, 0, "Should receive borrow shares");

        // Verify position is assigned to the borrower
        _verifyPosition(borrower, borrowAmount, collateralAmount);
        vm.stopPrank();
    }

    function testBorrowAndRepayWithBothZero() public {
        uint256 collateralAmount = pool.previewBorrow(borrower, 500e6, DEFAULT_COLLATERAL_BUFFER);

        vm.startPrank(borrower);

        // Deposit collateral
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower);

        // Try to borrow with both assets and shares as zero (should fail)
        vm.expectRevert(); // InvalidInput
        pool.borrow(0, 0, borrower, borrower, 0);
        vm.stopPrank();
    }

    function testBorrowWithZeroMinExpected() public {
        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);

        vm.startPrank(borrower);

        // Deposit collateral
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower);

        // Borrow with zero minExpected (should succeed)
        (uint256 assets, uint256 shares) = pool.borrow(borrowAmount, 0, borrower, borrower, 0);

        // Verify results
        assertEq(assets, borrowAmount, "Should receive requested borrow amount");
        assertGt(shares, 0, "Should receive borrow shares");
        vm.stopPrank();
    }

    function testBorrowWithTooHighMinExpected() public {
        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);

        vm.startPrank(borrower);

        // Deposit collateral
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower);

        // Borrow with too high minExpected (should fail)
        vm.expectRevert(); // InsufficientAmountReceived
        pool.borrow(borrowAmount, 0, borrower, borrower, borrowAmount + 1);
        vm.stopPrank();
    }

    function testBorrowWithInsufficientCollateralEdgeCase() public {
        uint256 borrowAmount = 500e6;
        // Get almost but not quite enough collateral
        uint256 collateralAmount = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);
        uint256 almostEnoughCollateral = collateralAmount - 0.01e18;

        vm.startPrank(borrower);

        // Deposit insufficient collateral
        collateralToken.approve(address(pool), almostEnoughCollateral);
        pool.depositCollateral(almostEnoughCollateral, borrower);

        // Try to borrow (should fail with InsufficientCollateral)
        vm.expectRevert(); // InsufficientCollateral
        pool.borrow(borrowAmount, 0, borrower, borrower, borrowAmount);
        vm.stopPrank();
    }

    function testBorrowWithExactSharesAndInsufficientCollateral() public {
        // First setup a successful borrow to calculate share rate
        uint256 borrowAmount = 100e6;
        uint256 collateralAmount = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);

        vm.startPrank(borrower);
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower);

        (, uint256 shares) = pool.borrow(borrowAmount, 0, borrower, borrower, borrowAmount);
        vm.stopPrank();

        // Now try to borrow with shares that would require more collateral than available
        address borrower2 = makeAddr("borrower2");
        vm.prank(owner);
        collateralToken.mint(borrower2, 0.1e18); // Very little collateral

        vm.startPrank(borrower2);
        collateralToken.approve(address(pool), 0.1e18);
        pool.depositCollateral(0.1e18, borrower2);

        // Try to borrow with shares (should fail)
        vm.expectRevert(); // InsufficientCollateral
        pool.borrow(
            0,
            shares * 5, // More shares than collateral can support
            borrower2,
            borrower2,
            1
        );
        vm.stopPrank();
    }

    function testRepayMoreThanBorrowed() public {
        // Setup small borrow position
        uint256 borrowAmount = 100e6;
        uint256 collateralAmount = 0.5e18;
        _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        // Try to repay more than borrowed
        uint256 excessiveRepayAmount = borrowAmount * 2;

        vm.startPrank(borrower);
        loanToken.approve(address(pool), excessiveRepayAmount);

        (uint256 repaidAssets,) = pool.repay(excessiveRepayAmount, 0, borrower);

        // Should only repay what was actually borrowed
        assertEq(repaidAssets, borrowAmount, "Should only repay the actual borrowed amount");
        _verifyPosition(borrower, 0, collateralAmount); // Position should be fully repaid
        vm.stopPrank();
    }

    function testRepayWithExactSharesMoreThanOwed() public {
        // Setup borrow position
        uint256 borrowAmount = 100e6;
        uint256 collateralAmount = 0.5e18;
        (, uint256 borrowShares) = _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        // Try to repay more shares than owed
        uint256 excessiveSharesAmount = borrowShares * 2;

        vm.startPrank(borrower);
        loanToken.approve(address(pool), borrowAmount * 2); // Approve enough for any asset amount

        (uint256 repaidAssets, uint256 repaidShares) = pool.repay(0, excessiveSharesAmount, borrower);

        // Should only repay the actual shares owed
        assertEq(repaidShares, borrowShares, "Should only repay actual shares owed");
        assertEq(repaidAssets, borrowAmount, "Should repay full borrow amount");
        _verifyPosition(borrower, 0, collateralAmount); // Position should be fully repaid
        vm.stopPrank();
    }

    function testRepayAsOtherPayer() public {
        // Setup borrow position
        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = 1e18;
        _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        // Have lender2 repay on behalf of borrower
        vm.startPrank(lender2);
        loanToken.approve(address(pool), borrowAmount);

        (uint256 repaidAssets, uint256 repaidShares) = pool.repay(
            borrowAmount,
            0,
            borrower // repay for borrower
        );

        // Verify repayment
        assertEq(repaidAssets, borrowAmount, "Should repay the requested amount");
        assertGt(repaidShares, 0, "Should burn shares");

        // Verify borrower's position is cleared
        _verifyPosition(borrower, 0, collateralAmount);
        vm.stopPrank();
    }

    function testRepayWithInsufficientAllowance() public {
        // Setup borrow position
        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = 1e18;
        _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        // Try to repay without sufficient approval
        vm.startPrank(borrower);
        loanToken.approve(address(pool), borrowAmount - 1); // Approve less than needed

        vm.expectRevert(); // SafeERC20: insufficient allowance
        pool.repay(borrowAmount, 0, borrower);
        vm.stopPrank();
    }

    function testBorrowAndRepayWithInterestAccrual() public {
        // Setup borrow position
        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = 1e18;
        (, uint256 borrowShares) = _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        // Fast forward time to accrue interest
        vm.warp(block.timestamp + 30 days);

        // Get updated position with accrued interest
        PoolGetter.BorrowPosition memory positionWithInterest = pool.getPosition(borrower);
        uint256 borrowAmountWithInterest = positionWithInterest.borrowAssets;

        // Verify interest accrued
        assertGt(borrowAmountWithInterest, borrowAmount, "Interest should have accrued");

        // Repay with exact shares
        vm.prank(owner);
        loanToken.mint(borrower, borrowAmountWithInterest - borrowAmount); // Mint extra tokens for interest

        vm.startPrank(borrower);
        loanToken.approve(address(pool), borrowAmountWithInterest);
        (uint256 repaidAssets, uint256 repaidShares) = pool.repay(0, borrowShares, borrower);

        // Verify full repayment
        assertGt(repaidAssets, borrowAmount, "Should repay original amount plus interest");
        assertEq(repaidShares, borrowShares, "Should repay all shares");
        _verifyPosition(borrower, 0, collateralAmount);
        vm.stopPrank();
    }
}
