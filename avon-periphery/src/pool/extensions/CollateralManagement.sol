// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PositionGuard} from "./PositionGuard.sol";
import {PoolStorage} from "../PoolStorage.sol";
import {PoolErrors} from "../utils/PoolErrors.sol";
import {PoolEvents} from "../utils/PoolEvents.sol";

library CollateralManagement {
    using PositionGuard for PoolStorage.PoolState;

    /// @notice Increase collateral for a position.
    /// @param s Pool storage state.
    /// @param assets Amount of collateral token to deposit.
    /// @param onBehalf Position owner whose collateral increases.
    function _depositCollateral(PoolStorage.PoolState storage s, uint256 assets, address onBehalf) internal {
        if (assets == 0) revert PoolErrors.ZeroAssets();
        if (onBehalf == address(0)) revert PoolErrors.ZeroAddress();

        s.positions[onBehalf].collateral += assets;

        SafeERC20.safeTransferFrom(ERC20(s.config.collateralToken), msg.sender, address(this), assets);

        emit PoolEvents.DepositCollateral(address(this), msg.sender, onBehalf, assets);
    }

    /// @notice Withdraw collateral from a position, ensuring the position remains safe.
    /// @param s Pool storage state.
    /// @param assets Amount of collateral token to withdraw.
    /// @param onBehalf Position owner whose collateral decreases.
    /// @param receiver Recipient of withdrawn collateral.
    function _withdrawCollateral(PoolStorage.PoolState storage s, uint256 assets, address onBehalf, address receiver)
        internal
    {
        if (assets == 0) revert PoolErrors.ZeroAssets();
        if (receiver == address(0)) revert PoolErrors.ZeroAddress();
        if (!s._isSenderPermitted(onBehalf)) revert PoolErrors.Unauthorized();

        s.positions[onBehalf].collateral -= assets;

        if (!s._isPositionSafe(onBehalf)) revert PoolErrors.InsufficientCollateral();

        SafeERC20.safeTransfer(ERC20(s.config.collateralToken), receiver, assets);

        emit PoolEvents.WithdrawCollateral(address(this), msg.sender, onBehalf, receiver, assets);
    }
}
