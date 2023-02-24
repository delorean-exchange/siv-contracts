// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { Controller } from "y2k-earthquake/src/Controller.sol";
import { ControllerHelper } from "y2k-earthquake/test/ControllerHelper.sol";
import "y2k-earthquake/src/Vault.sol";

import "./BaseTest.sol";
import "../src/providers/Y2KEarthquakeV1InsuranceProvider.sol";

contract Y2KEarthquakeV1InsuranceProviderTest is BaseTest, ControllerHelper {

    address usdtVault = 0x76b1803530A3608bD5F1e4a8bdaf3007d7d2D7FA;

    Vault public vault = Vault(usdtVault);

    Y2KEarthquakeV1InsuranceProvider provider;

    // -- Forking sanity checks -- //
    function forkToActiveEpoch() public {
        // This block is at the 11'th epoch, ID 1676851200.
        // This epoch has started, but has not yet ended.
        vm.selectFork(vm.createFork(ARBITRUM_RPC_URL, 61330138));
        provider = new Y2KEarthquakeV1InsuranceProvider(usdtVault);
    }

    function forkToNoActiveEpoch() public {
        // This block is at the 10'th epoch, ID 1676246400.
        // This epoch has started and ended.
        // The next epoch has not yet been created.
        vm.selectFork(vm.createFork(ARBITRUM_RPC_URL, 58729505));
        provider = new Y2KEarthquakeV1InsuranceProvider(usdtVault);
    }

    function testCallToY2K() public {
        forkToActiveEpoch();

        assertEq(vault.tokenInsured(), address(usdt));
    }

    function testActiveFork() public {
        forkToActiveEpoch();

        assertEq(address(provider.insuredToken()), address(usdt));
        assertEq(address(provider.paymentToken()), address(weth));
        assertEq(provider.currentEpoch(), 1676851200);
        assertEq(provider.nextEpoch(), 0);
    }

    function testNoActiveFork() public {
        forkToNoActiveEpoch();

        assertEq(provider.currentEpoch(), 0);
        assertEq(provider.nextEpoch(), 0);
    }

    // -- Depeg scenario -- //
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

    function testTriggerDepeg() public {
        depositDepeg();

        hedge = vaultFactory.getVaults(1)[0];
        risk = vaultFactory.getVaults(1)[1];

        vHedge = Vault(hedge);
        vRisk = Vault(risk);

        address user0 = createUser(0);
        vm.startPrank(user0);

        provider = new Y2KEarthquakeV1InsuranceProvider(address(vHedge));

        IERC20(weth).approve(address(provider), 10 ether);
        assertEq(provider.nextEpochPurchased(user0), 0);
        provider.purchaseForNextEpoch(user0, 10 ether);

        assertEq(provider.nextEpochPurchased(user0), 10 ether);
        assertEq(provider.currentEpochPurchased(user0), 0);

        vm.warp(beginEpoch + 10 days);

        assertEq(provider.nextEpochPurchased(user0), 0);
        assertEq(provider.currentEpochPurchased(user0), 10 ether);

        controller.triggerDepeg(SINGLE_MARKET_INDEX, endEpoch);

        uint256 pending = provider.pendingPayout(user0, endEpoch);
        uint256 before = IERC20(weth).balanceOf(user0);

        uint256 result = provider.claimPayout(user0, endEpoch);

        uint256 delta = IERC20(weth).balanceOf(user0) - before;

        assertEq(result, pending);
        assertEq(delta, result);

        vm.stopPrank(user0);
    }
}
