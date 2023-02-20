// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import "y2k-earthquake/interfaces/IVault.sol";

import "./BaseTest.sol";
import "../src/providers/Y2KEarthquakeV1InsuranceProvider.sol";

contract Y2KEarthquakeV1InsuranceProviderTest is BaseTest {

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

        /* console.log("Length:", vault.epochsLength()); */

        /* for (uint256 i = 0; i < vault.epochsLength(); i++) { */
        /*     uint256 epochId = vault.epochs(i); */
        /*     console.log("Epoch %d: ID=   %d", i, epochId); */
        /*     console.log("Epoch %d: begin %o", i, vault.idEpochBegin(epochId)); */
        /*     console.log("Epoch %d: ended %o", i, vault.idEpochEnded(epochId)); */
        /*     console.log("--"); */
        /* } */

        /* console.log("Current Epoch ID:", provider.currentEpoch()); */
    }

    function testNoActiveFork() public {
        forkToNoActiveEpoch();
        init();

        assertEq(provider.currentEpoch(), 0);
    }
}

