// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

import { Controller } from "y2k-earthquake/src/Controller.sol";
import { ControllerHelper } from "y2k-earthquake/test/ControllerHelper.sol";
import { Vault } from "y2k-earthquake/src/Vault.sol";

import { BaseTest } from "./BaseTest.sol";
import { Y2KEarthquakeV1InsuranceProvider } from "../src/providers/Y2KEarthquakeV1InsuranceProvider.sol";

contract Y2KEarthquakeV1InsuranceProviderTest is BaseTest, ControllerHelper {

    address usdtVault = 0x76b1803530A3608bD5F1e4a8bdaf3007d7d2D7FA;

    Vault public vault = Vault(usdtVault);

    Y2KEarthquakeV1InsuranceProvider provider;

    // -- Depeg scenario -- //
    // Based on Y2K ControllerTest
    function testTriggerDepeg() public {
        depositDepeg();

        hedge = vaultFactory.getVaults(1)[0];
        risk = vaultFactory.getVaults(1)[1];

        vHedge = Vault(hedge);
        vRisk = Vault(risk);

        address user0 = createTestUser(0);
        vm.startPrank(user0);

        provider = new Y2KEarthquakeV1InsuranceProvider(address(vHedge), user0);

        IERC20(weth).approve(address(provider), 10 ether);
        assertEq(provider.nextEpochPurchased(), 0);
        provider.purchaseForNextEpoch(10 ether);

        assertEq(provider.nextEpochPurchased(), 10 ether);
        assertEq(provider.currentEpochPurchased(), 0);

        vm.warp(beginEpoch + 10 days);

        assertEq(provider.nextEpochPurchased(), 0);
        assertEq(provider.currentEpochPurchased(), 10 ether);

        controller.triggerDepeg(SINGLE_MARKET_INDEX, endEpoch);

        uint256 pending = provider.pendingPayouts();
        uint256 before = IERC20(weth).balanceOf(user0);
        uint256 result = provider.claimPayouts(provider.vault().epochs(0));
        uint256 delta = IERC20(weth).balanceOf(user0) - before;

        console.log("Weth is:", address(weth));

        assertEq(result, pending, "result == pending");
        assertEq(delta, result, "delta == result");

        vm.stopPrank();
    }

    // From Y2K ControllerTest
    function testDeposit() public {
        vm.deal(ALICE, AMOUNT);
        vm.deal(BOB, AMOUNT * BOB_MULTIPLIER);
        vm.deal(CHAD, AMOUNT * CHAD_MULTIPLIER);
        vm.deal(DEGEN, AMOUNT * DEGEN_MULTIPLIER);

        vm.prank(ADMIN);
        vaultFactory.createNewMarket(FEE, TOKEN_FRAX, DEPEG_AAA, beginEpoch, endEpoch, ORACLE_FRAX, "y2kFRAX_99*");

        hedge = vaultFactory.getVaults(1)[0];
        risk = vaultFactory.getVaults(1)[1];

        vHedge = Vault(hedge);
        vRisk = Vault(risk);

        //ALICE hedge deposit
        vm.startPrank(ALICE);

        ERC20(WETH).approve(hedge, AMOUNT);

        vHedge.depositETH{value: AMOUNT}(endEpoch, ALICE);
        vm.stopPrank();

        //BOB hedge deposit
        vm.startPrank(BOB);
        ERC20(WETH).approve(hedge, AMOUNT * BOB_MULTIPLIER);

        vHedge.depositETH{value: AMOUNT * BOB_MULTIPLIER}(endEpoch, BOB);

        assertTrue(vHedge.balanceOf(BOB,endEpoch) == AMOUNT * BOB_MULTIPLIER);
        vm.stopPrank();

        //CHAD risk deposit
        vm.startPrank(CHAD);
        ERC20(WETH).approve(risk, AMOUNT * CHAD_MULTIPLIER);
        vRisk.depositETH{value: AMOUNT * CHAD_MULTIPLIER}(endEpoch, CHAD);

        assertTrue(vRisk.balanceOf(CHAD,endEpoch) == (AMOUNT * CHAD_MULTIPLIER));
        vm.stopPrank();

        //DEGEN risk deposit
        vm.startPrank(DEGEN);
        ERC20(WETH).approve(risk, AMOUNT * DEGEN_MULTIPLIER);
        vRisk.depositETH{value: AMOUNT * DEGEN_MULTIPLIER}(endEpoch, DEGEN);

        assertTrue(vRisk.balanceOf(DEGEN,endEpoch) == (AMOUNT * DEGEN_MULTIPLIER));
        vm.stopPrank();
    }

    function testTriggerNoDepeg() public {
        testDeposit();

        hedge = vaultFactory.getVaults(1)[0];
        risk = vaultFactory.getVaults(1)[1];

        vHedge = Vault(hedge);
        vRisk = Vault(risk);

        address user0 = createTestUser(0);
        vm.startPrank(user0);

        provider = new Y2KEarthquakeV1InsuranceProvider(address(vHedge), address(this));
        IERC20(weth).approve(address(provider), 10 ether);
        provider.purchaseForNextEpoch(10 ether);

        vm.warp(endEpoch + 1 days);
        controller.triggerEndEpoch(SINGLE_MARKET_INDEX, endEpoch);

        uint256 pending = provider.pendingPayouts();
        uint256 before = IERC20(weth).balanceOf(user0);
        uint256 result = provider.claimPayouts(provider.vault().epochs(0));
        uint256 delta = IERC20(weth).balanceOf(user0) - before;

        assertEq(pending, 0);
        assertEq(result, 0);
        assertEq(delta, 0);

        vm.stopPrank();
    }
}
