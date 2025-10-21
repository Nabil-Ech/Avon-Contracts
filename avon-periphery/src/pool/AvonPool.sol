// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IOrderbookFactory} from "../interface/IOrderbookFactory.sol";
import {IOrderbook} from "../interface/IOrderbook.sol";
import {CollateralManagement} from "./extensions/CollateralManagement.sol";
import {DepositWithdraw} from "./extensions/DepositWithdraw.sol";
import {AccrueInterest} from "./extensions/AccrueInterest.sol";
import {PositionGuard} from "./extensions/PositionGuard.sol";
import {UpdateOrders} from "./extensions/UpdateOrders.sol";
import {Liquidation} from "./extensions/Liquidation.sol";
import {BorrowRepay} from "./extensions/BorrowRepay.sol";
import {FlashLoan} from "./extensions/FlashLoan.sol";
import {PoolConstants} from "./utils/PoolConstants.sol";
import {PoolErrors} from "./utils/PoolErrors.sol";
import {PoolGetter} from "./utils/PoolGetter.sol";
import {PoolStorage} from "./PoolStorage.sol";
import {PoolEvents} from "./utils/PoolEvents.sol";
import {IIrm} from "../interface/IIrm.sol";
import {IPoolImplementation} from "../interface/IPoolImplementation.sol";
import {Utils} from "./extensions/Utils.sol";

