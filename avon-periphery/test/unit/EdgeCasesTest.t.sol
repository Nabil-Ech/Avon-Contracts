// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../BasePoolTest.t.sol";

contract EdgeCasesTest is BasePoolTest {
    function testDepositWithdrawEdgeCases() public {
        // Test deposit/withdraw with edge cases to improve branch coverage

        // Setup initial deposit
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Test withdrawing when there are borrows but still enough liquidity
        _setupBorrowingPosition(borrower, DEFAULT_DEPOSIT_AMOUNT / 2, 1e18);

        vm.startPrank(lender1);
        uint256 withdrawAmount = DEFAULT_DEPOSIT_AMOUNT / 4;
        uint256 sharesBurned = pool.withdraw(withdrawAmount, lender1, lender1);

        assertGt(sharesBurned, 0, "Should burn shares for partial withdrawal");

        // Test redeeming with all shares
        uint256 remainingShares = pool.balanceOf(lender1);
        vm.expectRevert(); // Should revert due to insufficient liquidity
        pool.redeem(remainingShares, lender1, lender1);

        vm.stopPrank();
    }

    function testBorrowRepayEdgeCases() public {
        // Test borrow/repay edge cases to improve branch coverage
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Setup initial borrow
        uint256 borrowAmount = DEFAULT_DEPOSIT_AMOUNT / 2;
        uint256 collateralAmount = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);
        (, uint256 borrowShares) = _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        // Test repaying with more than owed (should only repay the actual debt)
        vm.startPrank(borrower);
        loanToken.approve(address(pool), borrowAmount * 2);

        (uint256 repaidAssets, uint256 repaidShares) = pool.repay(
            borrowAmount * 2, // More than borrowed
            0,
            borrower
        );

        assertEq(repaidShares, borrowShares, "Should repay all shares");
        assertEq(repaidAssets, borrowAmount, "Should only repay actual debt amount");

        // Verify position is cleared
        PoolGetter.BorrowPosition memory position = pool.getPosition(borrower);
        assertEq(position.borrowShares, 0, "Borrow shares should be zero after full repayment");
        assertEq(position.borrowAssets, 0, "Borrow assets should be zero after full repayment");
        vm.stopPrank();
    }

    function testBorrowRepayWithExactSharesEdgeCases() public {
        // Test borrow/repay with exact shares edge cases
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Setup initial borrow
        uint256 borrowAmount = DEFAULT_DEPOSIT_AMOUNT / 2;
        uint256 collateralAmount = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);
        (, uint256 borrowShares) = _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        // Test repaying with more shares than owed (should cap at the actual debt)
        vm.startPrank(borrower);
        loanToken.approve(address(pool), borrowAmount * 2);

        (uint256 repaidAssets, uint256 repaidShares) = pool.repay(
            0,
            borrowShares * 2, // More than actual shares
            borrower
        );

        assertEq(repaidShares, borrowShares, "Should repay only actual shares");
        assertGt(repaidAssets, 0, "Should repay some assets");

        // Verify position is cleared
        PoolGetter.BorrowPosition memory position = pool.getPosition(borrower);
        assertEq(position.borrowShares, 0, "Borrow shares should be zero after full repayment");
        vm.stopPrank();
    }

    function testLiquidationEdgeCases() public {
        // Test liquidation edge cases
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Setup borrower with collateral and loan
        uint256 borrowAmount = DEFAULT_DEPOSIT_AMOUNT / 2;
        uint256 collateralAmount = 1e18;
        _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        // Make position unsafe
        _makePositionUnsafe();

        // Try liquidation with inconsistent input (both assets and shares non-zero)
        vm.startPrank(liquidator);
        loanToken.approve(address(pool), borrowAmount);
        bytes memory data;

        vm.expectRevert(); // InconsistentInput
        pool.liquidate(borrower, borrowAmount, 100, 0, 0, data);

        // Try liquidation with inconsistent input (both assets and shares zero)
        vm.expectRevert(); // InconsistentInput
        pool.liquidate(borrower, 0, 0, 0, 0, data);

        vm.stopPrank();
    }

    function testPositionGuardEdgeCases() public {
        // Test PositionGuard edge cases

        // Test authorization that's already set
        vm.startPrank(borrower);

        // First set authorization
        pool.setAuthorization(lender2, true);

        // Try to set again (should revert)
        vm.expectRevert(); // AlreadySet
        pool.setAuthorization(lender2, true);

        // Remove authorization
        pool.setAuthorization(lender2, false);

        // Try to remove again (should revert)
        vm.expectRevert(); // AlreadySet
        pool.setAuthorization(lender2, false);

        vm.stopPrank();
    }

    // function testUpdateOrdersEdgeCases() public {
    //     // Test different branches in UpdateOrders._getTicks

    //     // Small liquidity pool (< 100 USD)
    //     _setupLendingPosition(lender1, 10e6); // 10 USDC
    //     vm.prank(owner);
    //     oracle.setPrice((1e6*1e36)/1e18);  // 1 USDC = 1 USD

    //     // Medium liquidity pool (100 USD - 1M USD)
    //     _setupLendingPosition(lender1, 1000e6); // 1000 USDC
    //     vm.prank(owner);
    //     oracle.setPrice((1e6*1e36)/1e18);  // 1 USDC = 1 USD

    //     // Large liquidity pool (1M USD - 100M USD)
    //     _setupLendingPosition(lender1, 2000000e6); // 2M USDC
    //     vm.prank(owner);
    //     oracle.setPrice((1e6*1e36)/1e18);  // 1 USDC = 1 USD

    //     // Huge liquidity pool (> 100M USD)
    //     _setupLendingPosition(lender1, 200000000e6); // 200M USDC
    //     vm.prank(owner);
    //     oracle.setPrice((1e6*1e36)/1e18);  // 1 USDC = 1 USD
    // }

    function testCollateralManagementEdgeCases() public {
        // Test CollateralManagement edge cases

        // Test depositing zero collateral
        vm.startPrank(borrower);
        vm.expectRevert(); // ZeroAssets
        pool.depositCollateral(0, borrower);

        // Test withdrawing to zero address
        collateralToken.approve(address(pool), 1e18);
        pool.depositCollateral(1e18, borrower);

        vm.expectRevert(); // ZeroAddress
        pool.withdrawCollateral(0.5e18, borrower, address(0));
        vm.stopPrank();
    }

    function testAvonPoolEdgeCases() public {
        // Test AvonPool edge cases

        // Test updateOrderbook with zero address
        vm.startPrank(manager);
        vm.expectRevert(); // InvalidInput
        pool.updateOrderbook(address(0), address(orderbookFactory));

        vm.expectRevert(); // InvalidInput
        pool.updateOrderbook(address(orderbook), address(0));
        vm.stopPrank();

        // Test increaseLLTV with invalid values
        vm.startPrank(manager);
        vm.expectRevert(); // InvalidInput
        pool.updateLLTVUpward(0.05e18); // Below minimum LTV

        vm.expectRevert(); // InvalidInput
        pool.updateLLTVUpward(1.1e18); // Above maximum LTV

        vm.expectRevert(); // InvalidInput
        pool.updateLLTVUpward(0.7e18); // Below current LTV (0.8e18)
        vm.stopPrank();
    }
}
