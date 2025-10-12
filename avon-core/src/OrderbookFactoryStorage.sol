// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

library OrderbookFactoryStorage {
    bytes32 constant FACTORY_STORAGE_SLOT = keccak256("avon.factory.storage");

    struct FactoryState {
        address feeRecipient;
        mapping(address => bool) isKeeper;
        mapping(address => bool) isIRMEnabled;
        mapping(bytes32 => address) orderBooks;
        mapping(address => bool) isPoolManager;
        mapping(address => bool) isPoolFactory;
        address[] orderbookAddresses;
    }

    function initialize(address feeRecipient) internal {
        FactoryState storage s = _state();
        s.feeRecipient = feeRecipient;
    }

    function _state() internal pure returns (FactoryState storage s) {
        bytes32 slot = FACTORY_STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }
}