contract AvonPool is ERC4626, Pausable, TimelockController, IPoolImplementation {
    using CollateralManagement for PoolStorage.PoolState;
    using DepositWithdraw for PoolStorage.PoolState;
    using AccrueInterest for PoolStorage.PoolState;
    using PositionGuard for PoolStorage.PoolState;
    using UpdateOrders for PoolStorage.PoolState;
    using Liquidation for PoolStorage.PoolState;
    using BorrowRepay for PoolStorage.PoolState;
    using PoolGetter for PoolStorage.PoolState;
    using FlashLoan for PoolStorage.PoolState;
    using Math for uint256;

    // This role should be granted to an auction contract.
    // The sole functionality this role has access to is transient liquidation bonus updates.
    bytes32 public constant AUCTION_ROLE = keccak256("AUCTION_ROLE");

    constructor(
        PoolStorage.PoolConfig memory _cfg,
        address _manager,
        address _orderBook,
        address _orderBookFactory,
        uint64 _fee,
        uint256 _liquidationBonus,
        uint256 _softRange,
        uint256 _softSeizeCap,
        uint256 _auctionPriorityWindow,
        uint256 _depositCap,
        uint256 _borrowCap,
        address[] memory _proposers,
        address[] memory _executors,
        address _admin
    )
        ERC4626(IERC20(_cfg.loanToken))
        ERC20(
            string(abi.encodePacked("Avon ", ERC20(_cfg.loanToken).name(), "/", ERC20(_cfg.collateralToken).name())),
            string(abi.encodePacked("a", ERC20(_cfg.loanToken).symbol(), "/", ERC20(_cfg.collateralToken).symbol()))
        )
        TimelockController(PoolConstants.DEFAULT_TIMELOCK_DURATION, _proposers, _executors, _admin)
    {
        PoolStorage.initialize(
            _cfg,
            _manager,
            _orderBook,
            _orderBookFactory,
            _fee,
            _liquidationBonus,
            _softRange,
            _softSeizeCap,
            _auctionPriorityWindow,
            _depositCap,
            _borrowCap
        );
        // granting role to the contract itself, why ?
        _grantRole(PROPOSER_ROLE, address(this));
        _grantRole(EXECUTOR_ROLE, address(this));
        _grantRole(CANCELLER_ROLE, _admin);

        // Pool contract (via PROPOSER_ROLE) manages AUCTION_ROLE
        // Pool manager can grant/revoke through wrapper functions
        _setRoleAdmin(AUCTION_ROLE, PROPOSER_ROLE);
    }
    
    modifier onlyPoolManagerORProposerRole() {
        if (msg.sender != PoolStorage._state().poolManager && !hasRole(PROPOSER_ROLE, msg.sender)) {
            revert PoolErrors.Unauthorized();
        }
        _;
    }

    /// @inheritdoc IPoolImplementation
    function deposit(uint256 assets, address receiver)
        public
        override(ERC4626, IPoolImplementation)
        whenNotPaused
        returns (uint256 shares)
    {
        PoolStorage.PoolState storage s = PoolStorage._state();
        accrueInterest(s);
        // Check deposit cap
        if (s.depositCap > 0 && s.totalSupplyAssets + assets > s.depositCap) {
            revert PoolErrors.DepositCapExceeded();
        }
        shares = super.deposit(assets, receiver);
        // at htis point exchange has happened
        if (shares == 0) revert PoolErrors.ZeroShares();
        s._deposit(assets, shares, receiver);
        s._updateOrders();
    }

    /// @inheritdoc IPoolImplementation
    function mint(uint256 shares, address receiver)
        public
        override(ERC4626, IPoolImplementation)
        whenNotPaused
        returns (uint256 assets)
    {
        PoolStorage.PoolState storage s = PoolStorage._state();
        accrueInterest(s);
        // Check deposit cap
        if (s.depositCap > 0 && s.totalSupplyAssets + assets > s.depositCap) {
            revert PoolErrors.DepositCapExceeded();
        }
        assets = super.mint(shares, receiver);
        s._mint(assets, shares, receiver);
        s._updateOrders();
    }

    /// @inheritdoc IPoolImplementation
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override(ERC4626, IPoolImplementation)
        whenNotPaused
        returns (uint256 shares)
    {
        PoolStorage.PoolState storage s = PoolStorage._state();
        accrueInterest(s);
        shares = super.withdraw(assets, receiver, owner);
        s._withdraw(assets, shares, receiver);
        s._updateOrders();
    }

    /// @inheritdoc IPoolImplementation
    function redeem(uint256 shares, address receiver, address owner)
        public
        override(ERC4626, IPoolImplementation)
        whenNotPaused
        returns (uint256 assets)
    {
        PoolStorage.PoolState storage s = PoolStorage._state();
        accrueInterest(s);
        assets = super.redeem(shares, receiver, owner);
        s._redeem(assets, shares, receiver);
        s._updateOrders();
    }

    /// @inheritdoc IPoolImplementation
    function borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, uint256 minAmountExpected)
        external
        whenNotPaused
        returns (uint256, uint256)
    {
        PoolStorage.PoolState storage s = PoolStorage._state();
        if (!Utils.exactlyOneZero(assets, shares)) revert PoolErrors.InvalidInput();
        accrueInterest(s);
        (assets, shares) = assets > 0
            ? s._borrow(assets, onBehalf, receiver, minAmountExpected)
            : s._borrowWithExactShares(shares, onBehalf, receiver, minAmountExpected);
        s._updateOrders();
        return (assets, shares);
    }

    /// @inheritdoc IPoolImplementation
    function repay(uint256 assets, uint256 shares, address onBehalf)
        external
        whenNotPaused
        returns (uint256, uint256)
    {
        PoolStorage.PoolState storage s = PoolStorage._state();
        accrueInterest(s);
        (assets, shares) = assets > 0 ? s._repay(assets, onBehalf) : s._repayWithExactShares(shares, onBehalf);
        s._updateOrders();
        return (assets, shares);
    }

    /// @inheritdoc IPoolImplementation
    function depositCollateral(uint256 assets, address onBehalf) external whenNotPaused {
        PoolStorage._state()._depositCollateral(assets, onBehalf);
    }

    /// @inheritdoc IPoolImplementation
    function withdrawCollateral(uint256 assets, address onBehalf, address receiver) external whenNotPaused {
        PoolStorage.PoolState storage s = PoolStorage._state();
        accrueInterest(s);
        s._withdrawCollateral(assets, onBehalf, receiver);
    }

    /// @inheritdoc IPoolImplementation
    function liquidate(
        address borrower,
        uint256 assets,
        uint256 shares,
        uint256 minSeizedAmount,
        uint256 maxRepaidAsset,
        bytes calldata data
    ) external whenNotPaused {
        PoolStorage.PoolState storage s = PoolStorage._state();
        accrueInterest(s);
        s._liquidate(borrower, assets, shares, minSeizedAmount, maxRepaidAsset, data);
        s._updateOrders();
    }

    /// @inheritdoc IPoolImplementation
    function flashLoan(address token, uint256 assets, bytes calldata data) external whenNotPaused {
        PoolStorage.PoolState storage s = PoolStorage._state();
        accrueInterest(s);
        s._flashLoan(token, assets, data);
        s._updateOrders();
    }

    /// @inheritdoc IPoolImplementation
    function setAuthorization(address authorized, bool isPermitted) external whenNotPaused {
        PoolStorage._state()._setPermission(authorized, isPermitted);
    }

    /// @inheritdoc IPoolImplementation
    function pausePool(bool pause) external {
        if (msg.sender != IOrderbook(PoolStorage._state().orderBook).owner()) revert PoolErrors.Unauthorized();
        PoolStorage.PoolState storage s = PoolStorage._state();
        if (pause) {
            _pause();
            accrueInterest(s);
            s._cancelOrders();
        } else {
            _unpause();
            s.lastUpdate = block.timestamp;
            s._updateOrders();
        }
    }

    /// @inheritdoc IPoolImplementation
    function updateOrderbook(address newOrderbook, address newOrderbookFactory)
        external
        onlyPoolManagerORProposerRole
    {
        if (newOrderbook == address(0) || newOrderbookFactory == address(0)) revert PoolErrors.InvalidInput();
        PoolStorage.PoolState storage s = PoolStorage._state();
        if (IOrderbook(s.orderBook).newOrderbook() != newOrderbook) revert PoolErrors.InvalidInput();
        if (IOrderbook(newOrderbook).ORDERBOOK_FACTORY() != newOrderbookFactory) revert PoolErrors.InvalidInput();

        bytes memory callData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            address(this),
            0,
            abi.encodeWithSelector(this._executeUpdateOrderbook.selector, newOrderbook, newOrderbookFactory),
            bytes32(0),
            bytes32(keccak256("UPDATE_ORDERBOOK")),
            getMinDelay()
        );

        (bool success,) = address(this).call(callData);
        if (!success) revert PoolErrors.ExecutionFailed();

        emit PoolEvents.OrderbookUpdateScheduled(address(this), newOrderbook, newOrderbookFactory);
    }

    // Internal function that will be called by the timelock
    /// @notice Execute the timelocked orderbook migration.
    /// @dev Cancels existing orders, updates storage, and re-inserts orders.
    /// @param newOrderbook Address of the new orderbook.
    /// @param newOrderbookFactory Address of the new orderbook's factory.
    function _executeUpdateOrderbook(address newOrderbook, address newOrderbookFactory) external {
        if (msg.sender != address(this)) revert PoolErrors.Unauthorized();

        if (newOrderbook == address(0) || newOrderbookFactory == address(0)) revert PoolErrors.InvalidInput();
        PoolStorage.PoolState storage s = PoolStorage._state();
        if (IOrderbook(s.orderBook).newOrderbook() != newOrderbook) revert PoolErrors.InvalidInput();
        if (IOrderbook(newOrderbook).ORDERBOOK_FACTORY() != newOrderbookFactory) revert PoolErrors.InvalidInput();
        address oldOrderbook = s.orderBook;
        address oldOrderbookFactory = s.orderBookFactory;

        accrueInterest(s);
        s._cancelOrders();
        s.orderBook = newOrderbook;
        s.orderBookFactory = newOrderbookFactory;
        s._updateOrders();

        emit PoolEvents.OrderbookUpdated(
            address(this), oldOrderbook, newOrderbook, oldOrderbookFactory, newOrderbookFactory
        );
    }

    // New function to change pool manager with timelock
    /// @inheritdoc IPoolImplementation
    function updatePoolManager(address newPoolManager) external onlyPoolManagerORProposerRole {
        if (newPoolManager == address(0)) revert PoolErrors.InvalidInput();

        bytes memory callData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            address(this),
            0,
            abi.encodeWithSelector(this._executeUpdatePoolManager.selector, newPoolManager),
            bytes32(0),
            bytes32(keccak256("UPDATE_POOL_MANAGER")),
            getMinDelay()
        );

        (bool success,) = address(this).call(callData);
        if (!success) revert PoolErrors.ExecutionFailed();

        emit PoolEvents.PoolManagerUpdateScheduled(address(this), newPoolManager);
    }

    // Internal function that will be called by the timelock
    /// @notice Execute the timelocked pool manager change.
    /// @param newPoolManager Address of the new pool manager.
    function _executeUpdatePoolManager(address newPoolManager) external {
        if (msg.sender != address(this)) revert PoolErrors.Unauthorized();
        if (newPoolManager == address(0)) revert PoolErrors.InvalidInput();

        PoolStorage.PoolState storage s = PoolStorage._state();
        accrueInterest(s);
        address oldPoolManager = s.poolManager;
        s.poolManager = newPoolManager;

        emit PoolEvents.PoolManagerUpdated(address(this), oldPoolManager, newPoolManager);
    }

    // New function to update manager fee with timelock
    /// @inheritdoc IPoolImplementation
    function updateManagerFee(uint64 newFee) external onlyPoolManagerORProposerRole {
        if (newFee + getProtocolFee() > PoolConstants.MAX_TOTAL_FEE) revert PoolErrors.InvalidInput();

        bytes memory callData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            address(this),
            0,
            abi.encodeWithSelector(this._executeUpdateManagerFee.selector, newFee),
            bytes32(0),
            bytes32(keccak256("UPDATE_MANAGER_FEE")),
            getMinDelay()
        );

        (bool success,) = address(this).call(callData);
        if (!success) revert PoolErrors.ExecutionFailed();

        emit PoolEvents.ManagerFeeUpdateScheduled(address(this), newFee);
    }

    // Internal function that will be called by the timelock
    /// @notice Execute the timelocked manager fee update.
    /// @param newFee New manager fee in WAD.
    function _executeUpdateManagerFee(uint64 newFee) external {
        if (msg.sender != address(this)) revert PoolErrors.Unauthorized();
        if (newFee + PoolStorage._state().protocolFee > PoolConstants.MAX_TOTAL_FEE) revert PoolErrors.InvalidInput();

        PoolStorage.PoolState storage s = PoolStorage._state();
        accrueInterest(s);
        uint64 oldFee = s.managerFee;
        s.managerFee = newFee;

        emit PoolEvents.ManagerFeeUpdated(address(this), oldFee, newFee);
    }

    /// @inheritdoc IPoolImplementation
    function updateProtocolFee(uint64 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFee + PoolStorage._state().managerFee > PoolConstants.MAX_TOTAL_FEE) revert PoolErrors.InvalidInput();

        bytes memory callData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            address(this),
            0,
            abi.encodeWithSelector(this._executeUpdateProtocolFee.selector, newFee),
            bytes32(0),
            bytes32(keccak256("UPDATE_PROTOCOL_FEE")),
            getMinDelay()
        );

        (bool success,) = address(this).call(callData);
        if (!success) revert PoolErrors.ExecutionFailed();
        emit PoolEvents.ProtocolFeeUpdateScheduled(address(this), newFee);
    }

    // Internal function that will be called by the timelock
    /// @notice Execute the timelocked protocol fee update.
    /// @param newFee New protocol fee in WAD.
    function _executeUpdateProtocolFee(uint64 newFee) external {
        if (msg.sender != address(this)) revert PoolErrors.Unauthorized();
        if (newFee + PoolStorage._state().managerFee > PoolConstants.MAX_TOTAL_FEE) revert PoolErrors.InvalidInput();

        PoolStorage.PoolState storage s = PoolStorage._state();
        accrueInterest(s);
        uint64 oldFee = s.protocolFee;
        s.protocolFee = newFee;

        emit PoolEvents.ProtocolFeeUpdated(address(this), oldFee, newFee);
    }

    /// @inheritdoc IPoolImplementation
    function updateTimeLockDuration(uint256 newDuration) external onlyPoolManagerORProposerRole {
        if (newDuration < PoolConstants.MIN_TIMELOCK_DURATION || newDuration > PoolConstants.MAX_TIMELOCK_DURATION) {
            revert PoolErrors.InvalidInput();
        }

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
        if (!success) revert PoolErrors.ExecutionFailed();
        emit PoolEvents.UpdateTimeLockDurationScheduled(address(this), newDuration);
    }

    /// @notice Execute the timelocked update to the pool timelock minimum delay.
    /// @param newDuration New timelock delay (seconds).
    function _executeUpdateTimelockDuration(uint256 newDuration) external {
        if (msg.sender != address(this)) revert PoolErrors.Unauthorized();
        if (newDuration < PoolConstants.MIN_TIMELOCK_DURATION || newDuration > PoolConstants.MAX_TIMELOCK_DURATION) {
            revert PoolErrors.InvalidInput();
        }

        bytes memory callData = abi.encodeWithSelector(this.updateDelay.selector, newDuration);

        uint256 oldDuration = getMinDelay();

        (bool success,) = address(this).call(callData);
        if (!success) revert PoolErrors.ExecutionFailed();

        emit PoolEvents.TimelockDurationUpdated(address(this), oldDuration, newDuration);
    }

    /// @inheritdoc IPoolImplementation
    function updateFlashLoanFee(uint64 newFee) external onlyPoolManagerORProposerRole {
        if (newFee > PoolConstants.MAX_FLASH_LOAN_FEE) revert PoolErrors.InvalidInput();

        bytes memory callData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            address(this),
            0,
            abi.encodeWithSelector(this._executeUpdateFlashLoanFee.selector, newFee),
            bytes32(0),
            bytes32(keccak256("UPDATE_FLASH_LOAN_FEE")),
            getMinDelay()
        );

        (bool success,) = address(this).call(callData);
        if (!success) revert PoolErrors.ExecutionFailed();

        emit PoolEvents.FlashLoanFeeUpdateScheduled(address(this), newFee);
    }

    // Internal function that will be called by the timelock
    /// @notice Execute the timelocked flash loan fee update.
    /// @param newFee New flash loan fee in WAD.
    function _executeUpdateFlashLoanFee(uint64 newFee) external {
        if (msg.sender != address(this)) revert PoolErrors.Unauthorized();
        if (newFee > PoolConstants.MAX_FLASH_LOAN_FEE) revert PoolErrors.InvalidInput();

        PoolStorage.PoolState storage s = PoolStorage._state();
        uint64 oldFee = s.flashLoanFee;
        s.flashLoanFee = newFee;

        emit PoolEvents.FlashLoanFeeUpdated(address(this), oldFee, newFee);
    }

    /// @inheritdoc IPoolImplementation
    function updateLiquidationBonus(uint256 newBonus) external onlyPoolManagerORProposerRole {
        if (newBonus < PoolConstants.MIN_LIQ_BONUS || newBonus > PoolConstants.MAX_SOFT_RANGE_LIQ_BONUS) {
            revert PoolErrors.InvalidInput();
        }

        bytes memory callData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            address(this),
            0,
            abi.encodeWithSelector(this._executeLiquidationBonus.selector, newBonus),
            bytes32(0),
            bytes32(keccak256("UPDATE_LIQUIDATION_BONUS")),
            getMinDelay()
        );

        (bool success,) = address(this).call(callData);
        if (!success) revert PoolErrors.ExecutionFailed();

        emit PoolEvents.LiquidationBonusUpdateScheduled(address(this), newBonus);
    }

    /// @notice Execute the timelocked base liquidation bonus update.
    /// @param newBonus New base liquidation bonus (WAD).
    function _executeLiquidationBonus(uint256 newBonus) external {
        if (msg.sender != address(this)) revert PoolErrors.Unauthorized();
        if (newBonus < PoolConstants.MIN_LIQ_BONUS || newBonus > PoolConstants.MAX_SOFT_RANGE_LIQ_BONUS) {
            revert PoolErrors.InvalidInput();
        }

        PoolStorage.PoolState storage s = PoolStorage._state();
        uint256 oldBonus = s.liquidationBonus;
        s.liquidationBonus = newBonus;

        emit PoolEvents.LiquidationBonusUpdated(address(this), oldBonus, newBonus);
    }

    /// @inheritdoc IPoolImplementation
    function updateTransientLiquidationBonus(uint256 newBonus) external onlyRole(AUCTION_ROLE) {
        PoolStorage.PoolState storage s = PoolStorage._state();

        uint256 oldBonus = PoolStorage.getTransientLiquidationBonus();
        // Transient bonus must be: 1) greater than 100% (WAD), 2) less than persistent bonus,
        // 3) greater than or equal to previous transient bonus to enforce ordering.
        if (newBonus <= PoolConstants.WAD || newBonus >= s.liquidationBonus || newBonus < oldBonus) {
            revert PoolErrors.InvalidInput();
        }

        PoolStorage.setTransientLiquidationBonus(newBonus);

        emit PoolEvents.TransientLiquidationBonusSet(address(this), msg.sender, oldBonus, newBonus);
    }

    /// @inheritdoc IPoolImplementation
    function updateSoftRange(uint256 newSoftRange) external onlyPoolManagerORProposerRole {
        if (newSoftRange < PoolConstants.MIN_SOFT_RANGE || newSoftRange > PoolConstants.MAX_SOFT_RANGE) {
            revert PoolErrors.InvalidInput();
        }

        bytes memory callData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            address(this),
            0,
            abi.encodeWithSelector(this._executeUpdateSoftRange.selector, newSoftRange),
            bytes32(0),
            bytes32(keccak256("UPDATE_SOFT_RANGE")),
            getMinDelay()
        );

        (bool success,) = address(this).call(callData);
        if (!success) revert PoolErrors.ExecutionFailed();

        emit PoolEvents.SoftRangeUpdateScheduled(address(this), newSoftRange);
    }

    /// @notice Execute the timelocked soft range update.
    /// @param newSoftRange New soft range width (WAD).
    function _executeUpdateSoftRange(uint256 newSoftRange) external {
        if (msg.sender != address(this)) revert PoolErrors.Unauthorized();
        if (newSoftRange < PoolConstants.MIN_SOFT_RANGE || newSoftRange > PoolConstants.MAX_SOFT_RANGE) {
            revert PoolErrors.InvalidInput();
        }

        PoolStorage.PoolState storage s = PoolStorage._state();
        uint256 oldSoftRange = s.softRange;
        s.softRange = newSoftRange;

        emit PoolEvents.SoftRangeUpdated(address(this), oldSoftRange, newSoftRange);
    }

    /// @inheritdoc IPoolImplementation
    function updateSeizeCap(uint256 newSeizeCap) external onlyPoolManagerORProposerRole {
        if (newSeizeCap < PoolConstants.MIN_SOFT_SEIZE_CAP || newSeizeCap > PoolConstants.MAX_SOFT_SEIZE_CAP) {
            revert PoolErrors.InvalidInput();
        }

        bytes memory callData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            address(this),
            0,
            abi.encodeWithSelector(this._executeUpdateSeizeCap.selector, newSeizeCap),
            bytes32(0),
            bytes32(keccak256("UPDATE_SOFT_SEIZE_CAP")),
            getMinDelay()
        );

        (bool success,) = address(this).call(callData);
        if (!success) revert PoolErrors.ExecutionFailed();

        emit PoolEvents.SoftSeizeCapUpdateScheduled(address(this), newSeizeCap);
    }

    /// @notice Execute the timelocked soft-range seize cap update.
    /// @param newSeizeCap New seize cap as a fraction of collateral (WAD).
    function _executeUpdateSeizeCap(uint256 newSeizeCap) external {
        if (msg.sender != address(this)) revert PoolErrors.Unauthorized();
        if (newSeizeCap < PoolConstants.MIN_SOFT_SEIZE_CAP || newSeizeCap > PoolConstants.MAX_SOFT_SEIZE_CAP) {
            revert PoolErrors.InvalidInput();
        }

        PoolStorage.PoolState storage s = PoolStorage._state();
        uint256 oldSeizeCap = s.softSeizeCap;
        s.softSeizeCap = newSeizeCap;

        emit PoolEvents.SoftSeizeCapUpdated(address(this), oldSeizeCap, newSeizeCap);
    }

    /// @inheritdoc IPoolImplementation
    function updateFlashLoanProtocolFeePercentage(uint64 newPercentage) external onlyPoolManagerORProposerRole {
        if (newPercentage > PoolConstants.MAX_PROTOCOL_FLASH_LOAN_FEE) revert PoolErrors.InvalidInput();

        bytes memory callData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            address(this),
            0,
            abi.encodeWithSelector(this._executeUpdateFlashLoanProtocolFeePercentage.selector, newPercentage),
            bytes32(0),
            bytes32(keccak256("UPDATE_FLASH_LOAN_PROTOCOL_FEE_PERCENTAGE")),
            getMinDelay()
        );

        (bool success,) = address(this).call(callData);
        if (!success) revert PoolErrors.ExecutionFailed();

        emit PoolEvents.FlashLoanProtocolFeePercentageUpdateScheduled(address(this), newPercentage);
    }

    // Internal function that will be called by the timelock
    /// @notice Execute the timelocked update to the protocol share of flash loan fees.
    /// @param newPercentage New protocol fee percentage (WAD) of flash loan fee.
    function _executeUpdateFlashLoanProtocolFeePercentage(uint64 newPercentage) external {
        if (msg.sender != address(this)) revert PoolErrors.Unauthorized();
        if (newPercentage > PoolConstants.MAX_PROTOCOL_FLASH_LOAN_FEE) revert PoolErrors.InvalidInput();

        PoolStorage.PoolState storage s = PoolStorage._state();
        uint64 oldPercentage = s.protocolFlashLoanFeePercentage;
        s.protocolFlashLoanFeePercentage = newPercentage;

        emit PoolEvents.FlashLoanProtocolFeePercentageUpdated(address(this), oldPercentage, newPercentage);
    }

    /// @inheritdoc IPoolImplementation
    function updateLLTVUpward(uint64 newLTV) external onlyPoolManagerORProposerRole {
        if (newLTV < PoolConstants.MIN_LTV || newLTV > PoolConstants.MAX_LTV) revert PoolErrors.InvalidInput();
        if (newLTV <= PoolStorage._state().config.lltv) revert PoolErrors.InvalidInput();

        bytes memory callData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            address(this),
            0,
            abi.encodeWithSelector(this._executeLLTVUpward.selector, newLTV),
            bytes32(0),
            bytes32(keccak256("INCREASE_LTV")),
            getMinDelay()
        );

        (bool success,) = address(this).call(callData);
        if (!success) revert PoolErrors.ExecutionFailed();

        emit PoolEvents.UpwardLLTVUpdateScheduled(address(this), newLTV);
    }

    /// @notice Execute the timelocked upward LTV update.
    /// @param newLTV New LTV (WAD), must be greater than current LTV and within bounds.
    function _executeLLTVUpward(uint64 newLTV) external {
        if (msg.sender != address(this)) revert PoolErrors.Unauthorized();
        if (newLTV < PoolConstants.MIN_LTV || newLTV > PoolConstants.MAX_LTV) revert PoolErrors.InvalidInput();
        if (newLTV <= PoolStorage._state().config.lltv) revert PoolErrors.InvalidInput();

        PoolStorage.PoolState storage s = PoolStorage._state();
        uint64 oldLTV = s.config.lltv;
        s._cancelOrders();
        s.config.lltv = newLTV;
        s._updateOrders();

        emit PoolEvents.UpwardLLTVUpdated(address(this), oldLTV, newLTV);
    }

    /// @notice Schedule an update to the deposit cap via timelock.
    /// @param newDepositCap New maximum deposit amount in loan token units (0 = no cap).
    /// @inheritdoc IPoolImplementation
    function updateDepositCap(uint256 newDepositCap) external onlyPoolManagerORProposerRole {
        bytes memory callData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            address(this),
            0,
            abi.encodeWithSelector(this._executeUpdateDepositCap.selector, newDepositCap),
            bytes32(0),
            bytes32(keccak256("UPDATE_DEPOSIT_CAP")),
            getMinDelay()
        );

        (bool success,) = address(this).call(callData);
        if (!success) revert PoolErrors.ExecutionFailed();

        emit PoolEvents.DepositCapUpdateScheduled(address(this), newDepositCap);
    }

    /// @notice Execute the timelocked deposit cap update.
    /// @param newDepositCap New maximum deposit amount in loan token units (0 = no cap).
    function _executeUpdateDepositCap(uint256 newDepositCap) external {
        if (msg.sender != address(this)) revert PoolErrors.Unauthorized();

        PoolStorage.PoolState storage s = PoolStorage._state();
        uint256 oldDepositCap = s.depositCap;
        s.depositCap = newDepositCap;

        emit PoolEvents.DepositCapUpdated(address(this), oldDepositCap, newDepositCap);
    }

    /// @notice Schedule an update to the borrow cap via timelock.
    /// @param newBorrowCap New maximum borrow amount in loan token units (0 = no cap).
    /// @inheritdoc IPoolImplementation
    function updateBorrowCap(uint256 newBorrowCap) external onlyPoolManagerORProposerRole {
        bytes memory callData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            address(this),
            0,
            abi.encodeWithSelector(this._executeUpdateBorrowCap.selector, newBorrowCap),
            bytes32(0),
            bytes32(keccak256("UPDATE_BORROW_CAP")),
            getMinDelay()
        );

        (bool success,) = address(this).call(callData);
        if (!success) revert PoolErrors.ExecutionFailed();

        emit PoolEvents.BorrowCapUpdateScheduled(address(this), newBorrowCap);
    }

    /// @notice Execute the timelocked borrow cap update.
    /// @param newBorrowCap New maximum borrow amount in loan token units (0 = no cap).
    function _executeUpdateBorrowCap(uint256 newBorrowCap) external {
        if (msg.sender != address(this)) revert PoolErrors.Unauthorized();

        PoolStorage.PoolState storage s = PoolStorage._state();
        uint256 oldBorrowCap = s.borrowCap;
        s.borrowCap = newBorrowCap;

        emit PoolEvents.BorrowCapUpdated(address(this), oldBorrowCap, newBorrowCap);
    }

    /// @inheritdoc IPoolImplementation
    function configureAuctionPriorityWindow(uint256 window) external onlyPoolManagerORProposerRole {
        if (window > PoolConstants.MAX_AUCTION_PRIORITY_WINDOW) revert PoolErrors.InvalidInput();

        PoolStorage.PoolState storage s = PoolStorage._state();
        if (s.auctionPriorityWindow == window) revert PoolErrors.AlreadySet();

        uint256 oldWindow = s.auctionPriorityWindow;
        s.auctionPriorityWindow = window;

        emit PoolEvents.AuctionPriorityWindowUpdated(address(this), msg.sender, oldWindow, window);
    }

    /// @inheritdoc IPoolImplementation
    function grantAuctionRole(address account) external onlyPoolManagerORProposerRole {
        if (account == address(0)) revert PoolErrors.InvalidInput();
        _grantRole(AUCTION_ROLE, account);
        emit PoolEvents.AuctionRoleGranted(address(this), msg.sender, account);
    }

    /// @inheritdoc IPoolImplementation
    function revokeAuctionRole(address account) external onlyPoolManagerORProposerRole {
        if (account == address(0)) revert PoolErrors.InvalidInput();
        _revokeRole(AUCTION_ROLE, account);
        emit PoolEvents.AuctionRoleRevoked(address(this), msg.sender, account);
    }

    /// @inheritdoc IPoolImplementation
    function accrueInterest() external {
        PoolStorage.PoolState storage s = PoolStorage._state();
        if (block.timestamp < s.lastUpdate + PoolConstants.ACCRUAL_INTERVAL) {
            revert PoolErrors.NotEnoughTimePassed();
        }
        accrueInterest(s);
    }

    /// @inheritdoc IPoolImplementation
    function getPoolConfig() external view returns (PoolStorage.PoolConfig memory poolConfig) {
        return PoolStorage._state().config;
    }

    /// @inheritdoc IPoolImplementation
    function getOrderbook() external view returns (address) {
        return PoolStorage._state().orderBook;
    }

    /// @inheritdoc IPoolImplementation
    function getOrderbookFactory() external view returns (address) {
        return PoolStorage._state().orderBookFactory;
    }

    /// @inheritdoc IPoolImplementation
    function getPoolManager() external view returns (address) {
        return PoolStorage._state().poolManager;
    }

    function getPoolData() external view returns (PoolGetter.PoolData memory previewPool, uint256 ir, uint256 ltv) {
        return PoolStorage._state().getPoolData();
    }

    /// @inheritdoc IPoolImplementation
    function getPosition(address account) external view returns (PoolGetter.BorrowPosition memory currentPosition) {
        return PoolStorage._state().getPosition(account);
    }

    /// @inheritdoc IPoolImplementation
    function getAuctionPriorityWindow() external view returns (uint256) {
        return PoolStorage._state().getAuctionPriorityWindow();
    }

    /// @inheritdoc IPoolImplementation
    function getTransientLiquidationBonus() external view returns (uint256) {
        return PoolStorage.getTransientLiquidationBonus();
    }

    /// @inheritdoc IPoolImplementation
    function getIRM() external view returns (address) {
        return PoolStorage._state().config.irm;
    }

    /// @inheritdoc IPoolImplementation
    function getLTV() external view returns (uint256) {
        return PoolStorage._state().config.lltv;
    }

    /// @inheritdoc IPoolImplementation
    function isAuthorized(address account, address authorized) external view returns (bool) {
        return PoolStorage._state().isPermitted[account][authorized];
    }

    /// @inheritdoc IPoolImplementation
    function getProtocolFee() public view returns (uint64) {
        return PoolStorage._state().protocolFee;
    }

    /// @inheritdoc IPoolImplementation
    function getManagerFee() public view returns (uint64) {
        return PoolStorage._state().managerFee;
    }

    /// @inheritdoc IPoolImplementation
    function getFlashLoanFee() public view returns (uint64) {
        return PoolStorage._state().flashLoanFee;
    }

    /// @inheritdoc IPoolImplementation
    function getFlashLoanProtocolFeePercentage() public view returns (uint64) {
        return PoolStorage._state().protocolFlashLoanFeePercentage;
    }

    /// @inheritdoc IPoolImplementation
    function getDepositCap() public view returns (uint256) {
        return PoolStorage._state().depositCap;
    }

    /// @inheritdoc IPoolImplementation
    function getBorrowCap() public view returns (uint256) {
        return PoolStorage._state().borrowCap;
    }

    /// @inheritdoc IPoolImplementation
    function previewBorrow(address borrower, uint256 assets, uint256 collateralBuffer)
        external
        view
        returns (uint256 collateralAmount)
    {
        return PoolStorage._state().borrow(borrower, assets, collateralBuffer);
    }

    /// @inheritdoc IPoolImplementation
    function previewBorrowWithExactCollateral(address borrower, uint256 collateralAmount, uint256 collateralBuffer)
        external
        view
        returns (uint256 borrowAmount)
    {
        return PoolStorage._state().previewBorrowWithExactCollateral(borrower, collateralAmount, collateralBuffer);
    }

    /// @inheritdoc IPoolImplementation
    function previewRedeem(uint256 shares) public view override(ERC4626, IPoolImplementation) returns (uint256) {
        PoolStorage.PoolState storage s = PoolStorage._state();
        (PoolGetter.PoolData memory previewPool) = s._previewAccrueInterest();
        return shares.mulDiv(
            previewPool.totalSupplyAssets + 1,
            previewPool.totalSupplyShares + 10 ** _decimalsOffset(),
            Math.Rounding.Floor
        );
    }

    /// @inheritdoc IPoolImplementation
    function previewWithdraw(uint256 assets) public view override(ERC4626, IPoolImplementation) returns (uint256) {
        PoolStorage.PoolState storage s = PoolStorage._state();
        (PoolGetter.PoolData memory previewPool) = s._previewAccrueInterest();
        return assets.mulDiv(
            previewPool.totalSupplyShares + 10 ** _decimalsOffset(),
            previewPool.totalSupplyAssets + 1,
            Math.Rounding.Ceil
        );
    }

    /// @inheritdoc IPoolImplementation
    function totalAssets() public view override(ERC4626, IPoolImplementation) returns (uint256) {
        PoolStorage.PoolState storage s = PoolStorage._state();
        (PoolGetter.PoolData memory previewPool) = s._previewAccrueInterest();
        return previewPool.totalSupplyAssets;
    }

    function accrueInterest(PoolStorage.PoolState storage s) internal {
        if (s.lastUpdate == 0) revert PoolErrors.InvalidInput();
        (uint256 managerFeeShares, uint256 protocolFeeShares) = s._accrueInterest();
        if (managerFeeShares > 0) {
            _mint(s.poolManager, managerFeeShares);
        }
        if (protocolFeeShares > 0) {
            _mint(IOrderbookFactory(s.orderBookFactory).feeRecipient(), protocolFeeShares);
        }
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256) {
        PoolStorage.PoolState storage s = PoolStorage._state();
        return assets.mulDiv(s.totalSupplyShares + 10 ** _decimalsOffset(), s.totalSupplyAssets + 1, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256) {
        PoolStorage.PoolState storage s = PoolStorage._state();
        return shares.mulDiv(s.totalSupplyAssets + 1, s.totalSupplyShares + 10 ** _decimalsOffset(), rounding);
    }

    // Gives pool state for future utility
    /// @notice Return a snapshot of key pool state and the current borrow rate.
    function getPoolState()
        public
        view
        returns (
            PoolStorage.PoolConfig memory config,
            address orderBook,
            address poolManager,
            address orderBookFactory,
            uint64 managerFee,
            uint64 protocolFee,
            uint64 flashLoanFee,
            uint256 rate,
            uint256 totalSupplyAssets,
            uint256 totalSupplyShares,
            uint256 totalBorrowAssets,
            uint256 totalBorrowShares,
            uint256 lastUpdate
        )
    {
        PoolStorage.PoolState storage s = PoolStorage._state();
        rate = IIrm(s.config.irm).computeBorrowRate(s.totalSupplyAssets, s.totalBorrowAssets);

        return (
            s.config,
            s.orderBook,
            s.poolManager,
            s.orderBookFactory,
            s.managerFee,
            s.protocolFee,
            s.flashLoanFee,
            rate,
            s.totalSupplyAssets,
            s.totalSupplyShares,
            s.totalBorrowAssets,
            s.totalBorrowShares,
            s.lastUpdate
        );
    }
}
