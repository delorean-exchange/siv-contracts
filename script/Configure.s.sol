// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Helper.sol";

import {SelfInsuredVault} from "../src/vaults/SelfInsuredVault.sol";

// forge script AddMarkets --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --skip-simulation --slow --verify -vv
contract AddMarkets is HelperConfig {
    function run() public {
        address sivAddress = getSiv();
        console.log("SIV", sivAddress);
        SelfInsuredVault siv = SelfInsuredVault(sivAddress);

        vm.startBroadcast();

        console2.log(
            "-------------------------Set MARKETS----------------------"
        );

        ConfigMarket[] memory markets = getConfigMarket();

        for (uint256 i = 0; i < markets.length; ++i) {
            ConfigMarket memory market = markets[i];

            siv.addMarket(
                market.insuranceProvider,
                market.marketId,
                market.premiumWeight,
                market.collateralWeight
            );

            console2.log("insurnaceProvider", market.insuranceProvider);
            console2.log("marketId", market.marketId);
            console2.log(
                "----------------------------------------------------------------"
            );
            console2.log("\n");
        }

        vm.stopBroadcast();
    }
}

// forge script Purchase --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --skip-simulation --slow --verify -vv
contract Purchase is HelperConfig {
    function run() public {
        address sivAddress = getSiv();
        console.log("SIV", sivAddress);
        SelfInsuredVault siv = SelfInsuredVault(sivAddress);

        vm.startBroadcast();

        siv.purchaseInsuranceForNextEpoch();

        vm.stopBroadcast();
    }
}
