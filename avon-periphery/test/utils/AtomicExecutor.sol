// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAvonPool {
    function updateTransientLiquidationBonus(uint256 newBonus) external;
    function liquidate(
        address borrower,
        uint256 assets,
        uint256 shares,
        uint256 minSeizedAmount,
        uint256 maxRepaidAsset,
        bytes calldata data
    ) external;
}

contract AtomicExecutor {
    function setBonusAndLiquidate(
        address pool,
        uint256 newBonus,
        address borrower,
        uint256 assets,
        uint256 shares,
        uint256 minSeizedAmount,
        uint256 maxRepaidAsset
    ) external {
        IAvonPool(pool).updateTransientLiquidationBonus(newBonus);
        IAvonPool(pool).liquidate(borrower, assets, shares, minSeizedAmount, maxRepaidAsset, "");
    }
}
