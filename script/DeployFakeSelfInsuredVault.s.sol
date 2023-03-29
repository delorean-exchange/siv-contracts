// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { NPVSwap } from  "dlx/src/core/NPVSwap.sol";
import { YieldSlice } from  "dlx/src/core/YieldSlice.sol";
import { IYieldSource } from  "dlx/src/interfaces/IYieldSource.sol";

import { FakeYieldOracle } from "../test/helpers/FakeYieldOracle.sol";

import { VaultFactory, TimeLock } from "y2k-earthquake/src/VaultFactory.sol";
import { FakeOracle } from "y2k-earthquake/test/oracles/FakeOracle.sol";
import { Controller } from "y2k-earthquake/src/Controller.sol"; 

import { BaseScript } from "./BaseScript.sol";

contract DeployFakeSelfInsuredVaultScript is BaseScript {
    using stdJson for string;

    NPVSwap npvSwap;

    Controller public controller;
    VaultFactory public vaultFactory;

    function setUp() public {
        init();
    }

    function run() public {
        console.log("DeploySelfInsuredVaultsScript");

        vm.startBroadcast(pk);

        if (eq(vm.envString("NETWORK"), "arbitrum")) {
            string memory config = vm.readFile("json/dlx-config.arbitrum.json");
            npvSwap = NPVSwap(vm.parseJsonAddress(config, ".fakeglp_weth_npvSwap.address"));
        } else {
            string memory config = vm.readFile("json/dlx-config.localhost.json");
            npvSwap = NPVSwap(vm.parseJsonAddress(config, ".fakeglp_weth_npvSwap.address"));
        }

        console.log("Deploying with npvSwap", address(npvSwap));
        console.log("Deploying with slice  ", address(npvSwap.slice()));
        console.log("Deploying with source ", address(YieldSlice(npvSwap.slice()).yieldSource()));

        IYieldSource vaultSource = YieldSlice(npvSwap.slice()).yieldSource();

        FakeYieldOracle oracle = new FakeYieldOracle(address(vaultSource.generatorToken()),
                                                     address(vaultSource.yieldToken()),
                                                     200,
                                                     18);

        vaultFactory = new VaultFactory(deployerAddress,
                                        arbitrumWeth,
                                        deployerAddress);
        controller = new Controller(address(vaultFactory), arbitrumSequencer);

        vm.stopBroadcast();
    }
}
