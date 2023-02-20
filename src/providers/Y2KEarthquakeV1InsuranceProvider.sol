// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import { Ownable } from "openzeppelin/access/Ownable.sol";
import "y2k-earthquake/Vault.sol";

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
        return address(0);
    }

    function activeEpoch() external override view returns (uint256) {
        return 0;
    }

    function nextEpoch() external override view returns (uint256) {
        return 0;
    }

    function isNextEpochOpen() external override view returns (bool) {
        return false;
    }

    function purchaseInsurance(address beneficiary, uint256 amountPremium) external override {
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
