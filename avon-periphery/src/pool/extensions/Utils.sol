// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

/// @title Miscellaneous utility functions
library Utils {
    /// @notice Returns true if exactly one of the inputs is zero
    function exactlyOneZero(uint256 x, uint256 y) internal pure returns (bool) {
        return (x == 0 && y != 0) || (x != 0 && y == 0);
    }
}
