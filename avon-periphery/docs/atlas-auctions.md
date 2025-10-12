# Executive Summary

## Overview

Avon LAS builds on top of the already existing RedStone OEV implementation that is currently in production with Compound, Venus, and Felix (HyperEVM). RedStone OEV today can be thought of as using a bucket to capture value leakage from static liquidation bonuses; Avon LAS will instead patch the leak in the first place by directly modifying the liquidation bonus in real-time based on the auctions. 
By lowering the effective liquidation bonuses this service aims to enable less conservative risk parameters such as higher LTVs, higher supply caps, and faster asset listings. Avon strategy managers must already compete on the interest rates that are offered to borrowers, and this service allows strategy managers to also compete on liquidation mechanisms. This service positions Avon to be the lending protocol with the most optimized liquidation engine, and creates strong competitive advantages for Avon in terms of the capital efficiency and yield that strategy managers can offer; positioning Avon to win the most scalable and important user base in lending: institutional and sophisticated users that are optimizing for risk-adjusted returns.

## Goals

- Provide strategy managers on Avon with the ability to integrate modular services to determine auction-driven liquidation bonuses.
- Dynamic auction-driven liquidation bonuses can never exceed the default liquidation bonus, they can only lower it.
- The path for non-auction liquidations cannot be impacted, non-auction liquidations can occur as normal using the default bonus if the auction has failed to capture the liquidation for any reason.
- Support liquidations triggered by interest accrual as well as oracle updates.

## Requirements

1. This service operates without any changes to the smart contract data feed implementations.
2. This service builds seamlessly on top of the existing RedStone OEV off-chain infrastructure with minimal modifications.

# OEV Service Primer

This section will describe the RedStone OEV service in production today, as Avon LAS builds on top of this existing service.

### Value Proposition

- Liquidations can now occur at a lower latency than they otherwise would, enabled by the fact that OEV liquidations can be triggered in-between deviation thresholds by a low-latency pull-oracle.
- A very reasonable worst-case scenario (in the case where Auctioneer infrastructure is unavailable) of 200ms delays to data feeds.
- Atlas uniquely settles auctions on-chain between many liquidators. Settling auctions on-chain removes dependencies on a single liquidator, block builders, RPCs, or private mempools; and provides a level of resiliency and robustness not present in any other order flow auction.
- Atlas allows the oracle itself to retain control of transaction propagation, and for these transactions to be propagated to any mempool (public or private); again removing external dependencies. These features enable OEV to provide unique guarantees that the liquidation will execute in the given transaction without delays, and most times at a lower latency.

### OEV-Specific Atlas Documentation

Atlas is a multicall or ERC-4337-like smart contract framework for customizing auctions that settle on-chain. Notably, Atlas enables single atomic transactions that contain both a data feed update, and OEV-capturing liquidations. The atomicity of operations within Atlas, and the oracle propagating the transaction to the regular mempool, ensures that the individual data feed operations cannot be re-ordered, or delayed by a third party RPC service. If all Atlas liquidations fail, the Atlas smart contracts ensure that the standard feed update is still processed in the same transaction, so the consumer protocol can fall back immediately to non‐auction liquidations.

DappControl

The DAppControl contract is an application-specific module where developers define functions that will execute at specific stages during the Atlas transaction. The contract also contains app-specific settings. These functions and settings are referenced by the Atlas smart contract during execution.

Atlas Transaction Structure

This will provide the flow of an Atlas transaction in order, with some details specific to RedStone OEV. 

1. **PreOps() Hook**: The implementation of this hook is defined in the OEV DappControl, and is used to perform validation of the transaction and the data feed update.
2. **UserOperation() Hook**: The implementation of this hook is defined in the OEV DappControl, and is used to perform the data feed update.
3. **PreSolver() Hook**: This hook is used for OEV v2 to modify the risk parameters on the application based on the given Solver bid.
4. **SolverOperations**: SolverOperations contain all of the data necessary to call out to the liquidators custom contract, and execute arbitrary functionality for the liquidator.
5. **PostSolver() Hook**: This hook is unused for OEV services.
6. **AllocateValue() Hook**: The implementation of this hook is defined in the OEV DappControl, and in OEV v1 is used to send the bid proceeds to the respective parties. In OEV v2 it will be un-used. 

These functions are executed by the Execution Environment via "delegatecall."

Auctioneer

