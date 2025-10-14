// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IIrm} from "../interface/IIrm.sol";
import {PoolStorage} from "../pool/PoolStorage.sol";
import {PoolConstants} from "../pool/utils/PoolConstants.sol";

/// @title Liquidity Band Discretization Library
/// @dev All functions assume basis points (0-10000) for utilization and rates
library LiquidityAllocator {
    /**
     * @notice Suggests quotes for liquidity allocation based on the pool parameters and current utilization.
     * @param s The pool state.
     * @param tickCount The number of ticks to divide the liquidity into.
     * @return rates An array of suggested rates for each quote.
     * @return liquidity An array of suggested liquidity amounts for each quote.
     */
    function getQuoteSuggestions(PoolStorage.PoolState storage s, uint16 tickCount, uint256 availableLiquidity)
        internal
        view
        returns (uint64[] memory rates, uint256[] memory liquidity)
    {
        // even if tickcount is 10, the quoute is 1
        uint16 quoteSuggestions = tickCount > 10 ? PoolConstants.QUOTE_SUGGESTIONS : tickCount;
        rates = new uint64[](quoteSuggestions);
        liquidity = new uint256[](quoteSuggestions);
        uint256 currentUtilization = availableLiquidity == 0
            ? PoolConstants.MAX_UTILIZATION
            : (s.totalBorrowAssets * PoolConstants.MAX_UTILIZATION) / s.totalSupplyAssets;

        uint256 utilizationPerTick = (PoolConstants.MAX_UTILIZATION - currentUtilization) / tickCount;
        uint256 liquidityPerTick = availableLiquidity / tickCount;

        // Track how much liquidity has been allocated
        uint256 allocatedLiquidity = 0;

        for (uint256 i; i < quoteSuggestions; ++i) {
            uint256 startUtil = currentUtilization + uint256(i * utilizationPerTick);
            rates[i] = IIrm(s.config.irm).computeBorrowRate(PoolConstants.MAX_UTILIZATION, startUtil);
            // If this is the last tick, allocate all remaining liquidity
            if (i == quoteSuggestions - 1) {
                liquidity[i] = availableLiquidity - allocatedLiquidity;
            } else {
                liquidity[i] = liquidityPerTick;
                allocatedLiquidity += liquidityPerTick;
            }
        }
    }
}
