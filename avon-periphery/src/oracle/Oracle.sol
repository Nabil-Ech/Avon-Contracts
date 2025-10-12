// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {IOracle} from "../interface/IOracle.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @notice Minimal interface for external price feeds compatible with Redstone Oracles
interface IExternalPriceFeed {
    function latestAnswer() external view returns (int256);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title Oracle
/// @author Avon Labs
/// @notice Oracle adapter that computes collateral->loan and loan->USD prices with adjustable scaling.
/// - getCollateralToLoanPrice(): returns 1 collateral asset priced in loan asset
/// - getLoanToUsdPrice(): returns price of 1 loan asset in USD
/// @dev Adjustment variables allow adapting to different feed decimals. Owner can update oracles and settings.
contract Oracle is IOracle, Ownable2Step {
    // External feeds
    IExternalPriceFeed public collateralFeed; // price of collateral in loan terms
    IExternalPriceFeed public loanUsdFeed; // price of loan in USD

    // Staleness controls
    uint256 public maxAge = 10 minutes;

    // Adjustment factors
    // For collateral: output is (answer * 1e36) / collateralAdjustment
    // collateralAdjustment factor will be calculated as 1e(collateral token decimals) * 1e2
    uint256 public collateralAdjustment;

    // For loan USD price: output is answer * loanAdjustment
    // loanAdjustment factor will be calculated as 1e36 / (1e(loan token decimals) * 1e(oracle default scaling factor for redstone it is 8))
    uint256 public loanAdjustment;

    error InvalidPrice();
    error StalePrice();
    error InvalidParam();

    constructor(address _collateralFeed, address _loanUsdFeed, uint256 _collateralAdjustment, uint256 _loanAdjustment)
        Ownable(msg.sender)
    {
        collateralFeed = IExternalPriceFeed(_collateralFeed);
        loanUsdFeed = IExternalPriceFeed(_loanUsdFeed);
        collateralAdjustment = _collateralAdjustment;
        loanAdjustment = _loanAdjustment;
    }

    // --- Admin ---

    function setFeeds(address _collateralFeed, address _loanUsdFeed) external onlyOwner {
        collateralFeed = IExternalPriceFeed(_collateralFeed);
        loanUsdFeed = IExternalPriceFeed(_loanUsdFeed);
    }

    function setMaxAge(uint256 _maxAge) external onlyOwner {
        if (_maxAge == 0) revert InvalidParam();
        maxAge = _maxAge;
    }

    function setAdjustments(uint256 _collateralAdjustment, uint256 _loanAdjustment) external onlyOwner {
        if (_collateralAdjustment == 0 || _loanAdjustment == 0) revert InvalidParam();
        collateralAdjustment = _collateralAdjustment;
        loanAdjustment = _loanAdjustment;
    }

    // --- IOracle ---

    function getCollateralToLoanPrice() external view override returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = collateralFeed.latestRoundData();
        if (answer <= 0) revert InvalidPrice();
        if (updatedAt < block.timestamp - maxAge) revert StalePrice();

        uint256 price = uint256(answer);
        return (price * 1e36) / collateralAdjustment;
    }

    function getLoanToUsdPrice() external view override returns (uint256) {
        int256 answer = loanUsdFeed.latestAnswer();
        if (answer <= 0) revert InvalidPrice();
        return uint256(answer) * loanAdjustment;
    }
}
