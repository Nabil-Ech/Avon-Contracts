// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IIrm} from "../interface/IIrm.sol";

/// @title LinearKinkIRM
/// @author Based on Euler Labs' implementation
/// @notice Implementation of an interest rate model where interest rate grows linearly with utilization
/// and spikes after reaching a kink point

contract LinearKinkIRM is IIrm, Ownable2Step {
    uint256 private constant WAD = 1e18;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    /// @notice Base interest rate when utilization is zero (scaled by WAD)
    uint256 public immutable baseRate;
    /// @notice Slope of the interest rate curve before kink (scaled by WAD)
    uint256 public immutable slope1;
    /// @notice Slope of the interest rate curve after kink (scaled by WAD)
    uint256 public immutable slope2;
    /// @notice Utilization point where slope changes (scaled by WAD)
    uint256 public immutable kink;

    error InvalidParam();

    constructor(uint256 baseRate_, uint256 slope1_, uint256 slope2_, uint256 kink_) Ownable(msg.sender) {
        if (kink_ > WAD) revert InvalidParam();
        baseRate = baseRate_;
        slope1 = slope1_;
        slope2 = slope2_;
        kink = kink_;
    }

    /// @inheritdoc IIrm
    function computeBorrowRate(uint256 totalAssets, uint256 totalBorrows) external view override returns (uint64) {
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

        uint256 perSecond = yearlyRate / SECONDS_PER_YEAR;
        return uint64(perSecond);
    }
}
