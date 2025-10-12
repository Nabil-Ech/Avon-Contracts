// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../BasePoolTest.t.sol";
import {PoolEvents} from "../../src/pool/utils/PoolEvents.sol";
import {PoolConstants} from "../../src/pool/utils/PoolConstants.sol";

contract PermissionAndAdminTest is BasePoolTest {
    // Constants for timelock testing
    bytes32 constant UPDATE_ORDERBOOK_SALT = keccak256("UPDATE_ORDERBOOK");
    bytes32 constant UPDATE_POOL_MANAGER_SALT = keccak256("UPDATE_POOL_MANAGER");
    bytes32 constant UPDATE_MANAGER_FEE_SALT = keccak256("UPDATE_MANAGER_FEE");
    bytes32 constant UPDATE_PROTOCOL_FEE_SALT = keccak256("UPDATE_PROTOCOL_FEE");
    bytes32 constant UPDATE_TIMELOCK_DURATION_SALT = keccak256("UPDATE_TIMELOCK_DURATION");
    bytes32 constant INCREASE_LTV_SALT = keccak256("INCREASE_LTV");

    // Test variables
    address newManager;
    uint64 newManagerFee;
    uint64 newProtocolFee;
    uint64 newTimelockDuration;

    function setUp() public override {
        super.setUp();

        // Setup additional test actors and contracts for timelock tests
        newManager = makeAddr("newManager");
        newManagerFee = 0.05e18; // 5% fee
        newProtocolFee = 0.02e18; // 2% fee
        newTimelockDuration = 48 hours; // 48 hours
    }

    function testPermissionManagement() public {
        // Setup a lending position
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Setup collateral for borrower
        vm.startPrank(borrower);
        collateralToken.approve(address(pool), 1e18);
        pool.depositCollateral(1e18, borrower);

        // Verify lender2 can't borrow on behalf of borrower
        vm.stopPrank();
        vm.startPrank(lender2);
        vm.expectRevert(); // Unauthorized
        pool.borrow(100e6, 0, borrower, lender2, 100e6);
        vm.stopPrank();

        // Borrower grants permission to lender2
        vm.startPrank(borrower);
        pool.setAuthorization(lender2, true);
        vm.stopPrank();

        // Now lender2 can borrow on behalf of borrower
        vm.startPrank(lender2);
        (uint256 assets,) = pool.borrow(100e6, 0, borrower, lender2, 100e6);
        assertEq(assets, 100e6, "Should be able to borrow after permission is granted");

        // Borrower revokes permission
        vm.stopPrank();
        vm.prank(borrower);
        pool.setAuthorization(lender2, false);

        // lender2 can't borrow anymore
        vm.startPrank(lender2);
        vm.expectRevert(); // Unauthorized
        pool.borrow(100e6, 0, borrower, lender2, 100e6);
        vm.stopPrank();
    }

    function testPauseAndUnpause() public {
        // Setup
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Non-owner can't pause
        vm.prank(random);
        vm.expectRevert(); // Unauthorized
        pool.pausePool(true);

        // Owner can pause
        vm.prank(owner);
        pool.pausePool(true);

        // Verify operations are blocked when paused
        vm.startPrank(lender2);
        loanToken.approve(address(pool), 100e6);
        vm.expectRevert(); // Paused
        pool.deposit(100e6, lender2);
        vm.stopPrank();

        // Owner can unpause
        vm.prank(owner);
        pool.pausePool(false);

        // Operations work again
        vm.startPrank(lender2);
        loanToken.approve(address(pool), 100e6);
        uint256 shares = pool.deposit(100e6, lender2);
        assertGt(shares, 0, "Should be able to deposit after unpausing");
        vm.stopPrank();
    }

    function testUpdateOrderbook() public {
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Deploy new mock orderbook
        vm.startPrank(owner);
        MockOrderbookFactory newOrderbookFactory = new MockOrderbookFactory(manager);
        MockOrderbook newOrderbook = new MockOrderbook(address(newOrderbookFactory));
        newOrderbookFactory.mockSetPoolManager(manager, true);
        newOrderbookFactory.mockSetOrderbook(address(orderbook));
        newOrderbookFactory.mockSetPoolFactory(address(poolFactory), true);
        vm.stopPrank();

        vm.prank(manager);
        newOrderbook.mockWhitelistPool(address(pool), address(poolFactory));

        // Non-manager can't update orderbook
        vm.prank(random);
        vm.expectRevert(); // Unauthorized
        pool.updateOrderbook(address(newOrderbook), address(newOrderbookFactory));

        vm.prank(owner);
        orderbook.setNewOrderbook(address(newOrderbook));

        // Manager can schedule orderbook update
        vm.prank(manager);
        pool.updateOrderbook(address(newOrderbook), address(newOrderbookFactory));

        // Try to execute immediately - should fail due to timelock
        bytes memory callData = abi.encodeWithSelector(
            pool.execute.selector,
            address(pool),
            0,
            abi.encodeWithSelector(
                pool._executeUpdateOrderbook.selector, address(newOrderbook), address(newOrderbookFactory)
            ),
            bytes32(0),
            UPDATE_ORDERBOOK_SALT
        );

        vm.prank(manager);
        (bool success,) = address(pool).call(callData);
        assertFalse(success, "Should not be able to execute before timelock expires");

        // Forward time but not enough
        skip(PoolConstants.DEFAULT_TIMELOCK_DURATION / 2);

        vm.prank(manager);
        (success,) = address(pool).call(callData);
        assertFalse(success, "Should not be able to execute when timelock partially expired");

        // Forward time to complete the timelock period
        skip(PoolConstants.DEFAULT_TIMELOCK_DURATION / 2 + 100);

        // Execute the update
        vm.prank(manager);
        (success,) = address(pool).call(callData);

        // Verify orderbook was updated
        assertEq(pool.getOrderbook(), address(newOrderbook), "Orderbook should be updated");
        assertEq(pool.getOrderbookFactory(), address(newOrderbookFactory), "Orderbook factory should be updated");

        // Ensure basic operations still work
        vm.startPrank(lender1);
        loanToken.approve(address(pool), 100e6);
        uint256 shares = pool.deposit(100e6, lender1);
        assertGt(shares, 0, "Should be able to deposit after orderbook update");
        vm.stopPrank();
    }

    function testUpdatePoolManager() public {
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        pool.getPoolManager();

        // Non-manager can't update pool manager
        vm.prank(random);
        vm.expectRevert(); // Unauthorized
        pool.updatePoolManager(newManager);

        // Manager can schedule pool manager update
        vm.prank(manager);
        pool.updatePoolManager(newManager);

        // Try to execute immediately - should fail due to timelock
        bytes memory callData = abi.encodeWithSelector(
            pool.execute.selector,
            address(pool),
            0,
            abi.encodeWithSelector(pool._executeUpdatePoolManager.selector, newManager),
            bytes32(0),
            UPDATE_POOL_MANAGER_SALT
        );

        vm.prank(manager);
        (bool success,) = address(pool).call(callData);
        assertFalse(success, "Should not be able to execute before timelock expires");

        // Forward time to complete the timelock period
        skip(PoolConstants.DEFAULT_TIMELOCK_DURATION + 100);

        // Execute the update
        vm.prank(manager);
        (success,) = address(pool).call(callData);

        // Verify pool manager was updated
        assertEq(pool.getPoolManager(), newManager, "Pool manager should be updated");
    }

    function testUpdateManagerFee() public {
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Non-manager can't update manager fee
        vm.prank(random);
        vm.expectRevert(); // Unauthorized
        pool.updateManagerFee(newManagerFee);

        // Manager can schedule manager fee update
        vm.prank(manager);
        pool.updateManagerFee(newManagerFee);

        // Try to execute immediately - should fail due to timelock
        bytes memory callData = abi.encodeWithSelector(
            pool.execute.selector,
            address(pool),
            0,
            abi.encodeWithSelector(pool._executeUpdateManagerFee.selector, newManagerFee),
            bytes32(0),
            UPDATE_MANAGER_FEE_SALT
        );

        vm.prank(manager);
        (bool success,) = address(pool).call(callData);
        assertFalse(success, "Should not be able to execute before timelock expires");

        // Forward time to complete the timelock period
        skip(PoolConstants.DEFAULT_TIMELOCK_DURATION + 100);

        // Execute the update
        vm.prank(manager);
        (success,) = address(pool).call(callData);
    }

    function testUpdateProtocolFee() public {
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Non-admin can't update protocol fee
        vm.prank(random);
        vm.expectRevert(); // Unauthorized
        pool.updateProtocolFee(newProtocolFee);

        // Admin can schedule protocol fee update
        vm.prank(owner); // owner has DEFAULT_ADMIN_ROLE
        pool.updateProtocolFee(newProtocolFee);

        // Try to execute immediately - should fail due to timelock
        bytes memory callData = abi.encodeWithSelector(
            pool.execute.selector,
            address(pool),
            0,
            abi.encodeWithSelector(pool._executeUpdateProtocolFee.selector, newProtocolFee),
            bytes32(0),
            UPDATE_PROTOCOL_FEE_SALT
        );

        vm.prank(owner);
        (bool success,) = address(pool).call(callData);
        assertFalse(success, "Should not be able to execute before timelock expires");

        // Forward time to complete the timelock period
        skip(PoolConstants.DEFAULT_TIMELOCK_DURATION + 100);

        // Execute the update
        vm.prank(owner);
        (success,) = address(pool).call(callData);

        // Verify protocol fee was updated
        assertEq(pool.getProtocolFee(), newProtocolFee, "Protocol fee should be updated");
    }

    function testUpdateTimelockDuration() public {
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Non-admin can't update timelock duration
        vm.prank(random);
        vm.expectRevert(); // Unauthorized
        pool.updateTimeLockDuration(newTimelockDuration);

        // Admin can schedule timelock duration update
        vm.prank(owner); // owner has DEFAULT_ADMIN_ROLE
        pool.updateTimeLockDuration(newTimelockDuration);

        // Try to execute immediately - should fail due to timelock
        bytes memory callData = abi.encodeWithSelector(
            pool.execute.selector,
            address(pool),
            0,
            abi.encodeWithSelector(pool.updateDelay.selector, newTimelockDuration),
            bytes32(0),
            UPDATE_TIMELOCK_DURATION_SALT
        );

        vm.prank(owner);
        (bool success,) = address(pool).call(callData);
        assertFalse(success, "Should not be able to execute before timelock expires");

        // Forward time to complete the timelock period
        skip(PoolConstants.DEFAULT_TIMELOCK_DURATION + 100);

        // Execute the update
        vm.prank(owner);
        (success,) = address(pool).call(callData);

        // Verify timelock duration was updated
        assertEq(pool.getMinDelay(), newTimelockDuration, "Timelock duration should be updated");
    }

    function testTimelockCancellation() public {
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Schedule a pool manager update
        vm.prank(manager);
        pool.updatePoolManager(newManager);

        // Get the operation ID
        bytes32 operationId = keccak256(
            abi.encode(
                address(pool),
                0,
                abi.encodeWithSelector(pool._executeUpdatePoolManager.selector, newManager),
                bytes32(0),
                UPDATE_POOL_MANAGER_SALT
            )
        );

        // Check operation is pending
        assertTrue(pool.isOperationPending(operationId), "Operation should be pending");

        // Cancel the operation
        vm.prank(owner); // Owner has CANCELLER_ROLE
        pool.cancel(operationId);

        // Check operation is no longer pending
        assertFalse(pool.isOperationPending(operationId), "Operation should not be pending after cancellation");

        // Forward time past the timelock period
        skip(PoolConstants.DEFAULT_TIMELOCK_DURATION + 100);

        // Try to execute the cancelled operation - should fail
        bytes memory callData = abi.encodeWithSelector(
            pool.execute.selector,
            address(pool),
            0,
            abi.encodeWithSelector(pool._executeUpdatePoolManager.selector, newManager),
            bytes32(0),
            UPDATE_POOL_MANAGER_SALT
        );

        vm.prank(manager);
        (bool success,) = address(pool).call(callData);
        assertFalse(success, "Should not be able to execute cancelled operation");
    }

    function testIncreaseLLTV() public {
        uint64 initialLTV = uint64(pool.getLTV());
        uint64 newLTV = uint64(initialLTV + 0.05e18); // Increase by 5%

        // Non-manager can't increase LLTV
        vm.prank(random);
        vm.expectRevert(); // Unauthorized
        pool.updateLLTVUpward(newLTV);

        // Manager can increase LLTV
        vm.prank(owner);
        pool.updateLLTVUpward(newLTV);

        // Verify LLTV was updated
        vm.warp(3 days);
        bytes memory callData = abi.encodeWithSelector(
            pool.execute.selector,
            address(pool),
            0,
            abi.encodeWithSelector(pool._executeLLTVUpward.selector, newLTV),
            bytes32(0),
            INCREASE_LTV_SALT
        );
        vm.prank(manager);
        (bool success,) = address(pool).call(callData);
        assertTrue(success, "Should be able to execute after timelock expires");
        assertEq(pool.getLTV(), newLTV, "LLTV should be updated");

        // Try to decrease LLTV (should fail)
        vm.prank(manager);
        vm.expectRevert(); // InvalidInput
        pool.updateLLTVUpward(initialLTV); // Decreasing LLTV is not allowed

        // Try to set too high LLTV (should fail)
        vm.prank(manager);
        vm.expectRevert(); // InvalidInput
        pool.updateLLTVUpward(1e18); // 100% LTV is too high
    }

    function testProtocolFeeValidation() public {
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Try to set protocol fee that would exceed MAX_TOTAL_FEE when combined with manager fee
        uint64 currentManagerFee = pool.getManagerFee();
        uint64 invalidProtocolFee = PoolConstants.MAX_TOTAL_FEE - currentManagerFee + 1;

        vm.prank(owner);
        vm.expectRevert(); // InvalidInput
        pool.updateProtocolFee(invalidProtocolFee);
    }

    function testTimelockDurationValidation() public {
        _setupLendingPosition(lender1, DEFAULT_DEPOSIT_AMOUNT);

        // Try to set timelock duration below minimum
        vm.prank(owner);
        vm.expectRevert(); // InvalidInput
        pool.updateTimeLockDuration(PoolConstants.MIN_TIMELOCK_DURATION - 1);

        // Try to set timelock duration above maximum
        vm.prank(owner);
        vm.expectRevert(); // InvalidInput
        pool.updateTimeLockDuration(PoolConstants.MAX_TIMELOCK_DURATION + 1);

        // Valid timelock duration should work
        uint64 validDuration = PoolConstants.MIN_TIMELOCK_DURATION + 1 hours;
        vm.prank(owner);
        pool.updateTimeLockDuration(validDuration);
    }
}
