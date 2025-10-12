// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

/// @title IAvonLiquidationCallback
/// @notice Interface that users willing to use `liquidate`'s callback must implement
interface IAvonLiquidationCallback {
    /// @notice Callback called when a liquidation occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param seizedAssets The amount of assets that was seized.
    /// @param repaidShares The amount of shares that was repaid.
    /// @param data Arbitrary data passed to the `liquidate` function.
    function onAvonLiquidation(uint256 seizedAssets, uint256 repaidShares, bytes calldata data) external;
}
