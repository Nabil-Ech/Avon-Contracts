// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
import {IIrm} from "../../interface/IIrm.sol";
import {IPoolImplementation} from "../../interface/IPoolImplementation.sol";
import {PoolStorage} from "../PoolStorage.sol";
import {PoolEvents} from "../utils/PoolEvents.sol";
import {PoolConstants} from "../utils/PoolConstants.sol";

library AccrueInterest {
    using Math for uint256;
    using ABDKMath64x64 for int128;
    using ABDKMath64x64 for uint256;

    /// @notice Accrue interest on borrows since the last update and mint fee shares.
    /// @dev Uses continuous compounding with ABDKMath64x64: accrued = borrows * (e^(r*t) - 1).
    /// @param s Pool storage state.
    /// @return managerFeeShares Shares minted to manager due to interest.
    /// @return protocolFeeShares Shares minted to protocol due to interest.
    function _accrueInterest(PoolStorage.PoolState storage s)
        internal
        returns (uint256 managerFeeShares, uint256 protocolFeeShares)
    {
        uint256 currentTime = block.timestamp;
        uint256 elapsed = currentTime - s.lastUpdate;
        if (elapsed == 0) return (0, 0);

        uint256 totalBorrowAssets = s.totalBorrowAssets;
        uint256 totalSupplyAssets = s.totalSupplyAssets;
        uint256 totalSupplyShares = s.totalSupplyShares;
        uint256 managerFee = s.managerFee;

        uint256 rate = IIrm(s.config.irm).computeBorrowRate(totalSupplyAssets, totalBorrowAssets);

        // Calculate compound interest using ABDKMath64x64's exp function with proper scaling
        int128 scaledRate = ABDKMath64x64.divu(rate, PoolConstants.WAD);
        int128 scaledTime = ABDKMath64x64.fromUInt(elapsed);
        int128 expInput = ABDKMath64x64.mul(scaledRate, scaledTime);
        int128 expResult = ABDKMath64x64.exp(expInput); // e^(r*t)

        // Convert back to uint256 with WAD precision
        uint256 expFactor = ABDKMath64x64.mulu(expResult, PoolConstants.WAD);

        // Accrued interest = totalBorrowAssets * (e^(r*t) - 1)
        uint256 accruedInterest = totalBorrowAssets.mulDiv(expFactor - PoolConstants.WAD, PoolConstants.WAD);
        if (accruedInterest == 0) {
            s.lastUpdate = currentTime;
            return (0, 0);
        }

        // Update pool totals
        totalBorrowAssets += accruedInterest;
        totalSupplyAssets += accruedInterest;

        uint256 totalNewShares;
        uint256 managerFeeAmount = accruedInterest.mulDiv(managerFee, PoolConstants.WAD);
        uint256 protocolFeeAmount =
            accruedInterest.mulDiv(IPoolImplementation(address(this)).getProtocolFee(), PoolConstants.WAD);

        uint256 assetsWithoutFees = totalSupplyAssets - managerFeeAmount - protocolFeeAmount;

        // Calculate manager fee shares if applicable
        if (managerFee != 0 && accruedInterest > 0) {
            managerFeeShares = managerFeeAmount.mulDiv(totalSupplyShares, assetsWithoutFees);
            totalNewShares += managerFeeShares;
        }

        // Calculate protocol fee shares if there's interest
        if (accruedInterest > 0) {
            protocolFeeShares = protocolFeeAmount.mulDiv(totalSupplyShares, assetsWithoutFees);
            totalNewShares += protocolFeeShares;
        }

        // Only update if there are new shares
        if (totalNewShares > 0) {
            totalSupplyShares += totalNewShares;
        }

        // Write to storage
        s.totalBorrowAssets = totalBorrowAssets;
        s.totalSupplyAssets = totalSupplyAssets;
        s.totalSupplyShares = totalSupplyShares;
        s.lastUpdate = currentTime;

        emit PoolEvents.AccrueInterest(address(this), rate, accruedInterest, totalNewShares);
    }
}
