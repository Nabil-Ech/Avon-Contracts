// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title IIrm
/// @author Avon Labs
/// @notice Interface that Interest Rate Models (IRMs) used by Avon must implement.
interface IIrm {
    function computeBorrowRate(uint256 totalAssets, uint256 totalBorrows) external view returns (uint64);
}
