// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {PoolGetter} from "../pool/utils/PoolGetter.sol";
import {IOrderbookFactory} from "../interface/IOrderbookFactory.sol";
import {IPoolImplementation} from "../interface/IPoolImplementation.sol";
import {IPoolFactory} from "../interface/IPoolFactory.sol";

contract Vault is ERC4626, Ownable2Step, ReentrancyGuard, TimelockController {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for ERC20;
    using Math for uint256;

    struct PriorityEntry {
        uint256 totalAmount;
        uint256 remaining;
        address pool;
        address poolFactory;
    }

    struct Queue {
        uint128 depositHead;
        uint128 withdrawHead;
        PriorityEntry[] depositQueue;
        PriorityEntry[] withdrawQueue;
    }

    enum QueueType {
        Deposit,
        Withdraw
    }

    address public feeRecipient;
    uint256 public managerFees;
    uint256 public constant MAX_MANAGER_FEES = 0.5e18; // 50% maximum manager fees
    uint256 public prevTotal;

    address public vaultManager;
    address public immutable ORDERBOOK_FACTORY;
    uint256 public constant MAX_QUEUE_PROCESSING = 10;

    uint256 public constant DEFAULT_TIMELOCK_DURATION = 2 days;
    uint256 public constant MIN_TIMELOCK_DURATION = 1 days;
    uint256 public constant MAX_TIMELOCK_DURATION = 7 days;

    Queue private _queue;
    EnumerableSet.AddressSet private _pools;

    mapping(address => uint256) public poolShares;

    event RelocatedLiquidity(address indexed poolAddress, uint256 indexed amount, uint256 shares);
    event RemovedLiquidity(address indexed poolAddress, uint256 indexed amount, uint256 shares);
    event VaultManagerChanged(address indexed oldVaultManager, address indexed newVaultManager);
    event PoolFactorySet(address indexed poolFactory, bool status);
    event QueueEntryAdded(PriorityEntry newEntry, QueueType queueType);
    event QueueEntryRemoved(uint256 index, QueueType queueType);
    event QueueEntryUpdated(uint256 index, uint256 newAmount, QueueType queueType);
    event QueueReset(QueueType queueType);
    event VaultFeesChanged(uint256 newManagerFees);
    event TotalAssetsUpdated(uint256 newTotalAssets);
    event ManagerFeesAccrued(uint256 managerFeesAmount, uint256 shares);
    event FeeRecipientChanged(address indexed newFeeRecipient);
    event VaultManagerUpdateScheduled(address indexed vault, address indexed newVaultManager);
    event ManagerFeeUpdateScheduled(address indexed vault, uint256 newManagerFees);
    event UpdateTimeLockDurationScheduled(address indexed vault, uint256 newDuration);
    event TimelockDurationUpdated(address indexed vault, uint256 oldDuration, uint256 newDuration);

    error NotVaultManager();
    error IncorrectInput();
    error NotValidFactory();
    error NotEnoughLiquidity();
    error PoolNotFound(address poolAddress);
    error QueueAlreadySet(QueueType queueType);
    error Unauthorized();
    error ExecutionFailed();

    constructor(
        address _token,
        address _vaultManager,
        address _orderbookFactory,
        address _feeRecipient,
        uint256 _managerFees,
        address[] memory _proposers,
        address[] memory _executors,
        address _admin
    )
        Ownable(_admin)
        ERC4626(ERC20(_token))
        ERC20(
            string(abi.encodePacked("AvonVault ", ERC20(_token).name())),
            string(abi.encodePacked("av", ERC20(_token).symbol()))
        )
        TimelockController(DEFAULT_TIMELOCK_DURATION, _proposers, _executors, _admin)
    {
        ORDERBOOK_FACTORY = _orderbookFactory;
        if (_managerFees > MAX_MANAGER_FEES) revert IncorrectInput();
        managerFees = _managerFees;
        vaultManager = _vaultManager;
        feeRecipient = _feeRecipient;

        // Setup TimelockController roles
        _grantRole(PROPOSER_ROLE, address(this));
        _grantRole(EXECUTOR_ROLE, address(this));
        _grantRole(CANCELLER_ROLE, _admin);
    }

    modifier onlyVaultManagerORProposerRole() {
        if (msg.sender != vaultManager && !hasRole(PROPOSER_ROLE, msg.sender)) {
            revert NotVaultManager();
        }
        _;
    }

    /// @notice Schedule a vault manager change via timelock.
    /// @param _vaultManager Address of the new vault manager.
    function updateVaultManager(address _vaultManager) external onlyVaultManagerORProposerRole {
        if (_vaultManager == address(0)) revert IncorrectInput();

        bytes memory callData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            address(this),
            0,
            abi.encodeWithSelector(this._executeUpdateVaultManager.selector, _vaultManager),
            bytes32(0),
            bytes32(keccak256("UPDATE_VAULT_MANAGER")),
            getMinDelay()
        );

        (bool success,) = address(this).call(callData);
        if (!success) revert ExecutionFailed();

        emit VaultManagerUpdateScheduled(address(this), _vaultManager);
    }

    /// @notice Execute the timelocked vault manager change.
    /// @param _vaultManager Address of the new vault manager.
    function _executeUpdateVaultManager(address _vaultManager) external {
        if (msg.sender != address(this)) revert Unauthorized();
        if (_vaultManager == address(0)) revert IncorrectInput();

        address oldVaultManager = vaultManager;
        vaultManager = _vaultManager;

        emit VaultManagerChanged(oldVaultManager, _vaultManager);
    }

    /// @notice Schedule an update to vault manager fees via timelock.
    /// @dev Fees are charged on gains since the last accrual; capped by MAX_MANAGER_FEES.
    /// @param _managerFees New manager fee (WAD).
    function updateManagerFees(uint256 _managerFees) external onlyVaultManagerORProposerRole {
        if (_managerFees > MAX_MANAGER_FEES) revert IncorrectInput();

        bytes memory callData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            address(this),
            0,
            abi.encodeWithSelector(this._executeUpdateManagerFees.selector, _managerFees),
            bytes32(0),
            bytes32(keccak256("UPDATE_MANAGER_FEES")),
            getMinDelay()
        );

        (bool success,) = address(this).call(callData);
        if (!success) revert ExecutionFailed();

        emit ManagerFeeUpdateScheduled(address(this), _managerFees);
    }

    /// @notice Execute the timelocked update to vault manager fees.
    /// @param _managerFees New manager fee (WAD).
    function _executeUpdateManagerFees(uint256 _managerFees) external {
        if (msg.sender != address(this)) revert Unauthorized();
        if (_managerFees > MAX_MANAGER_FEES) revert IncorrectInput();

        _accrueInterest();
        managerFees = _managerFees;
        _updatePrevTotal();

        emit VaultFeesChanged(_managerFees);
    }

    /// @notice Update the fee recipient address.
    /// @param _feeRecipient New fee recipient.
    function updateFeeRecipient(address _feeRecipient) external onlyVaultManagerORProposerRole {
        if (_feeRecipient == address(0)) revert IncorrectInput();

        _accrueInterest();
        feeRecipient = _feeRecipient;
        _updatePrevTotal();

        emit FeeRecipientChanged(_feeRecipient);
    }

    /// @notice Schedule an update to the vault's timelock minimum delay.
    /// @param newDuration New delay in seconds.
    function updateTimeLockDuration(uint256 newDuration) external onlyVaultManagerORProposerRole {
        if (newDuration < MIN_TIMELOCK_DURATION || newDuration > MAX_TIMELOCK_DURATION) revert IncorrectInput();

        bytes memory callData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            address(this),
            0,
            abi.encodeWithSelector(this._executeUpdateTimelockDuration.selector, newDuration),
            bytes32(0),
            bytes32(keccak256("UPDATE_TIMELOCK_DURATION")),
            getMinDelay()
        );

        (bool success,) = address(this).call(callData);
        if (!success) revert ExecutionFailed();

        emit UpdateTimeLockDurationScheduled(address(this), newDuration);
    }

    /// @notice Execute the timelocked update to the vault's timelock minimum delay.
    /// @param newDuration New delay in seconds.
    function _executeUpdateTimelockDuration(uint256 newDuration) external {
        if (msg.sender != address(this)) revert Unauthorized();
        if (newDuration < MIN_TIMELOCK_DURATION || newDuration > MAX_TIMELOCK_DURATION) revert IncorrectInput();

        bytes memory callData = abi.encodeWithSelector(this.updateDelay.selector, newDuration);

        uint256 oldDuration = getMinDelay();

        (bool success,) = address(this).call(callData);
        if (!success) revert ExecutionFailed();

        emit TimelockDurationUpdated(address(this), oldDuration, newDuration);
    }

    /// @notice Set the initial priority queue for deposits or withdrawals.
    /// @dev Can be set once for each queue; use `resetQueue` to clear.
    /// @param _queuePriority Array of queue entries in priority order.
    /// @param _queueType Queue to set (Deposit or Withdraw).
    function setQueue(PriorityEntry[] memory _queuePriority, QueueType _queueType)
        external
        onlyVaultManagerORProposerRole
    {
        uint256 len = _queuePriority.length;
        if (len == 0) revert IncorrectInput();
        PriorityEntry[] storage queue = _queueType == QueueType.Deposit ? _queue.depositQueue : _queue.withdrawQueue;
        if (queue.length != 0) revert QueueAlreadySet(_queueType);
        for (uint256 i = 0; i < len; i++) {
            _validatePool(_queuePriority[i]);
            queue.push(_queuePriority[i]);
        }
        if (_queueType == QueueType.Deposit) {
            _queue.depositHead = 0;
        } else {
            _queue.withdrawHead = 0;
        }
    }

    /// @notice Append a new entry to a priority queue.
    /// @param newEntry Queue entry to add.
    /// @param _queueType Queue to modify (Deposit or Withdraw).
    function addQueueEntry(PriorityEntry memory newEntry, QueueType _queueType)
        external
        onlyVaultManagerORProposerRole
    {
        _validatePool(newEntry);
        (_queueType == QueueType.Deposit ? _queue.depositQueue : _queue.withdrawQueue).push(newEntry);
        emit QueueEntryAdded(newEntry, _queueType);
    }

    /// @notice Remove an entry at `index` from a priority queue.
    /// @param index Index to remove.
    /// @param _queueType Queue to modify (Deposit or Withdraw).
    function removeQueueEntry(uint256 index, QueueType _queueType) external onlyVaultManagerORProposerRole {
        PriorityEntry[] storage queue = _queueType == QueueType.Deposit ? _queue.depositQueue : _queue.withdrawQueue;
        uint256 lastIndex = queue.length - 1;
        if (queue.length == 0 || index >= queue.length) revert IncorrectInput();
        for (uint256 i = index; i < lastIndex; i++) {
            queue[i] = queue[i + 1];
        }
        queue.pop();

        if (_queueType == QueueType.Deposit) {
            if (_queue.depositHead > index) {
                _queue.depositHead--;
            }
            if (_queue.depositHead >= queue.length) {
                _queue.depositHead = 0;
            }
        } else {
            if (_queue.withdrawHead > index) {
                _queue.withdrawHead--;
            }
            if (_queue.withdrawHead >= queue.length) {
                _queue.withdrawHead = 0;
            }
        }
        emit QueueEntryRemoved(index, _queueType);
    }

    /// @notice Update the `totalAmount` of a queue entry.
    /// @param index Entry index in the queue.
    /// @param newAmount New total amount for the entry.
    /// @param _queueType Queue to modify (Deposit or Withdraw).
    function updateQueueEntry(uint256 index, uint256 newAmount, QueueType _queueType)
        external
        onlyVaultManagerORProposerRole
    {
        PriorityEntry[] storage queue = _queueType == QueueType.Deposit ? _queue.depositQueue : _queue.withdrawQueue;
        if (index >= queue.length) revert IncorrectInput();
        PriorityEntry storage e = queue[index];
        e.totalAmount = newAmount;
        if (e.remaining > newAmount) {
            e.remaining = newAmount;
        }
        emit QueueEntryUpdated(index, newAmount, _queueType);
    }

    /// @notice Clear and reset a priority queue.
    /// @param _queueType Queue to reset (Deposit or Withdraw).
    function resetQueue(QueueType _queueType) external onlyVaultManagerORProposerRole {
        if (_queueType == QueueType.Deposit) {
            delete _queue.depositQueue;
            _queue.depositHead = 0;
        } else {
            delete _queue.withdrawQueue;
            _queue.withdrawHead = 0;
        }
        emit QueueReset(_queueType);
    }

    /// @notice Deposit vault asset tokens and receive vault shares.
    /// @dev Allocates deposits to pools according to the deposit queue.
    /// @param assets Amount of assets to deposit.
    /// @param receiver Recipient of minted shares.
    /// @return shares Amount of shares minted to `receiver`.
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        _accrueInterest();
        shares = super.deposit(assets, receiver);
        _allocateDeposit(assets);
        _updatePrevTotal();
    }

    /// @notice Mint an exact number of vault shares by depositing the required assets.
    /// @dev Allocates deposits to pools according to the deposit queue.
    /// @param shares Number of shares to mint.
    /// @param receiver Recipient of minted shares.
    /// @return assets Amount of assets pulled from caller to mint `shares`.
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        _accrueInterest();
        assets = super.mint(shares, receiver);
        _allocateDeposit(assets);
        _updatePrevTotal();
    }

    /// @notice Withdraw an exact amount of assets by burning the necessary shares.
    /// @dev Sources liquidity according to the withdraw queue if idle balance is insufficient.
    /// @param assets Amount of assets to withdraw.
    /// @param receiver Recipient of withdrawn assets.
    /// @param owner Address whose shares are burned.
    /// @return shares Number of shares burned.
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        _accrueInterest();
        uint256 idle = ERC20(asset()).balanceOf(address(this));
        if (idle < assets) {
            _performWithdraw(assets - idle);
        }

        shares = super.withdraw(assets, receiver, owner);
        _updatePrevTotal();
    }

    /// @notice Redeem an exact number of shares for assets.
    /// @dev Sources liquidity according to the withdraw queue if idle balance is insufficient.
    /// @param shares Number of shares to redeem.
    /// @param receiver Recipient of redeemed assets.
    /// @param owner Address whose shares are redeemed.
    /// @return assets Amount of assets returned to `receiver`.
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        _accrueInterest();
        assets = previewRedeem(shares);

        uint256 idle = ERC20(asset()).balanceOf(address(this));
        if (idle < assets) {
            _performWithdraw(assets - idle);
        }

        assets = super.redeem(shares, receiver, owner);
        _updatePrevTotal();
    }

    /// @notice Deposit idle assets into pools using a one-off priority list.
    /// @dev Validates each pool via its factory; emits RelocatedLiquidity for each successful deposit.
    /// @param _queuePriority Priority list of destinations and amounts.
    function relocateLiquidity(PriorityEntry[] memory _queuePriority)
        external
        onlyVaultManagerORProposerRole
        nonReentrant
    {
        _accrueInterest();
        uint256 len = _queuePriority.length;
        for (uint256 i = 0; i < len; i++) {
            if (_queuePriority[i].totalAmount > availableLiquidity()) {
                _queuePriority[i].totalAmount = availableLiquidity();
            }
            _validatePool(_queuePriority[i]);
            ERC20(asset()).safeIncreaseAllowance(_queuePriority[i].pool, _queuePriority[i].totalAmount);
            uint256 shares = ERC4626(_queuePriority[i].pool).deposit(_queuePriority[i].totalAmount, address(this));
            ERC20(asset()).forceApprove(_queuePriority[i].pool, 0);
            if (poolShares[_queuePriority[i].pool] == 0) {
                _pools.add(_queuePriority[i].pool);
            }
            poolShares[_queuePriority[i].pool] += shares;
            emit RelocatedLiquidity(_queuePriority[i].pool, _queuePriority[i].totalAmount, shares);
            if (availableLiquidity() == 0) {
                break;
            }
        }
        _updatePrevTotal();
    }

    function removeLiquidity(PriorityEntry[] memory _queuePriority)
        external
        onlyVaultManagerORProposerRole
        nonReentrant
    {
        _accrueInterest();
        uint256 len = _queuePriority.length;
        for (uint256 i = 0; i < len; i++) {
            if (!poolExists(_queuePriority[i].pool)) revert PoolNotFound(_queuePriority[i].pool);
            if (_queuePriority[i].totalAmount > poolAssets(_queuePriority[i].pool)) revert NotEnoughLiquidity();
            _validatePool(_queuePriority[i]);
            uint256 shares = ERC4626(_queuePriority[i].pool).previewWithdraw(_queuePriority[i].totalAmount);
            if (poolShares[_queuePriority[i].pool] < shares) continue;

            try ERC4626(_queuePriority[i].pool).withdraw(_queuePriority[i].totalAmount, address(this), address(this))
            returns (uint256 _shares) {
                poolShares[_queuePriority[i].pool] -= _shares;
                if (poolShares[_queuePriority[i].pool] == 0) {
                    _pools.remove(_queuePriority[i].pool);
                }
                emit RemovedLiquidity(_queuePriority[i].pool, _queuePriority[i].totalAmount, _shares);
            } catch {
                // If withdrawal fails, skip this entry and continue with the next one
                continue;
            }
        }
        _updatePrevTotal();
    }

    /// @notice Accrue vault fees on gains since the last accrual and update the reference total.
    function accrueInterest() external {
        _accrueInterest();
        _updatePrevTotal();
    }

    /// @notice Total assets managed by the vault (idle + pooled).
    function totalAssets() public view override returns (uint256) {
        address[] memory pools = totalPools();
        uint256 assets = ERC20(asset()).balanceOf(address(this));
        uint256 len = pools.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 shares = poolShares[pools[i]];
            if (shares > 0) {
                assets += poolAssets(pools[i]);
            }
        }
        return assets;
    }

    /// @notice Idle asset balance held by the vault.
    function availableLiquidity() public view returns (uint256) {
        return ERC20(asset()).balanceOf(address(this));
    }

    /// @notice Best-effort estimate of assets that can be withdrawn across all pools at current conditions.
    function maxWithdrawableAssets() external view returns (uint256) {
        address[] memory pools = totalPools();
        uint256 assets = availableLiquidity();
        uint256 len = pools.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 availablePoolAssets = poolAssets(pools[i]);
            (PoolGetter.PoolData memory previewPool,,) = IPoolImplementation(pools[i]).getPoolData();
            uint256 poolAvailableLiquidity = previewPool.totalSupplyAssets - previewPool.totalBorrowAssets;
            if (poolAvailableLiquidity > availablePoolAssets) {
                assets += availablePoolAssets;
            } else {
                assets += poolAvailableLiquidity;
            }
        }
        return assets;
    }

    /// @notice Number of pools the vault currently has a non-zero share balance in.
    function poolCount() public view returns (uint256) {
        return _pools.length();
    }

    /// @notice Whether the vault currently tracks `poolAddress`.
    function poolExists(address poolAddress) public view returns (bool) {
        return _pools.contains(poolAddress);
    }

    /// @notice List of pools the vault currently tracks.
    function totalPools() public view returns (address[] memory) {
        return _pools.values();
    }

    /// @notice Preview the asset value of the vault's shares in a pool.
    /// @param poolAddress Pool to preview.
    function poolAssets(address poolAddress) public view returns (uint256) {
        return ERC4626(poolAddress).previewRedeem(poolShares[poolAddress]);
    }

    /// @notice Get a copy of the deposit or withdraw priority queue.
    /// @param _queueType Queue to read (Deposit or Withdraw).
    function getQueue(QueueType _queueType) external view returns (PriorityEntry[] memory) {
        return _queueType == QueueType.Deposit ? _queue.depositQueue : _queue.withdrawQueue;
    }

    function _validatePool(PriorityEntry memory entry) internal view {
        if (!IOrderbookFactory(ORDERBOOK_FACTORY).isPoolFactory(entry.poolFactory)) revert NotValidFactory();
        if (!IPoolFactory(entry.poolFactory).isValidPool(entry.pool)) revert PoolNotFound(entry.pool);
    }

    function _allocateDeposit(uint256 assets) internal {
        uint256 toAllocate = assets;
        uint256 steps;
        uint256 len = _queue.depositQueue.length;

        while (toAllocate > 0 && len > 0 && steps < MAX_QUEUE_PROCESSING) {
            PriorityEntry storage e = _queue.depositQueue[_queue.depositHead];
            // Resetting remaining if we wrapped around
            if (e.remaining == 0) {
                e.remaining = e.totalAmount;
            }

            uint256 delta = toAllocate < e.remaining ? toAllocate : e.remaining;
            // Deposit the assets into the pool
            ERC20(asset()).safeIncreaseAllowance(e.pool, delta);
            try ERC4626(e.pool).deposit(delta, address(this)) returns (uint256 shares) {
                ERC20(asset()).forceApprove(e.pool, 0);
                // Update the shares for the pool
                if (poolShares[e.pool] == 0) {
                    _pools.add(e.pool);
                }
                poolShares[e.pool] += shares;

                // Update the remaining amount
                e.remaining -= delta;
                toAllocate -= delta;
                // If the remaining amount is zero, move to the next entry in the queue
                if (e.remaining == 0) {
                    _queue.depositHead = uint128((_queue.depositHead + 1) % _queue.depositQueue.length);
                }

                emit RelocatedLiquidity(e.pool, delta, shares);
            } catch {
                // If deposit fails, skip this entry and move to the next one
                ERC20(asset()).forceApprove(e.pool, 0);
                e.remaining = 0;
                _queue.depositHead = uint128((_queue.depositHead + 1) % _queue.depositQueue.length);
            }

            steps++;
        }
    }

    function _performWithdraw(uint256 assets) internal {
        uint256 toWithdraw = assets;
        uint256 len = _queue.withdrawQueue.length;

        while (toWithdraw > 0 && len > 0) {
            PriorityEntry storage e = _queue.withdrawQueue[_queue.withdrawHead];
            // Resetting remaining if we wrapped around
            if (e.remaining == 0) {
                e.remaining = e.totalAmount;
            }

            uint256 delta = toWithdraw < e.remaining ? toWithdraw : e.remaining;
            (PoolGetter.PoolData memory previewPool,,) = IPoolImplementation(e.pool).getPoolData();
            // Check if the pool has enough assets to withdraw\
            uint256 poolAvailableLiquidity = previewPool.totalSupplyAssets - previewPool.totalBorrowAssets;
            delta = delta < poolAvailableLiquidity ? delta : poolAvailableLiquidity;
            // Withdraw the assets from the pool
            uint256 shares = ERC4626(e.pool).previewWithdraw(delta);
            if (poolShares[e.pool] < shares || poolAvailableLiquidity == 0) {
                e.remaining = 0;
                _queue.withdrawHead = uint128((_queue.withdrawHead + 1) % _queue.withdrawQueue.length);
                continue;
            }

            // Attempt the withdrawal, move to next pool if it fails
            try ERC4626(e.pool).withdraw(delta, address(this), address(this)) returns (uint256 _shares) {
                // Update the shares for the pool
                poolShares[e.pool] -= _shares;
                if (poolShares[e.pool] == 0) {
                    _pools.remove(e.pool);
                }

                // Update the remaining amount
                e.remaining -= delta;
                toWithdraw -= delta;

                // If the remaining amount is zero, move to the next entry in the queue
                if (e.remaining == 0) {
                    _queue.withdrawHead = uint128((_queue.withdrawHead + 1) % _queue.withdrawQueue.length);
                }

                emit RemovedLiquidity(e.pool, delta, _shares);
            } catch {
                // If withdrawal fails, skip this entry and move to the next one
                e.remaining = 0;
                _queue.withdrawHead = uint128((_queue.withdrawHead + 1) % _queue.withdrawQueue.length);
            }
        }
    }

    function _accrueInterest() internal {
        uint256 currentAssets = totalAssets();

        // Only calculate fees if this isn't the first accrual and there's a gain
        if (prevTotal > 0 && currentAssets > prevTotal) {
            // Calculate the gain (interest earned)
            uint256 gain = currentAssets - prevTotal;

            // Calculate manager's share of the gains
            uint256 managerFeesAmount = gain.mulDiv(managerFees, 1e18);

            if (managerFeesAmount > 0) {
                uint256 shares =
                    managerFeesAmount.mulDiv(totalSupply(), currentAssets - managerFeesAmount, Math.Rounding.Floor);
                if (shares > 0) {
                    _mint(feeRecipient, shares);
                    emit ManagerFeesAccrued(managerFeesAmount, shares);
                }
            }
        }
    }

    function _updatePrevTotal() internal {
        prevTotal = totalAssets();
        emit TotalAssetsUpdated(prevTotal);
    }
}
