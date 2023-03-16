//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "openzeppelin/token/ERC20/ERC20.sol";

contract FakeToken is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }

    function publicMint(address who, uint256 amount) external {
        _mint(who, amount);
    }
}