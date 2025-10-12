// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {PoolStorage} from "../pool/PoolStorage.sol";
import {PoolGetter} from "../pool/utils/PoolGetter.sol";

interface IPoolImplementation {
    /// @notice Deposit loan assets and receive pool shares.
    /// @param assets Amount of loan token to deposit.
    /// @param receiver Address to receive minted shares.
    /// @return shares Amount of shares minted to `receiver`.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @notice Mint an exact number of shares by depositing the required assets.
    /// @param shares Number of shares to mint.
    /// @param receiver Recipient of minted shares.
    /// @return assets Amount of assets pulled from caller to mint `shares`.
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    /// @notice Withdraw an exact amount of assets by burning the necessary shares.
    /// @param assets Amount of assets to withdraw.
    /// @param receiver Recipient of withdrawn assets.
    /// @param owner Address whose shares are burned.
    /// @return shares Amount of shares burned from `owner`.
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /// @notice Redeem an exact number of shares for assets.
    /// @param shares Amount of shares to redeem.
    /// @param receiver Recipient of redeemed assets.
    /// @param owner Address whose shares are redeemed.
    /// @return assets Amount of assets returned to `receiver`.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /// @notice Borrow against collateral; specify either `assets` or `shares` (exactly one must be zero).
    /// @param assets Desired borrow amount in loan token (set 0 to specify `shares`).
    /// @param shares Desired borrow amount in borrow shares (set 0 to specify `assets`).
    /// @param onBehalf Borrower address whose position increases.
    /// @param receiver Recipient of borrowed assets.
    /// @param minAmountExpected Minimum assets expected to be transferred to `receiver`.
    /// @return assets Actual borrowed assets.
    /// @return shares Actual borrow shares minted.
    function borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, uint256 minAmountExpected)
        external
        returns (uint256, uint256);

    /// @notice Repay debt; specify either `assets` or `shares` (exactly one must be zero).
    /// @param assets Repayment amount in assets (set 0 to specify `shares`).
    /// @param shares Repayment amount in borrow shares (set 0 to specify `assets`).
    /// @param onBehalf Borrower address whose debt is repaid.
    /// @return assets Actual assets paid.
    /// @return shares Actual borrow shares burned.
    function repay(uint256 assets, uint256 shares, address onBehalf) external returns (uint256, uint256);

    /// @notice Deposit collateral into a borrow position.
    /// @param assets Amount of collateral token to deposit.
    /// @param onBehalf Position owner to credit.
    function depositCollateral(uint256 assets, address onBehalf) external;

    /// @notice Withdraw collateral from a borrow position.
    /// @param assets Amount of collateral to withdraw.
    /// @param onBehalf Position owner to debit.
    /// @param receiver Recipient of collateral tokens.
    function withdrawCollateral(uint256 assets, address onBehalf, address receiver) external;

    /// @notice Liquidate an unhealthy position.
    /// @param borrower Address whose position is liquidated.
    /// @param assets Seized collateral amount (set 0 to specify `shares`).
    /// @param shares Repaid borrow shares (set 0 to specify `assets`).
    /// @param minSeizedAmount Minimum collateral amount the liquidator must receive.
    /// @param maxRepaidAsset Maximum loan assets the liquidator is willing to repay.
    /// @param data Optional data for `IAvonLiquidationCallback.onAvonLiquidation`.
    function liquidate(
        address borrower,
        uint256 assets,
        uint256 shares,
        uint256 minSeizedAmount,
        uint256 maxRepaidAsset,
        bytes calldata data
    ) external;

    /// @notice Perform a flash loan of the pool's loan token with a callback.
    /// @param token Token to borrow (must equal the pool loan token).
    /// @param assets Amount of tokens to borrow.
    /// @param data Calldata forwarded to `onAvonFlashLoan` on the borrower.
    function flashLoan(address token, uint256 assets, bytes calldata data) external;

    /// @notice Grant or revoke permission for `authorized` to act on behalf of `msg.sender`.
    /// @param authorized Address to grant or revoke.
    /// @param isPermitted True to grant permission, false to revoke.
    function setAuthorization(address authorized, bool isPermitted) external;

    /// @notice Pause or unpause pool operations.
    /// @param pause True to pause, false to unpause.
    function pausePool(bool pause) external;

    /// @notice Schedule migration to a new orderbook via timelock.
    /// @param newOrderbook Address of the new orderbook.
    /// @param newOrderbookFactory Address of the factory that created the new orderbook.
    function updateOrderbook(address newOrderbook, address newOrderbookFactory) external;

    /// @notice Set a transient liquidation bonus for this transaction based on auction results.
    /// @param newBonus New transient bonus (WAD) applied for this transaction only.
    function updateTransientLiquidationBonus(uint256 newBonus) external;

    /// @notice Configure the auction priority window size (WAD) for interest-triggered liquidations.
    /// @param window Priority window size (0 to disable, max 10bps WAD).
    function configureAuctionPriorityWindow(uint256 window) external;

    /// @notice Grant AUCTION_ROLE to an address.
    /// @param account The address to grant AUCTION_ROLE to.
    function grantAuctionRole(address account) external;

    /// @notice Revoke AUCTION_ROLE from an address.
    /// @param account The address to revoke AUCTION_ROLE from.
    function revokeAuctionRole(address account) external;

    /// @notice Schedule a pool manager change via timelock.
    /// @param newPoolManager Address of the new pool manager.
    function updatePoolManager(address newPoolManager) external;

    /// @notice Schedule an update to the pool manager fee via timelock.
    /// @param newFee New manager fee in WAD.
    function updateManagerFee(uint64 newFee) external;

    /// @notice Schedule an update to the protocol fee via timelock.
    /// @param newFee New protocol fee in WAD.
    function updateProtocolFee(uint64 newFee) external;

    /// @notice Schedule an update to the pool timelock minimum delay.
    /// @param newDuration New timelock delay (seconds).
    function updateTimeLockDuration(uint256 newDuration) external;

    /// @notice Schedule an update to the pool flash loan fee via timelock.
    /// @param newFee New flash loan fee in WAD.
    function updateFlashLoanFee(uint64 newFee) external;

    /// @notice Schedule an update to the base liquidation bonus via timelock.
    /// @param newBonus New base liquidation bonus (WAD), within configured bounds.
    function updateLiquidationBonus(uint256 newBonus) external;

    /// @notice Schedule an update to the soft liquidation range via timelock.
    /// @param newSoftRange New soft range width (WAD).
    function updateSoftRange(uint256 newSoftRange) external;

    /// @notice Schedule an update to the soft-range seize cap via timelock.
    /// @param newSeizeCap New seize cap as a fraction of collateral (WAD).
    function updateSeizeCap(uint256 newSeizeCap) external;

    /// @notice Schedule an update to the protocol share of flash loan fees via timelock.
    /// @param newPercentage New protocol fee percentage (WAD) of flash loan fee.
    function updateFlashLoanProtocolFeePercentage(uint64 newPercentage) external;

    /// @notice Schedule an upward-only update to the loan-to-value (LTV) parameter via timelock.
    /// @param newLTV New LTV (WAD), must be greater than current LTV and within bounds.
    function updateLLTVUpward(uint64 newLTV) external;

    /// @notice Schedule an update to the deposit cap via timelock.
    /// @param newDepositCap New maximum deposit amount in loan token units (0 = no cap).
    function updateDepositCap(uint256 newDepositCap) external;

    /// @notice Schedule an update to the borrow cap via timelock.
    /// @param newBorrowCap New maximum borrow amount in loan token units (0 = no cap).
    function updateBorrowCap(uint256 newBorrowCap) external;

    /// @notice Accrue interest up to the current block, minting manager and protocol fee shares.
    function accrueInterest() external;

    /// @notice Return the immutable pool configuration.
    function getPoolConfig() external view returns (PoolStorage.PoolConfig memory poolConfig);

    /// @notice Return the current orderbook address.
    function getOrderbook() external view returns (address);

    /// @notice Return the orderbook factory address.
    function getOrderbookFactory() external view returns (address);

    /// @notice Return the pool manager address.
    function getPoolManager() external view returns (address);

    /// @notice Return projected pool data, current borrow rate, and LTV.
    function getPoolData() external view returns (PoolGetter.PoolData memory previewPool, uint256 ir, uint256 ltv);

    /// @notice Return the current borrow position for `account` (projected with interest).
    function getPosition(address account) external view returns (PoolGetter.BorrowPosition memory currentPosition);

    /// @notice Return the address of the interest rate model (IRM).
    function getIRM() external view returns (address);

    /// @notice Return the current LTV parameter (WAD).
    function getLTV() external view returns (uint256);

    /// @notice Return the configured auction priority window size (WAD).
    function getAuctionPriorityWindow() external view returns (uint256);

    /// @notice Return the current transient liquidation bonus (WAD) for this transaction.
    function getTransientLiquidationBonus() external view returns (uint256);

    /// @notice Check if `authorized` can act on behalf of `account`.
    function isAuthorized(address account, address authorized) external view returns (bool);

    /// @notice Return the protocol fee (WAD).
    function getProtocolFee() external view returns (uint64);

    /// @notice Return the manager fee (WAD).
    function getManagerFee() external view returns (uint64);

    /// @notice Return the flash loan fee (WAD).
    function getFlashLoanFee() external view returns (uint64);

    /// @notice Return the protocol share percentage (WAD) of the flash loan fee.
    function getFlashLoanProtocolFeePercentage() external view returns (uint64);

    /// @notice Return the current deposit cap (0 = no cap).
    function getDepositCap() external view returns (uint256);

    /// @notice Return the current borrow cap (0 = no cap).
    function getBorrowCap() external view returns (uint256);

    /// @notice Preview the required collateral to borrow `assets`, given a `collateralBuffer`.
    /// @param borrower Borrower address (ignored for preview).
    /// @param assets Desired borrow amount in assets.
    /// @param collateralBuffer Extra buffer over LTV in WAD (e.g., 0.05e18 for 5%).
    /// @return collateralAmount Required collateral amount.
    function previewBorrow(address borrower, uint256 assets, uint256 collateralBuffer)
        external
        view
        returns (uint256 collateralAmount);

    /// @notice Preview the borrowable amount for a given `collateralAmount`, given a `collateralBuffer`.
    /// @param borrower Borrower address (ignored for preview).
    /// @param collateralAmount Amount of collateral to post.
    /// @param collateralBuffer Extra buffer over LTV in WAD.
    /// @return borrowAmount Maximum borrowable amount in assets.
    function previewBorrowWithExactCollateral(address borrower, uint256 collateralAmount, uint256 collateralBuffer)
        external
        view
        returns (uint256 borrowAmount);

    /// @notice Preview assets received by redeeming `shares`.
    function previewRedeem(uint256 shares) external view returns (uint256);

    /// @notice Preview shares required to withdraw `assets`.
    function previewWithdraw(uint256 assets) external view returns (uint256);

    /// @notice Total assets managed by the pool (projected with interest).
    function totalAssets() external view returns (uint256);
}
