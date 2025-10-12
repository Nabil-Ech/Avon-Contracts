// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOrderbook} from "../../interface/IOrderbook.sol";
import {IOracle} from "../../interface/IOracle.sol";
import {LiquidityAllocator} from "../../libraries/LiquidityAllocator.sol";
import {PoolConstants} from "../utils/PoolConstants.sol";
import {PoolStorage} from "../PoolStorage.sol";

library UpdateOrders {
    using LiquidityAllocator for PoolStorage.PoolState;

    /// @notice Recompute liquidity quotes and update orderbook with suggested quotes.
    /// @param s Pool storage state.
    function _updateOrders(PoolStorage.PoolState storage s) internal {
        uint256 totalLiquidity = s.totalSupplyAssets - s.totalBorrowAssets;
        uint16 tickCount = _getTicks(totalLiquidity, s.config.oracle);
        (uint64[] memory rates, uint256[] memory liquidity) =
            s.getQuoteSuggestions(tickCount, s.totalSupplyAssets - s.totalBorrowAssets);
        IOrderbook(s.orderBook).batchInsertOrder(rates, liquidity);
    }

    /// @notice Clear liquidity quotes from the orderbook.
    /// @param s Pool storage state.
    function _cancelOrders(PoolStorage.PoolState storage s) internal {
        uint64[] memory rates = new uint64[](0);
        uint256[] memory liquidity = new uint256[](0);
        IOrderbook(s.orderBook).batchInsertOrder(rates, liquidity);
    }

    /// @notice Determine number of ticks to spread quotes across based on USD liquidity scale.
    /// @param totalLiquidity Current available liquidity in loan tokens.
    /// @param oracle Oracle used to convert to USD.
    /// @return ticksCount Number of ticks for allocation granularity.
    function _getTicks(uint256 totalLiquidity, address oracle) internal view returns (uint16 ticksCount) {
        uint256 liquidityUSD = (totalLiquidity * IOracle(oracle).getLoanToUsdPrice());

        if (liquidityUSD < 100 * 1e36) {
            ticksCount = 1;
        } else if (liquidityUSD < 1e6 * 1e36) {
            ticksCount = 10;
        } else if (liquidityUSD < 1e8 * 1e36) {
            ticksCount = 100;
        } else {
            ticksCount = 1000;
        }
    }
}
