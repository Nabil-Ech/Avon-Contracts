// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

/// @title IAvonFlashLoanCallback
/// @notice Interface that users willing to use `flashLoan`'s callback must implement.
interface IAvonFlashLoanCallback {
    /// @notice Callback called when a flash loan occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param assets The amount of assets that was flash loaned.
    /// @param data Arbitrary data passed to the `flashLoan` function.
    function onAvonFlashLoan(uint256 assets, bytes calldata data) external;
}
