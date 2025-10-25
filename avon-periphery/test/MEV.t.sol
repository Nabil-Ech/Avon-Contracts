pragma solidity ^0.8.28;

import "./BasePoolTest.t.sol";
import "forge-std/console.sol";

contract MEVTest is BasePoolTest {
    function setUp() public override {
        super.setUp();
        
    }

    function testBorrowWithExactAssets() public {
        // Setup borrow position
        uint256 borrowAmount = 500e6;
        uint256 collateralAmount = 1e18;
        (, uint256 shares) = _setupBorrowingPosition(borrower, borrowAmount, collateralAmount);

        // 1 year later, repay the borrow
        vm.warp(block.timestamp + 365 days);

        // lender 2 front runs the repay witha flash loan
        uint256 balanceBefore = loanToken.balanceOf(lender2);
        vm.startPrank(lender2);
        uint256 deposit2 = loanToken.balanceOf(lender2);
        loanToken.approve(address(pool), deposit2);
        pool.deposit(deposit2, lender2);
        vm.stopPrank();

        // Now borrower repays
        vm.startPrank(borrower);
        loanToken.approve(address(pool), borrowAmount);
        
        (uint256 repaidAssets, uint256 repaidShares) = pool.repay(borrowAmount, 0, borrower);

        vm.stopPrank();

        // lender2 redeems immediately after
        vm.startPrank(lender2);
        uint256 sharesToRedeem = pool.balanceOf(lender2);
        pool.redeem(sharesToRedeem, lender2, lender2);
        vm.stopPrank();
        uint256 balanceAfter = loanToken.balanceOf(lender2);
        console.log("Borrower balance diff:", (balanceBefore) / 1e6);


    }

}