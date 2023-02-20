// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import "y2k-earthquake/interfaces/IVault.sol";

import "./BaseTest.sol";
import "../src/providers/Y2KEarthquakeV1InsuranceProvider.sol";

contract Y2KEarthquakeV1InsuranceProviderTest is BaseTest {

    IVault public y2kUSDTVault = IVault(0x76b1803530A3608bD5F1e4a8bdaf3007d7d2D7FA);

    function forkToActiveEarthquakeV1Vault() public {
        vm.selectFork(vm.createFork(ARBITRUM_RPC_URL, 61330138));
    }

    function testCallToY2K() public {
        forkToActiveEarthquakeV1Vault();

        assertEq(y2kUSDTVault.tokenInsured(), address(usdt));
    }

    function testBasics() public {
        forkToActiveEarthquakeV1Vault();

        Y2KEarthquakeV1InsuranceProvider provider = new Y2KEarthquakeV1InsuranceProvider(0x76b1803530A3608bD5F1e4a8bdaf3007d7d2D7FA);
        assertEq(provider.insuredToken(), address(usdt));
        assertEq(provider.paymentToken(), address(weth));
    }

}

