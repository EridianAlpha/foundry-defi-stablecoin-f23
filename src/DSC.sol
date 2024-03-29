// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 *  @title DSC
 *  @author EridianAlpha
 *  @notice This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volatility coin
 *  Collateral: Exogenous
 *  Minting (Stability Mechanism): Decentralized (Algorithmic)
 *  Value (Relative Stability): Anchored (Pegged to USD)
 *  Collateral Type: Crypto
 *
 *  This is the contract meant to be owned by DSCEngine. It is a ERC20 token that can be minted and burned by the DSCEngine smart contract.
 */
contract DSC is ERC20Burnable, Ownable {
    error DSC__MintAmountMustBeMoreThanZero();
    error DSC__MintNotZeroAddress();
    error DSC__BurnAmountMustBeMoreThanZero();
    error DSC__BurnAmountExceedsBalance();

    constructor() ERC20("DSC", "DSC") Ownable() {}

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DSC__MintNotZeroAddress();
        }
        if (_amount <= 0) {
            revert DSC__MintAmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

    function burn(uint256 _amount) public override(ERC20Burnable) onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DSC__BurnAmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DSC__BurnAmountExceedsBalance();
        }
        ERC20Burnable.burn(_amount);
    }
}