The auctioneer for OEV is operated by Fastlane. The auctioneer is responsible for the following:

- Multiplexing between the oracle and the liquidators. Receiving potential data feed updates from the oracle, broadcasting them to liquidators, and receiving the bids + liquidations in the form of SolverOperations.
- Filtering and selecting the SolverOperations which will settle on-chain.
- Signing a DAppOperation. A DappOperation links a user operation with its corresponding solver operations, ensuring they cannot be altered independently and guaranteeing the execution order of the solver operations.

Bundler

The bundler for OEV is also operated by Fastlane, with the oracle acting as a quasi-bundler. The Fastlane Bundler is responsible for taking the UserOp (containing the data feed update), the SolverOperations selected by the Auctioneer, and the DappOperation signed by the auctioneer; and using these as inputs to generate an Atlas EVM transaction calling the metacall() function that can be sent to the mempool. 

The oracle acts as a quasi-bundler because they receive the full transaction from Fastlane Bundler, simulate it to validate that the data feed update will be successful, and re-propagate the transaction to a mempool of their choosing for redundancy and further assurances without needing to trust Fastlane. If the transaction generated by the Fastlane Bundler is not valid or acceptable to the oracle, the oracle node will propagate a standard data feed update instead. 

Auction Trigger

OEV enables “push” data feeds to also respond to liquidator-triggered data feed updates coming from a low latency pull oracle. These OEV-triggered data feed updates occur between deviation thresholds and heartbeats. Each time the price changes off-chain in the pull oracle, this price is delivered to Fastlane and an OEV auction is hosted.

Fallback Mechanism

The first and most important point to stress is that the OEV process can only impact data feed timeliness by 200ms. This potential delay of 200ms is the sole new risk that consumers of these data feeds take on. An important note regarding this is that OEV auctions are triggered upon every off-chain price deviation, meaning auctions are triggered in-between deviation thresholds. In many cases, this will enable lower latency data feed updates than standard data feeds, and may also work to offset the 200ms delay needed to host the auction. 

After triggering an auction, oracle nodes initiate a timeout that lasts 200ms. If this timeout is hit without a valid auction response from Fastlane containing liquidations, then oracle nodes  propagate a standard data feed update transaction. This data feed update is immediately available to the protocol, and standard (non-auction based) liquidations can occur immediately via the regular liquidation function. 

# Avon LAS Implementation

All references to “Auction Contract” are referencing a new Atlas DappControl implementation designed for Avon LAS.

### How It Works

From a high-level this mechanism is replacing gas-price priority for Avon liquidations with a new ordering rule. Example ordering of liquidators within a single auction transaction:

1. Liquidator A: 1% bonus.
2. Liquidator C: 1.5% bonus.
3. Liquidator B: 2% bonus.

Liquidators place bids off-chain in the form of the liquidation bonus that would be acceptable to them. These bids are then gathered by the off-chain auctioneer, and ordered by lowest liquidation bonus bids first. The auction contract on-chain then executes each liquidator in that pre-defined order; and prior to each liquidator executing, the auction contract modifies the liquidation bonus within the Avon Pool to that given liquidators bid. Auction-driven liquidation bonuses are effective immediately but persist only for a single transaction. Importantly, if the auction service fails in any way, the **standard liquidation path remains available in the same block** at the persistent bonus.

When an Avon Pool integrated with LAS is processing a liquidation, the `AvonPool` reads from local storage to determine if the Auction Contract has provided a valid auction-based liquidation bonus for the given transaction. If a valid auction-based liquidation bonus exists, the `AvonPool` will use this dynamic liquidation bonus in both the `SOFT_RANGE` and `HARD_RANGE` calculations to determine the effective liquidation bonus to offer to the current liquidator.

### Auction Priority Mechanisms

This section will outline exactly how Avon LAS auctions are awarded priority to liquidations on Avon:

1. Backrunning oracle updates in the same way as OEV currently operates.
2. Strategy managers can also provide liquidations that occur via the Auction Contract with a slightly earlier liquidation threshold than everyone else (maximum of 10bps), just enough to give the auction liquidations priority to liquidations triggered by interest accrual. This priority only applies to `SOFT_RANGE` liquidations. 

### Data Feed Requirements

