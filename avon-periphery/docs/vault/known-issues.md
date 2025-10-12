# Malicious users can reduce the manager fee charges by making frequent calls to the function accrueInterest

The function accrueInterest of the contract Vault allows anyone to call.

```
function accrueInterest() external {
  _accrueInterest();
  _updatePrevTotal();
}
```

This function first calculates managerFeesAmount based on the difference between the current return value of the function totalAssets and the previously recorded value, together with the manager fee rate. It then derives the corresponding shares, mints them to the feeRecipient, and finally records the current return value of the function totalAssets.

```javascript
function _accrueInterest() internal {
        uint256 currentAssets = totalAssets();
        
        // Only calculate fees if this isn't the first accrual and there's a gain
        if (prevTotal > 0 && currentAssets > prevTotal) {
            // Calculate the gain (interest earned)
            uint256 gain = currentAssets - prevTotal;
            
            // Calculate manager's share of the gains
            uint256 managerFeesAmount = gain.mulDiv(managerFees, 1e18);
            
            if (managerFeesAmount > 0) {
                uint256 shares = managerFeesAmount.mulDiv(
                    totalSupply(),
                    currentAssets - managerFeesAmount,
                    Math.Rounding.Floor
                );
                if (shares > 0) {
                    _mint(feeRecipient, shares);
                    emit ManagerFeesAccrued(managerFeesAmount, shares);
                }
            }
        }
}

function _updatePrevTotal() internal {
  prevTotal = totalAssets();
  emit TotalAssetsUpdated(prevTotal);
}
```

# Impact

If the function accrueInterest is called frequently, the change in total assets will be very small. Due to integer division, the manager fees collected will be reduced accordingly.
