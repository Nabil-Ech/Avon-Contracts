// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PoolConstants} from "./utils/PoolConstants.sol";
import {PoolErrors} from "./utils/PoolErrors.sol";

library PoolStorage {
    bytes32 constant POOL_STORAGE_SLOT = keccak256("avon.pool.storage");
    bytes32 internal constant T_LIQUIDATION_BONUS_SLOT = keccak256("avon.pool.transient.liquidationBonus");

    struct PoolConfig {
        address loanToken;
        address collateralToken;
        address oracle;
        address irm;
        uint64 lltv;
    }

    struct PoolState {
        PoolConfig config;
        address orderBook;
        address poolManager;
        address orderBookFactory;
        uint64 managerFee;
        uint64 protocolFee;
        uint64 flashLoanFee;
        uint64 protocolFlashLoanFeePercentage;
        uint256 liquidationBonus;
        uint256 softRange;
        uint256 softSeizeCap;
        uint256 depositCap;
        uint256 borrowCap;
        uint256 totalSupplyAssets;
        uint256 totalSupplyShares;
        uint256 totalBorrowAssets;
        uint256 totalBorrowShares;
        uint256 lastUpdate;
        /// @notice Auction priority window size (0 = disabled, max 10bps)
        /// @dev When > 0, positions within the health score range of (1 − window, 1) can only be liquidated
        ///      by auction transactions. The window size is configurable from 0 to MAX_AUCTION_PRIORITY_WINDOW.
        uint256 auctionPriorityWindow;
        mapping(address => Position) positions;
        mapping(address => mapping(address => bool)) isPermitted;
    }

    struct Position {
        uint256 borrowShares;
        uint256 collateral;
        uint256 poolBorrowAssets;
        uint256 poolBorrowShares;
        uint256 updatedAt;
    }

    /// @notice One-time initializer for pool storage parameters.
    /// @dev Validates bounds on LTV, fees, liquidation params, caps, and priority window.
    /// @param cfg Pool configuration (tokens, oracle, IRM, LTV).
    /// @param manager Initial pool manager.
    /// @param orderbook Associated orderbook address.
    /// @param orderbookFactory Orderbook factory address.
    /// @param fee Manager fee (WAD), subject to MAX_TOTAL_FEE with protocol fee.
    /// @param liquidationBonus Base liquidation bonus (WAD).
    /// @param softRange Soft range width (WAD).
    /// @param softSeizeCap Soft range seize cap as fraction of collateral (WAD).
    /// @param auctionPriorityWindow Auction priority window size (WAD).
    /// @param depositCap Max deposits in asset units (0 = no cap).
    /// @param borrowCap Max borrows in asset units (0 = no cap).
    function initialize(
        PoolConfig memory cfg,
        address manager,
        address orderbook,
        address orderbookFactory,
        uint64 fee,
        uint256 liquidationBonus,
        uint256 softRange,
        uint256 softSeizeCap,
        uint256 auctionPriorityWindow,
        uint256 depositCap,
        uint256 borrowCap
    ) internal {
        // no check for oracle
        PoolState storage s = _state();
        if (cfg.lltv < PoolConstants.MIN_LTV || cfg.lltv > PoolConstants.MAX_LTV) revert PoolErrors.InvalidInput();
        if (fee + PoolConstants.DEFAULT_PROTOCOL_FEE > PoolConstants.MAX_TOTAL_FEE) revert PoolErrors.InvalidInput();
        if (liquidationBonus < PoolConstants.MIN_LIQ_BONUS || liquidationBonus > PoolConstants.MAX_SOFT_RANGE_LIQ_BONUS)
        {
            revert PoolErrors.InvalidInput();
        }
        if (softRange < PoolConstants.MIN_SOFT_RANGE || softRange > PoolConstants.MAX_SOFT_RANGE) {
            revert PoolErrors.InvalidInput();
        }
        if (softSeizeCap < PoolConstants.MIN_SOFT_SEIZE_CAP || softSeizeCap > PoolConstants.MAX_SOFT_SEIZE_CAP) {
            revert PoolErrors.InvalidInput();
        }
        if (auctionPriorityWindow > PoolConstants.MAX_AUCTION_PRIORITY_WINDOW) revert PoolErrors.InvalidInput();
        s.config = cfg;
        s.orderBook = orderbook;
        s.orderBookFactory = orderbookFactory;
        s.poolManager = manager;
        s.managerFee = fee;
        s.liquidationBonus = liquidationBonus;
        s.softRange = softRange;
        s.softSeizeCap = softSeizeCap;
        s.depositCap = depositCap;
        s.borrowCap = borrowCap;
        s.protocolFee = PoolConstants.DEFAULT_PROTOCOL_FEE;
        s.flashLoanFee = PoolConstants.DEFAULT_FLASH_LOAN_FEE;
        s.protocolFlashLoanFeePercentage = PoolConstants.PROTOCOL_FLASH_LOAN_FEE;
        s.auctionPriorityWindow = auctionPriorityWindow;
        s.lastUpdate = block.timestamp;
    }

    /// @notice Accessor to the dedicated pool storage slot.
    /// @return s The pool storage reference.
    function _state() internal pure returns (PoolState storage s) {
        bytes32 slot = POOL_STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /// @notice Retrieves the current transient liquidation bonus value for this transaction
    /// @dev Uses EIP-1153 TLOAD opcode to read from transient storage
    /// @return value The transient liquidation bonus (0 indicates to protocol to use default bonus)
    function getTransientLiquidationBonus() internal view returns (uint256 value) {
        bytes32 slot = T_LIQUIDATION_BONUS_SLOT;
        assembly {
            value := tload(slot)
        }
    }

    /// @notice Sets a transient liquidation bonus
    /// @dev Uses EIP-1153 TSTORE opcode to write to transient storage
    /// @dev This value will automatically reset to 0 at the end of the transaction
    /// @param value The liquidation bonus based on the auction bid
    function setTransientLiquidationBonus(uint256 value) internal {
        // Note: Validation happens at the external entry point (AvonPool)
        bytes32 slot = T_LIQUIDATION_BONUS_SLOT;
        assembly {
            tstore(slot, value)
        }
    }
}
