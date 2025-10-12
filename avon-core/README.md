# Avon Protocol

Avon Protocol is a decentralized orderbook system that aggregates liquidity from isolated lending pools and matches borrowers with lenders using augmented red-black trees for efficient price discovery and order matching.

## Architecture

### Core Components

The **Orderbook** maintains separate order books for lenders (pools) and borrowers using red-black trees with composite keys combining interest rate and LTV. This design enables efficient sorting and matching of orders while preserving the distinct characteristics of lending and borrowing requirements.

**Pool Integration** allows external lending pools implementing `IPoolImplementation` to register their available liquidity as orders in the system. Borrowers can then place market or limit orders that get matched against this aggregated pool liquidity, creating an efficient capital allocation mechanism.

### Order Types

**Lender Orders** represent pool liquidity and are sorted by lowest interest rate first, then highest LTV to prioritize the most attractive terms for borrowers. These orders are batch inserted by pools as their liquidity conditions change and are automatically cancelled when pools are removed from the system to maintain data integrity.

**Borrower Orders** come in two varieties: market orders for immediate execution against the best available rates, and limit orders that are placed in the borrower tree and executed by authorized keepers when market conditions become favorable. The system sorts borrower orders by highest interest rate first, then lowest LTV, reflecting borrowers' willingness to pay and their conservative borrowing preferences.

### Key Data Structure

The protocol uses an **Augmented Red-Black Tree** that packs composite keys with interest rate data in bits 160-223 and LTV data in bits 96-159 within a single 256-bit key. This structure supports heap storage where multiple entries per key are organized to prioritize larger amounts and earlier timestamps. The implementation provides O(log n) complexity for insertion, matching, and removal operations, ensuring scalable performance as the orderbook grows.
## Order Matching

**Market Orders** operate by traversing the lender tree starting from the lowest available rates, aggregating liquidity across multiple pools until the requested amount is filled or available liquidity is exhausted. The entire matching and execution process happens atomically to ensure consistency and prevent partial failures that could leave the system in an inconsistent state.

**Limit Orders** require borrowers to deposit the full collateral amount upfront, after which authorized keepers monitor market conditions and execute the orders when favorable terms become available. Any excess collateral beyond what's actually needed for the executed transaction is automatically refunded to the borrower, ensuring capital efficiency.

The system operates under several important **constraints** to maintain safety and performance. LTV ratios are restricted to a range between 50% and 99% to balance capital efficiency with risk management. Gas consumption is controlled by limiting orders to a maximum of 30 pools per execution to prevent out-of-gas scenarios. Additionally, all borrowing operations must include a minimum 1% collateral buffer above the required LTV to provide a safety margin against immediate liquidation due to minor price movements.

## Access Control & Roles

The **OrderbookFactory** serves as the central deployment and management hub, creating exactly one orderbook per unique loan/collateral token pair to ensure proper market segmentation. It maintains a whitelist of approved Interest Rate Models that pools must use to participate in the system, providing an additional layer of security and standardization. The factory also manages the authorization of various role-based actors including pool managers, pool factories, and keepers.

The protocol operates with four distinct **roles** that each serve specific functions. **Pool Managers** have the authority to whitelist pools for participation in the orderbook, acting as curators who ensure only legitimate pools can contribute liquidity. 
**Pool Factories** are responsible for validating pool authenticity through approved deployment mechanisms, preventing malicious or improperly configured pools from entering the system. 
**Keepers** are authorized entities that execute limit orders on behalf of borrowers when market conditions are favorable, providing essential automation services. Finally, 
**Owners** maintain ultimate control over protocol configuration and can invoke emergency functions when necessary to protect the system's integrity.

## Security Mechanisms

The protocol implements comprehensive **access control** through a multi-layered approach that includes pool whitelisting combined with Interest Rate Model and factory validation. Role-based permissions govern all critical operations, ensuring that only authorized entities can perform sensitive functions. Additionally, ReentrancyGuard protection is applied to all state-changing functions to prevent reentrancy attacks that could manipulate the system's state during execution.

**Collateral safety** is ensured through several mechanisms designed to protect both borrowers and lenders. Limit orders require upfront collateral deposits, eliminating the risk of execution failure due to insufficient collateral. The system enforces minimum buffer requirements above the base LTV to provide protection against minor price movements that could immediately trigger liquidations. When orders are executed with less collateral than initially deposited, the excess amount is automatically refunded to maintain capital efficiency.

**Gas optimization** strategies prevent denial-of-service attacks and ensure reliable execution under various network conditions. Pool operations and order matching use batch processing to minimize transaction costs and improve efficiency. The system limits each order to a maximum of 30 pools to prevent gas exhaustion scenarios that could cause transaction failures. Matching loops include minimum gas checks to ensure sufficient gas remains for transaction completion.

**Emergency controls** provide circuit breakers and recovery mechanisms for various failure scenarios. The owner can pause operations when threats are detected, providing time to assess and address issues without compromising existing positions. Pool removal functionality includes automatic cleanup of associated orders to maintain data consistency. For pools that become unresponsive, force removal capabilities allow the system to maintain operational integrity even when external dependencies fail.

## Security Considerations

### Oracle Dependencies

While the orderbook itself doesn't directly use oracles, integrated pools typically depend on price feeds for collateral valuation to determine position health, liquidation triggers to identify underwater positions, and LTV calculations to convert between different asset values. This creates an indirect dependency on oracle reliability and accuracy.

Risk mitigation occurs primarily at the pool level through oracle validation mechanisms, staleness checks, and fallback systems. The protocol also enforces conservative LTV limits to provide buffers against price volatility that could affect oracle-dependent calculations.

