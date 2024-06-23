// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface ISalesFactory {
    function setSaleOwnerAndToken(address saleOwner, address saleToken) external;
    function isSaleCreatedThroughFactory(address sale) external view returns (bool);
}
