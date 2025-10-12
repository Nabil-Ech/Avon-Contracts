// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {AvonPool} from "../pool/AvonPool.sol";
import {PoolStorage} from "../pool/PoolStorage.sol";
import {IOrderbookFactory} from "../interface/IOrderbookFactory.sol";
import {PoolErrors} from "../pool/utils/PoolErrors.sol";

/**
 * @title AvonPoolFactory
 * @notice Factory contract for deploying and tracking AvonPool contracts
 */
contract AvonPoolFactory is Ownable2Step {
    // State variables
    address public immutable orderbookFactory;

    // Mapping to track valid pools deployed by this factory
    mapping(address => bool) public isValidPool;

    // Events
    event PoolCreated(address indexed pool, address indexed loanToken, address indexed collateralToken);

    /**
     * @notice Constructor sets the OrderbookFactory address and initial owner
     * @param _orderbookFactory Address of the OrderbookFactory contract
     */
    constructor(address _orderbookFactory) Ownable(msg.sender) {
        if (_orderbookFactory == address(0)) revert PoolErrors.InvalidInput();
        orderbookFactory = _orderbookFactory;
    }

    /**
     * @notice Deploys a new AvonPool contract with the given parameters
     * @param config Pool configuration including tokens, oracle, IRM, and LLTV
     * @param fee Manager fee for the pool
     * @param liquidationBonus Liquidation bonus for the pool
     * @param softRange Soft liquidation range
     * @param softSeizeCap Soft liquidation seize cap
     * @param depositCap Maximum deposit limit (in token units, 0 means no cap)
     * @param borrowCap Maximum borrow limit (in token units, 0 means no cap)
     * @return pool Address of the newly created pool
     */
    function deployPool(
        PoolStorage.PoolConfig memory config,
        uint64 fee,
        uint256 liquidationBonus,
        uint256 softRange,
        uint256 softSeizeCap,
        uint256 auctionPriorityWindow,
        uint256 depositCap,
        uint256 borrowCap
    ) external returns (address pool) {
        // Verify the caller is an approved pool manager
        if (!IOrderbookFactory(orderbookFactory).isPoolManager(msg.sender)) {
            revert PoolErrors.Unauthorized();
        }

        // Get the orderbook address for the token pair from the factory
        address orderbook = IOrderbookFactory(orderbookFactory).getOrderbook(config.loanToken, config.collateralToken);

        if (orderbook == address(0)) revert PoolErrors.InvalidInput();

        address owner = Ownable(orderbook).owner();

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](2);
        proposers[0] = owner;
        executors[0] = owner;
        executors[1] = msg.sender; // Pool manager

        // Deploy the new pool
        pool = address(
            new AvonPool(
                config,
                msg.sender, // pool manager
                orderbook,
                orderbookFactory,
                fee,
                liquidationBonus,
                softRange,
                softSeizeCap,
                auctionPriorityWindow,
                depositCap,
                borrowCap,
                proposers,
                executors,
                Ownable(orderbookFactory).owner() //ultimate owner
            )
        );

        // Mark the pool as valid
        isValidPool[pool] = true;

        // Emit event with pool details
        emit PoolCreated(pool, config.loanToken, config.collateralToken);
    }

    /**
     * @notice Check if an address is a pool deployed by this factory
     * @param pool Address to check
     * @return True if the address is a valid pool
     */
    function validatePool(address pool) external view returns (bool) {
        return isValidPool[pool];
    }
}
