// SPDX-License-Identifier: Busl-1.1
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
import {IOracle} from "../../interface/IOracle.sol";
import {IIrm} from "../../interface/IIrm.sol";
import {IPoolImplementation} from "../../interface/IPoolImplementation.sol";
import {SharesLib} from "../../libraries/SharesLib.sol";
import {PoolConstants} from "./PoolConstants.sol";
import {PoolStorage} from "../PoolStorage.sol";
import {PoolErrors} from "./PoolErrors.sol";

library PoolGetter {
    using Math for uint256;
    using SharesLib for uint256;

    struct PoolData {
        uint256 totalSupplyAssets;
        uint256 totalSupplyShares;
        uint256 totalBorrowAssets;
        uint256 totalBorrowShares;
        uint256 lastUpdate;
    }

    struct BorrowPosition {
        uint256 borrowAssets;
        uint256 borrowShares;
        uint256 collateral;
    }

    function getPoolData(PoolStorage.PoolState storage s)
        internal
        view
        returns (PoolData memory previewPool, uint256 ir, uint256 ltv)
    {
        previewPool = _previewAccrueInterest(s);
        ir = IIrm(s.config.irm).computeBorrowRate(previewPool.totalSupplyAssets, previewPool.totalBorrowAssets);
        ltv = s.config.lltv;
    }

    function getPosition(PoolStorage.PoolState storage s, address account)
        internal
        view
        returns (BorrowPosition memory currentPosition)
    {
        (currentPosition.borrowShares, currentPosition.collateral) =
            (s.positions[account].borrowShares, s.positions[account].collateral);
        PoolData memory previewPool = _previewAccrueInterest(s);
        currentPosition.borrowAssets =
            currentPosition.borrowShares.toAssetsUp(previewPool.totalBorrowAssets, previewPool.totalBorrowShares);
    }

    function previewBorrow(PoolStorage.PoolState storage s, address, uint256 assets, uint256 collateralBuffer)
        internal
        view
        returns (uint256 collateralAmount)
    {
        uint256 collateralPrice = IOracle(s.config.oracle).getCollateralToLoanPrice();
        PoolData memory previewPool = _previewAccrueInterest(s);
        if (collateralBuffer < 0.01e18) revert PoolErrors.InvalidInput();
        uint256 lltv = s.config.lltv;

        uint256 availableLiquidity = previewPool.totalSupplyAssets - previewPool.totalBorrowAssets;
        if (assets > availableLiquidity) return 0;

        collateralAmount = assets.mulDiv(PoolConstants.ORACLE_PRICE_SCALE, collateralPrice, Math.Rounding.Ceil).mulDiv(
            (PoolConstants.WAD + collateralBuffer), lltv, Math.Rounding.Ceil
        );
    }

    function previewBorrowWithExactCollateral(
        PoolStorage.PoolState storage s,
        address,
        uint256 collateralAmount,
        uint256 collateralBuffer
    ) internal view returns (uint256 loanTokenAmount) {
        uint256 collateralPrice = IOracle(s.config.oracle).getCollateralToLoanPrice();
        if (collateralBuffer < 0.01e18) revert PoolErrors.InvalidInput();
        uint256 lltv = s.config.lltv;

        loanTokenAmount = collateralAmount.mulDiv(collateralPrice, PoolConstants.ORACLE_PRICE_SCALE).mulDiv(
            lltv, (PoolConstants.WAD + collateralBuffer)
        );
    }

    function _previewAccrueInterest(PoolStorage.PoolState storage s)
        internal
        view
        returns (PoolData memory previewPool)
    {
        uint256 elapsed = block.timestamp - s.lastUpdate;
        previewPool = PoolData({
            totalSupplyAssets: s.totalSupplyAssets,
            totalSupplyShares: s.totalSupplyShares,
            totalBorrowAssets: s.totalBorrowAssets,
            totalBorrowShares: s.totalBorrowShares,
            lastUpdate: s.lastUpdate
        });

        uint256 rate = IIrm(s.config.irm).computeBorrowRate(s.totalSupplyAssets, s.totalBorrowAssets);

        // Calculate compound interest using ABDKMath64x64's exp function with proper scaling
        int128 scaledRate = ABDKMath64x64.divu(rate, PoolConstants.WAD);
        int128 scaledTime = ABDKMath64x64.fromUInt(elapsed);
        int128 expInput = ABDKMath64x64.mul(scaledRate, scaledTime);
        int128 expResult = ABDKMath64x64.exp(expInput); // e^(r*t)

        // Convert back to uint256 with WAD precision
        uint256 expFactor = ABDKMath64x64.mulu(expResult, PoolConstants.WAD);

        // Accrued interest = totalBorrowAssets * (e^(r*t) - 1)
        uint256 accruedInterest = s.totalBorrowAssets.mulDiv(expFactor - PoolConstants.WAD, PoolConstants.WAD);
        if (accruedInterest == 0) return (previewPool);

        previewPool.totalBorrowAssets += accruedInterest;
        previewPool.totalSupplyAssets += accruedInterest;

        uint256 managerFeeAmount = accruedInterest.mulDiv(s.managerFee, PoolConstants.WAD);
        uint256 protocolFeeAmount =
            accruedInterest.mulDiv(IPoolImplementation(address(this)).getProtocolFee(), PoolConstants.WAD);

        uint256 assetsWithoutFees = previewPool.totalSupplyAssets - managerFeeAmount - protocolFeeAmount;

        if (s.managerFee != 0) {
            uint256 managerFeeShares = managerFeeAmount.mulDiv(s.totalSupplyShares, assetsWithoutFees);
            previewPool.totalSupplyShares += managerFeeShares;
        }

        uint256 protocolFeeShares = protocolFeeAmount.mulDiv(s.totalSupplyShares, assetsWithoutFees);
        previewPool.totalSupplyShares += protocolFeeShares;

        if (managerFeeAmount > 0 || protocolFeeAmount > 0) {
            accruedInterest -= (managerFeeAmount + protocolFeeAmount);
        }

        previewPool.lastUpdate = block.timestamp;
    }

    /// @notice Get the configured auction priority window size
    /// @param s Pool storage state
    /// @return auctionPriorityWindow The window size (0 = disabled)
    function getAuctionPriorityWindow(PoolStorage.PoolState storage s)
        internal
        view
        returns (uint256 auctionPriorityWindow)
    {
        return s.auctionPriorityWindow;
    }
}
