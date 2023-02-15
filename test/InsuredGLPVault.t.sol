// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/vaults/InsuredGLPVault.sol";

contract InsuredGLPVaultTest is Test {
    uint256 arbitrumFork;
    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");

    address y2kUSDTVault = 0x76b1803530a3608bd5f1e4a8bdaf3007d7d2d7fa;
    address usdt = 0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9;

    InsuredGLPVault public vault;

    function setUp() public {
        arbitrumFork = vm.createFork(ARBITRUM_RPC_URL, 58729505);

        vault = new InsuredGLPVault("Self Insured GLP Vault", "siGLP");
    }

    function testBasic() public {
        vm.selectFork(arbitrumFork);
        assertEq(uint256(1), 1);
    }
}
