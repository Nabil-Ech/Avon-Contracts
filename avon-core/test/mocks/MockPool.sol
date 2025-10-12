// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOrderbook} from "../../src/interface/IOrderbook.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract MockPool is ERC4626, Pausable {
    mapping(address => mapping(address => bool)) public isAuthorized;
    mapping(address => Position) internal userPositions;

    struct Position {
        uint256 collateral;
        uint256 debt;
    }

    struct Pool {
        address asset;
        uint256 totalAssets;
        uint256 totalShares;
    }

    address internal orderBook;
    address internal irm;
    address internal collateral;
    uint64 internal _interestRate = 1e18;
    uint256 internal _ltv = 0.5e18;

    constructor(ERC20 _asset, address _orderbook, address _irm, address _collateral)
        ERC20("Mock LP Token", "mLP")
        ERC4626(_asset)
    {
        orderBook = _orderbook;
        irm = _irm;
        collateral = _collateral;
    }

    // === IPoolImplementation ===

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        super.deposit(assets, receiver);
        userPositions[receiver].collateral += assets;
        _updateOrders();
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        super.withdraw(assets, receiver, owner);
        userPositions[owner].collateral -= assets;
        _updateOrders();
    }

    /// @dev Pool will have a different calculation for shares
    function borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, uint256)
        external
        returns (uint256, uint256)
    {
        userPositions[onBehalf].debt += shares;
        ERC20(asset()).transfer(receiver, assets);
        _updateOrders();
        return (assets, shares);
    }

    /// @dev Pool will have a different calculation for shares
    function repay(uint256 assets, uint256 shares, address onBehalf) external returns (uint256, uint256) {
        ERC20(asset()).transferFrom(msg.sender, address(this), assets);
        userPositions[onBehalf].debt -= shares;
        _updateOrders();
        return (assets, shares);
    }

    /// @dev sullyCollateral is important to make the position healthy
    function depositCollateral(uint256 assets, address onBehalf) external {
        ERC20(collateral).transferFrom(msg.sender, address(this), assets);
        userPositions[onBehalf].collateral += assets;
    }

    function withdrawCollateral(uint256 assets, address onBehalf, address receiver) external {
        require(userPositions[onBehalf].collateral >= assets, "Insufficient collateral");
        userPositions[onBehalf].collateral -= assets;
        ERC20(collateral).transfer(receiver, assets);
    }

    function liquidate(address borrower, uint256 seizedAssets, uint256 repaidShares)
        external
        returns (uint256, uint256)
    {
        userPositions[borrower].collateral -= seizedAssets;
        ERC20(asset()).transfer(msg.sender, seizedAssets);
        userPositions[borrower].debt -= repaidShares;
        return (seizedAssets, repaidShares);
    }

    /// @dev IRM will be used to calculate the interest rate
    function _updateOrders() internal {
        uint256 totalAssets = totalAssets();
        uint256 assetsPerTick = totalAssets / 10;
        uint64[] memory irs = new uint64[](10);
        uint256[] memory amounts = new uint256[](10);
        for (uint64 i = 0; i < 10; i++) {
            irs[i] = _interestRate + (i * 1e16);
            amounts[i] = assetsPerTick;
        }
        IOrderbook(orderBook).batchInsertOrder(irs, amounts);
    }

    /// @dev This is a dummy function in real pools it will calculated by LTV and price of the asset
    function previewBorrow(address, uint256 assets, uint256) external pure returns (uint256) {
        return assets / 2;
    }

    function getIR() external view returns (uint256) {
        return _interestRate;
    }

    function getLTV() external view returns (uint256) {
        return _ltv;
    }

    function getIRM() external view returns (address) {
        return irm;
    }

    function previewBorrowWithExactCollateral(address, uint256 collateralAmount, uint256)
        external
        pure
        returns (uint256)
    {
        return collateralAmount * 2;
    }
}
