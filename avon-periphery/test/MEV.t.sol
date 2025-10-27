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
import "./BasePoolTest.t.sol";
import "forge-std/console.sol";

contract MEVTest is Test {
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

        // Set up orderbook and pool factory
        orderbookFactory.mockSetPoolManager(manager, true);
        orderbookFactory.mockSetOrderbook(address(orderbook));
        orderbookFactory.mockSetPoolFactory(address(poolFactory), true);

        vm.stopPrank();

    }

    function testBorrowWithExactAssets() public {
        // Prepare PoolConfig with maliscious Oracle
        address malisciousOracle = makeAddr("malisciousOracle");

        PoolStorage.PoolConfig memory cfg = PoolStorage.PoolConfig({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: malisciousOracle,
            irm: address(irm),
            lltv: 0.8e18 // 80% LTV
        });

        // Deploy pool using the factory
        vm.startPrank(manager);

        pool =
            TestAvonPool(payable(poolFactory.deployPool(cfg, MANAGER_FEE, 1.03e18, 0.03e18, 0.25e18, 0.001e18, 0, 0))); // No caps
        cfg.lltv = 0.9e18;
        
        vm.stopPrank();
        assertTrue(poolFactory.isValidPool(address(pool)), "Pool not valid");

        // Whitelist pool in orderbook with maliscious oracle
        vm.startPrank(manager);
        orderbook.mockWhitelistPool(address(pool), address(poolFactory));
        // verifyng that pool was whitelisted with maliscious oracle 
        assertEq(orderbook.isWhitelisted(address(pool)), true, "Pool not whitelisted");
        vm.stopPrank();

    }

}