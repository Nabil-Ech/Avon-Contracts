// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../BasePoolTest.t.sol";

contract CollateralManagementTest is BasePoolTest {
    function testDepositCollateral() public {
        uint256 collateralAmount = 1e18;

        vm.startPrank(borrower);
        collateralToken.approve(address(pool), collateralAmount);
        uint256 balanceBefore = collateralToken.balanceOf(borrower);

        pool.depositCollateral(collateralAmount, borrower);

        // Verify results
        assertEq(
            collateralToken.balanceOf(borrower), balanceBefore - collateralAmount, "Collateral balance should decrease"
        );
        _verifyPosition(borrower, 0, collateralAmount);
        vm.stopPrank();
    }

    function testWithdrawCollateral() public {
        uint256 collateralAmount = 1e18;

        // Setup - deposit collateral
        vm.startPrank(borrower);
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower);

        uint256 balanceBefore = collateralToken.balanceOf(borrower);
        pool.withdrawCollateral(collateralAmount, borrower, borrower);

        // Verify results
        assertEq(
            collateralToken.balanceOf(borrower), balanceBefore + collateralAmount, "Collateral balance should increase"
        );
        _verifyPosition(borrower, 0, 0);
        vm.stopPrank();
    }

    function testDepositCollateralForOther() public {
        uint256 collateralAmount = 1e18;

        vm.prank(owner);
        collateralToken.mint(lender1, collateralAmount);
        vm.startPrank(lender1);
        collateralToken.approve(address(pool), collateralAmount);

        pool.depositCollateral(collateralAmount, borrower);

        // Verify results
        _verifyPosition(borrower, 0, collateralAmount);
        vm.stopPrank();
    }

    function testWithdrawCollateralWithOutstandingDebt() public {
        // Setup - deposit, borrow, then try to withdraw
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = 1e18;

        vm.startPrank(borrower);
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower);

        // Borrow
        pool.borrow(borrowAmount, 0, borrower, borrower, borrowAmount);

        // Try to withdraw all collateral (should fail)
        vm.expectRevert(); // InsufficientCollateral
        pool.withdrawCollateral(collateralAmount, borrower, borrower);

        // Calculate safe withdrawal amount
        uint256 requiredCollateral = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);
        uint256 excessCollateral = collateralAmount - requiredCollateral;

        // Should be able to withdraw excess collateral
        if (excessCollateral > 0) {
            pool.withdrawCollateral(excessCollateral, borrower, borrower);
            _verifyPosition(borrower, borrowAmount, collateralAmount - excessCollateral);
        }
        vm.stopPrank();
    }

    function testWithdrawCollateralAsOtherWithoutPermission() public {
        uint256 collateralAmount = 1e18;

        // Setup - deposit collateral
        vm.startPrank(borrower);
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower);
        vm.stopPrank();

        // Try to withdraw as someone else (should fail)
        vm.startPrank(lender1);
        vm.expectRevert(); // Unauthorized
        pool.withdrawCollateral(collateralAmount, borrower, lender1);
        vm.stopPrank();
    }

    function testWithdrawCollateralAsOtherWithPermission() public {
        uint256 collateralAmount = 1e18;

        // Setup - deposit collateral and give permission
        vm.startPrank(borrower);
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower);
        pool.setAuthorization(lender1, true);
        vm.stopPrank();

        // Should be able to withdraw as authorized user
        vm.startPrank(lender1);
        pool.withdrawCollateral(collateralAmount, borrower, lender1);

        // Verify results
        assertEq(collateralToken.balanceOf(lender1), collateralAmount, "Authorized user should receive collateral");
        _verifyPosition(borrower, 0, 0);
        vm.stopPrank();
    }
}
