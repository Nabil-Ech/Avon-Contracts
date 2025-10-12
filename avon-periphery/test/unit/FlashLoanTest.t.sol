// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../BasePoolTest.t.sol";
import {IAvonFlashLoanCallback} from "../../src/interface/IAvonFlashLoanCallback.sol";

// Mock flash loan receiver contract
contract MockFlashLoanReceiver is IAvonFlashLoanCallback {
    address public pool;
    address public loanToken;
    bool public shouldRepay;
    uint256 public lastLoanAmount;
    bytes public lastData;

    constructor(address _pool, address _loanToken) {
        pool = _pool;
        loanToken = _loanToken;
        shouldRepay = true;
    }

    function onAvonFlashLoan(uint256 assets, bytes calldata data) external override {
        require(msg.sender == pool, "Callback only from pool");

        lastLoanAmount = assets;
        lastData = data;

        // Use the loan funds however needed

        // Repay the loan if configured to do so
        if (shouldRepay) {
            // Mock returning the funds
            IERC20(loanToken).approve(pool, assets);
        }
    }

    function setShouldRepay(bool _shouldRepay) external {
        shouldRepay = _shouldRepay;
    }
}

contract FlashLoanTest is BasePoolTest {
    MockFlashLoanReceiver public flashBorrower;

    function setUp() public override {
        super.setUp();

        // Deploy the flash loan receiver
        flashBorrower = new MockFlashLoanReceiver(address(pool), address(loanToken));

        // Add liquidity to the pool
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);
    }

    function testFlashLoan() public {
        uint256 loanAmount = 500e6;
        bytes memory data = abi.encode("flash loan data");

        // Execute flash loan
        vm.prank(address(flashBorrower));
        pool.flashLoan(address(loanToken), loanAmount, data);

        // Verify flash loan was processed correctly
        assertEq(flashBorrower.lastLoanAmount(), loanAmount, "Flash loan amount should match");
        assertEq(flashBorrower.lastData(), data, "Flash loan data should match");
    }

    function testFlashLoanWithZeroAmount() public {
        bytes memory data = abi.encode("flash loan data");

        // Try flash loan with zero amount (should revert)
        vm.prank(address(flashBorrower));
        vm.expectRevert(); // ZeroAddress error
        pool.flashLoan(address(loanToken), 0, data);
    }

    function testFlashLoanWithInvalidToken() public {
        uint256 loanAmount = 500e6;
        bytes memory data = abi.encode("flash loan data");

        // Try flash loan with invalid token (should revert)
        vm.prank(address(flashBorrower));
        vm.expectRevert(); // InvalidInput error
        pool.flashLoan(address(collateralToken), loanAmount, data);
    }

    function testFlashLoanWithInsufficientLiquidity() public {
        // Setup a borrow position that uses most of the pool's liquidity
        _setupBorrowingPosition(borrower, DEFAULT_DEPOSIT_AMOUNT - 100e6, 1e18);

        // Try flash loan that exceeds available liquidity
        bytes memory data = abi.encode("flash loan data");

        vm.prank(address(flashBorrower));
        vm.expectRevert(); // InsufficientLiquidity error
        pool.flashLoan(address(loanToken), DEFAULT_DEPOSIT_AMOUNT * 2, data);
    }

    function testFlashLoanWithoutRepayment() public {
        uint256 loanAmount = 500e6;
        bytes memory data = abi.encode("flash loan data");

        // Configure the receiver to not repay the loan
        flashBorrower.setShouldRepay(false);

        // Execute flash loan
        vm.prank(address(flashBorrower));
        vm.expectRevert(); // SafeERC20 transfer from error expected
        pool.flashLoan(address(loanToken), loanAmount, data);
    }
}
