// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

contract MockOracle {
    uint256 public assetPrice = (4000e6 * 1e36) / 1e18;
    uint256 public loanToUsdPrice = 1e12 * 1e18;

    function setPrice(uint256 _price) external {
        assetPrice = _price;
    }

    function getCollateralToLoanPrice() external view returns (uint256) {
        return assetPrice;
    }

    function getLoanToUsdPrice() external view returns (uint256) {
        return loanToUsdPrice;
    }
}
