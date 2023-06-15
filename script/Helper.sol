// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

contract HelperConfig is Script {
    using stdJson for string;

    struct DeployConfig {
        address factoryV1;
        address factoryV2;
        address carouselFactory;
        address paymentToken;
        address emissionsToken;
        uint256 stargatePoolId;
        address stargateLPToken;
        address stargateStaking;
        address sushiRouter;
    }

    struct ConfigMarket {
        address insuranceProvider;
        uint256 strikePrice;
        address token;
        address depositAsset;
        uint256 marketId;
        uint256 premiumWeight;
        uint256 collateralWeight;
    }

    struct Contracts {
        address siv;
    }

    DeployConfig deployConfig;
    Contracts contracts;

    function getConfig() public returns (DeployConfig memory constants) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/configs/config.json");
        string memory json = vm.readFile(path);
        bytes memory parseJsonByteCode = json.parseRaw(".deployConfig");
        constants = abi.decode(parseJsonByteCode, (DeployConfig));
        deployConfig = constants;
    }

    function getSiv() public returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/configs/config.json");
        string memory json = vm.readFile(path);
        bytes memory parseJsonByteCode = json.parseRaw(".contracts");
        contracts = abi.decode(parseJsonByteCode, (Contracts));
        return contracts.siv;
    }

    function getConfigMarket() public view returns (ConfigMarket[] memory markets) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/script/configs/markets.json"
        );
        string memory json = vm.readFile(path);
        bytes memory marketsRaw = vm.parseJson(json, ".markets");
        markets = abi.decode(marketsRaw, (ConfigMarket[]));
    }
}
