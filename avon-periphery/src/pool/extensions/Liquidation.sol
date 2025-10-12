// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IOracle} from "../../interface/IOracle.sol";
import {SharesLib} from "../../libraries/SharesLib.sol";
import {PoolConstants} from "../utils/PoolConstants.sol";
import {PoolErrors} from "../utils/PoolErrors.sol";
import {PoolEvents} from "../utils/PoolEvents.sol";
import {PositionGuard} from "./PositionGuard.sol";
import {PoolStorage} from "../PoolStorage.sol";
import {IAvonLiquidationCallback} from "../../interface/IAvonLiquidationCallback.sol";
import {Utils} from "./Utils.sol";

library Liquidation {
    using PositionGuard for PoolStorage.PoolState;
    using Math for uint256;
    using SharesLib for uint256;

    /// @notice Liquidates an under-collateralized position with a quadratic health bonus
    function _liquidate(
        PoolStorage.PoolState storage s,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares,
        uint256 minSeizedAmount,
        uint256 maxRepaidAsset,
        bytes calldata data
    ) internal returns (uint256, uint256) {
        if (!Utils.exactlyOneZero(seizedAssets, repaidShares)) revert PoolErrors.InconsistentInput();

        PoolStorage.Position storage position = s.positions[borrower];
        uint256 totalBorrowAssets = s.totalBorrowAssets;
        uint256 totalBorrowShares = s.totalBorrowShares;

        if (s._isPositionSafe(borrower)) revert PoolErrors.HealthyPosition();

        // 1) Compute healthScore, bonusFactor & seizeCap
        uint256 collateralPrice = IOracle(s.config.oracle).getCollateralToLoanPrice();
        // collateral value in loan tokens
        uint256 collateralValue = position.collateral.mulDiv(collateralPrice, PoolConstants.ORACLE_PRICE_SCALE);
        // borrowed amount in loan tokens
        uint256 borrowedAssets = position.borrowShares.toAssetsUp(totalBorrowAssets, totalBorrowShares);

        // healthScore = (collateralValue * ltv) / borrowedAssets
        uint256 healthScore =
            collateralValue.mulDiv(s.config.lltv, PoolConstants.WAD).mulDiv(PoolConstants.WAD, borrowedAssets);

        // how far below the safe threshold (WAD)
        uint256 diff = PoolConstants.WAD - healthScore;

        // Check if this is an auction transaction by reading transient storage
        uint256 transientBonus = PoolStorage.getTransientLiquidationBonus();

        // Enforce auction priority window for interest-triggered liquidations
        // When window > 0, positions within the health score range of 1 to (1 - window) can only be liquidated by auctions
        // This gives auction service priority for liquidations triggered by interest accrual in correlated asset pools
        if (s.auctionPriorityWindow > 0 && transientBonus == 0 && diff <= s.auctionPriorityWindow) {
            revert PoolErrors.NonAuctionLiquidationWithinAuctionPriorityWindow();
        }

        uint256 bonusFactor;
        uint256 seizeCap;

        // Check for non-zero transient bonus value (0 means use default bonus)
        uint256 liquidationBonus = transientBonus == 0 ? s.liquidationBonus : transientBonus;

        if (diff <= s.softRange) {
            // Soft range: flat bonus, cap seize to 25% of collateral
            bonusFactor = liquidationBonus;
            seizeCap = position.collateral.mulDiv(s.softSeizeCap, PoolConstants.WAD);
        } else {
            // Hard range: quadratic ramp up to MAX_LIQ_BONUS
            uint256 quad = diff.mulDiv(diff, PoolConstants.WAD); // (diff)^2/WAD
            bonusFactor =
                liquidationBonus + (PoolConstants.MAX_LIQ_BONUS - liquidationBonus).mulDiv(quad, PoolConstants.WAD);
            seizeCap = position.collateral; // full seize allowed
        }

        // 2) Compute repaidShares or seizedAssets using bonusFactor & seizeCap
        if (seizedAssets > 0) {
            // cap collateral seized in soft range
            uint256 actualSeized = seizedAssets > seizeCap ? seizeCap : seizedAssets;
            // quote collateral into loan tokens
            uint256 seizedQuoted =
                actualSeized.mulDiv(collateralPrice, PoolConstants.ORACLE_PRICE_SCALE, Math.Rounding.Ceil);
            // compute how many borrow-shares this repays
            repaidShares = seizedQuoted.mulDiv(PoolConstants.WAD, bonusFactor, Math.Rounding.Ceil).toSharesUp(
                totalBorrowAssets, totalBorrowShares
            );
            seizedAssets = actualSeized;
        } else {
            // compute raw seize amount from repaidShares
            uint256 rawSeize = repaidShares.toAssetsDown(totalBorrowAssets, totalBorrowShares).mulDiv(
                bonusFactor, PoolConstants.WAD
            ).mulDiv(PoolConstants.ORACLE_PRICE_SCALE, collateralPrice);

            // If capping is needed, also adjust repaidShares proportionally
            if (rawSeize > seizeCap) {
                seizedAssets = seizeCap;

                // Recalculate repaidShares based on the capped seized assets
                uint256 seizedQuoted =
                    seizedAssets.mulDiv(collateralPrice, PoolConstants.ORACLE_PRICE_SCALE, Math.Rounding.Ceil);

                repaidShares = seizedQuoted.mulDiv(PoolConstants.WAD, bonusFactor, Math.Rounding.Ceil).toSharesUp(
                    totalBorrowAssets, totalBorrowShares
                );
            } else {
                seizedAssets = rawSeize;
            }
        }

        // Convert repaidShares to loan tokens
        uint256 repaidAssets = repaidShares.toAssetsUp(totalBorrowAssets, totalBorrowShares);

        // 3) Update position & pool accounting
        // Seize collateral & burn borrow-shares
        uint256 amountToSeize = Math.min(seizedAssets, position.collateral);
        position.collateral -= amountToSeize;
        position.borrowShares -= repaidShares;

        // Reduce pool totals
        totalBorrowShares -= repaidShares;
        totalBorrowAssets = totalBorrowAssets > repaidAssets ? totalBorrowAssets - repaidAssets : 0;

        uint256 badDebtShares;
        uint256 badDebtAssets;

        if (position.collateral == 0 && position.borrowShares > 0) {
            badDebtShares = position.borrowShares;
            badDebtAssets = Math.min(totalBorrowAssets, badDebtShares.toAssetsUp(totalBorrowAssets, totalBorrowShares));

            totalBorrowAssets -= badDebtAssets;
            totalBorrowShares -= badDebtShares;
            s.totalSupplyAssets -= badDebtAssets;
            position.borrowShares = 0;
        }

        s.totalBorrowAssets = totalBorrowAssets;
        s.totalBorrowShares = totalBorrowShares;
        position.poolBorrowAssets = totalBorrowAssets;
        position.poolBorrowShares = totalBorrowShares;
        position.updatedAt = s.lastUpdate;

        if (repaidAssets > maxRepaidAsset || amountToSeize < minSeizedAmount) revert PoolErrors.LiquidationFailed();

        SafeERC20.safeTransfer(ERC20(s.config.collateralToken), msg.sender, amountToSeize);

        if (data.length > 0) IAvonLiquidationCallback(msg.sender).onAvonLiquidation(seizedAssets, repaidShares, data);

        SafeERC20.safeTransferFrom(ERC20(s.config.loanToken), msg.sender, address(this), repaidAssets);

        emit PoolEvents.Liquidate(
            address(this), msg.sender, borrower, repaidAssets, repaidShares, seizedAssets, badDebtAssets, badDebtShares
        );

        return (seizedAssets, repaidAssets);
    }
}
