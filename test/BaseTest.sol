// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

contract BaseTest is Test {
    function createUser(uint32 i) public returns (address) {
        string memory mnemonic = "test test test test test test test test test test test junk";
        uint256 privateKey = vm.deriveKey(mnemonic, i);
        address user = vm.addr(privateKey);
        vm.deal(user, 100 ether);
        return user;
    }
}
