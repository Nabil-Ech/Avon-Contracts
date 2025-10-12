// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../BasePoolTest.t.sol";

contract CompleteFlowTest is BasePoolTest {
    function testCompleteLendingBorrowingCycle() public {
        // Step 1: Lender deposits
        uint256 depositAmount = 1000e6;
        vm.startPrank(lender1);
        loanToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount, lender1);
        vm.stopPrank();

        // Step 2: Borrower deposits collateral
        uint256 collateralAmount = 1e18;
        vm.startPrank(borrower);
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, borrower);

        // Step 3: Borrower borrows
        uint256 borrowAmount = 500e6;

        pool.borrow(borrowAmount, 0, borrower, borrower, borrowAmount);

        // Step 4: Wait some time for interest to accrue
        vm.warp(block.timestamp + 30 days);

        // Step 5: Borrower repays with interest
        vm.stopPrank();
        vm.prank(owner);
        loanToken.mint(borrower, 25e6); // Mint extra for interest
        vm.startPrank(borrower);
        uint256 repayAmount = borrowAmount * 105 / 100; // 5% extra for interest
        loanToken.approve(address(pool), repayAmount);

        pool.repay(repayAmount, 0, borrower);

        // Step 6: Borrower withdraws collateral
        pool.withdrawCollateral(collateralAmount, borrower, borrower);
        vm.stopPrank();

        // Step 7: Lender withdraws with interest
        vm.startPrank(lender1);
        uint256 currentShares = pool.balanceOf(lender1);
        uint256 withdrawnAssets = pool.redeem(currentShares, lender1, lender1);

        // Verify lender got back original deposit plus interest
        assertGt(withdrawnAssets, depositAmount, "Lender should receive original deposit plus interest");
        vm.stopPrank();
    }

    function testMultipleBorrowersAndLenders() public {
        // Setup two lenders
        uint256 lender1Amount = 1000e6;
        uint256 lender2Amount = 500e6;
        _setupLendingPosition(lender1, lender1Amount);
        _setupLendingPosition(lender2, lender2Amount);

        // Setup two borrowers
        address borrower2 = makeAddr("borrower2");
        vm.prank(owner);
        collateralToken.mint(borrower2, INITIAL_COLLATERAL_AMOUNT);

        uint256 borrower1BorrowAmount = 400e6;
        uint256 borrower2BorrowAmount = 200e6;
        uint256 borrower1CollateralAmount =
            pool.previewBorrow(borrower, borrower1BorrowAmount, DEFAULT_COLLATERAL_BUFFER);
        uint256 borrower2CollateralAmount =
            pool.previewBorrow(borrower2, borrower2BorrowAmount, DEFAULT_COLLATERAL_BUFFER);

        // Borrower 1 borrows
        _setupBorrowingPosition(borrower, borrower1BorrowAmount, borrower1CollateralAmount);

        // Borrower 2 borrows
        _setupBorrowingPosition(borrower2, borrower2BorrowAmount, borrower2CollateralAmount);

        // Warp time for interest accrual
        vm.warp(block.timestamp + 30 days);

        // Mint extra tokens for interest
        vm.prank(owner);
        loanToken.mint(borrower, borrower1BorrowAmount * 105 / 100); // Mint extra for interest

        // Borrower 1 repays
        vm.startPrank(borrower);
        uint256 repayAmount = borrower1BorrowAmount * 105 / 100; // 5% extra for interest
        loanToken.approve(address(pool), repayAmount);
        pool.repay(repayAmount, 0, borrower);
        pool.withdrawCollateral(borrower1CollateralAmount, borrower, borrower);
        vm.stopPrank();

        // Borrower 2 defaults and gets liquidated fully
        vm.prank(owner);
        oracle.setPrice((3276e6 * 1e36) / 1e18);

        vm.startPrank(liquidator);
        loanToken.approve(address(pool), borrower2BorrowAmount + 305517); // interest + fees
        uint256 borrowShares = pool.getPosition(borrower2).borrowShares;
        bytes memory data;
        pool.liquidate(borrower2, 0, borrowShares, borrower2CollateralAmount, borrower2BorrowAmount + 305517, data);
        vm.stopPrank();

        // Lenders withdraw
        vm.startPrank(lender1);
        uint256 lender1Shares = pool.balanceOf(lender1);
        uint256 lender1WithdrawnAssets = pool.redeem(lender1Shares, lender1, lender1);
        vm.stopPrank();

        vm.startPrank(lender2);
        uint256 lender2Shares = pool.balanceOf(lender2);
        uint256 lender2WithdrawnAssets = pool.redeem(lender2Shares, lender2, lender2);
        vm.stopPrank();

        assertGt(lender1WithdrawnAssets, lender1Amount, "lender1 should receive their interest");
        assertGt(lender2WithdrawnAssets, lender2Amount, "lender2 should receive their interest");
    }

    function testInterestAccrualAndFees() public {
        // Setup deposit and borrow
        uint256 collateralAmount = 1e18;
        uint256 borrowAmount = 500e6;
        _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        // Warp time for significant interest accrual
        vm.warp(block.timestamp + 365 days);

        // Trigger interest accrual by performing some action
        _setupLendingPosition(lender1, 1000e6);

        // Check manager and protocol fee accrual
        uint256 managerBalance = pool.balanceOf(manager);
        uint256 protocolFeeRecipient = pool.balanceOf(feeRecipient);

        assertGt(managerBalance, 0, "Manager should have received fee shares");
        assertGt(protocolFeeRecipient, 0, "Protocol fee recipient should have received fee shares");
    }
}
