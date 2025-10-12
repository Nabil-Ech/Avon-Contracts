// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../BasePoolTest.t.sol";
import {PoolGetter} from "../../src/pool/utils/PoolGetter.sol";
import {PoolConstants} from "../../src/pool/utils/PoolConstants.sol";

contract PoolGetterTest is BasePoolTest {
    function testGetPoolData() public {
        // Setup a basic pool state with lending and borrowing
        _setupBorrowingPosition(borrower, DEFAULT_BORROW_AMOUNT, 1e18);

        // Call getPoolData and verify it returns expected values
        // This will also add the accrue interest for quote duration
        (PoolGetter.PoolData memory poolData, uint256 ir, uint256 ltv) = pool.getPoolData();

        // Verify pool data components
        assertEq(poolData.totalSupplyAssets, DEFAULT_DEPOSIT_AMOUNT, "Total supply assets incorrect");
        assertEq(poolData.totalBorrowAssets, DEFAULT_BORROW_AMOUNT, "Total borrow assets incorrect");
        assertGt(poolData.totalSupplyShares, 0, "Supply shares should be > 0");
        assertGt(poolData.totalBorrowShares, 0, "Borrow shares should be > 0");

        // Verify other components
        assertEq(ltv, 0.8e18, "LLTV should match pool config");
        assertGe(ir, 0, "Interest rate should be calculated");
    }

    function testGetPosition() public {
        // Setup a borrowing position
        _setupBorrowingPosition(borrower, DEFAULT_BORROW_AMOUNT, 1e18);

        // Get position data
        PoolGetter.BorrowPosition memory position = pool.getPosition(borrower);

        // Verify position data
        assertEq(position.collateral, 1e18, "Collateral should match setup");
        assertEq(position.borrowAssets, DEFAULT_BORROW_AMOUNT, "Borrow assets should match setup");
        assertGt(position.borrowShares, 0, "Borrow shares should be > 0");
    }

    function testPreviewBorrowOnly() public {
        // Setup a lending position for liquidity
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Test previewBorrow with different scenarios
        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);

        // Verify the calculation is reasonable
        assertGt(collateralAmount, 0, "Collateral amount should be > 0");

        // Verify that the calculation works with an existing position
        // First create a position
        _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        // Fast forward time to ensure updatedAt != block.timestamp
        vm.warp(block.timestamp + 1 days);

        // Now preview additional borrowing
        uint256 additionalCollateralAmount = pool.previewBorrow(borrower, borrowAmount, DEFAULT_COLLATERAL_BUFFER);

        // Verify the calculation is reasonable and considers existing debt
        assertGe(
            additionalCollateralAmount, collateralAmount, "Additional collateral amount should be > collateralAmount"
        );
    }

    function testPreviewBorrowFailsWithInsufficientBuffer() public {
        // Try to preview borrow with insufficient buffer
        vm.expectRevert(); // InvalidInput
        pool.previewBorrow(borrower, 100e6, 0.009e18); // Below 0.01e18 minimum
    }

    function testPreviewBorrowWithExactCollateral() public {
        // Setup a lending position for liquidity
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Test previewBorrowWithExactCollateral
        uint256 collateralAmount = 1e18;
        uint256 expectedBorrowAmount =
            pool.previewBorrowWithExactCollateral(borrower, collateralAmount, DEFAULT_COLLATERAL_BUFFER);

        // Verify the calculation is reasonable
        assertGt(expectedBorrowAmount, 0, "Expected borrow amount should be > 0");

        // Verify that the calculation works with an existing position
        // First create a position
        _setupBorrowingPosition(borrower, 100e6, 0.5e18);

        // Fast forward time to ensure updatedAt != block.timestamp
        vm.warp(block.timestamp + 1 days);

        // Now preview borrowing with exact collateral
        uint256 newExpectedBorrowAmount =
            pool.previewBorrowWithExactCollateral(borrower, collateralAmount, DEFAULT_COLLATERAL_BUFFER);

        // Verify the calculation is reasonable and considers existing debt
        assertLe(
            newExpectedBorrowAmount, expectedBorrowAmount, "New expected borrow amount should be < expectedBorrowAmount"
        );
    }

    function testPreviewBorrowWithExactCollateralFailsWithInsufficientBuffer() public {
        // Try to preview borrow with insufficient buffer
        vm.expectRevert(); // InvalidInput
        pool.previewBorrowWithExactCollateral(borrower, 1e18, 0.009e18); // Below 0.01e18 minimum
    }

    function testPreviewAccrueInterestWithZeroAccruedInterest() public {
        // Setup initial state
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Get pool data immediately (should have zero accrued interest since no time has passed)
        (PoolGetter.PoolData memory poolData,,) = pool.getPoolData();

        // Verify pool data reflects zero accrued interest
        assertEq(poolData.totalSupplyAssets, DEFAULT_DEPOSIT_AMOUNT, "Supply assets should match deposit");
        assertEq(poolData.totalBorrowAssets, 0, "Borrow assets should be zero");
    }

    // Additional edge case tests
    function testPoolDataWithZeroUtilization() public {
        // Just add supply, no borrows
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        (PoolGetter.PoolData memory poolData, uint256 ir,) = pool.getPoolData();

        // Verify interest rate at zero utilization
        uint256 ratePerSecond = uint256(0.01e18) / 31536000;
        assertEq(ir, ratePerSecond, "Interest rate should be base rate at zero utilization");
        assertEq(poolData.totalBorrowAssets, 0, "Total borrow assets should be zero");
    }

    function testPositionWithAccruedInterest() public {
        // Setup a borrowing position
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);
        _setupBorrowingPosition(borrower, DEFAULT_BORROW_AMOUNT, 1e18);

        // Fast forward time to accrue interest
        vm.warp(block.timestamp + 30 days);

        // Get position with accrued interest
        PoolGetter.BorrowPosition memory position = pool.getPosition(borrower);

        // Verify borrow assets includes accrued interest
        assertGt(position.borrowAssets, DEFAULT_BORROW_AMOUNT, "Borrow assets should include accrued interest");
    }
}
