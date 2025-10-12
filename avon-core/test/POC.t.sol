// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TreeState, PreviewBorrowParams, BorrowerLimitOrder, MatchedOrder} from "../src/interface/Types.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {OrderbookFactory} from "../src/OrderbookFactory.sol";
import {MockPoolFactory} from "./mocks/MockPoolFactory.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockIRM} from "./mocks/MockIRM.sol";
import {MockPool} from "./mocks/MockPool.sol";

contract POC_Test is Test {
    OrderbookFactory factory;
    Orderbook orderbook;
    MockPool pool;
    MockERC20 loanToken;
    MockERC20 collateralToken;
    MockPoolFactory poolFactory;
    MockIRM irm;

    address admin = makeAddr("admin");
    address poolManager = makeAddr("poolManager");
    address borrower = makeAddr("borrower");
    address lender = makeAddr("lender");

    function setUp() public {
        // There are 2 tokens deployed: loanToken and collateralToken
        // There is an OrderbookFactory and an Orderbook deployed with bare minimum configuration
        // The orderbook uses loanToken as the loan asset and collateralToken as collateral
        // Both use the same MockIRM interest rate model
        // Neither price oracles for the assets nor specific LTVs are set in this basic setup

        vm.startPrank(admin);

        // Deploy tokens
        loanToken = new MockERC20("Loan Token", "LOAN");
        collateralToken = new MockERC20("Collateral Token", "COLL");

        // Deploy factory and IRM
        factory = new OrderbookFactory(admin);
        irm = new MockIRM(0.01e18, 0.1e18, 1e18, 0.8e18);
        factory.setIrm(address(irm), true);

        // Deploy pool factory and set configurations
        poolFactory = new MockPoolFactory();
        factory.setPoolManager(poolManager, true);
        factory.setPoolFactory(address(poolFactory), true);

        // Create orderbook
        orderbook = Orderbook(factory.createOrderbook(address(loanToken), address(collateralToken), address(irm)));
        vm.stopPrank();

        vm.prank(poolManager);
        pool = poolFactory.createPool(address(loanToken), address(orderbook), address(irm), address(collateralToken));

        // Setup accounts with tokens
        loanToken.mint(lender, 10000e18);
        collateralToken.mint(borrower, 10000e18);

        // Whitelist pool
        vm.prank(poolManager);
        orderbook.whitelistPool(address(pool), address(poolFactory));

        // In order to further configure the orderbook, refer to the IOrderbook interface functions.
    }

    function test_POC() external {
        // Write your POC here
    }
}
