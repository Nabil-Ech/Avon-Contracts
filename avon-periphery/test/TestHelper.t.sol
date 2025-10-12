// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {AvonPool} from "../src/pool/AvonPool.sol";
import {PoolStorage} from "../src/pool/PoolStorage.sol";
import {LiquidityAllocator} from "../src/libraries/LiquidityAllocator.sol";

// This contract extends AvonPool to expose internal functions for testing
contract TestAvonPool is AvonPool {
    using LiquidityAllocator for PoolStorage.PoolState;

    constructor(
        PoolStorage.PoolConfig memory _cfg,
        address _manager,
        address _orderBook,
        address _orderBookFactory,
        uint64 _fee,
        uint256 _liquidationBonus,
        uint256 _softRange,
        uint256 _softSeizeCap,
        uint256 _auctionPriorityWindow,
        uint256 _depositCap,
        uint256 _borrowCap,
        address[] memory _proposers,
        address[] memory _executors,
        address _admin
    )
        AvonPool(
            _cfg,
            _manager,
            _orderBook,
            _orderBookFactory,
            _fee,
            _liquidationBonus,
            _softRange,
            _softSeizeCap,
            _auctionPriorityWindow,
            _depositCap,
            _borrowCap,
            _proposers,
            _executors,
            _admin
        )
    {}

    // Expose getQuoteSuggestions for testing
    function exposed_getQuoteSuggestions(uint16 tickCount, uint256 availableLiquidity)
        external
        view
        returns (uint64[] memory rates, uint256[] memory liquidity)
    {
        return PoolStorage._state().getQuoteSuggestions(tickCount, availableLiquidity);
    }

    // Add more exposed functions as needed for testing
}
