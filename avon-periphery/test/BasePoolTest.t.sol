// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AvonPool} from "../src/pool/AvonPool.sol";
import {MyToken} from "./mock/MyToken.sol";
import {MockUSDC} from "./mock/MockUSDC.sol";
import {MockOracle} from "./mock/MockOracle.sol";
import {LinearKinkIRM} from "./mock/LinearKinkIRM.sol";
import {MockOrderbook} from "./mock/MockOrderbook.sol";
import {MockOrderbookFactory} from "./mock/MockOrderbookFactory.sol";
import {AvonPoolFactory} from "../src/factory/AvonPoolFactory.sol";
import {PoolStorage} from "../src/pool/PoolStorage.sol";
import {PoolGetter} from "../src/pool/utils/PoolGetter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestAvonPool} from "./TestHelper.t.sol";

abstract contract BasePoolTest is Test {
    MockUSDC loanToken;
    MyToken collateralToken;
    MockOracle oracle;
    LinearKinkIRM irm;
    MockOrderbook orderbook;
    MockOrderbookFactory orderbookFactory;
    AvonPoolFactory poolFactory;
    TestAvonPool pool;
    TestAvonPool pool1;
    TestAvonPool pool2;

    address owner = makeAddr("owner");
    address lender1 = makeAddr("lender1");
    address lender2 = makeAddr("lender2");
    address borrower = makeAddr("borrower");
    address liquidator = makeAddr("liquidator");
    address manager = makeAddr("manager");
    address feeRecipient = makeAddr("feeRecipient");
    address random = makeAddr("random");

    // Constants for testing
    uint256 constant INITIAL_LOAN_AMOUNT = 10000e6;
    uint256 constant INITIAL_COLLATERAL_AMOUNT = 10e18;
    uint256 constant DEFAULT_DEPOSIT_AMOUNT = 1000e6;
    uint256 constant DEFAULT_BORROW_AMOUNT = 500e6;
    uint256 constant DEFAULT_COLLATERAL_BUFFER = 0.01e18;
    uint64 constant MANAGER_FEE = 0.035e18;

    function setUp() public virtual {
        vm.startPrank(owner);

        // Deploy mocks
        loanToken = new MockUSDC("Mock USDC", "mUSDC");
        collateralToken = new MyToken("Mock DAI", "mDAI");
        oracle = new MockOracle();
        irm = new LinearKinkIRM(0.01e18, 0.05e18, 0.1e18, 0.8e18);
        orderbookFactory = new MockOrderbookFactory(feeRecipient);
        orderbook = new MockOrderbook(address(orderbookFactory));

        // Deploy the real pool factory instead of mock
        poolFactory = new AvonPoolFactory(address(orderbookFactory));

        // Prepare PoolConfig
        PoolStorage.PoolConfig memory cfg = PoolStorage.PoolConfig({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(oracle),
            irm: address(irm),
            lltv: 0.8e18 // 80% LTV
        });

        // Set up orderbook and pool factory
        orderbookFactory.mockSetPoolManager(manager, true);
        orderbookFactory.mockSetOrderbook(address(orderbook));
        orderbookFactory.mockSetPoolFactory(address(poolFactory), true);

        vm.stopPrank();

        // Deploy pool using the factory
        vm.startPrank(manager);

        pool =
            TestAvonPool(payable(poolFactory.deployPool(cfg, MANAGER_FEE, 1.03e18, 0.03e18, 0.25e18, 0.001e18, 0, 0))); // No caps
        cfg.lltv = 0.9e18;
        pool1 =
            TestAvonPool(payable(poolFactory.deployPool(cfg, MANAGER_FEE, 1.03e18, 0.03e18, 0.25e18, 0.001e18, 0, 0))); // No caps
        cfg.lltv = 0.7e18;
        pool2 =
            TestAvonPool(payable(poolFactory.deployPool(cfg, MANAGER_FEE, 1.03e18, 0.03e18, 0.25e18, 0.001e18, 0, 0))); // No caps
        vm.stopPrank();
        assertTrue(poolFactory.isValidPool(address(pool)), "Pool not valid");
        assertTrue(poolFactory.isValidPool(address(pool1)), "Pool1 not valid");
        assertTrue(poolFactory.isValidPool(address(pool2)), "Pool2 not valid");

        vm.startPrank(owner);
        // Mint tokens to users
        loanToken.mint(lender1, INITIAL_LOAN_AMOUNT);
        loanToken.mint(lender2, INITIAL_LOAN_AMOUNT);
        loanToken.mint(liquidator, INITIAL_LOAN_AMOUNT);
        collateralToken.mint(borrower, INITIAL_COLLATERAL_AMOUNT);

        vm.stopPrank();

        // Whitelist pool in orderbook
        vm.startPrank(manager);
        orderbook.mockWhitelistPool(address(pool), address(poolFactory));
        orderbook.mockWhitelistPool(address(pool1), address(poolFactory));
        orderbook.mockWhitelistPool(address(pool2), address(poolFactory));
        vm.stopPrank();
    }

    // Helper function to setup a lending position
    function _setupLendingPosition(address user, uint256 amount) internal {
        vm.startPrank(user);
        loanToken.approve(address(pool), amount);
        pool.deposit(amount, user);
        vm.stopPrank();
    }

    // Helper function to setup a borrowing position
    function _setupBorrowingPosition(address user, uint256 borrowAmount, uint256 collateralAmount)
        internal
        returns (uint256 assets, uint256 shares)
    {
        // First ensure there's liquidity in the pool
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Now setup the borrowing position
        vm.startPrank(user);

        // Deposit collateral
        collateralToken.approve(address(pool), collateralAmount);
        pool.depositCollateral(collateralAmount, user);

        // Borrow
        (assets, shares) = pool.borrow(borrowAmount, 0, user, user, borrowAmount);

        vm.stopPrank();
        return (assets, shares);
    }

    // Helper to make a position unsafe for liquidation testing
    function _makePositionUnsafe() internal {
        // Manipulate oracle to make position unsafe
        vm.prank(owner);
        oracle.setPrice((3000e6 * 1e36) / 1e18); // Lower collateral price
    }

    // Helper to verify position details
    function _verifyPosition(address user, uint256 expectedBorrowAssets, uint256 expectedCollateral) internal view {
        PoolGetter.BorrowPosition memory position = pool.getPosition(user);
        assertApproxEqRel(position.borrowAssets, expectedBorrowAssets, 0.01e18, "Borrow assets mismatch");
        assertEq(position.collateral, expectedCollateral, "Collateral mismatch");
    }
}
