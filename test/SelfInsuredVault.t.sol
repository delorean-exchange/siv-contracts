// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

import { ControllerHelper } from "y2k-earthquake/test/ControllerHelper.sol";
import { Vault } from "y2k-earthquake/src/Vault.sol";

import { BaseTest } from "./BaseTest.sol";
import { BaseTest as DLXBaseTest } from "dlx/test/BaseTest.sol";
import { FakeYieldSource as DLXFakeYieldSource } from "dlx/test/helpers/FakeYieldSource.sol";
import { FakeYieldSourceVariableAmount as DLXFakeYieldSourceVariableAmount } from "dlx/test/helpers/FakeYieldSourceVariableAmount.sol";
import { FakeYieldTracker } from "./helpers/FakeYieldTracker.sol";

import { IWrappedETH } from "../src/interfaces/IWrappedETH.sol";
import { IRewardTracker } from "../src/interfaces/gmx/IRewardTracker.sol";
import { IInsuranceProvider } from "../src/interfaces/IInsuranceProvider.sol";
import { SelfInsuredVault } from "../src/vaults/SelfInsuredVault.sol";
import { Y2KEarthquakeV1InsuranceProvider } from "../src/providers/Y2KEarthquakeV1InsuranceProvider.sol";

contract SelfInsuredVaultTest is BaseTest, DLXBaseTest, ControllerHelper {
    address glpWallet = 0x3aaF2aCA2a0A6b6ec227Bbc2bF5cEE86c2dC599d;

    IRewardTracker public gmxRewardsTracker = IRewardTracker(0x4e971a87900b931fF39d1Aad67697F49835400b6);

    function testYieldAccounting() public {
        vm.selectFork(vm.createFork(ARBITRUM_RPC_URL));

        /* DLXFakeYieldSource source = new DLXFakeYieldSource(200); */
        DLXFakeYieldSource source = new DLXFakeYieldSource(200);
        FakeYieldTracker tracker = new FakeYieldTracker(200);

        /* IERC20 gt = IERC20(source.generatorToken()); */
        /* IERC20 yt = IERC20(source.yieldToken()); */

        // TODO: fix import namespacing...
        address gtA = address(source.generatorToken());
        address ytA = address(source.yieldToken());
        IERC20 gt = IERC20(gtA);
        IERC20 yt = IERC20(ytA);

        SelfInsuredVault vault = new SelfInsuredVault("Self Insured YS:G Vault",
                                                      "siYS:G",
                                                      address(source)
                                                      /* address(tracker) */
                                                      );
        source.setOwner(address(vault));

        uint256 before;
        address user0 = createTestUser(0);
        source.mintGenerator(user0, 10e18);

        vm.startPrank(user0);
        IERC20(gt).approve(address(vault), 2e18);
        assertEq(vault.previewDeposit(2e18), 2e18);
        vault.deposit(2e18, user0);
        assertEq(IERC20(gt).balanceOf(user0), 8e18);
        /* assertEq(IERC20(gt).balanceOf(address(vault)), 2e18); */
        assertEq(IERC20(gt).balanceOf(address(vault)), 0);
        assertEq(IERC20(gt).balanceOf(address(source)), 2e18);
        assertEq(vault.balanceOf(user0), 2e18);
        vm.stopPrank();

        assertEq(vault.cumulativeYield(), 0);

        // Verify yield accounting with one user
        vm.roll(block.number + 1);
        assertEq(vault.cumulativeYield(), 400e18);
        assertEq(vault.calculatePendingYield(user0), 400e18);
        assertEq(IERC20(yt).balanceOf(address(vault)), 0);
        assertEq(IERC20(yt).balanceOf(user0), 0);

        vm.prank(user0);
        vault.claimRewards();

        assertEq(IERC20(yt).balanceOf(address(vault)), 0);
        assertEq(IERC20(yt).balanceOf(user0), 400e18);

        vm.prank(user0);
        vault.claimRewards();
        assertEq(IERC20(yt).balanceOf(address(vault)), 0);
        assertEq(IERC20(yt).balanceOf(user0), 400e18);

        // Advance multiple blocks
        vm.roll(block.number + 2);
        assertEq(vault.cumulativeYield(), 1200e18);
        assertEq(vault.calculatePendingYield(user0), 800e18);

        vm.roll(block.number + 3);
        assertEq(vault.cumulativeYield(), 2400e18);
        assertEq(vault.calculatePendingYield(user0), 2000e18);

        assertEq(IERC20(yt).balanceOf(address(vault)), 0);
        assertEq(IERC20(yt).balanceOf(user0), 400e18);

        vm.prank(user0);
        vault.claimRewards();
        assertEq(IERC20(yt).balanceOf(address(vault)), 0);
        assertEq(IERC20(yt).balanceOf(user0), 2400e18);

        // Advance multiple blocks, change yield rate, advance more blocks
        vm.roll(block.number + 2);
        assertEq(vault.cumulativeYield(), 3200e18);
        assertEq(vault.calculatePendingYield(user0), 800e18);

        before = source.amountPending();
        source.setYieldPerBlock(100);
        assertEq(source.amountPending(), before);

        vm.roll(block.number + 1);
        assertEq(vault.cumulativeYield(), 3400e18);
        assertEq(vault.calculatePendingYield(user0), 1000e18);

        vm.roll(block.number + 2);
        assertEq(vault.cumulativeYield(), 3800e18);
        assertEq(vault.calculatePendingYield(user0), 1400e18);

        vm.prank(user0);
        vault.claimRewards();
        assertEq(vault.cumulativeYield(), 3800e18);
        assertEq(vault.calculatePendingYield(user0), 0);
        assertEq(IERC20(yt).balanceOf(address(vault)), 0);
        assertEq(IERC20(yt).balanceOf(user0), 3800e18);

        // Add a second user
        address user1 = createTestUser(1);
        source.mintGenerator(user1, 20e18);
        assertEq(vault.calculatePendingYield(user0), 0);
        assertEq(vault.calculatePendingYield(user1), 0);

        vm.roll(block.number + 1);
        assertEq(vault.calculatePendingYield(user0), 200e18);
        assertEq(vault.calculatePendingYield(user1), 0);

        // Second user deposits
        vm.startPrank(user1);
        IERC20(gt).approve(address(vault), 4e18);
        assertEq(vault.previewDeposit(4e18), 4e18);

        console.log("");
        console.log("get before");
        before = vault.cumulativeYield();

        vault.deposit(4e18, user1);
        console.log("");
        console.log("get after");
        assertEq(vault.cumulativeYield(), before);
        assertEq(IERC20(gt).balanceOf(user0), 8e18);
        assertEq(IERC20(gt).balanceOf(user1), 16e18);
        assertEq(IERC20(gt).balanceOf(address(vault)), 0);
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
        vault.claimRewards();
        assertEq(vault.calculatePendingYield(user0), 0);
        assertEq(yt.balanceOf(user0), 4800e18);

        vm.prank(user1);
        vault.claimRewards();
        assertEq(vault.calculatePendingYield(user1), 0);
        assertEq(yt.balanceOf(user1), 1600e18);

        return;

        // Third user deposits, advance some blocks, change yield rate, users claim on different blocks
        address user2 = createTestUser(2);
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
        vault.claimRewards();
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
        vault.claimRewards();
        assertEq(vault.calculatePendingYield(user0), 1600e18);
        assertEq(vault.calculatePendingYield(user1), 1200e18);
        assertEq(vault.calculatePendingYield(user2), 0);
        assertEq(yt.balanceOf(user0), 4800e18);
        assertEq(yt.balanceOf(user1), 3600e18);
        assertEq(yt.balanceOf(user2), 6400e18);

        vm.prank(user0);
        vault.claimRewards();
        vm.prank(user1);
        vault.claimRewards();
        assertEq(vault.calculatePendingYield(user0), 0);
        assertEq(vault.calculatePendingYield(user1), 0);
        assertEq(vault.calculatePendingYield(user2), 0);
        assertEq(yt.balanceOf(user0), 6400e18);
        assertEq(yt.balanceOf(user1), 4800e18);
        assertEq(yt.balanceOf(user2), 6400e18);
    }

    function testPurchaseWithDLXFutureYield() public {
        depositDepeg();

        // TODO: Consolidate this setup code? it is duped in `testDepegYieldAccounting`
        FakeYieldTracker tracker = new FakeYieldTracker(200);
        IERC20 gt = IERC20(tracker.generatorToken());
        IERC20 yt = IERC20(tracker.yieldToken());
        vm.prank(ADMIN);
        SelfInsuredVault vault = new SelfInsuredVault("Self Insured YS:G Vault",
                                                      "siYS:G",
                                                      address(tracker));

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
        weights[0] = 10_00;

        // Set up Delorean market

        vm.prank(ADMIN);
        vault.setInsuranceProviders(providers, weights);

        tracker.mintGenerator(ALICE, 10e18);

        vm.startPrank(ALICE);
        gt.approve(address(vault), 2e18);
        assertEq(vault.previewDeposit(2e18), 2e18);
        vault.deposit(2e18, ALICE);
    }

    function testDepegYieldAccounting() public {
        depositDepeg();

        FakeYieldTracker tracker = new FakeYieldTracker(200);
        IERC20 gt = IERC20(tracker.generatorToken());
        IERC20 yt = IERC20(tracker.yieldToken());
        vm.prank(ADMIN);
        SelfInsuredVault vault = new SelfInsuredVault("Self Insured YS:G Vault",
                                                      "siYS:G",
                                                      address(tracker));

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
        weights[0] = 10_00;

        vm.prank(ADMIN);
        vault.setInsuranceProviders(providers, weights);

        // Alice deposits into self insured vault
        tracker.mintGenerator(ALICE, 10e18);

        vm.startPrank(ALICE);
        gt.approve(address(vault), 2e18);
        assertEq(vault.previewDeposit(2e18), 2e18);
        vault.deposit(2e18, ALICE);
        {
            (uint256 epochId, uint256 totalShares, , ) = vault.providerEpochs(address(provider), 0);
            assertEq(totalShares, 2e18);

            (uint256 startEpochId,
             uint256 shares,
             uint256 nextEpochId,
             uint256 nextShares,
             uint256 accumulatdPayouts) = vault.userEpochTrackers(ALICE);
            assertEq(startEpochId, 0);
            assertEq(shares, 0);
            assertEq(nextEpochId, epochId);
            assertEq(nextShares, 2e18);
            assertEq(accumulatdPayouts, 0);
        }

        gt.approve(address(vault), 1e18);
        vault.deposit(1e18, ALICE);
        {
            (uint256 epochId, uint256 totalShares, , ) = vault.providerEpochs(address(provider), 0);
            assertEq(totalShares, 3e18);

            (uint256 startEpochId,
             uint256 shares,
             uint256 nextEpochId,
             uint256 nextShares,
             uint256 accumulatdPayouts) = vault.userEpochTrackers(ALICE);
            assertEq(startEpochId, 0);
            assertEq(shares, 0);
            assertEq(nextEpochId, epochId);
            assertEq(nextShares, 3e18);
            assertEq(accumulatdPayouts, 0);
        }
        vm.stopPrank();

        // Move ahead to next epoch, end it
        vm.warp(beginEpoch + 10 days);
        vm.startPrank(vHedge.controller());
        vHedge.endEpoch(provider.currentEpoch());
        vm.stopPrank();

        // Create two more epochs
        vm.startPrank(vHedge.factory());
        vHedge.createAssets(endEpoch, endEpoch + 1 days, 5);
        vm.stopPrank();

        vm.startPrank(vHedge.factory());
        vHedge.createAssets(endEpoch + 1 days, endEpoch + 2 days, 5);
        vm.stopPrank();

        // Move into the first epoch, with one more created epoch available after it
        vm.warp(endEpoch + 10 minutes);
        vm.startPrank(vHedge.controller());
        vm.stopPrank();

        // Alice deposits more shares
        vm.startPrank(ALICE);
        gt.approve(address(vault), 3e18);
        vault.deposit(3e18, ALICE);
        vm.stopPrank();

        vault.pprintEpochs();

        {
            (uint256 epochId0, uint256 totalShares0, , ) = vault.providerEpochs(address(provider), 0);
            assertEq(totalShares0, 3e18);
            (uint256 epochId1, uint256 totalShares1, , ) = vault.providerEpochs(address(provider), 1);
            assertEq(totalShares1, 3e18);
            (uint256 epochId2, uint256 totalShares2, , ) = vault.providerEpochs(address(provider), 2);
            assertEq(totalShares2, 6e18);

            (uint256 startEpochId,
             uint256 shares,
             uint256 nextEpochId,
             uint256 nextShares,
             uint256 accumulatdPayouts) = vault.userEpochTrackers(ALICE);

            assertEq(startEpochId, epochId0);
            assertEq(nextEpochId, epochId2);
            assertEq(shares, 3e18);
            assertEq(nextShares, 6e18);
            assertEq(accumulatdPayouts, 0);
        }

        // Code below obseleted by refactor

        /* (uint256 shares1, ) = vault.userEpochs(ALICE, epoch1); */
        /* assertEq(totalShares1, 2e18); */
        /* assertEq(shares1, 2e18); */
        /* gt.approve(address(vault), 1e18); */
        /* vault.deposit(1e18, ALICE); */
        /* (, uint256 totalShares2, , ) = vault.providerEpochs(address(provider), 0); */
        /* (uint256 shares2, ) = vault.userEpochs(ALICE, epoch1); */
        /* assertEq(totalShares2, 3e18); */
        /* assertEq(shares2, 3e18); */
        /* vm.stopPrank(); */

        /* console.log("Yield token", address(tracker.yieldToken())); */
        /* console.log("ADMIN WETH", IERC20(WETH).balanceOf(ADMIN)); */
        /* tracker.mintYield(address(vault), 10000e18); */

        /* // TODO: Use DLX to get future WETH yield */
        /* vm.deal(address(vault), 200 ether); */
        /* vm.prank(address(vault)); */
        /* IWrappedETH(address(weth)).deposit{value: 100 ether}(); */

        /* vm.prank(ADMIN); */
        /* vault.purchaseForNextEpoch(); */

        /* return; */

        /* vm.warp(beginEpoch + 10 days); */

        /* controller.triggerDepeg(SINGLE_MARKET_INDEX, endEpoch); */

        /* uint256 pending = provider.pendingPayouts(); */
        /* console.log("pending", pending); */

        /* uint256 before = IERC20(weth).balanceOf(user0); */
        /* uint256 result = provider.claimPayouts(); */
        /* uint256 delta = IERC20(weth).balanceOf(user0) - before; */
    }
}
