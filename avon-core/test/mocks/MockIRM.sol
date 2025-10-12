// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockIRM {
    // Constants for scaling
    uint256 private constant WAD = 1e18;
    uint256 private constant SECONDS_PER_YEAR = 31536000;

    /// @notice Base interest rate when utilization is zero (scaled by WAD)
    uint256 public immutable baseRate;
    /// @notice Slope of the interest rate curve before kink (scaled by WAD)
    uint256 public immutable slope1;
    /// @notice Slope of the interest rate curve after kink (scaled by WAD)
    uint256 public immutable slope2;
    /// @notice Utilization point where slope changes (scaled by WAD)
    uint256 public immutable kink;

    constructor(uint256 baseRate_, uint256 slope1_, uint256 slope2_, uint256 kink_) {
        require(kink_ <= WAD, "Kink must be <= WAD");
        baseRate = baseRate_;
        slope1 = slope1_;
        slope2 = slope2_;
        kink = kink_;
    }

    /// @notice Computes the borrow rate based on the current utilization
    /// @param totalAssets Total assets in the pool
    /// @param totalBorrows Total borrowed from the pool
    /// @return The borrow rate per second, scaled by WAD
    function computeBorrowRate(uint256 totalAssets, uint256 totalBorrows) external view returns (uint256) {
        // Calculate utilization ratio scaled by WAD
        uint256 utilization = totalAssets == 0 ? 0 : (totalBorrows * WAD) / totalAssets;

        uint256 yearlyRate;

        if (utilization <= kink) {
            // Below kink: baseRate + (utilization * slope1)
            yearlyRate = baseRate + ((utilization * slope1) / WAD);
        } else {
            // Above kink: baseRate + (kink * slope1) + ((utilization - kink) * slope2)
            yearlyRate = baseRate + ((kink * slope1) / WAD);
            uint256 excessUtilization = utilization - kink;
            yearlyRate += ((excessUtilization * slope2) / WAD);
        }

        // Convert yearly rate to per-second rate
        return yearlyRate / SECONDS_PER_YEAR;
    }
}
