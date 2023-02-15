// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "y2k-earthquake/interfaces/IVault.sol";
import "../src/vaults/SelfInsuredVault.sol";

contract InsuredGLPVaultTest is Test {
    uint256 arbitrumFork;
    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");

    address y2kUSDTVault = 0x76b1803530A3608bD5F1e4a8bdaf3007d7d2D7FA;
    address usdt = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address sGLP = 0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf;

    SelfInsuredVault public vault;

    function setUp() public {
        arbitrumFork = vm.createFork(ARBITRUM_RPC_URL, 58729505);

        vault = new SelfInsuredVault("Self Insured GLP Vault",
                                     "siGLP",
                                     sGLP);
    }

    function testCallToY2K() public {
        vm.selectFork(arbitrumFork);
        address token = IVault(y2kUSDTVault).tokenInsured();
        assertEq(token, usdt);
    }
}
