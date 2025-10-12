// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IOracle} from "../../interface/IOracle.sol";
import {PoolConstants} from "../utils/PoolConstants.sol";
import {PoolEvents} from "../utils/PoolEvents.sol";
import {PoolErrors} from "../utils/PoolErrors.sol";
import {PoolStorage} from "../PoolStorage.sol";
import {SharesLib} from "../../libraries/SharesLib.sol";

library PositionGuard {
    using Math for uint256;
    using SharesLib for uint256;

    /// @notice Check if a borrow position is within the allowed LTV.
    /// @param s Pool storage state.
    /// @param borrower Address of the position owner.
    /// @return True if the position is safe, false otherwise.
    function _isPositionSafe(PoolStorage.PoolState storage s, address borrower) internal view returns (bool) {
        PoolStorage.Position memory position = s.positions[borrower];
        if (position.borrowShares == 0) return true;

        uint256 assetRatio = uint256(PoolConstants.WAD).toAssetsUp(s.totalBorrowAssets, s.totalBorrowShares);
        uint256 borrowedAssets = position.borrowShares * assetRatio;

        uint256 collateralPrice = IOracle(s.config.oracle).getCollateralToLoanPrice();
        uint256 maxBorrowLimit =
            position.collateral.mulDiv((collateralPrice * s.config.lltv), PoolConstants.ORACLE_PRICE_SCALE);

        return maxBorrowLimit >= borrowedAssets;
    }

    /// @notice Set or unset an operator permission for msg.sender.
    /// @param s Pool storage state.
    /// @param authorized Operator address.
    /// @param isPermitted True to grant, false to revoke.
    function _setPermission(PoolStorage.PoolState storage s, address authorized, bool isPermitted) internal {
        if (isPermitted == s.isPermitted[msg.sender][authorized]) revert PoolErrors.AlreadySet();

        s.isPermitted[msg.sender][authorized] = isPermitted;

        emit PoolEvents.SetPermission(msg.sender, msg.sender, authorized, isPermitted);
    }

    /// @notice Check if msg.sender is allowed to act on behalf of `onBehalf`.
    /// @param s Pool storage state.
    /// @param onBehalf Position owner.
    /// @return True if permitted.
    function _isSenderPermitted(PoolStorage.PoolState storage s, address onBehalf) internal view returns (bool) {
        return msg.sender == onBehalf || msg.sender == s.orderBook || s.isPermitted[onBehalf][msg.sender];
    }
}
