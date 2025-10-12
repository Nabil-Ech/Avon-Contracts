// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockOrderbookFactory} from "../mock/MockOrderbookFactory.sol";
import {MockOrderbook} from "../mock/MockOrderbook.sol";
import {TestAvonPool} from "../TestHelper.t.sol";
import {BasePoolTest} from "../BasePoolTest.t.sol";
import {VaultFactory} from "../../src/factory/VaultFactory.sol";
import {Vault} from "../../src/vault/Vault.sol";

contract VaultTest is BasePoolTest {
    Vault public vault;

    function setUp() public override {
        super.setUp();
        vm.prank(owner);
        // Deploy vault
        VaultFactory vaultFactory = new VaultFactory(address(orderbookFactory));

        vm.prank(manager);
        vault = Vault(payable(vaultFactory.deployVault(address(loanToken), manager, manager, 0)));
        assertTrue(vaultFactory.isValidVault(address(vault)), "Vault should be valid");

        vm.startPrank(manager);
        Vault.PriorityEntry[] memory priorityEntries = new Vault.PriorityEntry[](6);
        priorityEntries[0] = Vault.PriorityEntry({
            totalAmount: 10e6,
            remaining: 0,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        priorityEntries[1] = Vault.PriorityEntry({
            totalAmount: 20e6,
            remaining: 0,
            pool: address(pool2),
            poolFactory: address(poolFactory)
        });
        priorityEntries[2] = Vault.PriorityEntry({
            totalAmount: 30e6,
            remaining: 0,
            pool: address(pool),
            poolFactory: address(poolFactory)
        });
        priorityEntries[3] = Vault.PriorityEntry({
            totalAmount: 10e6,
            remaining: 0,
            pool: address(pool2),
            poolFactory: address(poolFactory)
        });
        priorityEntries[4] = Vault.PriorityEntry({
            totalAmount: 20e6,
            remaining: 0,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        priorityEntries[5] = Vault.PriorityEntry({
            totalAmount: 10e6,
            remaining: 0,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        vault.setQueue(priorityEntries, Vault.QueueType.Deposit);
        vault.setQueue(priorityEntries, Vault.QueueType.Withdraw);
    }

    function testQueueInitialization() public view {
        Vault.PriorityEntry[] memory depositQueue = vault.getQueue(Vault.QueueType.Deposit);
        Vault.PriorityEntry[] memory withdrawQueue = vault.getQueue(Vault.QueueType.Withdraw);

        assertEq(depositQueue.length, 6, "Deposit queue should have 6 entries");
        assertEq(withdrawQueue.length, 6, "Withdraw queue should have 6 entries");

        assertEq(depositQueue[0].totalAmount, 10e6, "First deposit entry total amount mismatch");
        assertEq(withdrawQueue[0].totalAmount, 10e6, "First withdraw entry total amount mismatch");
    }

    // Owner function tests
    function testSetmanager() public {
        address newManager = address(0x456);
        // Revert with zero address
        vm.startPrank(manager);
        vm.expectRevert();
        vault.updateVaultManager(address(0));
        vm.stopPrank();

        // Non owner trying to set pool manager will revert
        vm.startPrank(address(0x789));
        vm.expectRevert();
        vault.updateVaultManager(newManager);
        vm.stopPrank();

        vm.startPrank(manager);
        vault.updateVaultManager(newManager);

        skip(2 days + 100);

        bytes memory callData = abi.encodeWithSelector(
            vault.execute.selector,
            address(vault),
            0,
            abi.encodeWithSelector(vault._executeUpdateVaultManager.selector, newManager),
            bytes32(0),
            bytes32(keccak256("UPDATE_VAULT_MANAGER"))
        );
        address(vault).call(callData);

        assertEq(vault.vaultManager(), newManager);
        vm.stopPrank();
    }

    // Pool Manager function tests
    function testSetQueueAlreadySet() public {
        vm.startPrank(manager);

        Vault.PriorityEntry[] memory entries = new Vault.PriorityEntry[](1);
        entries[0] = Vault.PriorityEntry({
            totalAmount: 1000e6,
            remaining: 1000e6,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });

        vm.expectRevert();
        vault.setQueue(entries, Vault.QueueType.Deposit);
        vm.stopPrank();
    }

    function testResetQueue() public {
        // Need to reset and set queue again
        vm.startPrank(manager);
        vault.resetQueue(Vault.QueueType.Deposit);
        vm.stopPrank();
        assertEq(vault.getQueue(Vault.QueueType.Deposit).length, 0, "Deposit queue should be empty after reset");

        Vault.PriorityEntry[] memory entries = new Vault.PriorityEntry[](2);
        entries[0] = Vault.PriorityEntry({
            totalAmount: 1000e6,
            remaining: 0,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        entries[1] = Vault.PriorityEntry({
            totalAmount: 2000e6,
            remaining: 0,
            pool: address(pool2),
            poolFactory: address(poolFactory)
        });

        // Non pool manager trying to reset queue will revert
        vm.startPrank(address(0x789));
        vm.expectRevert();
        vault.setQueue(entries, Vault.QueueType.Deposit);
        vm.stopPrank();

        vm.startPrank(manager);
        vault.setQueue(entries, Vault.QueueType.Deposit);
        vm.stopPrank();

        Vault.PriorityEntry[] memory queueEntries = vault.getQueue(Vault.QueueType.Deposit);
        assertEq(queueEntries.length, 2);
        assertEq(queueEntries[0].totalAmount, 1000e6);
        assertEq(queueEntries[1].totalAmount, 2000e6);

        vm.stopPrank();
    }

    function testAddQueueEntry() public {
        vm.startPrank(manager);

        Vault.PriorityEntry memory entry = Vault.PriorityEntry({
            totalAmount: 1e6,
            remaining: 1e6,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });

        vault.addQueueEntry(entry, Vault.QueueType.Deposit);

        Vault.PriorityEntry[] memory queueEntries = vault.getQueue(Vault.QueueType.Deposit);
        assertEq(queueEntries.length, 7);
        assertEq(queueEntries[6].totalAmount, 1e6);

        vm.stopPrank();
    }

    function testRemoveQueueEntry() public {
        vm.startPrank(manager);

        vault.removeQueueEntry(1, Vault.QueueType.Deposit);

        Vault.PriorityEntry[] memory queueEntries = vault.getQueue(Vault.QueueType.Deposit);
        assertEq(queueEntries.length, 5);
        assertEq(queueEntries[0].totalAmount, 10e6);
        assertEq(queueEntries[0].pool, address(pool1));

        assertEq(queueEntries[1].totalAmount, 30e6);
        assertEq(queueEntries[1].pool, address(pool));

        vm.stopPrank();
    }

    function testUpdateQueueEntry() public {
        vm.startPrank(manager);

        vault.updateQueueEntry(1, 200e6, Vault.QueueType.Deposit);

        Vault.PriorityEntry[] memory queueEntries = vault.getQueue(Vault.QueueType.Deposit);
        assertEq(queueEntries.length, 6);
        assertEq(queueEntries[1].totalAmount, 200e6);
        assertEq(queueEntries[1].pool, address(pool2));

        vm.stopPrank();
    }

    function testVaultDeposit() public {
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 20e6);
        vault.deposit(20e6, lender1);
        vm.stopPrank();

        assertEq(vault.balanceOf(lender1), 20e6, "Lender1 should have 20e6 USDC in vault");
        assertEq(vault.totalAssets(), 20e6, "Vault total assets should be 20e6 USDC");
        assertEq(
            vault.getQueue(Vault.QueueType.Deposit)[0].remaining, 0, "First deposit entry remaining should be 10e6"
        );
        assertEq(
            vault.getQueue(Vault.QueueType.Deposit)[1].remaining, 10e6, "Second deposit entry remaining should be 10e6"
        );
        assertEq(
            ERC4626(address(pool1)).balanceOf(address(vault)), 10e6, "address(Pool1) should have 10e6 USDC from vault"
        );
        assertEq(
            ERC4626(address(pool2)).balanceOf(address(vault)), 10e6, "address(Pool2) should have 10e6 USDC from vault"
        );
        assertEq(ERC4626(address(pool1)).totalAssets(), 10e6, "address(Pool1) total assets should be 80e6 USDC");
        assertEq(ERC4626(address(pool2)).totalAssets(), 10e6, "address(Pool2) total assets should be 80e6 USDC");
    }

    function testMint() public {
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 150e6);
        uint256 shares = vault.mint(150e6, lender1);
        vm.stopPrank();

        assertEq(vault.balanceOf(lender1), shares);
    }

    function testWithdrawWithQueueProcessing() public {
        uint256 balanceBefore = loanToken.balanceOf(lender1);
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 150e6);
        vault.deposit(120e6, lender1);
        vault.withdraw(60e6, lender1, lender1);
        vm.stopPrank();
        uint256 balanceAfter = loanToken.balanceOf(lender1);

        assertEq(balanceBefore - balanceAfter, 60e6, "Lender1 should have net deposit of 100e6 USDC");
        assertEq(IERC20(pool).balanceOf(address(vault)), 0, "Pool should have 0 shares after withdraw");
    }

    function testRedeem() public {
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 150e6);
        vault.deposit(150e6, lender1);
        uint256 shares = vault.balanceOf(lender1);
        assertGt(IERC20(address(pool1)).balanceOf(address(vault)), 0, "address(Pool1) should have shares in vault");
        assertGt(IERC20(address(pool2)).balanceOf(address(vault)), 0, "address(Pool2) should have shares in vault");
        assertGt(IERC20(pool).balanceOf(address(vault)), 0, "Pool should have shares in vault");

        vault.redeem(shares, lender1, lender1);
        vm.stopPrank();

        assertEq(
            IERC20(address(pool1)).balanceOf(address(vault)), 0, "address(Pool1) should have 0 shares after redeem"
        );
        assertEq(
            IERC20(address(pool2)).balanceOf(address(vault)), 0, "address(Pool2) should have 0 shares after redeem"
        );
        assertEq(IERC20(pool).balanceOf(address(vault)), 0, "Pool should have 0 shares after redeem");
    }

    function testTotalAssetsAndAvailableLiquidity() public {
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 200e6);
        vault.deposit(200e6, lender1);
        vm.stopPrank();

        assertEq(
            loanToken.balanceOf(address(vault)), 30e6, "Vault should have 40e6 USDC left after 10 steps of deposit"
        );
        assertEq(vault.availableLiquidity(), 30e6, "Vault should have 40e6 USDC available liquidity");
        assertEq(vault.totalAssets(), 200e6, "Vault total assets should be 200e6 USDC");
    }

    function testMultipleDeposits() public {
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 50e6);
        vault.deposit(50e6, lender1);
        vm.stopPrank();
        assertEq(vault.totalAssets(), 50e6, "Vault total assets should be 50e6 USDC");
        assertEq(vault.poolCount(), 3, "Vault should have 3 pools");
        assertEq(
            vault.getQueue(Vault.QueueType.Deposit)[2].remaining, 10e6, "Third deposit entry remaining should be 10e6"
        );
        vm.startPrank(lender2);
        loanToken.approve(address(vault), 60e6);
        vault.deposit(60e6, lender2);
        vm.stopPrank();
        assertEq(vault.totalAssets(), 110e6, "Vault total assets should be 110e6 USDC");
        assertEq(vault.getQueue(Vault.QueueType.Deposit)[0].remaining, 0, "First deposit entry remaining should be 0");
        //As deposit head is just at 2nd entry, the second entry should be as it was left
        assertEq(vault.getQueue(Vault.QueueType.Deposit)[1].remaining, 0, "Second deposit entry remaining should be 0");
        assertEq(vault.availableLiquidity(), 0, "Vault should have no available liquidity after deposits");
    }

    function testAllocateLiquidity() public {
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 200e6);
        vault.deposit(200e6, lender1);
        vm.stopPrank();
        assertEq(vault.availableLiquidity(), 30e6, "Vault should have 30e6 USDC available liquidity");

        vm.startPrank(manager);
        Vault.PriorityEntry[] memory entries = new Vault.PriorityEntry[](2);
        entries[0] = Vault.PriorityEntry({
            totalAmount: 10e6,
            remaining: 0,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        entries[1] = Vault.PriorityEntry({
            totalAmount: 5e6,
            remaining: 0,
            pool: address(pool2),
            poolFactory: address(poolFactory)
        });

        vault.relocateLiquidity(entries);
        vm.stopPrank();
        assertEq(vault.availableLiquidity(), 15e6, "Vault should have 0 USDC available liquidity after relocating");

        vm.startPrank(manager);
        // Allocate more than available liquidity
        entries[0].totalAmount = 100e6;

        vault.relocateLiquidity(entries);
        vm.stopPrank();
        assertEq(vault.availableLiquidity(), 0, "Vault should have 0 USDC available liquidity after relocating");
    }

    function testRemoveLiquidity() public {
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 100e6);
        vault.deposit(100e6, lender1);
        vm.stopPrank();

        vm.startPrank(manager);
        Vault.PriorityEntry[] memory entries = new Vault.PriorityEntry[](2);
        entries[0] = Vault.PriorityEntry({
            totalAmount: 5e6,
            remaining: 0,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        entries[1] = Vault.PriorityEntry({
            totalAmount: 5e6,
            remaining: 0,
            pool: address(pool2),
            poolFactory: address(poolFactory)
        });

        vault.removeLiquidity(entries);
        vm.stopPrank();
        assertEq(vault.availableLiquidity(), 10e6, "Vault should have 15e6 USDC available liquidity after relocating");
    }

    function testRemoveQueueEntryRevertsOnInvalidIndex() public {
        vm.startPrank(manager);
        // Remove with invalid index (out of bounds)
        uint256 len = vault.getQueue(Vault.QueueType.Deposit).length;
        vm.expectRevert();
        vault.removeQueueEntry(len, Vault.QueueType.Deposit);
        // Remove with empty queue
        vault.resetQueue(Vault.QueueType.Withdraw);
        vm.expectRevert();
        vault.removeQueueEntry(0, Vault.QueueType.Withdraw);
        vm.stopPrank();
    }

    function testUpdateQueueEntryRevertsOnInvalidIndex() public {
        vm.startPrank(manager);
        uint256 len = vault.getQueue(Vault.QueueType.Deposit).length;
        vm.expectRevert();
        vault.updateQueueEntry(len, 1e6, Vault.QueueType.Deposit);
        vm.stopPrank();
    }

    function testResetQueueEmitsEvent() public {
        vm.startPrank(manager);
        vm.expectEmit();
        emit Vault.QueueReset(Vault.QueueType.Deposit);
        vault.resetQueue(Vault.QueueType.Deposit);
        vm.stopPrank();
    }

    function testAddQueueEntryEmitsEvent() public {
        vm.startPrank(manager);
        Vault.PriorityEntry memory entry = Vault.PriorityEntry({
            totalAmount: 1e6,
            remaining: 1e6,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        vm.expectEmit();
        emit Vault.QueueEntryAdded(entry, Vault.QueueType.Deposit);
        vault.addQueueEntry(entry, Vault.QueueType.Deposit);
        vm.stopPrank();
    }

    function testRemoveQueueEntryEmitsEvent() public {
        vm.startPrank(manager);
        vm.expectEmit();
        emit Vault.QueueEntryRemoved(0, Vault.QueueType.Deposit);
        vault.removeQueueEntry(0, Vault.QueueType.Deposit);
        vm.stopPrank();
    }

    function testUpdateQueueEntryEmitsEvent() public {
        vm.startPrank(manager);
        vm.expectEmit();
        emit Vault.QueueEntryUpdated(0, 123e6, Vault.QueueType.Deposit);
        vault.updateQueueEntry(0, 123e6, Vault.QueueType.Deposit);
        vm.stopPrank();
    }

    function testPoolCountAndExistsAndTotalPools() public {
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 60e6);
        vault.deposit(60e6, lender1);
        vm.stopPrank();

        assertEq(vault.poolCount(), 3, "Should have 3 pools");
        assertTrue(vault.poolExists(address(pool1)));
        assertTrue(vault.poolExists(address(pool2)));
        assertTrue(vault.poolExists(address(pool)));
        address[] memory pools = vault.totalPools();
        assertEq(pools.length, 3);
    }

    function testOnlymanagerModifier() public {
        // setQueue
        Vault.PriorityEntry[] memory entries = new Vault.PriorityEntry[](1);
        entries[0] = Vault.PriorityEntry({
            totalAmount: 1e6,
            remaining: 1e6,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        vm.startPrank(address(0x1234));
        vm.expectRevert();
        vault.setQueue(entries, Vault.QueueType.Deposit);
        vm.expectRevert();
        vault.addQueueEntry(entries[0], Vault.QueueType.Deposit);
        vm.expectRevert();
        vault.removeQueueEntry(0, Vault.QueueType.Deposit);
        vm.expectRevert();
        vault.updateQueueEntry(0, 1e6, Vault.QueueType.Deposit);
        vm.expectRevert();
        vault.resetQueue(Vault.QueueType.Deposit);
        vm.expectRevert();
        vault.relocateLiquidity(entries);
        vm.expectRevert();
        vault.removeLiquidity(entries);
        vm.stopPrank();
    }

    function testNotValidFactoryRevertInValidatePool() public {
        vm.startPrank(owner);
        Vault.PriorityEntry memory entry =
            Vault.PriorityEntry({totalAmount: 1e6, remaining: 1e6, pool: address(pool1), poolFactory: address(0xdead)});
        orderbookFactory.mockSetPoolFactory(address(0xdead), false);
        vm.stopPrank();
        vm.startPrank(manager);
        vm.expectRevert();
        vault.addQueueEntry(entry, Vault.QueueType.Deposit);
        vm.stopPrank();
    }

    function testNotEnoughLiquidityRemoveLiquidity() public {
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 10e6);
        vault.deposit(10e6, lender1);
        vm.stopPrank();
        vm.startPrank(manager);
        Vault.PriorityEntry[] memory entries = new Vault.PriorityEntry[](1);
        entries[0] = Vault.PriorityEntry({
            totalAmount: 100e6, // More than available
            remaining: 0,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        vm.expectRevert();
        vault.removeLiquidity(entries);
        vm.stopPrank();
    }

    function testPoolNotFoundRemoveLiquidity() public {
        vm.startPrank(manager);
        Vault.PriorityEntry[] memory entries = new Vault.PriorityEntry[](1);
        entries[0] = Vault.PriorityEntry({
            totalAmount: 1e6,
            remaining: 0,
            pool: address(0xdeadbeef),
            poolFactory: address(poolFactory)
        });
        vm.expectRevert();
        vault.removeLiquidity(entries);
        vm.stopPrank();
    }

    function testRelocateLiquidityEmitsEvent() public {
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 200e6);
        vault.deposit(200e6, lender1);
        vm.stopPrank();
        vm.startPrank(manager);
        Vault.PriorityEntry[] memory entries = new Vault.PriorityEntry[](1);
        entries[0] = Vault.PriorityEntry({
            totalAmount: 1e6,
            remaining: 0,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        vm.expectEmit();
        emit Vault.RelocatedLiquidity(address(pool1), 1e6, 1e6);
        vault.relocateLiquidity(entries);
        vm.stopPrank();
    }

    function testRemoveLiquidityEmitsEvent() public {
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 10e6);
        vault.deposit(10e6, lender1);
        vm.stopPrank();
        vm.startPrank(manager);
        Vault.PriorityEntry[] memory entries = new Vault.PriorityEntry[](1);
        entries[0] = Vault.PriorityEntry({
            totalAmount: 1e6,
            remaining: 0,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        vm.expectEmit();
        emit Vault.RemovedLiquidity(address(pool1), 1e6, 1e6);
        vault.removeLiquidity(entries);
        vm.stopPrank();
    }

    function testDepositAndMintNonReentrant() public {
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 10e6);
        vault.deposit(10e6, lender1);
        loanToken.approve(address(vault), 10e6);
        vault.mint(10e6, lender1);
        vm.stopPrank();
    }

    function testWithdrawAndRedeemNonReentrant() public {
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 20e6);
        vault.deposit(20e6, lender1);
        vm.stopPrank();
        vm.startPrank(lender1);
        vault.withdraw(10e6, lender1, lender1);
        vault.redeem(vault.balanceOf(lender1), lender1, lender1);
        vm.stopPrank();
    }

    function testAvailableLiquidityAndTotalAssets() public {
        assertEq(vault.availableLiquidity(), 0, "Initially no liquidity");
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 10e6);
        vault.deposit(10e6, lender1);
        vm.stopPrank();
        assertEq(vault.availableLiquidity(), 0, "All deposited should be allocated");
        assertGt(vault.totalAssets(), 0, "Total assets should be > 0 after deposit");
    }

    function testUpdateQueueEntryReducesRemainingIfGreaterThanNewAmount() public {
        vm.startPrank(manager);
        // Set up entry with remaining > newAmount
        vault.resetQueue(Vault.QueueType.Deposit);
        Vault.PriorityEntry[] memory entries = new Vault.PriorityEntry[](1);
        entries[0] = Vault.PriorityEntry({
            totalAmount: 100e6,
            remaining: 90e6,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        vault.setQueue(entries, Vault.QueueType.Deposit);
        vault.updateQueueEntry(0, 50e6, Vault.QueueType.Deposit);
        Vault.PriorityEntry[] memory queueEntries = vault.getQueue(Vault.QueueType.Deposit);
        assertEq(queueEntries[0].totalAmount, 50e6);
        assertEq(queueEntries[0].remaining, 50e6, "Remaining should be reduced to newAmount");
        vm.stopPrank();
    }

    function testAllocateDepositWrapsAroundQueue() public {
        vm.startPrank(manager);
        vault.resetQueue(Vault.QueueType.Deposit);
        Vault.PriorityEntry[] memory entries = new Vault.PriorityEntry[](2);
        entries[0] = Vault.PriorityEntry({
            totalAmount: 10e6,
            remaining: 0,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        entries[1] = Vault.PriorityEntry({
            totalAmount: 10e6,
            remaining: 0,
            pool: address(pool2),
            poolFactory: address(poolFactory)
        });
        vault.setQueue(entries, Vault.QueueType.Deposit);
        vm.stopPrank();

        vm.startPrank(lender1);
        loanToken.approve(address(vault), 40e6);
        vault.deposit(40e6, lender1);
        vm.stopPrank();

        // Should have wrapped around and allocated to both entries twice
        assertEq(ERC4626(address(pool1)).balanceOf(address(vault)), 20e6);
        assertEq(ERC4626(address(pool2)).balanceOf(address(vault)), 20e6);
    }

    function testPerformWithdrawSkipsPoolWithInsufficientShares() public {
        // Setup: deposit to address(pool1), then forcibly reduce poolShares to 0 to simulate insufficient shares
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 10e6);
        vault.deposit(10e6, lender1);
        vm.stopPrank();

        vm.startPrank(manager);
        // Withdraw queue with address(pool1) and address(pool2)
        vault.resetQueue(Vault.QueueType.Withdraw);
        Vault.PriorityEntry[] memory entries = new Vault.PriorityEntry[](2);
        entries[0] = Vault.PriorityEntry({
            totalAmount: 10e6,
            remaining: 0,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        entries[1] = Vault.PriorityEntry({
            totalAmount: 10e6,
            remaining: 0,
            pool: address(pool2),
            poolFactory: address(poolFactory)
        });
        vault.setQueue(entries, Vault.QueueType.Withdraw);
        vm.stopPrank();

        // Simulate poolShares[address(pool1)] = 0 (by removing liquidity)
        vm.startPrank(manager);
        Vault.PriorityEntry[] memory removeEntries = new Vault.PriorityEntry[](1);
        removeEntries[0] = Vault.PriorityEntry({
            totalAmount: 10e6,
            remaining: 0,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        vault.removeLiquidity(removeEntries);
        vm.stopPrank();

        assertEq(ERC4626(address(pool1)).balanceOf(address(vault)), 0);
        // Now withdraw, should skip address(pool1) and use address(pool2)
        vm.startPrank(lender1);
        vault.withdraw(10e6, lender1, lender1);
        vm.stopPrank();
        // address(pool1) shares should be 0, address(pool2) shares should be reduced
        assertEq(
            ERC4626(address(pool2)).balanceOf(address(vault)), 0, "address(Pool1) should have 0 shares after withdraw"
        );
    }

    function testPoolAssetsReturnsZeroForZeroShares() public view {
        // poolShares[pool] is 0 initially
        assertEq(vault.poolAssets(address(pool)), 0, "Should return 0 for zero shares");
    }

    function testRemoveLiquiditySkipsIfNotEnoughShares() public {
        // Setup: deposit to address(pool1), then try to remove more than available shares
        vm.startPrank(lender1);
        loanToken.approve(address(vault), 10e6);
        vault.deposit(10e6, lender1);
        vm.stopPrank();

        vm.startPrank(manager);
        Vault.PriorityEntry[] memory entries = new Vault.PriorityEntry[](1);
        entries[0] = Vault.PriorityEntry({
            totalAmount: 10e6,
            remaining: 0,
            pool: address(pool1),
            poolFactory: address(poolFactory)
        });
        // Remove all liquidity
        vault.removeLiquidity(entries);
        // Try to remove again
        vm.expectRevert();
        vault.removeLiquidity(entries);
        assertEq(vault.poolAssets(address(pool1)), 0, "Should remain 0 after skipping");
        vm.stopPrank();
    }

    function testUpdateTimelockDuration() public {
        uint256 newTimelockDuration = 3 days; // A valid duration between MIN and MAX
        bytes32 UPDATE_TIMELOCK_DURATION_SALT = bytes32(keccak256("UPDATE_TIMELOCK_DURATION"));

        // Verify initial timelock duration
        assertEq(vault.getMinDelay(), vault.DEFAULT_TIMELOCK_DURATION(), "Initial timelock duration should be default");

        // Non-manager cannot update timelock duration
        vm.startPrank(random);
        vm.expectRevert(); // Unauthorized - lacks PROPOSER_ROLE
        vault.updateTimeLockDuration(newTimelockDuration);
        vm.stopPrank();

        // Manager can schedule timelock duration update
        vm.startPrank(manager); // manager has PROPOSER_ROLE
        vault.updateTimeLockDuration(newTimelockDuration);

        // Try to execute immediately - should fail due to timelock
        bytes memory callData = abi.encodeWithSelector(
            vault.execute.selector,
            address(vault),
            0,
            abi.encodeWithSelector(vault._executeUpdateTimelockDuration.selector, newTimelockDuration),
            bytes32(0),
            UPDATE_TIMELOCK_DURATION_SALT
        );

        (bool success,) = address(vault).call(callData);
        assertFalse(success, "Should not be able to execute before timelock expires");

        // Forward time to complete the timelock period
        skip(vault.DEFAULT_TIMELOCK_DURATION() + 100);

        // Execute the update
        (success,) = address(vault).call(callData);
        assertTrue(success, "Execution should succeed after timelock period");

        // Verify timelock duration was updated
        assertEq(vault.getMinDelay(), newTimelockDuration, "Timelock duration should be updated");
    }

    function testTimelockDurationValidation() public {
        // Try to set timelock duration below minimum
        vm.startPrank(manager);
        vm.expectRevert(); // IncorrectInput
        vault.updateTimeLockDuration(1 days - 1);

        // Try to set timelock duration above maximum
        vm.expectRevert(); // IncorrectInput
        vault.updateTimeLockDuration(7 days + 1);

        // Valid timelock duration should schedule successfully
        uint256 validDuration = vault.MIN_TIMELOCK_DURATION() + 1 hours;
        vault.updateTimeLockDuration(validDuration);
    }

    function testUpdateTimelockDurationDirectlyFails() public {
        uint256 newTimelockDuration = 3 days;

        // Attempt to call _executeUpdateTimelockDuration directly
        vm.startPrank(manager);
        vm.expectRevert(); // Unauthorized - only contract can call this
        vault._executeUpdateTimelockDuration(newTimelockDuration);
        vm.stopPrank();

        // Verify timelock duration remains unchanged
        assertEq(vault.getMinDelay(), vault.DEFAULT_TIMELOCK_DURATION(), "Timelock duration should not change");
    }
}
