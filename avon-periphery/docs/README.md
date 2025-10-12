# Avon Protocol

Avon Protocol is a decentralized lending platform that enables efficient capital allocation through two main components: isolated lending pools and multi-pool liquidity aggregation vaults. The protocol combines the security of isolated markets with the capital efficiency of shared liquidity, providing users with both lending and borrowing capabilities across multiple asset pairs.

[AvonPool](./src/pool/AvonPool.sol) implements the ERC-4626 standard with additional borrowing functionality, while [Vault](./src/vault/Vault.sol) manages liquidity allocation across multiple pools using sophisticated queue systems. Both components feature governance through timelock controllers and comprehensive access control mechanisms.

## Overview

### Pool System

Pools are isolated lending markets where users can deposit assets to earn yield and borrow against collateral. Each pool operates independently with its own risk parameters, interest rate models, and liquidation mechanisms.

The pool architecture uses a modular design with library-based extensions that handle specific functionality:
- Interest accrual using continuous compounding with ABDKMath64x64 for precision
- Collateral management with position safety checks
- Liquidation mechanisms with configurable bonuses and bad debt handling
- Flash loan functionality with fee distribution
- Integration with external orderbooks for liquidity optimization

Users can deposit loan tokens to earn interest from borrowers, or deposit collateral to borrow loan tokens. All positions are tracked individually and subject to loan-to-value (LTV) ratio limits determined by oracle prices.

### Vault System

Vaults aggregate liquidity across multiple pools to optimize capital allocation and provide enhanced yields for depositors. The vault system uses circular priority queues to manage deposits and withdrawals efficiently.

When users deposit into a vault, their assets are automatically allocated across multiple pools according to predefined priorities and available capacity. The vault manager can configure allocation strategies and fee structures, while timelock mechanisms protect users from sudden configuration changes.

Vaults earn management fees and performance fees, distributed to designated recipients. The queue system ensures fair processing of deposits and withdrawals while maintaining optimal capital efficiency across the underlying pools.

### Interest Rate Models

The protocol uses a linear kink interest rate model where rates increase gradually with utilization until reaching a "kink" point, after which they rise more sharply to discourage excessive borrowing.

Interest accrual happens continuously using the exponential function `e^(r*t)` implemented with ABDKMath64x64 for high precision arithmetic. This approach provides smooth interest accumulation without the rounding errors common in simpler implementations.

Rate calculations consider total supplied assets versus total borrowed assets to determine utilization, with automatic updates triggered by any pool interaction. Both manager and protocol fees are calculated as shares of the accrued interest.

### Liquidation Mechanism

The liquidation system protects lenders by ensuring undercollateralized positions can be liquidated efficiently. The protocol implements a two-tier liquidation bonus system:

**Soft Liquidation Range**: When positions become slightly undercollateralized (within the configured soft range), liquidators receive a flat bonus percentage for liquidating the position. The amount of collateral that can be seized is capped to prevent excessive liquidations.

**Hard Liquidation Range**: For positions that are severely undercollateralized, the liquidation bonus increases quadratically with the health factor, providing stronger incentives for liquidators while maximizing collateral recovery.

Bad debt is handled automatically when positions cannot be fully liquidated due to insufficient collateral value. The protocol writes off the remaining debt and adjusts pool accounting accordingly.

### Oracle Integration

Price feeds are essential for determining collateral values and position health. The protocol integrates with Redstone-compatible oracles with built-in staleness detection and price validation.

Oracle prices are adjusted for token decimals and scaled appropriately for internal calculations. The system includes safety checks for negative prices and stale data, reverting transactions when price feeds become unreliable.

Collateral-to-loan price conversion accounts for decimal differences between tokens, ensuring accurate position valuations across different asset pairs.

### Flash Loans

Flash loans allow users to borrow assets temporarily within a single transaction, useful for arbitrage, liquidations, and other sophisticated DeFi strategies.

The implementation follows the standard pattern: transfer assets to the borrower, execute a callback, then verify repayment with fees. Flash loan fees are split between managers and the protocol according to configured percentages.

Security measures include reentrancy protection and validation that sufficient assets are returned to cover the loan plus fees. The callback interface allows borrowers to execute arbitrary logic while maintaining atomicity.

## Governance and Access Control

### Timelock Controllers

Both pools and vaults inherit from OpenZeppelin's TimelockController, providing governance capabilities with mandatory delays for sensitive operations. This ensures users have time to exit positions before unfavorable changes take effect.

The timelock system uses three roles:
- **Proposer**: Can schedule operations for future execution
- **Executor**: Can execute operations after the delay period
- **Canceller**: Can cancel pending operations

Critical operations like fee changes, parameter updates, and manager changes require timelock approval, while emergency functions like pausing can be executed immediately by authorized addresses.

### Permission System

User permissions are managed through a flexible authorization system where protocol owners can grant permission for other addresses to act on their behalf. This enables sophisticated integrations while maintaining security.

The orderbook contract automatically has permission to execute operations on behalf of users, facilitating integration with external market-making systems. Users can also grant permissions to smart contracts or other addresses as needed.

Permission checks are enforced at the protocol level, ensuring unauthorized users cannot manipulate positions they don't own or haven't been granted access to.

