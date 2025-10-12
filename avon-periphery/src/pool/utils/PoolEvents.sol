// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/// @title Events
/// @author Avon Labs
/// @notice Library exposing events.
library PoolEvents {
    /// @notice Emitted on supply of assets.
    /// @dev Warning: `feeRecipient` receives some shares during interest accrual without any supply event emitted.
    /// @param poolAddress The Pool address.
    /// @param caller The caller.
    /// @param receiver The address that received the minted shares.
    /// @param assets The amount of assets supplied.
    /// @param shares The amount of shares minted.
    event Deposit(
        address indexed poolAddress, address indexed caller, address indexed receiver, uint256 assets, uint256 shares
    );

    /// @notice Emitted on withdrawal of assets.
    /// @param poolAddress The Pool address.
    /// @param caller The caller.
    /// @param receiver The address that received the withdrawn assets.
    /// @param assets The amount of assets withdrawn.
    /// @param shares The amount of shares burned.
    event Withdraw(
        address indexed poolAddress, address caller, address indexed receiver, uint256 assets, uint256 shares
    );

    /// @notice Emitted on borrow of assets.
    /// @param poolAddress The Pool address.
    /// @param caller The caller.
    /// @param onBehalf The owner of the modified position.
    /// @param receiver The address that received the borrowed assets.
    /// @param assets The amount of assets borrowed.
    /// @param shares The amount of shares minted.
    event Borrow(
        address indexed poolAddress,
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );

    /// @notice Emitted on repayment of assets.
    /// @param poolAddress The Pool address.
    /// @param caller The caller.
    /// @param onBehalf The owner of the modified position.
    /// @param assets The amount of assets repaid. May be 1 over the corresponding Pool's `totalBorrowAssets`.
    /// @param shares The amount of shares burned.
    event Repay(
        address indexed poolAddress, address indexed caller, address indexed onBehalf, uint256 assets, uint256 shares
    );

    /// @notice Emitted on supply of collateral.
    /// @param poolAddress The Pool address.
    /// @param caller The caller.
    /// @param onBehalf The owner of the modified position.
    /// @param assets The amount of collateral supplied.
    event DepositCollateral(
        address indexed poolAddress, address indexed caller, address indexed onBehalf, uint256 assets
    );

    /// @notice Emitted on withdrawal of collateral.
    /// @param poolAddress The Pool address.
    /// @param caller The caller.
    /// @param onBehalf The owner of the modified position.
    /// @param receiver The address that received the withdrawn collateral.
    /// @param assets The amount of collateral withdrawn.
    event WithdrawCollateral(
        address indexed poolAddress, address caller, address indexed onBehalf, address indexed receiver, uint256 assets
    );

    /// @notice Emitted on liquidation of a position.
    /// @param poolAddress The Pool address.
    /// @param caller The caller.
    /// @param borrower The borrower of the position.
    /// @param repaidAssets The amount of assets repaid. May be 1 over the corresponding Pool's `totalBorrowAssets`.
    /// @param repaidShares The amount of shares burned.
    /// @param seizedAssets The amount of collateral seized.
    /// @param badDebtAssets The amount of assets of bad debt realized.
    /// @param badDebtShares The amount of borrow shares of bad debt realized.
    event Liquidate(
        address indexed poolAddress,
        address indexed caller,
        address indexed borrower,
        uint256 repaidAssets,
        uint256 repaidShares,
        uint256 seizedAssets,
        uint256 badDebtAssets,
        uint256 badDebtShares
    );

    /// @notice Emitted on flash loan.
    /// @param caller The caller.
    /// @param token The token that was flash loaned.
    /// @param assets The amount that was flash loaned.
    event FlashLoan(address indexed caller, address indexed token, uint256 assets);

    /// @notice Emitted when setting an Permission.
    /// @param caller The caller.
    /// @param authorizer The authorizer address.
    /// @param authorized The authorized address.
    /// @param newIsPermitted The new Permission status.
    event SetPermission(
        address indexed caller, address indexed authorizer, address indexed authorized, bool newIsPermitted
    );

    /// @notice Emitted when accruing interest.
    /// @param poolAddress The Pool address.
    /// @param prevBorrowRate The previous borrow rate.
    /// @param interest The amount of interest accrued.
    /// @param feeShares The amount of shares minted as fee.
    event AccrueInterest(address indexed poolAddress, uint256 prevBorrowRate, uint256 interest, uint256 feeShares);

    /// @notice Emitted when orderbook update proposal is scheduled
    /// @param poolAddress The Pool address
    /// @param newOrderbook The new orderbook address
    /// @param newOrderbookFactory The new orderbook factory address
    event OrderbookUpdateScheduled(address indexed poolAddress, address newOrderbook, address newOrderbookFactory);

    /// @notice Emitted when orderbook is updated
    /// @param poolAddress The Pool address
    /// @param oldOrderbook The previous orderbook address
    /// @param newOrderbook The new orderbook address
    /// @param oldOrderbookFactory The previous orderbook factory address
    /// @param newOrderbookFactory The new orderbook factory address
    event OrderbookUpdated(
        address indexed poolAddress,
        address oldOrderbook,
        address newOrderbook,
        address oldOrderbookFactory,
        address newOrderbookFactory
    );

    /// @notice Emitted when pool manager update proposal is scheduled
    /// @param poolAddress The Pool address
    /// @param newPoolManager The new pool manager address
    event PoolManagerUpdateScheduled(address indexed poolAddress, address newPoolManager);

    /// @notice Emitted when pool manager is updated
    /// @param poolAddress The Pool address
    /// @param oldPoolManager The previous pool manager address
    /// @param newPoolManager The new pool manager address
    event PoolManagerUpdated(address indexed poolAddress, address oldPoolManager, address newPoolManager);

    /// @notice Emitted when manager fee update proposal is scheduled
    /// @param poolAddress The Pool address
    /// @param newFee The new manager fee
    event ManagerFeeUpdateScheduled(address indexed poolAddress, uint64 newFee);

    /// @notice Emitted when manager fee is updated
    /// @param poolAddress The Pool address
    /// @param oldFee The previous manager fee
    /// @param newFee The new manager fee
    event ManagerFeeUpdated(address indexed poolAddress, uint64 oldFee, uint64 newFee);

    /// @notice Emitted when LLTV is increased
    /// @param poolAddress The Pool address
    /// @param newLLTV The new LLTV value
    event UpwardLLTVUpdateScheduled(address indexed poolAddress, uint64 newLLTV);

    event UpwardLLTVUpdated(address indexed poolAddress, uint64 oldLLTV, uint64 newLLTV);

    /// @notice Emitted when protocol fee update proposal is scheduled
    /// @param poolAddress The Pool address
    /// @param newFee The new protocol fee
    event ProtocolFeeUpdateScheduled(address indexed poolAddress, uint64 newFee);

    /// @notice Emitted when protocol fee is updated
    /// @param poolAddress The Pool address
    /// @param oldFee The previous protocol fee
    /// @param newFee The new protocol fee
    event ProtocolFeeUpdated(address indexed poolAddress, uint64 oldFee, uint64 newFee);

    /// @notice Emitted when timelock duration update proposal is scheduled
    /// @param poolAddress The Pool address
    /// @param newDuration The new timelock duration
    event UpdateTimeLockDurationScheduled(address indexed poolAddress, uint256 newDuration);

    event TimelockDurationUpdated(address indexed poolAddress, uint256 oldDuration, uint256 newDuration);

    /// @notice Emitted when flash loan fee update proposal is scheduled
    /// @param poolAddress The Pool address
    /// @param newFee The new flash loan fee
    event FlashLoanFeeUpdateScheduled(address indexed poolAddress, uint64 newFee);

    /// @notice Emitted when flash loan fee is updated
    /// @param poolAddress The Pool address
    /// @param oldFee The previous flash loan fee
    /// @param newFee The new flash loan fee
    event FlashLoanFeeUpdated(address indexed poolAddress, uint64 oldFee, uint64 newFee);

    /// @notice Emitted when liquidation bonus update proposal is scheduled
    /// @param poolAddress The Pool address
    /// @param newBonus The new liquidation bonus
    event LiquidationBonusUpdateScheduled(address indexed poolAddress, uint256 newBonus);

    /// @notice Emitted when liquidation bonus is updated
    /// @param poolAddress The Pool address
    /// @param oldBonus The previous liquidation bonus
    /// @param newBonus The new liquidation bonus
    event LiquidationBonusUpdated(address indexed poolAddress, uint256 oldBonus, uint256 newBonus);

    /// @notice Emitted when a per-transaction liquidation bonus is set via transient storage
    /// @dev This bonus will automatically reset to 0 at the end of the transaction (EIP-1153)
    /// @param pool The Pool address where the bonus is applied
    /// @param operator The address that set the transient bonus (msg.sender)
    /// @param oldBonus The previous transient liquidation bonus (0 if not previously set in this tx)
    /// @param newBonus The new transient liquidation bonus
    event TransientLiquidationBonusSet(
        address indexed pool, address indexed operator, uint256 oldBonus, uint256 newBonus
    );

    /// @notice Emitted when soft range update proposal is scheduled
    /// @param poolAddress The Pool address
    /// @param newSoftRange The new soft range
    event SoftRangeUpdateScheduled(address indexed poolAddress, uint256 newSoftRange);

    /// @notice Emitted when soft range is updated
    /// @param poolAddress The Pool address
    /// @param oldSoftRange The previous soft range
    /// @param newSoftRange The new soft range
    event SoftRangeUpdated(address indexed poolAddress, uint256 oldSoftRange, uint256 newSoftRange);

    /// @notice Emitted when soft seize cap update proposal is scheduled
    /// @param poolAddress The Pool address
    /// @param newSoftSeizeCap The new soft seize cap
    event SoftSeizeCapUpdateScheduled(address indexed poolAddress, uint256 newSoftSeizeCap);

    /// @notice Emitted when soft seize cap is updated
    /// @param poolAddress The Pool address
    /// @param oldSoftSeizeCap The previous soft seize cap
    /// @param newSoftSeizeCap The new soft seize cap
    event SoftSeizeCapUpdated(address indexed poolAddress, uint256 oldSoftSeizeCap, uint256 newSoftSeizeCap);

    /// @notice Emitted when flash loan protocol fee percentage update proposal is scheduled
    /// @param poolAddress The Pool address
    /// @param newPercentage The new flash loan protocol fee percentage
    event FlashLoanProtocolFeePercentageUpdateScheduled(address indexed poolAddress, uint64 newPercentage);

    /// @notice Emitted when flash loan protocol fee percentage is updated
    /// @param poolAddress The Pool address
    /// @param oldPercentage The previous flash loan protocol fee percentage
    /// @param newPercentage The new flash loan protocol fee percentage
    event FlashLoanProtocolFeePercentageUpdated(
        address indexed poolAddress, uint64 oldPercentage, uint64 newPercentage
    );

    /// @notice Emitted when auction priority window size is updated
    /// @param pool The Pool address (emitter)
    /// @param operator The msg.sender that performed the update
    /// @param oldWindow Previous window size in WAD (0 = disabled)
    /// @param newWindow New window size in WAD (0 = disabled, bounded by MAX_AUCTION_PRIORITY_WINDOW)
    event AuctionPriorityWindowUpdated(
        address indexed pool, address indexed operator, uint256 oldWindow, uint256 newWindow
    );

    /// @notice Emitted when AUCTION_ROLE is granted to an account
    /// @param pool The pool where the role was granted
    /// @param operator The address that initiated the grant
    /// @param account The address that received AUCTION_ROLE
    event AuctionRoleGranted(address indexed pool, address indexed operator, address indexed account);

    /// @notice Emitted when AUCTION_ROLE is revoked from an account
    /// @param pool The pool where the role was revoked
    /// @param operator The address that initiated the revocation
    /// @param account The address that lost AUCTION_ROLE
    event AuctionRoleRevoked(address indexed pool, address indexed operator, address indexed account);

    /// @notice Emitted when deposit cap update proposal is scheduled
    /// @param poolAddress The Pool address
    /// @param newDepositCap The new deposit cap
    event DepositCapUpdateScheduled(address indexed poolAddress, uint256 newDepositCap);

    /// @notice Emitted when deposit cap is updated
    /// @param poolAddress The Pool address
    /// @param oldDepositCap The previous deposit cap
    /// @param newDepositCap The new deposit cap
    event DepositCapUpdated(address indexed poolAddress, uint256 oldDepositCap, uint256 newDepositCap);

    /// @notice Emitted when borrow cap update proposal is scheduled
    /// @param poolAddress The Pool address
    /// @param newBorrowCap The new borrow cap
    event BorrowCapUpdateScheduled(address indexed poolAddress, uint256 newBorrowCap);

    /// @notice Emitted when borrow cap is updated
    /// @param poolAddress The Pool address
    /// @param oldBorrowCap The previous borrow cap
    /// @param newBorrowCap The new borrow cap
    event BorrowCapUpdated(address indexed poolAddress, uint256 oldBorrowCap, uint256 newBorrowCap);
}
