// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../BasePoolTest.t.sol";

contract LiquidationTest is BasePoolTest {
    function setUp() public override {
        super.setUp();

        // Setup initial pool state with lending and borrowing
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Setup borrower with collateral and loan
        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);
        _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);
    }

    function testLiquidateWithHealthyPosition() public {
        // Try to liquidate healthy position (should fail)
        vm.startPrank(liquidator);
        loanToken.approve(address(pool), DEFAULT_BORROW_AMOUNT);
        bytes memory data;

        vm.expectRevert(); // HealthyPosition
        pool.liquidate(borrower, DEFAULT_BORROW_AMOUNT, 0, 0, 0, data);
        vm.stopPrank();
    }

    function testLiquidateWithUnhealthyPosition() public {
        // Make position unsafe
        _makePositionUnsafe();

        // Liquidate
        vm.startPrank(liquidator);
        loanToken.approve(address(pool), DEFAULT_BORROW_AMOUNT);

        uint256 collateralBalanceBefore = collateralToken.balanceOf(liquidator);
        uint256 collateralAmount = pool.getPosition(borrower).collateral;
        bytes memory data;
        pool.liquidate(borrower, collateralAmount / 2, 0, 0, DEFAULT_BORROW_AMOUNT, data);

        // Verify liquidator received collateral
        assertGt(collateralToken.balanceOf(liquidator), collateralBalanceBefore, "Liquidator should receive collateral");

        // Check borrower position was reduced
        PoolGetter.BorrowPosition memory position = pool.getPosition(borrower);
        assertLt(position.borrowAssets, DEFAULT_BORROW_AMOUNT, "Borrow amount should be reduced");
        vm.stopPrank();
    }

    function testLiquidateWithExactShares() public {
        // Make position unsafe
        _makePositionUnsafe();

        // Get current borrow position to determine shares
        PoolGetter.BorrowPosition memory initialPosition = pool.getPosition(borrower);

        // Liquidate with shares
        vm.startPrank(liquidator);
        loanToken.approve(address(pool), DEFAULT_BORROW_AMOUNT);

        uint256 sharesToLiquidate = initialPosition.borrowShares / 2;
        uint256 collateralBalanceBefore = collateralToken.balanceOf(liquidator);

        bytes memory data;
        pool.liquidate(borrower, 0, sharesToLiquidate, 0, DEFAULT_BORROW_AMOUNT, data);

        // Verify liquidator received collateral
        assertGt(collateralToken.balanceOf(liquidator), collateralBalanceBefore, "Liquidator should receive collateral");

        // Check borrower position was reduced by the right amount of shares
        PoolGetter.BorrowPosition memory finalPosition = pool.getPosition(borrower);
        assertEq(
            finalPosition.borrowShares,
            initialPosition.borrowShares - sharesToLiquidate,
            "Borrow shares should be reduced by exact amount"
        );
        vm.stopPrank();
    }

    function testLiquidateFullPositionWithBadDebt() public {
        vm.prank(owner);
        oracle.setPrice((1e6 * 1e36) / 1e18);

        // Liquidate
        vm.startPrank(liquidator);
        loanToken.approve(address(pool), DEFAULT_BORROW_AMOUNT);

        uint256 borrowShares = pool.getPosition(borrower).borrowShares;
        bytes memory data;
        pool.liquidate(borrower, 0, borrowShares, 0, DEFAULT_BORROW_AMOUNT, data);

        // Check borrower position is completely liquidated with bad debt handled
        PoolGetter.BorrowPosition memory position = pool.getPosition(borrower);
        assertEq(position.borrowShares, 0, "Borrow shares should be zero after complete liquidation");
        assertEq(position.collateral, 0, "Collateral should be zero after complete liquidation");
        vm.stopPrank();
    }

    function testLiquidateTooMuch() public {
        // Make position unsafe
        _makePositionUnsafe();

        // Try to liquidate more than borrowed (should only liquidate actual debt)
        vm.startPrank(liquidator);
        loanToken.approve(address(pool), DEFAULT_BORROW_AMOUNT * 2);

        uint256 loanBalanceBefore = loanToken.balanceOf(liquidator);
        bytes memory data;
        pool.liquidate(borrower, DEFAULT_BORROW_AMOUNT * 2, 0, 0, DEFAULT_BORROW_AMOUNT * 2, data);

        // Verify only the actual debt amount was used
        uint256 actualRepaid = loanBalanceBefore - loanToken.balanceOf(liquidator);
        assertLe(actualRepaid, DEFAULT_BORROW_AMOUNT, "Should only repay up to the borrower's debt");
        vm.stopPrank();
    }

    function testLiquidationWithInvalidInputs() public {
        // Make position unsafe
        _makePositionUnsafe();

        // Try to liquidate with both assets and shares (should fail)
        vm.startPrank(liquidator);
        loanToken.approve(address(pool), DEFAULT_BORROW_AMOUNT);
        bytes memory data;

        vm.expectRevert(); // InconsistentInput
        pool.liquidate(borrower, DEFAULT_BORROW_AMOUNT, 100, 0, 0, data);

        // Try to liquidate with neither assets nor shares (should fail)
        vm.expectRevert(); // InconsistentInput
        pool.liquidate(borrower, 0, 0, 0, 0, data);
        vm.stopPrank();
    }
}
