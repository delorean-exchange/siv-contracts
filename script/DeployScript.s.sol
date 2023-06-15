// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Helper.sol";

import {SelfInsuredVault} from "../src/vaults/SelfInsuredVault.sol";
import {StargateLPYieldSource} from "../src/sources/StargateLPYieldSource.sol";

import {Y2KEarthquakeV1InsuranceProvider} from "../src/providers/Y2KEarthquakeV1InsuranceProvider.sol";
import {Y2KEarthquakeV2InsuranceProvider} from "../src/providers/Y2KEarthquakeV2InsuranceProvider.sol";
import {Y2KEarthquakeCarouselInsuranceProvider} from "../src/providers/Y2KEarthquakeCarouselInsuranceProvider.sol";

// forge script DeployScript --rpc-url $ARBITRUM_RPC_URL --broadcast --verify -slow -vv
// forge script DeployScript --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --skip-simulation --slow -vvvv
contract DeployScript is Script, HelperConfig {
    function run() public {
        DeployConfig memory config = getConfig();
        console2.log("Factory v1", config.factoryV1);
        console2.log("Factory V2", config.factoryV2);
        console2.log("Carousel factory", config.carouselFactory);
        console2.log("Emissions Token", config.emissionsToken);

        console2.log("Stargate Pool id", config.stargatePoolId);
        console2.log("Stargate lp", config.stargateLPToken);
        console2.log("Stargate staking", config.stargateStaking);
        console2.log("Sushi router", config.sushiRouter);
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

        StargateLPYieldSource yieldSource = new StargateLPYieldSource(
            config.stargatePoolId,
            config.stargateLPToken,
            config.stargateStaking,
            config.sushiRouter
        );
        SelfInsuredVault siv = new SelfInsuredVault(
            config.paymentToken,
            address(yieldSource),
            config.emissionsToken
        );

        yieldSource.transferOwnership(address(siv));

        vm.stopBroadcast();

        console2.log("V1 Insurance Provider", address(insuranceProviderV1));
        console2.log("V2 Insurance Provider", address(insuranceProviderV2));
        console2.log(
            "Carousel Insurance Provider",
            address(carouselInsuranceProvider)
        );

        console2.log("Yield Source", address(yieldSource));
        console2.log("Self Insured Vault", address(siv));

        console2.log("\n");
    }
}
