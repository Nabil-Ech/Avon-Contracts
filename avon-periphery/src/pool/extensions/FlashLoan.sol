// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAvonFlashLoanCallback} from "../../interface/IAvonFlashLoanCallback.sol";
import {PoolStorage} from "../PoolStorage.sol";
import {PoolErrors} from "../utils/PoolErrors.sol";
import {PoolEvents} from "../utils/PoolEvents.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PoolConstants} from "../utils/PoolConstants.sol";
import {IOrderbookFactory} from "../../interface/IOrderbookFactory.sol";

library FlashLoan {
    using Math for uint256;

    /// @notice Execute a flash loan of `assets` of `token` with a callback to the borrower.
    /// @dev Charges pool fee and splits a protocol portion to the fee recipient; requires same-transaction repay.
    /// @param s Pool storage state.
    /// @param token Token to flash loan (must equal pool loan token).
    /// @param assets Amount to loan.
    /// @param data Calldata passed to `onAvonFlashLoan`.
    function _flashLoan(PoolStorage.PoolState storage s, address token, uint256 assets, bytes calldata data) internal {
        if (assets == 0) revert PoolErrors.ZeroAddress();
        if (token != s.config.loanToken) revert PoolErrors.InvalidInput();
        if (s.totalBorrowAssets + assets > s.totalSupplyAssets) revert PoolErrors.InsufficientLiquidity();

        // Calculate flash loan fee
        uint256 feeAmount = assets.mulDiv(s.flashLoanFee, PoolConstants.WAD, Math.Rounding.Ceil);

        // Calculate protocol's portion of the fee
        uint256 protocolFeeAmount =
            feeAmount.mulDiv(s.protocolFlashLoanFeePercentage, PoolConstants.WAD, Math.Rounding.Ceil);

        emit PoolEvents.FlashLoan(msg.sender, token, assets);

        SafeERC20.safeTransfer(ERC20(token), msg.sender, assets);

        IAvonFlashLoanCallback(msg.sender).onAvonFlashLoan(assets, data);

        SafeERC20.safeTransferFrom(ERC20(token), msg.sender, address(this), assets + feeAmount);

        // If there's a protocol fee and it's non-zero, send it to the protocol fee recipient
        if (protocolFeeAmount > 0) {
            address feeRecipient = IOrderbookFactory(s.orderBookFactory).feeRecipient();
            if (feeRecipient != address(0)) {
                SafeERC20.safeTransfer(ERC20(token), feeRecipient, protocolFeeAmount);
            }
        }

        uint256 poolFeeAmount = feeAmount - protocolFeeAmount;
        s.totalSupplyAssets += poolFeeAmount;
    }
}
