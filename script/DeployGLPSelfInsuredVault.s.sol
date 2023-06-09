// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { NPVSwap } from  "dlx/src/core/NPVSwap.sol";
import { YieldSlice } from  "dlx/src/core/YieldSlice.sol";
import { IYieldSource } from  "dlx/src/interfaces/IYieldSource.sol";

import { VaultFactory, TimeLock } from "y2k-earthquake/src/legacy_v1/VaultFactory.sol";
import { Controller } from "y2k-earthquake/src/legacy_v1/Controller.sol"; 
import { Vault } from "y2k-earthquake/src/legacy_v1/Vault.sol";

import { IInsuranceProvider } from "../src/interfaces/IInsuranceProvider.sol";
import { SelfInsuredVault } from "../src/vaults/SelfInsuredVault.sol";
import { Y2KEarthquakeV1InsuranceProvider } from "../src/providers/Y2KEarthquakeV1InsuranceProvider.sol";
import { StakedGLPYieldSource } from "../src/sources/StakedGLPYieldSource.sol";

import { BaseScript } from "./BaseScript.sol";

contract DeployFakeSelfInsuredVaultScript is BaseScript {
    using stdJson for string;

    NPVSwap npvSwap;

    Controller public controller;
    VaultFactory public vaultFactory;
    address public hedge;
    address public risk;
    Vault public vHedge;
    Vault public vRisk;

    SelfInsuredVault public vault;

    function setUp() public {
        init();
    }

    function run() public {
        console.log("DeployGLPSelfInsuredVaultsScript");

        vm.startBroadcast(pk);

        string memory config;
        if (eq(vm.envString("NETWORK"), "arbitrum")) {
            config = vm.readFile("json/dlx-config.arbitrum.json");
        } else {
            config = vm.readFile("json/dlx-config.localhost.json");
        }
        npvSwap = NPVSwap(0x96c58797653E633dc48F1D1c3E3a6501B3771Be2);
        console.log("npvSwap:", address(npvSwap));

        vaultFactory = VaultFactory(y2kVaultFactory);
        uint256 miUSDC = 7;
        uint256 miUSDT = 8;
        uint256 miFrax = 13;
        uint256 miDai =  14;

        StakedGLPYieldSource source = new StakedGLPYieldSource(address(stakedGLP),
                                                               arbitrumWeth,
                                                               address(glpTracker));

        vault = new SelfInsuredVault("Hedged GLP Vault",
                                     "hGLP",
                                     address(source.yieldToken()),
                                     address(source),
                                     address(npvSwap));

        source.setOwner(address(vault));

        // GLP composition from https://app.gmx.io/#/dashboard
        // Sum of weights gives 10% of yield devoted to insurance
        Y2KEarthquakeV1InsuranceProvider providerUSDC = providerForIndex(miUSDC, address(vault));
        Y2KEarthquakeV1InsuranceProvider providerUSDT = providerForIndex(miUSDT, address(vault));
        Y2KEarthquakeV1InsuranceProvider providerDai  = providerForIndex(miDai,  address(vault));
        Y2KEarthquakeV1InsuranceProvider providerFrax = providerForIndex(miFrax, address(vault));

        providerUSDC.transferOwnership(address(vault));
        providerUSDT.transferOwnership(address(vault));
        providerDai.transferOwnership(address(vault));
        providerFrax.transferOwnership(address(vault));

        vault.addInsuranceProvider(providerUSDC, 7_90);  // 7.90%
        vault.addInsuranceProvider(providerUSDT,   55);  // 0.55%
        vault.addInsuranceProvider(providerDai,  1_20);  // 1.20%
        vault.addInsuranceProvider(providerFrax,   55);  // 0.55%

        vault.addRewardToken(y2kToken);

        vm.stopBroadcast();

        {
            string memory objName = "deploy";
            string memory json;
            json = vm.serializeAddress(objName, "address_vaultFactory", address(vaultFactory));
            json = vm.serializeAddress(objName, "address_controller", address(controller));
            json = vm.serializeAddress(objName, "address_siv", address(vault));

            json = vm.serializeString(objName, "contractName_vaultFactory", "VaultFactory");
            json = vm.serializeString(objName, "contractName_controller", "Controller");
            json = vm.serializeString(objName, "contractName_siv", "SelfInsuredVault");

            string memory filename = "./json/deploy_glpvault";
            if (eq(vm.envString("NETWORK"), "arbitrum")) {
                filename = string.concat(filename, ".arbitrum.json");
            } else {
                filename = string.concat(filename, ".localhost.json");
            }

            vm.writeJson(json, filename);
        }

    }

    function providerForIndex(uint256 marketIndex, address beneficiary) public returns (Y2KEarthquakeV1InsuranceProvider) {
        vHedge = Vault(vaultFactory.getVaults(marketIndex)[0]);
        Y2KEarthquakeV1InsuranceProvider provider;
        provider = new Y2KEarthquakeV1InsuranceProvider(address(vHedge), beneficiary, marketIndex);
        return provider;
    }
}
