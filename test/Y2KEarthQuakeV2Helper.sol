// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Helper.sol";

import "y2k-earthquake/src/v2/VaultFactoryV2.sol";
import "y2k-earthquake/src/v2/TimeLock.sol";
import "y2k-earthquake/src/v2/VaultV2.sol";
import "y2k-earthquake/src/v2/Controllers/ControllerPeggedAssetV2.sol";
import "y2k-earthquake/src/v2/interfaces/IWETH.sol";

import {Y2KEarthquakeV2InsuranceProvider} from "../src/providers/Y2KEarthquakeV2InsuranceProvider.sol";

contract Y2KEarthQuakeV2Helper is Helper {
    using FixedPointMathLib for uint256;

    VaultFactoryV2 public factory;
    ControllerPeggedAssetV2 public controller;
    Y2KEarthquakeV2InsuranceProvider public insuranceProvider;

    uint16 public fee = 50; // 0.5%

    function setUp() public virtual {
        TimeLock timelock = new TimeLock(ADMIN);

        factory = new VaultFactoryV2(WETH, TREASURY, address(timelock));

        controller = new ControllerPeggedAssetV2(
            address(factory),
            ARBITRUM_SEQUENCER,
            TREASURY
        );

        insuranceProvider = new Y2KEarthquakeV2InsuranceProvider(
            address(factory)
        );

        factory.whitelistController(address(controller));
    }

    function createEndEpochMarket(
        uint40 begin,
        uint40 end
    )
        public
        returns (
            address premium,
            address collateral,
            uint256 marketId,
            uint256 epochId
        )
    {
        //create end epoch market
        address oracle = address(0x3);
        uint256 strike = uint256(0x2);
        string memory name = string("USD Coin");
        string memory symbol = string("USDC");

        (premium, collateral, marketId) = factory.createNewMarket(
            VaultFactoryV2.MarketConfigurationCalldata(
                address(0x11111),
                strike,
                oracle,
                WETH,
                name,
                symbol,
                address(controller)
            )
        );

        (epochId, ) = factory.createEpoch(marketId, begin, end, fee);
    }

    function createDepegMarket(
        uint40 begin,
        uint40 end
    )
        public
        returns (
            address premium,
            address collateral,
            uint256 marketId,
            uint256 epochId
        )
    {
        //create end epoch market
        string memory name = string("USD Coin");
        string memory symbol = string("USDC");

        //create depeg market
        uint256 depegStrike = uint256(2 ether);
        (premium, collateral, marketId) = factory.createNewMarket(
            VaultFactoryV2.MarketConfigurationCalldata(
                USDC_TOKEN,
                depegStrike,
                USDC_CHAINLINK,
                WETH,
                name,
                symbol,
                address(controller)
            )
        );

        //create epoch for depeg
        (epochId, ) = factory.createEpoch(marketId, begin, end, fee);
    }

    function helperCalculateFeeAdjustedValue(
        uint256 amount
    ) internal view returns (uint256) {
        return amount - amount.mulDivUp(fee, 10000);
    }
}