This service can build seamlessly on existing oracle data feeds implementations by providing each `AvonPool` with it’s own unique data feed. Each `AvonPool` must only read from their own unique data feed. Each `AvonPool` will also require a unique Auction Contract that will be authorized as an updater only for this unique data feed, and only added as an authorized updater of the liquidation bonus for the given `AvonPool` associated with the data feed. This results in successfully isolating auctions triggered by an ETH/USD feed that cause liquidations on both an ETH/USDC pool and an ETH/BTC pool; or isolating auctions between an ETH/USD pool operated by Curator A and an ETH/USD pool operated by Curator B. 

### Use of MultipleSuccessfulSolvers Configuration in Atlas

Every SolverOp included in the Atlas transaction will have a chance to execute. Prior to the execution of each SolverOp, the preSolver hook will run and update the applications offered liquidation bonus to the bid offered by the liquidator. If one of the liquidator’s execution fails, the smart contract catches this failure and executes the next liquidator.

### Auctioneer Implementation

The off-chain auctioneer infrastructure will constantly host auctions on a defined cadence such as once per block, rather than hosting auctions whenever the oracle provides a new price.

### Transient Risk Parameters

The dynamic liquidation bonus set by the Auction Contract within an `AvonPool` lives within transient storage. Using transient storage enables the EVM to natively guarantee that the dynamic liquidation bonus will revert to the pool default as soon as the Auction Contract transaction has completed. This prevents the Auction Contract from leaving the liquidation bonus at a low value and this persisting, impacting non-auction liquidations. This ensures that any transaction outside of an Auction Contract transaction will be offered the default liquidation bonus.

# Appendix

## OEV Service Details

**Transaction-Inclusion**

The oracle, not a third‑party builder or liquidator, broadcasts the OEV transaction to any mempool (public or private). This removes external trust-assumptions and delay risk regarding inclusion of OEV transactions.

Execution Environment (EE)

The Auctioneer must have an Execution Environment (EE) instance for the specific DappControl. The Auctioneer address is used as a salt for the create2 deterministic deployment of the EE. The EE performs certain operations within Atlas using delegateCalls. The specific use of the EE for  OEV is documented in the DappControl section. 

Gas Accounting + atlETH

atlETH serves as a wrapped representation of the blockchain's native token within Atlas. While named "atlETH" for simplicity, it represents the native token of whichever blockchain Atlas is deployed on (e.g. ETH on Ethereum, POL on Polygon, etc).

In the Atlas protocol, while the bundler is fronting the overall gas cost for transactions, all solvers are required to cover at the least their respective gas costs. The atlETH token is facilitating this procedure. In order to participate in auctions, solvers must bond enough native token to cover the gas their operations will consume.

Atlas gas accounting also enforces that liquidators cannot consume more than their allocated gas. This and atlETH serve as forms of DoS protection.

**Details**: 

- If a solver fails to pay its bid within the allocated gas, their actions (liquidation) are reverted and the next solver in line is tried. The gas cost of a solver operation is subtracted from the solver’s escrowed balance regardless of whether they fail or succeed, and is paid to the transaction sender.
- The Atlas contract enforces per-operation gas limits, preventing one malicious liquidator from jeopardizing other liquidators, or the standard data feed update.
- To be considered eligible for inclusion in the array of Atlas SolverOperations, a solver must only “escrow” funds in advance to cover gas costs. This escrowed balance is used to atomically repay the upfront gas costs of the transaction back to the oracle operator who sent it.
- If all Atlas liquidation attempts fail, the data feed update will still be processed by Atlas, and available to the protocol without delay.

Auctioneer Filtering

Every OEV bidder is split into two tiers; a high-reputation tier, and a low-reputation tier. Any new bidder who joins will be immediately placed into the low-reputation tier. The top N bidders from each reputation tier are selected for on-chain auction settlement. These top bidders are then aggregated together and ordered by bid amount regardless of their reputation. This ensures a high bidding but low reputation solver can be ordered first, and has a fair shot at winning the auction.

Gas Price Selection

Fastlane is tasked with selecting a gas price for the Atlas transaction before the auction begins. This ensures that liquidators understand the gas cost they are responsible for covering prior to bidding. The Bundler must then adhere to this gas price when setting the tx.gasPrice. 

Prior to any deployment, Fastlane runs an analysis on historical block congestion and gas pricing to configure the gas price algorithm parameters for that given chain. This analysis encompasses:

