// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "../Y2KEarthQuakeV2Helper.sol";

import {SelfInsuredVault} from "../../src/vaults/SelfInsuredVault.sol";
import {StargateLPYieldSource} from "../../src/sources/StargateLPYieldSource.sol";
import {Y2KEarthquakeV2InsuranceProvider, IInsuranceProvider} from "../../src/providers/Y2KEarthquakeV2InsuranceProvider.sol";

import {IYieldSource} from "../../src/interfaces/IYieldSource.sol";
import {ILPStaking} from "../../src/interfaces/stargate/ILPStaking.sol";

contract EndToEndSIVTest is Y2KEarthQuakeV2Helper {
    uint256 public constant LP_DEPOSIT_AMOUNT = 10000000000;
    uint256 public constant WETH_DEPOSIT_AMOUNT = 10 ether;

    address public siv;
    address public insuranceProvider;
    address public yieldSource;

    function setUp() public override {
        yieldSource = address(
            new StargateLPYieldSource(
                STG_PID,
                STG_LPTOKEN,
                STG_STAKING,
                SUSHISWAP_ROUTER
            )
        );
        siv = address(new SelfInsuredVault(WETH, yieldSource));

        IYieldSource(yieldSource).transferOwnership(siv);
    }

    // Single epoch with multiple user
    function testEndToEndEndEpoch() public {
        // create market
        Y2KEarthQuakeV2Helper.setUp();
        Y2KEarthQuakeV2Helper.createEndEpochMarket();

        // setup insurance provider
        insuranceProvider = address(
            new Y2KEarthquakeV2InsuranceProvider(collateral)
        );
        IInsuranceProvider(insuranceProvider).transferOwnership(
            siv
        );
        SelfInsuredVault(siv).addInsuranceProvider(
            IInsuranceProvider(insuranceProvider),
            100
        );

        vm.warp(begin - 1 days);

        vm.startPrank(USER);

        // deal ether
        vm.deal(USER, WETH_DEPOSIT_AMOUNT);
        IWETH(WETH).deposit{value: WETH_DEPOSIT_AMOUNT}();

        // approve token
        IERC20(WETH).approve(premium, WETH_DEPOSIT_AMOUNT);
        IERC20(STG_LPTOKEN).approve(siv, LP_DEPOSIT_AMOUNT);

        // deposit in SIV
        VaultV2(premium).deposit(epochId, WETH_DEPOSIT_AMOUNT, USER);
        SelfInsuredVault(siv).deposit(LP_DEPOSIT_AMOUNT, USER);

        vm.stopPrank();

        // generate yields
        vm.roll(block.number + 100000000);

        // check farming balance
        uint256 SIV_WETH_AMOUNT = IYieldSource(yieldSource).pendingYieldInToken(
            WETH
        );

        // purchase for epoch
        SelfInsuredVault(siv).purchaseInsuranceForNextEpoch();

        // none left at siv
        assertEq(IERC20(WETH).balanceOf(siv), 0);

        // check deposit balances
        assertEq(
            VaultV2(premium).balanceOf(USER, epochId),
            WETH_DEPOSIT_AMOUNT
        );
        assertEq(VaultV2(collateral).balanceOf(insuranceProvider, epochId), SIV_WETH_AMOUNT);

        // warp to epoch end
        vm.warp(end + 1 days);

        // trigger end of epoch
        controller.triggerEndEpoch(marketId, epochId);

        // check vault balances on withdraw
        uint256 amountAfterFee = SIV_WETH_AMOUNT + helperCalculateFeeAdjustedValue(
            WETH_DEPOSIT_AMOUNT,
            FEE
        );
        assertEq(
            VaultV2(premium).previewWithdraw(epochId, WETH_DEPOSIT_AMOUNT),
            0
        );
        assertEq(
            VaultV2(collateral).previewWithdraw(epochId, SIV_WETH_AMOUNT),
            amountAfterFee
        );

        // withdraw from vaults
        vm.prank(USER);
        SelfInsuredVault(siv).claimPayouts();

        // check vaults balance
        assertEq(VaultV2(collateral).balanceOf(siv, epochId), 0);

        // check user balance
        assertEq(IERC20(WETH).balanceOf(USER), amountAfterFee);
    }

    // Multiple epochs with single user

    // Multiple insurance providers
}
