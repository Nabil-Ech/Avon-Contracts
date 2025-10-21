// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SharesLib} from "../../libraries/SharesLib.sol";
import {PositionGuard} from "./PositionGuard.sol";
import {PoolStorage} from "../PoolStorage.sol";
import {PoolErrors} from "../utils/PoolErrors.sol";
import {PoolEvents} from "../utils/PoolEvents.sol";

library BorrowRepay {
    using PositionGuard for PoolStorage.PoolState;
    using SharesLib for uint256;

    /// @notice Increase a borrow position by `assets`, transferring assets to `receiver`.
    /// @dev Updates pool and position accounting; enforces borrow cap, safety and liquidity.
    /// @param s Pool storage state.
    /// @param assets Assets to borrow.
    /// @param onBehalf Position owner whose borrow increases.
    /// @param receiver Recipient of borrowed assets.
    /// @param minAmountExpected Minimum assets expected to be transferred.
    /// @return Amounts The tuple (assets, shares) actually borrowed.
    function _borrow(
        PoolStorage.PoolState storage s,
        uint256 assets,
        address onBehalf,
        address receiver,
        uint256 minAmountExpected
    ) internal returns (uint256, uint256) {
        if (receiver == address(0)) revert PoolErrors.ZeroAddress();
        if (!s._isSenderPermitted(onBehalf)) revert PoolErrors.Unauthorized();
        // it should not be checked her 
        // Check borrow cap
        if (s.borrowCap > 0 && s.totalBorrowAssets + assets > s.borrowCap) {
            revert PoolErrors.BorrowCapExceeded();
        }

        uint256 shares = assets.toSharesUp(s.totalBorrowAssets, s.totalBorrowShares);

        s.positions[onBehalf].borrowShares += shares;
        s.totalBorrowShares += shares;
        s.totalBorrowAssets += assets;
        s.positions[onBehalf].poolBorrowAssets = s.totalBorrowAssets;
        s.positions[onBehalf].poolBorrowShares = s.totalBorrowShares;
        s.positions[onBehalf].updatedAt = s.lastUpdate;

        if (!s._isPositionSafe(onBehalf)) revert PoolErrors.InsufficientCollateral();
        if (s.totalBorrowAssets > s.totalSupplyAssets) revert PoolErrors.InsufficientLiquidity();
        if (assets < minAmountExpected) revert PoolErrors.InsufficientAmountReceived();

        SafeERC20.safeTransfer(ERC20(s.config.loanToken), receiver, assets);

        emit PoolEvents.Borrow(address(this), msg.sender, onBehalf, receiver, assets, shares);

        return (assets, shares);
    }

    /// @notice Increase a borrow position by an exact `shares` amount, transferring assets to `receiver`.
    /// @dev Computes assets from shares and applies the same checks as `_borrow`.
    /// @param s Pool storage state.
    /// @param shares Borrow shares to add.
    /// @param onBehalf Position owner whose borrow increases.
    /// @param receiver Recipient of borrowed assets.
    /// @param minAmountExpected Minimum assets expected to be transferred.
    /// @return Amounts The tuple (assets, shares) actually borrowed.
    function _borrowWithExactShares(
        PoolStorage.PoolState storage s,
        uint256 shares,
        address onBehalf,
        address receiver,
        uint256 minAmountExpected
    ) internal returns (uint256, uint256) {
        if (shares == 0) revert PoolErrors.InvalidInput();
        if (receiver == address(0)) revert PoolErrors.ZeroAddress();
        if (!s._isSenderPermitted(onBehalf)) revert PoolErrors.Unauthorized();

        uint256 assets = shares.toAssetsDown(s.totalBorrowAssets, s.totalBorrowShares);
        if (assets == 0) revert PoolErrors.InvalidInput();

        // Check borrow cap
        if (s.borrowCap > 0 && s.totalBorrowAssets + assets > s.borrowCap) {
            revert PoolErrors.BorrowCapExceeded();
        }

        s.positions[onBehalf].borrowShares += shares;
        s.totalBorrowShares += shares;
        s.totalBorrowAssets += assets;
        s.positions[onBehalf].poolBorrowAssets = s.totalBorrowAssets;
        s.positions[onBehalf].poolBorrowShares = s.totalBorrowShares;
        s.positions[onBehalf].updatedAt = s.lastUpdate;

        if (!s._isPositionSafe(onBehalf)) revert PoolErrors.InsufficientCollateral();
        if (s.totalBorrowAssets > s.totalSupplyAssets) revert PoolErrors.InsufficientLiquidity();
        if (assets < minAmountExpected) revert PoolErrors.InsufficientAmountReceived();

        SafeERC20.safeTransfer(ERC20(s.config.loanToken), receiver, assets);

        emit PoolEvents.Borrow(address(this), msg.sender, onBehalf, receiver, assets, shares);

        return (assets, shares);
    }

    /// @notice Repay debt with `assets`, burning the corresponding borrow shares.
    /// @dev If `assets` exceeds debt, clamps to full repayment.
    /// @param s Pool storage state.
    /// @param assets Repayment amount in assets.
    /// @param onBehalf Position owner whose debt is repaid.
    /// @return Amounts The tuple (assets, shares) actually repaid.
    function _repay(PoolStorage.PoolState storage s, uint256 assets, address onBehalf)
        internal
        returns (uint256, uint256)
    {
        if (onBehalf == address(0)) revert PoolErrors.ZeroAddress();

        uint256 shares = assets.toSharesDown(s.totalBorrowAssets, s.totalBorrowShares);

        if (shares > s.positions[onBehalf].borrowShares) {
            shares = s.positions[onBehalf].borrowShares;
            assets = shares.toAssetsUp(s.totalBorrowAssets, s.totalBorrowShares);
        }

        s.positions[onBehalf].borrowShares -= shares;
        s.totalBorrowShares -= shares;
        s.totalBorrowAssets = s.totalBorrowAssets > assets ? s.totalBorrowAssets - assets : 0;
        s.positions[onBehalf].poolBorrowAssets = s.totalBorrowAssets;
        s.positions[onBehalf].poolBorrowShares = s.totalBorrowShares;
        s.positions[onBehalf].updatedAt = s.lastUpdate;

        SafeERC20.safeTransferFrom(ERC20(s.config.loanToken), msg.sender, address(this), assets);

        emit PoolEvents.Repay(address(this), msg.sender, onBehalf, assets, shares);

        return (assets, shares);
    }

    /// @notice Repay an exact amount of borrow `shares`.
    /// @dev Computes assets from shares and clamps to remaining debt.
    /// @param s Pool storage state.
    /// @param shares Repayment amount in borrow shares.
    /// @param onBehalf Position owner whose debt is repaid.
    /// @return Amounts The tuple (assets, shares) actually repaid.
    function _repayWithExactShares(PoolStorage.PoolState storage s, uint256 shares, address onBehalf)
        internal
        returns (uint256, uint256)
    {
        if (onBehalf == address(0)) revert PoolErrors.ZeroAddress();

        uint256 assets = shares.toAssetsUp(s.totalBorrowAssets, s.totalBorrowShares);

        if (shares > s.positions[onBehalf].borrowShares) {
            shares = s.positions[onBehalf].borrowShares;
            assets = shares.toAssetsUp(s.totalBorrowAssets, s.totalBorrowShares);
        }

        s.positions[onBehalf].borrowShares -= shares;
        s.totalBorrowShares -= shares;
        s.totalBorrowAssets = s.totalBorrowAssets > assets ? s.totalBorrowAssets - assets : 0;
        s.positions[onBehalf].poolBorrowAssets = s.totalBorrowAssets;
        s.positions[onBehalf].poolBorrowShares = s.totalBorrowShares;
        s.positions[onBehalf].updatedAt = s.lastUpdate;

        SafeERC20.safeTransferFrom(ERC20(s.config.loanToken), msg.sender, address(this), assets);

        emit PoolEvents.Repay(address(this), msg.sender, onBehalf, assets, shares);

        return (assets, shares);
    }
}
