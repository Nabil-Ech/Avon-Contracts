// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {PoolStorage} from "../pool/PoolStorage.sol";

/**
 * @title IPoolFactory
 * @notice Interface for interacting with the Pool Factory
 */
interface IPoolFactory {
    /**
     * @notice Deploys a new AvonPool contract
     * @param config Pool configuration including tokens, oracle, IRM, and LLTV
     * @param fee Manager fee for the pool
     * @return pool Address of the newly created pool
     */
    function deployPool(PoolStorage.PoolConfig calldata config, uint64 fee) external returns (address pool);

    /**
     * @notice Check if an address is a pool deployed by this factory
     * @param pool Address to check
     * @return True if the address is a valid pool
     */
    function isValidPool(address pool) external view returns (bool);

    /**
     * @notice Get the address of the orderbook factory
     * @return Address of the orderbook factory
     */
    function orderbookFactory() external view returns (address);
}
