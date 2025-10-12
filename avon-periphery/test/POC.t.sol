// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./BasePoolTest.t.sol";
import {PoolStorage} from "../src/pool/PoolStorage.sol";
import {PoolGetter} from "../src/pool/utils/PoolGetter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title POC Test Suite
 * @notice This contract contains Proof of Concept tests for the Avon Periphery protocol
 * @dev Built on top of BasePoolTest which provides:
 *      - 3 pools (pool, pool1, pool2) with different LTV configurations (80%, 90%, 70%)
 *      - Mock tokens: loanToken (MockUSDC) and collateralToken (MyToken)
 *      - Mock oracle and interest rate model
 *      - Pre-configured users: owner, lender1, lender2, borrower, liquidator, manager
 *      - Helper functions for setting up lending/borrowing positions
 */
contract POC_Test is BasePoolTest {
    function setUp() public override {
        // The BasePoolTest.setUp() provides the complete test environment:
        // - Deploys and configures 3 pools with different LTV ratios
        // - Sets up mock tokens, oracle, IRM, and orderbook
        // - Mints initial tokens to test users
        // - Whitelists pools in the orderbook
        super.setUp();

        // Additional POC-specific setup can be added here if needed
    }

    function test_POC() external {
        // Write your POC here
    }
}