### MEV and Front-running

Potential attack vectors include order front-running where attackers observe pending orders and place competing orders to extract value, sandwich attacks that manipulate order execution through strategic transaction ordering, and keeper competition where multiple keepers compete for profitable limit order execution opportunities.

The protocol implements several mitigation strategies to reduce MEV extraction. Time-based ordering ensures the heap prioritizes earlier timestamps for orders with identical conditions, providing fair execution order. Batch processing allows multiple orders to be processed together, reducing opportunities for MEV extraction between individual transactions. Additionally, the system uses a limited set of authorized keepers rather than open competition, which reduces harmful competitive dynamics.

### Pool Integration Risks

Malicious pool attacks could involve pools reporting false liquidity amounts, failing to honor matched orders, or extracting excessive fees from users. The protocol mitigates these risks through pool whitelisting by authorized protocol managers, IRM validation requirements that ensure pools use approved interest rate models, and a pool factory verification system that validates pool authenticity.

Pool pause and failure scenarios include pools becoming paused mid-transaction, failing to fulfill borrow requests, or becoming insolvent. The system handles these situations by skipping paused pools during aggregation, implementing graceful failure handling in batch operations, and providing pool removal mechanisms for failed pools to maintain overall system integrity.

### Economic Security

Collateral buffer requirements include a minimum 1% buffer above LTV requirements to prevent edge-case liquidations that could occur due to minor price movements or calculation precision issues. This buffer provides cushion against market volatility and reduces the risk of immediate liquidation after borrowing, protecting borrowers from unfavorable execution conditions.

Fee economics are designed to align incentives across all participants. Flat fees provide consistent keeper compensation that encourages reliable order execution services. Protocol fee collection supports ongoing development and maintenance of the system. The fixed fee structure also provides predictable cost management for users, enabling better financial planning and reducing uncertainty about transaction costs.

## Operational Procedures

### Pool Onboarding

The pool onboarding process follows a structured sequence to ensure security and compatibility. First, the Interest Rate Model must be whitelisted by the protocol owner to establish that the pool uses approved rate calculation methods. Next, the pool factory must be approved for pool validation to ensure pools are deployed through trusted mechanisms. The pool manager must then be granted permission to whitelist pools, providing a human verification layer. The pool itself must be deployed through an approved factory using a valid IRM to meet technical requirements. Finally, the pool manager calls `whitelistPool` with proper validation to complete the integration process.

### Order Management

#### Pool Order Updates
```solidity
// Pools batch update their orders as liquidity changes
uint64[] memory rates = [100, 200, 300]; // Annual rates per second
uint256[] memory amounts = [1000e18, 500e18, 250e18]; // Available amounts
pool.batchInsertOrder(rates, amounts);
```

#### Borrower Order Placement
```solidity
// Market order - immediate execution
orderbook.matchMarketBorrowOrder(
    1000e18,      // amount to borrow  
    950e18,       // minimum expected
    0.01e18,      // 1% collateral buffer
    0,            // rate (0 = market rate)
    0             // ltv (0 = minimum LTV)
);

// Limit order - future execution
orderbook.insertLimitBorrowOrder(
    150,          // rate per second
    0.8e18,       // 80% LTV
    1000e18,      // amount to borrow
    950e18,       // minimum expected
    0.05e18,      // 5% collateral buffer
    collateralRequired // calculated collateral amount
);
```

### Keeper Operations

Keepers monitor the borrower order book and execute profitable limit orders:

```solidity
// Keepers execute limit orders when conditions are favorable
orderbook.matchLimitBorrowOrder(
    borrowerAddress,  // borrower whose order to execute
    orderIndex       // index in borrower's order array
);
```

### Emergency Procedures

#### Protocol Pause
```solidity
// Owner can pause all orderbook operations
orderbook.pause();

// Resume operations when safe
orderbook.unpause(); 
```

#### Pool Removal
```solidity
// Remove problematic pool (cancels all orders)
orderbook.removePool(poolAddress);

// Force remove with manual LTV (if pool is non-responsive)
orderbook.forceRemovePool(poolAddress, lastKnownLTV);
```

## Development Environment

### Build and Testing

The protocol uses Foundry for development:

```bash
# Install dependencies
forge install

# Compile contracts  
forge build

# Run tests
forge test

# Run specific test
forge test --match-contract OrderbookTest

# Generate gas reports
forge test --gas-report
```

### Key Dependencies

- **OpenZeppelin**: Access control, security utilities, token standards
- **Foundry**: Development framework and testing utilities  
- **Custom Libraries**: Augmented red-black trees, mathematical operations

### Contract Verification

All contracts are designed for verification on block explorers:
- **Immutable Deployments**: No proxy patterns or upgradeable logic
- **Standard Interfaces**: Implements common standards where applicable
- **Clear Documentation**: Comprehensive NatSpec documentation

This implementation provides a robust, gas-efficient orderbook system for decentralized lending markets while maintaining the security benefits of isolated pool architectures.

## License

This project is dual-licensed:

- **Primary License**: Business Source License 1.1 (BSL 1.1) - See [LICENSE](LICENSE) for details
  - Licensed under BSL 1.1 until the Change Date (2029-10-15)
  - After the Change Date, automatically converts to GNU General Public License v2.0 or later
  - Licensor: Avon Tech Ltd.

- **MIT Licensed Components**: Some components may be available under MIT License - See [LICENCE-MIT](LICENCE-MIT) for details
  - Applies to specific files or components where explicitly indicated
  - Provides more permissive usage rights for designated components

Please review both license files to understand the terms and conditions that apply to different parts of this codebase.