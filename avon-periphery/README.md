# Avon Protocol

Avon is a decentralized lending and borrowing protocol that combines capital-efficient pools with sophisticated liquidity management.

## Protocol Overview

Avon implements an ERC4626-compliant lending protocol with the following key features:

- Isolated lending pools with customizable risk parameters
- Advanced yield strategies through a vault system
- Flexible collateral management
- Automated interest rate models
- Flash loan capabilities
- Orderbook integration for optimal liquidity allocation

## Architecture

The protocol consists of three primary components:

1. **Lending Pools**: Isolated risk environments where users can supply assets, borrow against collateral, and earn yield
2. **Vaults**: Liquidity management system that allocates capital across pools based on yield optimization
3. **Orderbook**: External component that facilitates liquidity matching between pools

## Core Contracts

### Pool System
- `AvonPool.sol`: Main pool contract implementing ERC4626 with borrowing capabilities
- `PoolStorage.sol`: Diamond-pattern storage library for pool state
- Pool Extensions:
  - `AccrueInterest.sol`: Interest accrual using Taylor series approximation
  - `BorrowRepay.sol`: Borrow and repayment logic
  - `CollateralManagement.sol`: Deposit and withdrawal of collateral
  - `Liquidation.sol`: Position liquidation with customizable parameters
  - `FlashLoan.sol`: Flash loan functionality
  - `PositionGuard.sol`: Position health monitoring

### Vault System
- `Vault.sol`: ERC4626 vault that manages liquidity across multiple pools using a circular priority queue system
- Uses deposit and withdrawal queues to optimize capital allocation

### Factory Contracts
- `AvonPoolFactory.sol`: Deploys and validates pool instances
- `VaultFactory.sol`: Deploys and validates vault instances

### Libraries
- `SharesLib.sol`: Virtual shares implementation to prevent share price manipulation
- `LiquidityAllocator.sol`: Optimizes liquidity distribution across rates

## Risk Parameters

- LLTV (Liquidation Loan-To-Value): Configurable parameter that determines the maximum borrowing power
- Liquidation Incentives: Dynamic incentives based on position health
- Protocol Fees: Split between pool managers and protocol

## License

This repository is licensed under the Business Source License 1.1. See [`LICENCE`](./LICENCE) for full details.

