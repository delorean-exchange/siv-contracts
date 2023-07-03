// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Helper.sol";

import {SelfInsuredVault} from "../src/vaults/SelfInsuredVault.sol";
import {StakedGLPYieldSource} from "../src/sources/StakedGLPYieldSource.sol";

import {Y2KEarthquakeV1InsuranceProvider} from "../src/providers/Y2KEarthquakeV1InsuranceProvider.sol";
import {Y2KEarthquakeV2InsuranceProvider} from "../src/providers/Y2KEarthquakeV2InsuranceProvider.sol";
import {Y2KEarthquakeCarouselInsuranceProvider} from "../src/providers/Y2KEarthquakeCarouselInsuranceProvider.sol";

// forge script DeployGLPSIV --rpc-url $ARBITRUM_RPC_URL --broadcast --verify -slow -vv
// forge script DeployGLPSIV --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --skip-simulation --slow -vvvv
// forge verify-contract --chain-id 42161 --num-of-optimizations 200 --watch --constructor-args $(cast abi-encode "constructor(address)" 0x984E0EB8fB687aFa53fc8B33E12E04967560E092) --compiler-version 0.8.17+commit.8df45f5f 0x149a3dbf06acAC4b173546897679CFbFeB21b05C src/providers/Y2KEarthquakeV1InsuranceProvider.sol:Y2KEarthquakeV1InsuranceProvider
// forge verify-contract --chain-id 42161 --num-of-optimizations 200 --watch --constructor-args $(cast abi-encode "constructor(uint256,address,address,address)" 0 0x892785f33CdeE22A30AEF750F285E18c18040c3e 0xeA8DfEE1898a7e0a59f7527F076106d7e44c2176  0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506) --compiler-version 0.8.17+commit.8df45f5f 0x019C65cbfE3762De85C092D6c931C6521F61D84a src/sources/StargateLPYieldSource.sol:StargateLPYieldSource
contract DeployGLPSIV is Script, HelperConfig {
    function run() public {
        DeployConfig memory config = getConfig();
        console2.log("Payment Token", config.paymentToken);
        console2.log("Emissions Token", config.emissionsToken);

        console2.log("Staked GLP", config.stakedGlpToken);
        console2.log("WETH", config.wethToken);
        console2.log("GMX reward router", config.gmxRewardRouter);
        console2.log("Sushi router", config.sushiRouter);
        console2.log("\n");

        console2.log("Broadcast sender", msg.sender);

        vm.startBroadcast();

        StakedGLPYieldSource yieldSource = new StakedGLPYieldSource(
            config.stakedGlpToken,
            config.wethToken,
            config.gmxRewardRouter,
            config.sushiRouter
        );

        SelfInsuredVault siv = new SelfInsuredVault(
            config.paymentToken,
            address(yieldSource),
            config.emissionsToken
        );

        yieldSource.transferOwnership(address(siv));

        vm.stopBroadcast();

        console2.log("Yield Source", address(yieldSource));
        console2.log("Self Insured Vault", address(siv));

        console2.log("\n");

        {
            string memory objName = "deploy";
            string memory json;
            json = vm.serializeAddress(objName, "yieldSource", address(yieldSource));
            json = vm.serializeAddress(objName, "selfInsuredVault", address(siv));

            string memory filename = "./json/siv_glp.json";
            vm.writeJson(json, filename);
        }
    }
}
