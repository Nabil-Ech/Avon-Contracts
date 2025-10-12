# Avon Core - Production Dependencies and Setup Requirements

## Overview
This document outlines all external dependencies, parameters, and setup requirements needed to deploy and operate the Avon Core orderbook-based lending protocol in production.

## Build System Dependencies

### Foundry Framework
- **Solidity Version**: `0.8.28` (exact version required)
- **Foundry Installation**: Required for compilation, testing, and deployment
- **Configuration**: 
  - Via IR compilation enabled (`via_ir = true`)
  - Optimizer enabled
  - Auto-detect remappings enabled

### Node.js Dependencies
- **Node.js**: Required for package management and build scripts
- **NPM Scripts**:
  - `build`: `forge build && forge fmt`
  - `test`: `forge test` 
  - `coverage`: `forge coverage --via-ir --ir-minimum`

## External Contract Dependencies

### OpenZeppelin Contracts (v5.x)
**Location**: `lib/openzeppelin-contracts/`
**Required Contracts**:
- `@openzeppelin/contracts/access/Ownable2Step.sol`
- `@openzeppelin/contracts/token/ERC20/IERC20.sol`
- `@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol`
- `@openzeppelin/contracts/utils/ReentrancyGuard.sol`
- `@openzeppelin/contracts/utils/Pausable.sol`
- `@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol` (for Pool contracts)

### Forge Standard Library
**Location**: `lib/forge-std/`
**Purpose**: Testing and development utilities

### Pyth Network SDK (Optional/Future)
**Note**: Referenced in remappings but not currently used in code
- `@pythnetwork/pyth-sdk-solidity/` - May be for future price oracle integration

## Core Protocol Parameters

### OrderbookFactory Configuration

#### Required Initial Parameters
1. **Fee Recipient Address** (`address _feeRecipient`)
   - Must be a valid non-zero address
   - Receives protocol fees
   - Can be updated by owner

#### Role-Based Access Control
1. **Owner** (Deployer)
   - Controls all factory operations
   - Can enable/disable IRMs
   - Can set pool managers and factories
   - Can create new orderbooks

2. **Interest Rate Models (IRMs)**
   - Must be pre-enabled by owner before pool creation
   - External contracts implementing interest rate calculations
   - Mapping: `isIRMEnabled[address] => bool`

3. **Pool Managers**
   - Authorized addresses that can create and manage pools
   - Mapping: `isPoolManager[address] => bool`

4. **Pool Factories** 
   - Authorized factory contracts for pool creation
   - Mapping: `isPoolFactory[address] => bool`

5. **Keepers**
   - Authorized addresses for maintenance operations
   - Mapping: `isKeeper[address] => bool`

### Orderbook Configuration

#### Required Parameters for Creation
1. **Loan Token Address** (`address _loanToken`)
   - Must implement IERC20 interface
   - The asset being borrowed/lent

2. **Collateral Token Address** (`address _collateralToken`) 
   - Must implement IERC20 interface
   - The asset used as collateral

3. **Fee Recipient Address** (`address _feeRecipient`)
   - Address receiving matching fees
   - Can be different from factory fee recipient

#### Orderbook Configuration Parameters
- **Flat Matching Fee** (`uint256 flatMatchingFee`)
  - Fee in loan token units for order matching
  - Default: 0 (can be set by owner)

#### Operational Limits
- **MAX_LIMIT_ORDERS**: 10 per borrower
- **MAX_MATCHED_ORDER**: 30 (hardcoded limit for order matching)

## External Interface Requirements

### Pool Integration
The protocol expects external Pool contracts to implement:

#### Core ERC4626 Functions
- `deposit(uint256 assets, address receiver) returns (uint256 shares)`
- `mint(uint256 shares, address receiver) returns (uint256 assets)`
- `withdraw(uint256 assets, address receiver, address owner) returns (uint256 shares)`
- `redeem(uint256 shares, address receiver, address owner) returns (uint256 assets)`

#### Lending/Borrowing Functions
- `borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, uint256 minAmountExpected)`
- `repay(uint256 assets, uint256 shares, address onBehalf)`

#### Collateral Management
- `depositCollateral(uint256 assets, address onBehalf)`
- `withdrawCollateral(uint256 assets, address onBehalf, address receiver)`

#### Risk Management
- `liquidate(address borrower, uint256 assets, uint256 shares)`
- `previewBorrow(address borrower, uint256 assets, uint256 collateralBuffer)`

