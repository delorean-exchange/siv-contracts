// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import { Ownable } from "openzeppelin/access/Ownable.sol";
import "y2k-earthquake/src/Vault.sol";

import "../interfaces/IInsuranceProvider.sol";

contract Y2KEarthquakeV1InsuranceProvider is IInsuranceProvider, Ownable {
    Vault public vault;

    constructor(address vault_) {
        console.log("constructor", address(vault_));
        vault = Vault(vault_);
    }

    function setInsuranceAddress(address vault_) external onlyOwner {
        vault = Vault(vault_);
    }

    function insuredToken() external override view returns (address) {
        return vault.tokenInsured();
    }

    function paymentToken() external override view returns (address) {
        return address(vault.asset());
    }

    function rewardToken()  external override view returns (address) {
        return address(0x65c936f008BC34fE819bce9Fa5afD9dc2d49977f);  // Y2K token
    }

    // TODO: This method likely isn't needed for anything external
    function currentEpoch() external override view returns (uint256) {
        if (vault.epochsLength() == 0) return 0;

        // TODO: We only need to check at most the last two epochs
        for (int256 i = int256(vault.epochsLength()) - 1; i >= 0; i--) {
            uint256 epochId = vault.epochs(uint256(i));
            if (block.timestamp > vault.idEpochBegin(epochId) && !vault.idEpochEnded(epochId)) {
                return epochId;
            }
        }

        return 0;
    }

    function nextEpoch() external override view returns (uint256) {
        uint256 len = vault.epochsLength();
        if (len == 0) return 0;
        uint256 epochId = vault.epochs(len - 1);
        if (block.timestamp <= vault.idEpochBegin(epochId)) return 0;
        return 0;
    }

    function isNextEpochPurchasable() external override view returns (bool) {
        return false;
    }

    function nextEpochPurchased(address who) external returns (uint256) {
        return 0;
    }

    function currentEpochPurchased(address who) external returns (uint256) {
        return 0;
    }

    function purchaseForNextEpoch(address beneficiary, uint256 amountPremium) external override {
    }

    function pendingPayout(address who, uint256 epochId) external override view returns (uint256) {
        return 0;
    }

    function claimPayout(address receiver, uint256 epochId) external override returns (uint256) {
        return 0;
    }

    function pendingRewards(address who) external override view returns (uint256) {
        return 0;
    }

    function claimRewards(address receiver) external override returns (uint256) {
        return 0;
    }
}
