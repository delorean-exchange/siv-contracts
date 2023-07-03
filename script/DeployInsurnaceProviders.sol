// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Helper.sol";

import {SelfInsuredVault} from "../src/vaults/SelfInsuredVault.sol";
import {StargateLPYieldSource} from "../src/sources/StargateLPYieldSource.sol";

import {Y2KEarthquakeV1InsuranceProvider} from "../src/providers/Y2KEarthquakeV1InsuranceProvider.sol";
import {Y2KEarthquakeV2InsuranceProvider} from "../src/providers/Y2KEarthquakeV2InsuranceProvider.sol";
import {Y2KEarthquakeCarouselInsuranceProvider} from "../src/providers/Y2KEarthquakeCarouselInsuranceProvider.sol";

// forge script DeployInsurnaceProviders --rpc-url $ARBITRUM_RPC_URL --broadcast --verify -slow -vv
// forge script DeployInsurnaceProviders --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --skip-simulation --slow -vvvv
// forge verify-contract --chain-id 42161 --num-of-optimizations 200 --watch --constructor-args $(cast abi-encode "constructor(address)" 0x984E0EB8fB687aFa53fc8B33E12E04967560E092) --compiler-version 0.8.17+commit.8df45f5f 0x149a3dbf06acAC4b173546897679CFbFeB21b05C src/providers/Y2KEarthquakeV1InsuranceProvider.sol:Y2KEarthquakeV1InsuranceProvider
// forge verify-contract --chain-id 42161 --num-of-optimizations 200 --watch --constructor-args $(cast abi-encode "constructor(uint256,address,address,address)" 0 0x892785f33CdeE22A30AEF750F285E18c18040c3e 0xeA8DfEE1898a7e0a59f7527F076106d7e44c2176  0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506) --compiler-version 0.8.17+commit.8df45f5f 0x019C65cbfE3762De85C092D6c931C6521F61D84a src/sources/StargateLPYieldSource.sol:StargateLPYieldSource
contract DeployInsurnaceProviders is Script, HelperConfig {
    function run() public {
        DeployConfig memory config = getConfig();
        console2.log("Factory v1", config.factoryV1);
        console2.log("Factory V2", config.factoryV2);
        console2.log("Carousel factory", config.carouselFactory);
        console2.log("\n");

        console2.log("Broadcast sender", msg.sender);

        vm.startBroadcast();

        Y2KEarthquakeV1InsuranceProvider insuranceProviderV1 = new Y2KEarthquakeV1InsuranceProvider(
                config.factoryV1
            );
        Y2KEarthquakeV2InsuranceProvider insuranceProviderV2 = new Y2KEarthquakeV2InsuranceProvider(
                config.factoryV2
            );
        Y2KEarthquakeCarouselInsuranceProvider carouselInsuranceProvider = new Y2KEarthquakeCarouselInsuranceProvider(
                config.carouselFactory
            );

        vm.stopBroadcast();

        console2.log("V1 Insurance Provider", address(insuranceProviderV1));
        console2.log("V2 Insurance Provider", address(insuranceProviderV2));
        console2.log(
            "Carousel Insurance Provider",
            address(carouselInsuranceProvider)
        );

        console2.log("\n");

        {
            string memory objName = "deploy";
            string memory json;
            json = vm.serializeAddress(objName, "insuranceProviderV1", address(insuranceProviderV1));
            json = vm.serializeAddress(objName, "insuranceProviderV2", address(insuranceProviderV2));
            json = vm.serializeAddress(objName, "carouselInsuranceProvider", address(carouselInsuranceProvider));

            string memory filename = "./json/providers.json";
            vm.writeJson(json, filename);
        }
    }
}
