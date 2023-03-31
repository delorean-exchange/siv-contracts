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
import { Vault } from "y2k-earthquake/src/Vault.sol";

import { IInsuranceProvider } from "../src/interfaces/IInsuranceProvider.sol";
import { SelfInsuredVault } from "../src/vaults/SelfInsuredVault.sol";
import { Y2KEarthquakeV1InsuranceProvider } from "../src/providers/Y2KEarthquakeV1InsuranceProvider.sol";

import { BaseScript } from "./BaseScript.sol";

contract DeployFakeSelfInsuredVaultScript is BaseScript {
    using stdJson for string;

    NPVSwap npvSwap;

    Controller public controller;
    VaultFactory public vaultFactory;
    FakeOracle public fakeOracle;
    address public hedge;
    address public risk;
    Vault public vHedge;
    Vault public vRisk;

    Y2KEarthquakeV1InsuranceProvider public provider;
    SelfInsuredVault public vault;

    function setUp() public {
        init();
    }

    function run() public {
        console.log("DeploySelfInsuredVaultsScript");

        vm.startBroadcast(pk);
        string memory config;
        if (eq(vm.envString("NETWORK"), "arbitrum")) {
            config = vm.readFile("json/dlx-config.arbitrum.json");
        } else {
            config = vm.readFile("json/dlx-config.localhost.json");
        }

        npvSwap = NPVSwap(vm.parseJsonAddress(config, ".fakeglp_weth_npvSwap.address"));

        console.log("Deploying with npvSwap", address(npvSwap));
        console.log("Deploying with slice  ", address(npvSwap.slice()));
        console.log("Deploying with source ", address(YieldSlice(npvSwap.slice()).yieldSource()));

        IYieldSource vaultSource = YieldSlice(npvSwap.slice()).yieldSource();

        FakeYieldOracle yieldOracle = new FakeYieldOracle(address(vaultSource.generatorToken()),
                                                     address(vaultSource.yieldToken()),
                                                     200,
                                                     18);

        vaultFactory = new VaultFactory(deployerAddress,
                                        arbitrumWeth,
                                        deployerAddress);
        controller = new Controller(address(vaultFactory), arbitrumSequencer);
        vaultFactory.setController(address(controller));

        fakeOracle = new FakeOracle(0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8,  // Chainlink oracle
                                    90995265);  // Price simulation

        vaultFactory.createNewMarket(5,  // Fee
                                     0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F,  // Frax
                                     995555555555555555,  // Strike price
                                     block.timestamp + 10 minutes,  // Begin epoch
                                     block.timestamp + 1 days,  // End epoch
                                     address(fakeOracle),
                                     "y2kFRAX_99*");

        hedge = vaultFactory.getVaults(1)[0];
        risk = vaultFactory.getVaults(1)[1];
        vHedge = Vault(hedge);
        vRisk = Vault(risk);

        vault = new SelfInsuredVault("Self Insured fakeGLP Vault",
                                     "sivFakeGLP",
                                     address(vaultSource.yieldToken()),
                                     address(vaultSource),
                                     address(yieldOracle),
                                     address(npvSwap));

        provider = new Y2KEarthquakeV1InsuranceProvider(address(vHedge), address(vault));

        // Set the provider
        IInsuranceProvider[] memory providers = new IInsuranceProvider[](1);
        providers[0] = IInsuranceProvider(provider);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10_00;
        vault.setInsuranceProviders(providers, weights);

        vm.stopBroadcast();

        {
            string memory objName = "deploy";
            string memory json;
            json = vm.serializeAddress(objName, "address_vaultFactory", address(vaultFactory));
            json = vm.serializeAddress(objName, "address_yieldOracle", address(yieldOracle));
            json = vm.serializeAddress(objName, "address_controller", address(controller));
            json = vm.serializeAddress(objName, "address_siv", address(vault));

            json = vm.serializeString(objName, "contractName_vaultFactory", "VaultFactory");
            json = vm.serializeString(objName, "contractName_yieldOracle", "FakeYieldOracle");
            json = vm.serializeString(objName, "contractName_controller", "Controller");
            json = vm.serializeString(objName, "contractName_siv", "SelfInsuredVault");

            string memory filename = "./json/deploy_fakevault";
            if (eq(vm.envString("NETWORK"), "arbitrum")) {
                filename = string.concat(filename, ".arbitrum.json");
            } else {
                filename = string.concat(filename, ".localhost.json");
            }

            vm.writeJson(json, filename);
        }
    }
}
