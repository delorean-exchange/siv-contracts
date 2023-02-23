// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import "y2k-earthquake/src/interfaces/IVault.sol";
import { Controller } from "y2k-earthquake/src/Controller.sol";
import { ControllerHelper } from "y2k-earthquake/test/ControllerHelper.sol";

import "./BaseTest.sol";
import "../src/providers/Y2KEarthquakeV1InsuranceProvider.sol";

contract Y2KEarthquakeV1InsuranceProviderTest is BaseTest, ControllerHelper {
/* contract Y2KEarthquakeV1InsuranceProviderTest is BaseTest { */

    IVault public vault = IVault(0x76b1803530A3608bD5F1e4a8bdaf3007d7d2D7FA);
    Y2KEarthquakeV1InsuranceProvider provider;

    function init() public {
        provider = new Y2KEarthquakeV1InsuranceProvider(0x76b1803530A3608bD5F1e4a8bdaf3007d7d2D7FA);
    }

    function forkToActiveEpoch() public {
        // This block is at the 11'th epoch, ID 1676851200.
        // This epoch has started, but has not yet ended.
        vm.selectFork(vm.createFork(ARBITRUM_RPC_URL, 61330138));
    }

    function forkToNoActiveEpoch() public {
        // This block is at the 10'th epoch, ID 1676246400.
        // This epoch has started and ended.
        // The next epoch has not yet been created.
        vm.selectFork(vm.createFork(ARBITRUM_RPC_URL, 58729505));
    }

    // From Y2K ControllerTest
    function testY2KControllerDepeg() public {
        depositDepeg();

        hedge = vaultFactory.getVaults(1)[0];
        risk = vaultFactory.getVaults(1)[1];

        vHedge = Vault(hedge);
        vRisk = Vault(risk);

        vm.warp(beginEpoch + 10 days);

        emit log_named_int("strike price", vHedge.strikePrice());
        emit log_named_int("oracle price", controller.getLatestPrice(TOKEN_FRAX));
        assertTrue(controller.getLatestPrice(TOKEN_FRAX) > 900000000000000000 && controller.getLatestPrice(TOKEN_FRAX) < 1000000000000000000);
        assertTrue(vHedge.strikePrice() > 900000000000000000 && controller.getLatestPrice(TOKEN_FRAX) < 1000000000000000000);

        controller.triggerDepeg(SINGLE_MARKET_INDEX, endEpoch);

        assertTrue(vHedge.totalAssets(endEpoch) == vRisk.idClaimTVL(endEpoch), "Claim TVL Risk not equal to Total Tvl Hedge");
        assertTrue(vRisk.totalAssets(endEpoch) == vHedge.idClaimTVL(endEpoch), "Claim TVL Hedge not equal to Total Tvl Risk");
    }

    function testCallToY2K() public {
        forkToActiveEpoch();
        init();

        assertEq(vault.tokenInsured(), address(usdt));
    }

    function testActiveFork() public {
        forkToActiveEpoch();
        init();

        assertEq(provider.insuredToken(), address(usdt));
        assertEq(provider.paymentToken(), address(weth));
        assertEq(provider.currentEpoch(), 1676851200);
        assertEq(provider.nextEpoch(), 0);
    }

    function testNoActiveFork() public {
        forkToNoActiveEpoch();
        init();

        assertEq(provider.currentEpoch(), 0);
        assertEq(provider.nextEpoch(), 0);
    }


    function testTriggerDepeg() public {
        forkToActiveEpoch();
        init();
    }
}

