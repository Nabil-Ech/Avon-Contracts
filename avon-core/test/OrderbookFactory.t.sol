// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockIRM} from "./mocks/MockIRM.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {OrderbookFactory} from "../src/OrderbookFactory.sol";

contract OrderbookFactoryTest is Test {
    OrderbookFactory public orderbookFactory;
    MockERC20 public loanToken;
    MockERC20 public collateralToken;
    MockIRM public mockIrm;
    address public owner;
    address public nonOwner;
    address public feeRecipient;
    address public poolMaker1;
    address public poolMaker2;
    address irmAddress;

    function setUp() public {
        // Setup accounts
        owner = address(this);
        feeRecipient = makeAddr("feeRecipient");
        poolMaker1 = makeAddr("poolMaker1");
        poolMaker2 = makeAddr("poolMaker2");
        nonOwner = makeAddr("nonOwner");

        // Deploy mock tokens
        loanToken = new MockERC20("Loan Token", "LOAN");
        collateralToken = new MockERC20("Collateral Token", "COLL");

        // Deploy mock IRM
        mockIrm = new MockIRM(0.01e18, 0.1e18, 1e18, 0.8e18);
        irmAddress = address(mockIrm);

        // Deploy factory contract
        orderbookFactory = new OrderbookFactory(feeRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testConstructorSetsOwnerAsFeeRecipient() public view {
        assertEq(orderbookFactory.feeRecipient(), feeRecipient);
        assertEq(orderbookFactory.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                              IRM TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetIrm() public {
        // Owner enables an IRM contract.
        vm.prank(owner);
        orderbookFactory.setIrm(irmAddress, true);
        bool enabled = orderbookFactory.isIRMEnabled(irmAddress);
        assertTrue(enabled);

        // Expect revert if trying to enable the same IRM again.
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        orderbookFactory.setIrm(irmAddress, true);

        // Expect revert if a non-owner tries to enable an IRM.
        vm.prank(nonOwner);
        vm.expectRevert();
        orderbookFactory.setIrm(address(5), true);
    }

    function testDisableIrm() public {
        // First, enable the IRM.
        vm.prank(owner);
        orderbookFactory.setIrm(irmAddress, true);

        // Then disable it.
        vm.prank(owner);
        orderbookFactory.setIrm(irmAddress, false);
        bool enabled = orderbookFactory.isIRMEnabled(irmAddress);
        assertTrue(!enabled);

        // Attempting to disable a non-enabled IRM should revert.
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        orderbookFactory.setIrm(irmAddress, false);
    }

    /*//////////////////////////////////////////////////////////////
                        FEE RECIPIENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetFeeRecipient() public {
        // Update the feeRecipient with a new non-zero address.
        vm.prank(owner);
        orderbookFactory.setFeeRecipient(nonOwner);
        assertEq(orderbookFactory.feeRecipient(), nonOwner);

        // Expect revert when setting feeRecipient to the zero address.
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.InvalidInput.selector);
        orderbookFactory.setFeeRecipient(address(0));

        // Expect revert when setting feeRecipient to the same address as current.
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        orderbookFactory.setFeeRecipient(nonOwner);
    }

    /*//////////////////////////////////////////////////////////////
                          ORDERBOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function testCreateOrderbookInvalidInputs() public {
        // Invalid: _loanToken is the zero address.
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.InvalidInput.selector);
        orderbookFactory.createOrderbook(address(0), address(collateralToken), address(feeRecipient));

        // Invalid: _collateralToken is the zero address.
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.InvalidInput.selector);
        orderbookFactory.createOrderbook(address(loanToken), address(0), address(feeRecipient));
    }

    function testCreateOrderbook() public {
        // Create a new orderbook.
        vm.prank(owner);
        address orderbookAddr =
            orderbookFactory.createOrderbook(address(loanToken), address(collateralToken), address(feeRecipient));

        // Verify the orderbook is stored correctly in the mapping.
        address storedAddress = orderbookFactory.getOrderbook(address(loanToken), address(collateralToken));
        assertEq(storedAddress, orderbookAddr);

        // Verify that getAllOrderbooks returns the newly created orderbook.
        address[] memory allOrderbooks = orderbookFactory.getAllOrderbooks();
        assertEq(allOrderbooks.length, 1);

        // Attempting to create a duplicate orderbook should revert.
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.OrderbookAlreadyExists.selector);
        orderbookFactory.createOrderbook(address(loanToken), address(collateralToken), address(feeRecipient));
    }

    function testGetOrderbook() public {
        // Create an orderbook first.
        vm.prank(owner);
        address orderbookAddr =
            orderbookFactory.createOrderbook(address(loanToken), address(collateralToken), address(feeRecipient));

        // Retrieve the orderbook via getOrderbook and verify the address.
        address retrievedAddress = orderbookFactory.getOrderbook(address(loanToken), address(collateralToken));
        assertEq(retrievedAddress, orderbookAddr);

        // For a non-existent orderbook, getOrderbook should revert.
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.OrderbookNotFound.selector);
        orderbookFactory.getOrderbook(address(loanToken), nonOwner);
    }

    function testGetAllOrderbooks() public {
        // Create multiple orderbooks
        // Create first orderbook
        address orderbook1 =
            orderbookFactory.createOrderbook(address(loanToken), address(collateralToken), address(feeRecipient));

        // Create second orderbook with different token pair
        MockERC20 loanToken2 = new MockERC20("Loan Token 2", "LOAN2");
        address orderbook2 =
            orderbookFactory.createOrderbook(address(loanToken2), address(collateralToken), address(feeRecipient));

        // Get all orderbooks and verify
        address[] memory allOrderbooks = orderbookFactory.getAllOrderbooks();
        assertEq(allOrderbooks.length, 2);
        assertEq(allOrderbooks[0], orderbook1);
        assertEq(allOrderbooks[1], orderbook2);
    }

    function testFullWorkflow() public {
        // 1. Enable IRM
        orderbookFactory.setIrm(address(mockIrm), true);
        assertTrue(orderbookFactory.isIRMEnabled(address(mockIrm)));

        // 2. Set new fee recipient
        address newFeeRecipient = makeAddr("newFeeRecipient");
        orderbookFactory.setFeeRecipient(newFeeRecipient);
        assertEq(orderbookFactory.feeRecipient(), newFeeRecipient);

        // 3. Create orderbook
        address orderbookAddress =
            orderbookFactory.createOrderbook(address(loanToken), address(collateralToken), address(feeRecipient));

        // 4. Verify orderbook was created properly
        Orderbook orderbook = Orderbook(orderbookAddress);
        assertEq(orderbook.owner(), owner);
        (address loan, address collateral,) = orderbook.orderbookConfig();
        assertEq(loan, address(loanToken));
        assertEq(collateral, address(collateralToken));

        // 5. Get orderbook by token pair
        address retrievedOrderbook = orderbookFactory.getOrderbook(address(loanToken), address(collateralToken));
        assertEq(retrievedOrderbook, orderbookAddress);

        // 6. Disable IRM
        orderbookFactory.setIrm(address(mockIrm), false);
        assertFalse(orderbookFactory.isIRMEnabled(address(mockIrm)));
    }

    function testOwnershipTransfer() public {
        // Test owner transfer
        address newOwner = makeAddr("newOwner");

        // Transfer ownership
        orderbookFactory.transferOwnership(newOwner);

        // Owner is not changed until acceptance
        assertEq(orderbookFactory.owner(), owner);
        assertEq(orderbookFactory.pendingOwner(), newOwner);

        // Accept ownership
        vm.prank(newOwner);
        orderbookFactory.acceptOwnership();

        // Verify new owner
        assertEq(orderbookFactory.owner(), newOwner);

        // Old owner can no longer perform admin functions
        vm.expectRevert();
        orderbookFactory.setIrm(address(mockIrm), true);

        // New owner can perform admin functions
        vm.prank(newOwner);
        orderbookFactory.setIrm(address(mockIrm), true);
        assertTrue(orderbookFactory.isIRMEnabled(address(mockIrm)));
    }

    function testCreateMultipleOrderbooks() public {
        // Create multiple orderbooks with different token pairs
        for (uint256 i = 0; i < 10; i++) {
            MockERC20 loanTokenN = new MockERC20(
                string(abi.encodePacked("Loan Token ", uint8(i + 1))), string(abi.encodePacked("LOAN", uint8(i + 1)))
            );
            MockERC20 collateralTokenN = new MockERC20(
                string(abi.encodePacked("Collateral Token ", uint8(i + 1))),
                string(abi.encodePacked("COLL", uint8(i + 1)))
            );

            orderbookFactory.createOrderbook(address(loanTokenN), address(collateralTokenN), address(feeRecipient));
        }

        // Verify all orderbooks are created
        address[] memory allOrderbooks = orderbookFactory.getAllOrderbooks();
        assertEq(allOrderbooks.length, 10);
    }
}
