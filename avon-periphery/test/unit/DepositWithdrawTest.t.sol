// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../BasePoolTest.t.sol";

contract DepositWithdrawTest is BasePoolTest {
    function testDeposit() public {
        uint256 depositAmount = 1000e6;

        vm.startPrank(lender1);
        loanToken.approve(address(pool), depositAmount);
        uint256 sharesBefore = pool.balanceOf(lender1);
        uint256 shares = pool.deposit(depositAmount, lender1);

        // Verify results
        assertGt(shares, 0, "Should receive shares");
        assertEq(pool.balanceOf(lender1), sharesBefore + shares, "Shares balance should increase");
        assertEq(
            loanToken.balanceOf(lender1), INITIAL_LOAN_AMOUNT - depositAmount, "Loan token balance should decrease"
        );

        // Verify pool state
        (PoolGetter.PoolData memory poolData,,) = pool.getPoolData();
        assertEq(poolData.totalSupplyAssets, depositAmount, "Pool supply assets should match deposit");
        vm.stopPrank();
    }

    function testMint() public {
        uint256 mintShares = 500e6;

        vm.startPrank(lender1);
        loanToken.approve(address(pool), type(uint256).max);
        uint256 tokensBefore = loanToken.balanceOf(lender1);
        uint256 assets = pool.mint(mintShares, lender1);

        // Verify results
        assertGt(assets, 0, "Should deposit assets");
        assertEq(pool.balanceOf(lender1), mintShares, "Should receive requested shares");
        assertEq(loanToken.balanceOf(lender1), tokensBefore - assets, "Loan token balance should decrease");
        vm.stopPrank();
    }

    function testWithdraw() public {
        // Setup - deposit first
        uint256 depositAmount = 1000e6;
        _setupLendingPosition(lender1, depositAmount);

        uint256 withdrawAmount = 500e6;
        vm.startPrank(lender1);
        uint256 balanceBefore = loanToken.balanceOf(lender1);
        uint256 sharesBurned = pool.withdraw(withdrawAmount, lender1, lender1);

        // Verify results
        assertGt(sharesBurned, 0, "Should burn shares");
        assertEq(loanToken.balanceOf(lender1), balanceBefore + withdrawAmount, "Should receive withdrawn assets");

        // Verify pool state
        (PoolGetter.PoolData memory poolData,,) = pool.getPoolData();
        assertEq(poolData.totalSupplyAssets, depositAmount - withdrawAmount, "Pool supply assets should be reduced");
        vm.stopPrank();
    }

    function testRedeem() public {
        // Setup - deposit first
        uint256 depositAmount = 1000e6;
        _setupLendingPosition(lender1, depositAmount);

        uint256 sharesToRedeem = pool.balanceOf(lender1) / 2;
        vm.startPrank(lender1);
        uint256 balanceBefore = loanToken.balanceOf(lender1);
        uint256 assetsReceived = pool.redeem(sharesToRedeem, lender1, lender1);

        // Verify results
        assertGt(assetsReceived, 0, "Should receive assets");
        assertEq(loanToken.balanceOf(lender1), balanceBefore + assetsReceived, "Should receive redeemed assets");

        // Verify pool state
        (PoolGetter.PoolData memory poolData,,) = pool.getPoolData();
        assertEq(poolData.totalSupplyAssets, depositAmount - assetsReceived, "Pool supply assets should be reduced");
        vm.stopPrank();
    }

    function testDepositZeroAmount() public {
        vm.startPrank(lender1);
        loanToken.approve(address(pool), 0);
        vm.expectRevert(); // Should revert when trying to deposit 0
        pool.deposit(0, lender1);
        vm.stopPrank();
    }

    function testWithdrawExceedingBalance() public {
        // Setup - deposit first
        uint256 depositAmount = 1000e6;
        _setupLendingPosition(lender1, depositAmount);

        vm.startPrank(lender1);
        vm.expectRevert(); // Should revert when trying to withdraw more than balance
        pool.withdraw(depositAmount + 1, lender1, lender1);
        vm.stopPrank();
    }

    function testWithdrawWhenBorrowed() public {
        // Setup - deposit and borrow
        _setupBorrowingPosition(borrower, DEFAULT_BORROW_AMOUNT, 1e18);

        // Try to withdraw all (should fail due to insufficient liquidity)
        vm.startPrank(lender1);
        vm.expectRevert(); // Should revert due to insufficient liquidity
        pool.withdraw(DEFAULT_DEPOSIT_AMOUNT, lender1, lender1);

        // Should be able to withdraw unborrowed amount
        uint256 unborrowed = DEFAULT_DEPOSIT_AMOUNT - DEFAULT_BORROW_AMOUNT;
        uint256 sharesBurned = pool.withdraw(unborrowed, lender1, lender1);
        assertGt(sharesBurned, 0, "Should burn shares for unborrowed amount");
        vm.stopPrank();
    }

    function testMintWithZeroShares() public {
        vm.startPrank(lender1);
        loanToken.approve(address(pool), 1000e6);

        vm.expectRevert(); // ZeroShares
        pool.mint(0, lender1);
        vm.stopPrank();
    }

    function testDepositToZeroAddress() public {
        uint256 depositAmount = 1000e6;

        vm.startPrank(lender1);
        loanToken.approve(address(pool), depositAmount);

        vm.expectRevert(); // Cannot deposit to zero address, should revert at ERC4626 level
        pool.deposit(depositAmount, address(0));
        vm.stopPrank();
    }

    function testMintToZeroAddress() public {
        uint256 mintShares = 500e6;

        vm.startPrank(lender1);
        loanToken.approve(address(pool), type(uint256).max);

        vm.expectRevert(); // Cannot mint to zero address, should revert at ERC4626 level
        pool.mint(mintShares, address(0));
        vm.stopPrank();
    }

    function testWithdrawWithZeroAssets() public {
        // Setup - deposit first
        uint256 depositAmount = 1000e6;
        _setupLendingPosition(lender1, depositAmount);

        vm.startPrank(lender1);
        vm.expectRevert(); // ZeroAssets
        pool.withdraw(0, lender1, lender1);
        vm.stopPrank();
    }

    function testRedeemWithZeroShares() public {
        // Setup - deposit first
        uint256 depositAmount = 1000e6;
        _setupLendingPosition(lender1, depositAmount);

        vm.startPrank(lender1);
        vm.expectRevert(); // ZeroShares
        pool.redeem(0, lender1, lender1);
        vm.stopPrank();
    }

    function testWithdrawToZeroAddress() public {
        // Setup - deposit first
        uint256 depositAmount = 1000e6;
        _setupLendingPosition(lender1, depositAmount);

        vm.startPrank(lender1);
        vm.expectRevert(); // ZeroAddress
        pool.withdraw(100e6, address(0), lender1);
        vm.stopPrank();
    }

    function testRedeemToZeroAddress() public {
        // Setup - deposit first
        uint256 depositAmount = 1000e6;
        _setupLendingPosition(lender1, depositAmount);

        uint256 sharesToRedeem = pool.balanceOf(lender1) / 2;

        vm.startPrank(lender1);
        vm.expectRevert(); // ZeroAddress
        pool.redeem(sharesToRedeem, address(0), lender1);
        vm.stopPrank();
    }

    function testWithdrawFromZeroAddress() public {
        // Setup - deposit first
        uint256 depositAmount = 1000e6;
        _setupLendingPosition(lender1, depositAmount);

        vm.startPrank(lender1);
        vm.expectRevert(); // Attempt to withdraw from zero address should fail
        pool.withdraw(100e6, lender1, address(0));
        vm.stopPrank();
    }

    function testRedeemFromZeroAddress() public {
        // Setup - deposit first
        uint256 depositAmount = 1000e6;
        _setupLendingPosition(lender1, depositAmount);

        uint256 sharesToRedeem = pool.balanceOf(lender1) / 2;

        vm.startPrank(lender1);
        vm.expectRevert(); // Attempt to redeem from zero address should fail
        pool.redeem(sharesToRedeem, lender1, address(0));
        vm.stopPrank();
    }

    function testWithdrawOnBehalfOfOther() public {
        // Setup - deposit for lender1
        uint256 depositAmount = 1000e6;
        _setupLendingPosition(lender1, depositAmount);

        // Approve lender2 to spend lender1's shares
        vm.startPrank(lender1);
        pool.setAuthorization(lender2, true);
        pool.approve(lender2, pool.balanceOf(lender1));
        vm.stopPrank();

        // lender2 withdraws on behalf of lender1
        vm.startPrank(lender2);
        uint256 withdrawAmount = 500e6;
        uint256 sharesBurned = pool.withdraw(withdrawAmount, lender2, lender1);

        // Verify results
        assertGt(sharesBurned, 0, "Should burn shares");
        assertGt(loanToken.balanceOf(lender2), withdrawAmount, "Lender2 should receive withdrawn assets");
        vm.stopPrank();
    }

    function testRedeemOnBehalfOfOther() public {
        // Setup - deposit for lender1
        uint256 depositAmount = 1000e6;
        _setupLendingPosition(lender1, depositAmount);

        uint256 lender1Shares = pool.balanceOf(lender1);
        uint256 sharesToRedeem = lender1Shares / 2;

        // Approve lender2 to spend lender1's shares
        vm.startPrank(lender1);
        pool.setAuthorization(lender2, true);
        pool.approve(lender2, sharesToRedeem);
        vm.stopPrank();

        // lender2 redeems on behalf of lender1
        vm.startPrank(lender2);
        uint256 assetsReceived = pool.redeem(sharesToRedeem, lender2, lender1);

        // Verify results
        assertGt(assetsReceived, 0, "Should receive assets");
        assertGt(loanToken.balanceOf(lender2), assetsReceived, "Lender2 should receive redeemed assets");
        assertEq(pool.balanceOf(lender1), lender1Shares - sharesToRedeem, "Lender1's shares should decrease");
        vm.stopPrank();
    }

    function testWithdrawWithInsufficientBalance() public {
        // Setup - deposit first
        uint256 depositAmount = 1000e6;
        _setupLendingPosition(lender1, depositAmount);

        // Try to withdraw more than deposited from an account with no shares
        vm.startPrank(random);
        vm.expectRevert(); // Insufficient balance
        pool.withdraw(100e6, random, random);
        vm.stopPrank();
    }

    function testCompleteWithdrawalWithBorrows() public {
        // Setup - deposit with lender2
        _setupLendingPosition(lender2, DEFAULT_DEPOSIT_AMOUNT);
        _setupLendingPosition(lender2, DEFAULT_DEPOSIT_AMOUNT);
        // Create a borrow position using 75% of pool funds
        uint256 borrowAmount = (DEFAULT_DEPOSIT_AMOUNT * 2) * 75 / 100;
        uint256 collateralAmount = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);
        // This will create lending position of lender1 and borrowing position of borrower
        _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        vm.prank(lender2);
        pool.withdraw(DEFAULT_DEPOSIT_AMOUNT, lender2, lender2);

        // lender1 tries to withdraw everything (should fail due to insufficient liquidity)
        vm.startPrank(lender1);
        uint256 lender1Shares = pool.balanceOf(lender1);
        vm.expectRevert(); // InsufficientLiquidity
        pool.redeem(lender1Shares, lender1, lender1);

        // Try to withdraw partial amount that exceeds available liquidity (should fail)
        vm.expectRevert(); // InsufficientLiquidity
        pool.withdraw(DEFAULT_DEPOSIT_AMOUNT, lender1, lender1);

        // Withdraw maximum available amount (25% of total funds)
        uint256 availableLiquidity = (DEFAULT_DEPOSIT_AMOUNT * 2) - borrowAmount; // 25% of total
        uint256 maxWithdrawPerLender = availableLiquidity / 2; // Split between 2 lenders

        uint256 sharesBurned = pool.withdraw(maxWithdrawPerLender, lender1, lender1);
        assertGt(sharesBurned, 0, "Should burn shares for maximum available withdrawal");
        vm.stopPrank();

        // lender2 tries to withdraw everything (should fail due to insufficient liquidity)
        vm.startPrank(lender2);
        uint256 lender2Shares = pool.balanceOf(lender2);
        vm.expectRevert(); // InsufficientLiquidity
        pool.redeem(lender2Shares, lender2, lender2);
        vm.stopPrank();
    }

    function testDepositWithInterestAccrued() public {
        // Setup initial deposit and borrow
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);
        uint256 borrowAmount = DEFAULT_DEPOSIT_AMOUNT / 2;
        uint256 collateralAmount = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);
        _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        // Fast forward time to accrue interest
        vm.warp(block.timestamp + 365 days);

        // Get pool state before new deposit
        (PoolGetter.PoolData memory poolDataBefore,,) = pool.getPoolData();

        // New deposit after interest accrual
        uint256 newDepositAmount = 500e6;
        vm.startPrank(lender2);
        loanToken.approve(address(pool), newDepositAmount);
        uint256 shares = pool.deposit(newDepositAmount, lender2);
        vm.stopPrank();

        // Verify shares received account for accrued interest
        (PoolGetter.PoolData memory poolDataAfter,,) = pool.getPoolData();

        // Verify deposit was successful with interest accrual
        assertGe(
            poolDataAfter.totalSupplyAssets,
            poolDataBefore.totalSupplyAssets + newDepositAmount,
            "Total assets should increase by deposit amount but there will be buffer of interest accrued"
        );
        assertGe(
            poolDataAfter.totalSupplyShares,
            poolDataBefore.totalSupplyShares + shares,
            "Total shares should increase by shares minted but there will be buffer of interest accrued"
        );
    }
}
