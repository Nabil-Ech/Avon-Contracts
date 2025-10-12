// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title IOracle
/// @author Avon Labs
/// @notice Interface that oracles used by Avon must implement.
/// @dev It is the user's responsibility to select pools with safe oracles.
interface IOracle {
    /**
     * @notice Returns the price of 1 asset of collateral token quoted in 1 asset of loan token, scaled by 1e36.
     * @dev It corresponds to the price of 10**(collateral token decimals) assets of collateral token quoted in
     * 10**(loan token decimals) assets of loan token with `36 + loan token decimals - collateral token decimals`
     * decimals of precision.
     */
    function getCollateralToLoanPrice() external view returns (uint256);

    /**
     * @notice Retrieves the current price of the loan token in USD.
     */
    function getLoanToUsdPrice() external view returns (uint256);
}