- Percentage of blocks with > X% utilization.
- Gas prices required for inclusion in both congested and non-congested scenarios. Inclusion is measured using estimated gas consumption of Atlas transactions.
- Worst-case gas prices necessary for inclusion during highest measured congestion.
- Historical data on numbers of individual liquidations per block.
- Historical data on gas-consumption by liquidators.

Using this data we configure the following parameters such that based on historical data Atlas transactions would achieve 100% inclusion in the first block:

- metacall_gas_limit
- utilization_threshold (the threshold of block utilization that we consider to be congested)
- multiplier_high (the multiplier applied to recommended gas price in congestion)
- multiplier_low (the multiplier applied to recommended gas price when not congested)
- min_gwei
- max_gwei

Connecting as a Liquidator

- Connecting as a liquidator is permissionless, you simply start reading from a websocket and utilize the searcher SDK to submit bids.
- The only requirement from bidders is to escrow enough native token balance to cover a single transaction. There is no requirement to escrow any part of the bid amount, or requirement to escrow capital that may be slashed for mis-behaviour.

No Dependency on Private Mempools/RPCs

Atlas replaces the need for private mempools or RPCs such as MEV-Share. This ensures that:

- Operation ordering (i.e OEV liquidations directly preceding oracle updates) is respected without trusting anyone.
- There is no uptime reliance on centralized third party mempool services, and no ability to delay the data feeds or liquidations outside of the 200ms auction timeout.

Security Incident Monitoring and Management

24/7 monitoring is in place, and security incidents are reported to a shared channel with clients. This is implemented by a pager-duty system with engineers constantly on call, and being alerted to a number of potential issues or events within the system.

Emergency Controls

OEV uniquely enables consumers to turn OEV off without changing the data feed contract. The oracle themselves are in control of turning off the OEV mechanism, and the ability to trigger the oracle to do this can be implemented in any way deemed best. At any time, the data feed consumer can alert the oracle, and OEV can be turned off immediately, leaving the protocol protocol in a default state without any delays to data feeds.

Blockspace Usage

Atlas has a fixed cost of ~250k gas used for on-chain validation. Settling the auction on-chain also presents the tradeoff of potentially higher gas usage based on the number of SolverOperations that execute. Blockspace usage is mitigated in a couple ways:

- A reputation system is used by Fastlane to filter bids and only allow a certain number of low-reputation bidders to settle on-chain.
- Fastlane dynamically adjusts the number of solvers that settle on-chain based on the previous block congestion.

Finally, if the Atlas transaction is not included in the very first block, the oracle will propagate a standard data feed update instead. 

## DappControl as a Whitelisted Data Feed Updater

The oracle, as part of the integration process, must whitelist the OEV DAppControl smart contract as a whitelisted updater of the oracle data feed. Only a single entity will be able to trigger a data feed update via this DAppControl. This entity will be the assigned Atlas auctioneer EOA, who is also the assigned Atlas UserOp generator EOA. Note that multiple Bundler EOAs are allowed to be the tx.origin of a transaction that performs a data feed update via the DAppControl for performance reasons, but doing so always requires a valid signed UserOp and DAppOp pairing from the Auctioneer EOA. Furthermore, the Auctioneer EOA assigns a single Bundler the rights to do the data feed update transaction on a per-transaction basis, and no other party can perform that given data feed update.  

### **Implementation Details**

- Upon deployment of the OEV DAppControl, the governor EOA of the DAppControl must call setAuthorizedUserOpSigner() on the DAppControl, and provide the address of a single EOA that is allowed to generate UserOps that update the RedStone data feed. During the setAuthorizedUserOpSigner() function call, the DAppControl will query Atlas, and receive the ExecutionEnvironment address that is matched to the provided UserOp signer and the given DAppControl. Any data feed updates via the DAppControl will validate that the msg.sender is this ExecutionEnvironment.
- Upon deployment of OEV DAppControl, the governor EOA of the DAppControl must call AtlasVerification.initializeGovernance() for the given OEV DAppControl. The governor EOA must then also call AtlasVerification.addSignatory() for the given OEV DAppControl, and provide the EOA of the Atlas auctioneer. By setting userAuctioneer to false in the OEV DAppControl config, Atlas Verification will now validate that any calls to update the data feed via the DAppControl must include a DAppOp signed by the EOA of the Atlas auctioneer.
- Additional validations are in the preOps hook of the DAppControl, and validate that userOp.from is the authorizedUserOpSigner.