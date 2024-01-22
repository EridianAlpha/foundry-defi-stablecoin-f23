// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// This contract is used to test the CollateralDepositFailed error in DSCEngine.sol
// To avoid an EVM revert if the transferFrom function is called on an address that doesn't support it
// we create this contract that will always revert if transferFrom is called on it
contract CollateralDepositFailedHelper {
    function transferFrom(address _from, address _to, uint256 _amount) public pure returns (bool) {
        _from;
        _to;
        _amount;
        return false;
    }
}
