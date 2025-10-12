// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IPoolStorage} from "./IPoolStorage.sol";
import {IPoolGetter} from "./IPoolGetter.sol";

interface IPoolImplementation {
    function paused() external view returns (bool);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, uint256 minAmountExpected)
        external
        returns (uint256, uint256);
    function repay(uint256 assets, uint256 shares, address onBehalf) external returns (uint256, uint256);
    function depositCollateral(uint256 assets, address onBehalf) external;
    function withdrawCollateral(uint256 assets, address onBehalf, address receiver) external;
    function liquidate(address borrower, uint256 assets, uint256 shares) external;
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
    function setAuthorization(address authorized, bool isPermitted) external;
    function pausePool(bool pause) external;
    function updateOrderbook(address newOrderbook, address newOrderbookFactory) external;
    function increaseLLTV(uint64 newLTV) external;
    function getPoolConfig() external view returns (IPoolStorage.PoolConfig memory poolConfig);
    function getPoolData()
        external
        view
        returns (IPoolGetter.PoolData memory previewPool, uint256 ir, uint256 ltv, uint256 apy);
    function getPosition(address account) external view returns (IPoolGetter.BorrowPosition memory currentPosition);
    function getIRM() external view returns (address);
    function getLTV() external view returns (uint256);
    function previewBorrow(address borrower, uint256 assets, uint256 collateralBuffer)
        external
        view
        returns (uint256 collateralAmount);
    function previewBorrowWithExactCollateral(address borrower, uint256 collateralAmount, uint256 collateralBuffer)
        external
        view
        returns (uint256 borrowAmount);
}
