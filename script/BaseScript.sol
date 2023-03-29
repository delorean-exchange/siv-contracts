// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

contract BaseScript is Script {
    uint256 pk;
    address deployerAddress;

    address public constant arbitrumWeth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant arbitrumSequencer = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;

    function eq(string memory str1, string memory str2) public pure returns (bool) {
        return keccak256(abi.encodePacked(str1)) == keccak256(abi.encodePacked(str2));
    }

    function init() public {
        if (eq(vm.envString("NETWORK"), "arbitrum")) {
            console.log("Using Arbitrum mainnet private key");
            pk = vm.envUint("ARBITRUM_PRIVATE_KEY");
            deployerAddress = vm.envAddress("ARBITRUM_DEPLOYER_ADDRESS");
        } else {
            console.log("Using localhost private key");
            pk = vm.envUint("LOCALHOST_PRIVATE_KEY");
            deployerAddress = vm.envAddress("LOCALHOST_DEPLOYER_ADDRESS");
        }
    }
}
