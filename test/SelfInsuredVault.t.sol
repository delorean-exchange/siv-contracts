// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "y2k-earthquake/interfaces/IVault.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "gmx/staking/interfaces/IRewardTracker.sol"

import "../src/vaults/SelfInsuredVault.sol";

contract SelfInsuredVaultTest is Test {
    uint256 arbitrumFork;
    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");

    IVault y2kUSDTVault = IVault(0x76b1803530A3608bD5F1e4a8bdaf3007d7d2D7FA);
    IRewardTracker gmxRewardsTracker = IRewardTracker(0x4e971a87900b931ff39d1aad67697f49835400b6);

    IERC20 usdt = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    IERC20 sGLP = IERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);

    address glpWallet = 0x3aaF2aCA2a0A6b6ec227Bbc2bF5cEE86c2dC599d;

    SelfInsuredVault public vault;

    function createUser(uint32 i) public returns (address) {
        string memory mnemonic = "test test test test test test test test test test test junk";
        uint256 privateKey = vm.deriveKey(mnemonic, i);
        address user = vm.addr(privateKey);
        vm.deal(user, 100 ether);
        return user;
    }

    function setUp() public {
        /* arbitrumFork = vm.createFork(ARBITRUM_RPC_URL, 58729505); */
        arbitrumFork = vm.createFork(ARBITRUM_RPC_URL, 61330138);

        vault = new SelfInsuredVault("Self Insured GLP Vault", "siGLP", sGLP);

    }

    function testCallToY2K() public {
        vm.selectFork(arbitrumFork);
        address token = y2kUSDTVault.tokenInsured();
        assertEq(token, usdt);
    }

    function testDepositWithdraw() public {
        vm.selectFork(arbitrumFork);
        console.log(sGLP.balanceOf(glpWallet));

        address user = createUser(0);

        vm.prank(glpWallet);
        sGLP.transfer(user, 10e18);

        console.log("claimable", gmxRewardsTracker.claimable(glpWallet));

        console.log(sGLP.balanceOf(glpWallet));
        console.log(sGLP.balanceOf(user));

        console.log("claimable", gmxRewardsTracker.claimable(glpWallet));
        console.log("claimable", gmxRewardsTracker.claimable(user));
    }
}
