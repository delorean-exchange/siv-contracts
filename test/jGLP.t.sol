// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { BaseTest } from "./BaseTest.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { JonesGLPYieldSource } from "dlx/src/sources/JonesGLPYieldSource.sol";
import { NPVSwap } from  "dlx/src/core/NPVSwap.sol";

import { IJonesGlpCompoundRewards } from "../src/interfaces/jglp/IJonesGlpCompoundRewards.sol";
import { IGlpAdapter } from "../src/interfaces/jglp/IGlpAdapter.sol";
import { IWhitelistController } from "../src/interfaces/jglp/IWhitelistController.sol";

import { SelfInsuredVault } from "../src/vaults/SelfInsuredVault.sol";

contract JGLPTest is BaseTest {
    uint256 arbitrumForkJonesGLP;

    function setUp() public {
        arbitrumForkJonesGLP = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"), 81645858);
    }

    function testJGLP() public {
        vm.selectFork(arbitrumForkJonesGLP);

        address user = 0x9bb98140F36553dB71fe4a570aC0b1401BC61B4F;
        JonesGLPYieldSource source = new JonesGLPYieldSource();


        uint256 bal = source.jglp().balanceOf(user);
        console.log("bal", bal);

        NPVSwap npvSwap = NPVSwap(address(0));
        SelfInsuredVault vault = new SelfInsuredVault("Self Insured jGLP Vault",
                                                      "sivjGLP",
                                                      address(source.yieldToken()),
                                                      address(source),
                                                      address(npvSwap));
        source.setOwner(address(vault));

        vm.startPrank(user);
        source.jglp().approve(address(vault), bal);
        vault.deposit(bal, address(user));

        vm.stopPrank();
    }

}
