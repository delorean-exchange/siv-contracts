// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import "openzeppelin/token/ERC20/IERC20.sol";

import { ControllerHelper } from "y2k-earthquake/test/ControllerHelper.sol";
import { Vault } from "y2k-earthquake/src/Vault.sol";

import { BaseTest } from "./BaseTest.sol";
import { FakeYieldSource } from "./helpers/FakeYieldSource.sol";

import { IRewardTracker } from "../src/interfaces/gmx/IRewardTracker.sol";
import { IInsuranceProvider } from "../src/interfaces/IInsuranceProvider.sol";
import { SelfInsuredVault } from "../src/vaults/SelfInsuredVault.sol";
import { Y2KEarthquakeV1InsuranceProvider } from "../src/providers/Y2KEarthquakeV1InsuranceProvider.sol";

contract SelfInsuredVaultTest is BaseTest, ControllerHelper {
    address glpWallet = 0x3aaF2aCA2a0A6b6ec227Bbc2bF5cEE86c2dC599d;

    IRewardTracker public gmxRewardsTracker = IRewardTracker(0x4e971a87900b931fF39d1Aad67697F49835400b6);

    function testYieldAccounting() public {
        vm.selectFork(vm.createFork(ARBITRUM_RPC_URL));

        FakeYieldSource source = new FakeYieldSource(200);
        IERC20 gt = IERC20(source.generatorToken());
        IERC20 yt = IERC20(source.yieldToken());
        SelfInsuredVault vault = new SelfInsuredVault("Self Insured YS:G Vault",
                                                      "siYS:G",
                                                      address(source));

        uint256 before;
        address user0 = createUser(0);
        source.mintGenerator(user0, 10e18);

        vm.startPrank(user0);
        gt.approve(address(vault), 2e18);
        assertEq(vault.previewDeposit(2e18), 2e18);
        vault.deposit(2e18, user0);
        assertEq(gt.balanceOf(user0), 8e18);
        assertEq(gt.balanceOf(address(vault)), 2e18);
        assertEq(vault.balanceOf(user0), 2e18);
        vm.stopPrank();

        assertEq(vault.cumulativeYield(), 0);

        // Verify yield accounting with one user
        vm.roll(block.number + 1);
        assertEq(vault.cumulativeYield(), 400e18);
        assertEq(vault.calculatePendingYield(user0), 400e18);
        assertEq(yt.balanceOf(address(vault)), 0);
        assertEq(yt.balanceOf(user0), 0);

        vm.prank(user0);
        vault.claim();

        assertEq(yt.balanceOf(address(vault)), 0);
        assertEq(yt.balanceOf(user0), 400e18);

        vm.prank(user0);
        vault.claim();
        assertEq(yt.balanceOf(address(vault)), 0);
        assertEq(yt.balanceOf(user0), 400e18);

        // Advance multiple blocks
        vm.roll(block.number + 2);
        assertEq(vault.cumulativeYield(), 1200e18);
        assertEq(vault.calculatePendingYield(user0), 800e18);

        vm.roll(block.number + 3);
        assertEq(vault.cumulativeYield(), 2400e18);
        assertEq(vault.calculatePendingYield(user0), 2000e18);

        assertEq(yt.balanceOf(address(vault)), 0);
        assertEq(yt.balanceOf(user0), 400e18);

        vm.prank(user0);
        vault.claim();
        assertEq(yt.balanceOf(address(vault)), 0);
        assertEq(yt.balanceOf(user0), 2400e18);

        // Advance multiple blocks, change yield rate, advance more blocks
        vm.roll(block.number + 2);
        assertEq(vault.cumulativeYield(), 3200e18);
        assertEq(vault.calculatePendingYield(user0), 800e18);

        before = source.amountPending(address(vault));
        source.setYieldPerBlock(100);
        assertEq(source.amountPending(address(vault)), before);

        vm.roll(block.number + 1);
        assertEq(vault.cumulativeYield(), 3400e18);
        assertEq(vault.calculatePendingYield(user0), 1000e18);

        vm.roll(block.number + 2);
        assertEq(vault.cumulativeYield(), 3800e18);
        assertEq(vault.calculatePendingYield(user0), 1400e18);

        vm.prank(user0);
        vault.claim();
        assertEq(vault.cumulativeYield(), 3800e18);
        assertEq(vault.calculatePendingYield(user0), 0);
        assertEq(yt.balanceOf(address(vault)), 0);
        assertEq(yt.balanceOf(user0), 3800e18);

        // Add a second user
        address user1 = createUser(1);
        source.mintGenerator(user1, 20e18);
        assertEq(vault.calculatePendingYield(user0), 0);
        assertEq(vault.calculatePendingYield(user1), 0);

        vm.roll(block.number + 1);
        assertEq(vault.calculatePendingYield(user0), 200e18);
        assertEq(vault.calculatePendingYield(user1), 0);

        // Second user deposits
        vm.startPrank(user1);
        gt.approve(address(vault), 4e18);
        assertEq(vault.previewDeposit(4e18), 4e18);
        before = vault.cumulativeYield();
        vault.deposit(4e18, user1);
        assertEq(vault.cumulativeYield(), before);
        assertEq(gt.balanceOf(user0), 8e18);
        assertEq(gt.balanceOf(user1), 16e18);
        assertEq(gt.balanceOf(address(vault)), 6e18);
        assertEq(vault.balanceOf(user0), 2e18);
        assertEq(vault.balanceOf(user1), 4e18);
        assertEq(vault.totalAssets(), 6e18);
        vm.stopPrank();

        vm.roll(block.number + 1);
        assertEq(vault.calculatePendingYield(user0), 400e18);
        assertEq(vault.calculatePendingYield(user1), 400e18);

        vm.roll(block.number + 1);
        assertEq(vault.calculatePendingYield(user0), 600e18);
        assertEq(vault.calculatePendingYield(user1), 800e18);

        vm.roll(block.number + 2);
        assertEq(vault.calculatePendingYield(user0), 1000e18);
        assertEq(vault.calculatePendingYield(user1), 1600e18);

        vm.prank(user0);
        vault.claim();
        assertEq(vault.calculatePendingYield(user0), 0);
        assertEq(yt.balanceOf(user0), 4800e18);

        vm.prank(user1);
        vault.claim();
        assertEq(vault.calculatePendingYield(user1), 0);
        assertEq(yt.balanceOf(user1), 1600e18);

        // Third user deposits, advance some blocks, change yield rate, users claim on different blocks
        address user2 = createUser(2);
        source.mintGenerator(user2, 20e18);
        vm.startPrank(user2);
        gt.approve(address(vault), 8e18);
        assertEq(vault.previewDeposit(8e18), 8e18);
        before = vault.cumulativeYield();
        vault.deposit(8e18, user2);
        assertEq(vault.cumulativeYield(), before);
        assertEq(gt.balanceOf(user0), 8e18);
        assertEq(gt.balanceOf(user1), 16e18);
        assertEq(gt.balanceOf(user2), 12e18);
        assertEq(gt.balanceOf(address(vault)), 14e18);
        assertEq(vault.balanceOf(user0), 2e18);
        assertEq(vault.balanceOf(user1), 4e18);
        assertEq(vault.balanceOf(user2), 8e18);
        assertEq(vault.totalAssets(), 14e18);
        vm.stopPrank();

        vm.roll(block.number + 1);
        assertEq(vault.calculatePendingYield(user0), 200e18);
        assertEq(vault.calculatePendingYield(user1), 400e18);
        assertEq(vault.calculatePendingYield(user2), 800e18);

        vm.roll(block.number + 1);
        assertEq(vault.calculatePendingYield(user0), 400e18);
        assertEq(vault.calculatePendingYield(user1), 800e18);
        assertEq(vault.calculatePendingYield(user2), 1600e18);

        source.setYieldPerBlock(300);

        vm.roll(block.number + 1);
        assertEq(vault.calculatePendingYield(user0), 1000e18);
        assertEq(vault.calculatePendingYield(user1), 2000e18);
        assertEq(vault.calculatePendingYield(user2), 4000e18);

        vm.prank(user1);
        vault.claim();
        assertEq(vault.calculatePendingYield(user0), 1000e18);
        assertEq(vault.calculatePendingYield(user1), 0);
        assertEq(vault.calculatePendingYield(user2), 4000e18);
        assertEq(yt.balanceOf(user0), 4800e18);
        assertEq(yt.balanceOf(user1), 3600e18);
        assertEq(yt.balanceOf(user2), 0);

        vm.roll(block.number + 1);
        assertEq(vault.calculatePendingYield(user0), 1600e18);
        assertEq(vault.calculatePendingYield(user1), 1200e18);
        assertEq(vault.calculatePendingYield(user2), 6400e18);

        vm.prank(user2);
        vault.claim();
        assertEq(vault.calculatePendingYield(user0), 1600e18);
        assertEq(vault.calculatePendingYield(user1), 1200e18);
        assertEq(vault.calculatePendingYield(user2), 0);
        assertEq(yt.balanceOf(user0), 4800e18);
        assertEq(yt.balanceOf(user1), 3600e18);
        assertEq(yt.balanceOf(user2), 6400e18);

        vm.prank(user0);
        vault.claim();
        vm.prank(user1);
        vault.claim();
        assertEq(vault.calculatePendingYield(user0), 0);
        assertEq(vault.calculatePendingYield(user1), 0);
        assertEq(vault.calculatePendingYield(user2), 0);
        assertEq(yt.balanceOf(user0), 6400e18);
        assertEq(yt.balanceOf(user1), 4800e18);
        assertEq(yt.balanceOf(user2), 6400e18);
    }

    function testDepegYieldAccounting() public {
        FakeYieldSource source = new FakeYieldSource(200);
        IERC20 gt = IERC20(source.generatorToken());
        IERC20 yt = IERC20(source.yieldToken());
        SelfInsuredVault vault = new SelfInsuredVault("Self Insured YS:G Vault",
                                                      "siYS:G",
                                                      address(source));

        // Set up Y2K insurance vault
        vm.prank(ADMIN);
        vaultFactory.createNewMarket(FEE, TOKEN_FRAX, DEPEG_AAA, beginEpoch, endEpoch, ORACLE_FRAX, "y2kFRAX_99*");

        hedge = vaultFactory.getVaults(1)[0];
        risk = vaultFactory.getVaults(1)[1];

        vHedge = Vault(hedge);
        vRisk = Vault(risk);

        // Set up the insurance provider
        Y2KEarthquakeV1InsuranceProvider provider = new Y2KEarthquakeV1InsuranceProvider(address(vHedge));

        // Set the insurance provider at 10% of expected yield
        IInsuranceProvider[] memory providers = new IInsuranceProvider[](1);
        providers[0] = IInsuranceProvider(provider);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1000;
        vault.setInsuranceProviders(providers, weights);

        // Alice deposits into self insured vault
        source.mintGenerator(ALICE, 10e18);

        vm.startPrank(ALICE);
        gt.approve(address(vault), 2e18);
        assertEq(vault.previewDeposit(2e18), 2e18);
        vault.deposit(2e18, ALICE);
        (uint256 epoch1, uint256 totalShares1, ) = vault.providerEpochs(address(provider), 0);
        (uint256 shares1, ) = vault.userEpochs(ALICE, epoch1);
        assertEq(totalShares1, 2e18);
        assertEq(shares1, 2e18);
        gt.approve(address(vault), 1e18);
        vault.deposit(1e18, ALICE);
        (, uint256 totalShares2, ) = vault.providerEpochs(address(provider), 0);
        (uint256 shares2, ) = vault.userEpochs(ALICE, epoch1);
        assertEq(totalShares2, 3e18);
        assertEq(shares2, 3e18);
        vm.stopPrank();
    }
}
