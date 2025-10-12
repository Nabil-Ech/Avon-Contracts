// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {PoolErrors} from "../utils/PoolErrors.sol";
import {PoolEvents} from "../utils/PoolEvents.sol";
import {PoolStorage} from "../PoolStorage.sol";

library DepositWithdraw {
    /// @notice Internal accounting for deposit flow after ERC4626 mint.
    /// @dev Increases pool totals and emits Deposit event.
    /// @param s Pool storage state.
    /// @param assets Amount of assets deposited.
    /// @param shares Shares minted to the receiver by ERC4626.
    /// @param receiver Recipient of the shares.
    function _deposit(PoolStorage.PoolState storage s, uint256 assets, uint256 shares, address receiver) internal {
        if (assets == 0) revert PoolErrors.ZeroAssets();

        s.totalSupplyAssets += assets;
        s.totalSupplyShares += shares;

        emit PoolEvents.Deposit(address(this), msg.sender, receiver, assets, shares);
    }

    /// @notice Internal accounting for mint flow after ERC4626 mint.
    /// @dev Increases pool totals and emits Deposit event.
    /// @param s Pool storage state.
    /// @param assets Assets pulled by ERC4626 to mint `shares`.
    /// @param shares Shares minted to the receiver by ERC4626.
    /// @param receiver Recipient of the shares.
    function _mint(PoolStorage.PoolState storage s, uint256 assets, uint256 shares, address receiver) internal {
        if (shares == 0) revert PoolErrors.ZeroShares();

        s.totalSupplyAssets += assets;
        s.totalSupplyShares += shares;

        emit PoolEvents.Deposit(address(this), msg.sender, receiver, assets, shares);
    }

    /// @notice Internal accounting for withdraw flow after ERC4626 burn.
    /// @dev Checks liquidity, decreases pool totals, and emits Withdraw event.
    /// @param s Pool storage state.
    /// @param assets Amount of assets withdrawn.
    /// @param shares Shares burned from the owner by ERC4626.
    /// @param receiver Recipient of the assets.
    function _withdraw(PoolStorage.PoolState storage s, uint256 assets, uint256 shares, address receiver) internal {
        if (assets == 0) revert PoolErrors.ZeroAssets();
        if (receiver == address(0)) revert PoolErrors.ZeroAddress();

        uint256 newSupplyAssets = s.totalSupplyAssets - assets;
        if (s.totalBorrowAssets > newSupplyAssets) revert PoolErrors.InsufficientLiquidity();

        s.totalSupplyAssets = newSupplyAssets;
        s.totalSupplyShares -= shares;

        emit PoolEvents.Withdraw(address(this), msg.sender, receiver, assets, shares);
    }

    /// @notice Internal accounting for redeem flow after ERC4626 burn.
    /// @dev Checks liquidity, decreases pool totals, and emits Withdraw event.
    /// @param s Pool storage state.
    /// @param assets Assets returned for `shares`.
    /// @param shares Shares burned from the owner by ERC4626.
    /// @param receiver Recipient of the assets.
    function _redeem(PoolStorage.PoolState storage s, uint256 assets, uint256 shares, address receiver) internal {
        if (shares == 0) revert PoolErrors.ZeroShares();
        if (receiver == address(0)) revert PoolErrors.ZeroAddress();

        uint256 newSupplyAssets = s.totalSupplyAssets - assets;
        /* 
        in case of a bad debt
        
        */
        if (s.totalBorrowAssets > newSupplyAssets) revert PoolErrors.InsufficientLiquidity();

        s.totalSupplyAssets = newSupplyAssets;
        s.totalSupplyShares -= shares;

        emit PoolEvents.Withdraw(address(this), msg.sender, receiver, assets, shares);
    }
}