#### Configuration
- `getIRM() returns (address)`
- `getLTV() returns (uint256)`
- `pausePool(bool pause)`

### Interest Rate Model (IRM) Requirements
External IRM contracts must implement rate calculation functions compatible with:
- Pool utilization ratios
- Time-based interest accrual
- Dynamic rate adjustments

## Token Requirements

### ERC20 Compliance
All tokens (loan and collateral) must:
- Implement standard ERC20 interface
- Have proper `transfer` and `transferFrom` functions
- Support SafeERC20 wrapper functions
- Have consistent decimals handling

### Token Permissions
- Orderbook contracts require `transferFrom` approval for collateral handling
- Pool contracts require approval for asset transfers

## Network and Infrastructure Requirements

### Blockchain Network
- **EVM-Compatible Network**: Ethereum mainnet or compatible L2s
- **Gas Considerations**: 
  - Complex order matching operations
  - Red-black tree operations are gas-intensive
  - Consider gas limits for batch operations

### Deployment Sequence

1. **Deploy OrderbookFactory**
   ```solidity
   constructor(address _feeRecipient)
   ```

2. **Configure Factory**
   - Enable required IRMs: `setIrm(address irm, bool status)`
   - Set pool managers: `setPoolManager(address manager, bool status)`
   - Set pool factories: `setPoolFactory(address factory, bool status)`
   - Set keepers: `setKeeper(address keeper, bool status)`

3. **Deploy Orderbooks**
   ```solidity
   createOrderbook(address _loanToken, address _collateralToken, address _feeRecipient)
   ```

4. **Pool Integration**
   - Pools must be whitelisted: `whitelistPool(address pool)`
   - Pools must use enabled IRMs
   - Pool managers must be authorized

## Security Considerations

### Access Control
- Multi-signature recommended for owner operations
- Proper validation of all external addresses
- Role separation for different operational functions

### Economic Parameters
- **Collateral Buffers**: Required for borrower protection
- **LTV Ratios**: Defined per pool, must be reasonable
- **Interest Rates**: Validated through enabled IRMs only

### Emergency Controls
- **Pausable Functionality**: Available on Orderbook contracts
- **Owner Controls**: Can pause operations and update critical parameters

## Monitoring and Maintenance

### Required Monitoring
1. **Order Matching Performance**: Track matching efficiency
2. **Gas Usage**: Monitor for optimization opportunities  
3. **Liquidation Events**: Ensure healthy protocol operation
4. **Fee Collection**: Track protocol revenue

### Maintenance Operations
1. **Keeper Operations**: Automated maintenance tasks
2. **Parameter Updates**: Interest rates, fees, limits
3. **Pool Management**: Whitelist/delist pools as needed

## Licensing

### License Structure
- **Core Contracts**: Business Source License 1.1 (BUSL-1.1)
  - `OrderbookFactory.sol`
  - `Orderbook.sol` 
  - `OrderbookLib.sol`
- **Red-Black Tree Library**: MIT License (from Vectorized/solady)
- **Interfaces and Other Libraries**: GPL-2.0 or later

### Production Usage
- BUSL-1.1 license may restrict commercial usage
- Review license terms before production deployment
- Consider licensing implications for integrations

## Integration Checklist

### Pre-Deployment
- [ ] Deploy and verify all required external dependencies
- [ ] Prepare IRM contracts and get them audited
- [ ] Set up multi-signature wallet for owner operations
- [ ] Configure monitoring and alerting systems
- [ ] Test all integration points with mock contracts

### Deployment
- [ ] Deploy OrderbookFactory with proper fee recipient
- [ ] Enable required IRMs
- [ ] Set authorized pool managers and factories
- [ ] Deploy orderbooks for required token pairs
- [ ] Configure flat matching fees if needed
- [ ] Set up keeper accounts for maintenance

### Post-Deployment
- [ ] Verify all contract interactions work correctly
- [ ] Monitor initial operations closely
- [ ] Set up automated monitoring for key metrics
- [ ] Establish incident response procedures
- [ ] Regular security audits and updates

## Additional Notes

### Order Matching Mechanics
- Maximum 30 orders can be matched per transaction
- Market orders execute immediately at best available rates
- Limit orders are stored until favorable conditions
- Red-black tree structure ensures efficient order management

### Collateral Management
- Borrowers provide collateral upfront for limit orders
- Collateral is held in escrow by the orderbook
- Liquidations are handled at the pool level
- Health factors must be maintained for active positions

This documentation should be updated as the protocol evolves and new dependencies or requirements are identified.