### Factory Contracts

Pool and vault deployment is managed through factory contracts that ensure proper initialization and maintain registries of valid instances. Only approved managers can deploy new pools or vaults through the factories.

The factories integrate with orderbook factories to ensure proper cross-system compatibility and maintain security standards across all deployed instances.

## Caps and Risk Management

The protocol implements comprehensive risk management through configurable caps on deposits and borrowing. These limits help prevent excessive concentration of assets and maintain healthy market conditions.

Deposit caps limit the maximum amount that can be supplied to a pool, while borrow caps limit total borrowing. Both caps can be set to zero to disable limits entirely, or adjusted by governance to respond to changing market conditions.

The caps system is enforced at the protocol level across all entry points, preventing users from bypassing limits through different function calls or contract interactions.

## Virtual Shares and Manipulation Prevention

To prevent share price manipulation attacks, the protocol implements virtual shares that add a small offset to total supply and assets calculations. This approach prevents attackers from inflating share prices through large donations or early depositor advantages.

The virtual shares mechanism ensures that share prices remain stable and predictable, protecting late depositors from unfair dilution and maintaining consistent pricing across all users.

Share conversions use careful rounding rules that favor the protocol in edge cases, preventing users from extracting value through rounding manipulation while maintaining fair treatment for normal operations.

## Technical Implementation Details

### Pool Storage Architecture

The protocol uses a diamond-pattern storage system where all pool state is managed through a single storage slot accessed via `PoolStorage._state()`. This approach provides gas efficiency while maintaining clean separation of concerns across different functional modules.

Pool state includes configuration parameters, token addresses, fee structures, liquidation parameters, and individual position mappings. The storage pattern ensures consistent state access across all pool extensions while preventing storage conflicts.

### Modular Extension System

Pool functionality is implemented through library-based extensions that operate on the shared storage. This modular approach enhances code maintainability and allows for focused testing of individual components:

- **AccrueInterest**: Handles continuous compounding interest calculations using the exponential function
- **BorrowRepay**: Manages borrowing and repayment logic with share-based accounting
- **CollateralManagement**: Controls collateral deposits and withdrawals with safety checks
- **Liquidation**: Implements the two-tier liquidation system with bonus calculations
- **FlashLoan**: Provides flash loan functionality with callback mechanisms
- **PositionGuard**: Monitors position health and manages user permissions
- **UpdateOrders**: Integrates with external orderbooks for liquidity optimization

### Share-Based Accounting

Both pools and vaults use share-based accounting to track user positions and handle fee distribution efficiently. Shares represent proportional ownership of the underlying assets and automatically adjust as interest accrues or fees are collected.

The share conversion uses virtual shares to prevent manipulation attacks where early depositors could artificially inflate share prices. Virtual assets and shares are added to calculations to ensure stable pricing across all market conditions.

Share rounding is implemented to favor the protocol in edge cases, preventing users from extracting value through precision manipulation while maintaining fair treatment for normal operations.

### Queue System Implementation

Vaults implement circular priority queues for managing deposits and withdrawals across multiple pools. The queue system processes entries in order while respecting capacity limits and allocation priorities.

Each queue entry specifies a pool, target amount, and remaining allocation. The system processes entries sequentially, allocating available funds according to priorities and updating remaining amounts as capacity becomes available.

The circular nature allows efficient processing by maintaining head pointers and avoiding array shifts. Queue manipulation is restricted to vault managers through access control mechanisms.

## Security Considerations

### Oracle Dependency and Price Manipulation

The protocol's liquidation system depends heavily on oracle price feeds to determine collateral values and position health. Price feed staleness is detected through timestamp checks, and negative prices are rejected to prevent manipulation.

Oracle prices are scaled and adjusted for token decimals to ensure accurate valuations across different asset pairs. The system includes safety margins and liquidation bonuses to account for potential price volatility and slippage during liquidations.

### Interest Rate Edge Cases

The continuous compounding interest model using exponential calculations could potentially overflow with extreme interest rates or time periods. The implementation includes bounds checking and uses the ABDKMath64x64 library for high precision arithmetic.

Interest accrual is triggered by pool interactions, ensuring rates remain current and preventing manipulation through timing attacks. The system handles edge cases like zero utilization and maximum utilization gracefully.

### Liquidation Incentives and MEV

The liquidation bonus structure is designed to incentivize timely liquidations while preventing excessive value extraction. The quadratic bonus system provides increasing rewards for liquidating unhealthier positions.

Maximum extractable value (MEV) opportunities exist in liquidations, particularly during market volatility. The protocol's liquidation parameters are tuned to balance liquidator incentives with borrower protection.

## Developers

The protocol is implemented in Solidity 0.8.28 and uses Foundry for compilation, testing, and deployment. The codebase follows OpenZeppelin security standards and implements comprehensive test coverage.

Key dependencies include:
- OpenZeppelin contracts for standard implementations and security utilities
- ABDKMath64x64 for high precision mathematical operations
- ERC-4626 standard for vault implementations

All contracts are designed to be immutable after deployment, with governance functions handled through timelock controllers rather than upgrade mechanisms.