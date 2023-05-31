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
        /* npvSwap = NPVSwap(vm.parseJsonAddress(config, ".glp_npvSwap.address")); */
        npvSwap = NPVSwap(0x96c58797653E633dc48F1D1c3E3a6501B3771Be2);
        console.log("npvSwap:", address(npvSwap));

        vaultFactory = VaultFactory(y2kVaultFactory);
        uint256 miUSDC = 7;
        uint256 miUSDT = 8;
        uint256 miFrax = 13;
        uint256 miDai =  14;

        /* Find market indexes in Y2K */
        /* for (uint256 i = 1; i < vaultFactory.marketIndex(); i++) { */
        /*     hedge = vaultFactory.getVaults(i)[0]; */
        /*     risk = vaultFactory.getVaults(i)[1]; */
        /*     if (address(Vault(hedge).tokenInsured()) == arbitrumUSDC) { */
        /*         /\* console.log("USDC hedge", hedge, i); *\/ */
        /*         /\* miUSDC = i; *\/ */
        /*     } else if (address(Vault(hedge).tokenInsured()) == arbitrumUSDT) { */
        /*         /\* console.log("USDT hedge", hedge, i); *\/ */
        /*         /\* miUSDT = i; *\/ */
        /*     } else if (address(Vault(hedge).tokenInsured()) == arbitrumFrax) { */
        /*         /\* console.log("Frax hedge", hedge, i); *\/ */
        /*         /\* miFrax = i; *\/ */
        /*     } else if (address(Vault(hedge).tokenInsured()) == arbitrumDai) { */
        /*         /\* console.log("Dai hedge ", hedge, i); *\/ */
        /*         /\* miDai = i; *\/ */
        /*     } */
        /* } */

        console.log("miUSDC", miUSDC);
        console.log("miUSDT", miUSDT);
        console.log("miFrax", miFrax);
        console.log("miDai ", miDai);

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
        /* vault.addInsuranceProvider(providerUSDT,   55);  // 0.55% */
        /* vault.addInsuranceProvider(providerDai,  1_20);  // 1.20% */
        /* vault.addInsuranceProvider(providerFrax,   55);  // 0.55% */

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

        console.log("");
        console.log("");
        console.log("===");
        console.log("Looking up vHedge for", marketIndex);
        vHedge = Vault(vaultFactory.getVaults(marketIndex)[0]);
        console.log("Got", address(vHedge));

        Y2KEarthquakeV1InsuranceProvider provider;
        provider = new Y2KEarthquakeV1InsuranceProvider(address(vHedge), beneficiary, marketIndex);

        uint256 len = vHedge.epochsLength();
        console.log("LEN", len);

        for (uint256 i = len - 1; i > len - 4; i--) {
            uint256 epochId = vHedge.epochs(i);
            uint256 end = epochId;
            uint256 begin = vHedge.idEpochBegin(epochId);
            address addr = provider.rewardsFactory().getFarmAddresses(marketIndex, begin, end)[0];

            console.log("addr:", i, addr);
        }

        /* console.log("Current epoch", epochId); */
        /* console.log("Begin", vHedge.idEpochBegin(epochId)); */
        /* console.log("Next epoch", provider.nextEpoch()); */
        /* console.log("Next epoch purchasable?", provider.isNextEpochPurchasable()); */

        /* console.log("provider.rewardsFactory()", address(provider.rewardsFactory())); */
        /* console.log("addr", provider.rewardsFactory().getFarmAddresses(marketIndex, */
        /*                                                                vHedge.idEpochBegin(epochId), */
        /*                                                                epochId)[0]); */

        return provider;
    }
}
