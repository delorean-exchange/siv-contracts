// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import { Ownable } from "openzeppelin/access/Ownable.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "y2k-earthquake/src/Vault.sol";

import "../interfaces/IInsuranceProvider.sol";

contract Y2KEarthquakeV1InsuranceProvider is IInsuranceProvider, Ownable {
    using SafeERC20 for IERC20;

    Vault public vault;

    IERC20 public override insuredToken;
    IERC20 public override paymentToken;
    IERC20 public override constant rewardToken = IERC20(0x65c936f008BC34fE819bce9Fa5afD9dc2d49977f);  // Y2K token

    constructor(address vault_) {
        setInsuranceVault(vault_);
    }

    function setInsuranceVault(address vault_) public onlyOwner {
        vault = Vault(vault_);
        insuredToken = IERC20(address(vault.tokenInsured()));
        paymentToken = IERC20(address(vault.asset()));
    }

    function _currentEpoch() internal view returns (uint256) {
        if (vault.epochsLength() == 0) return 0;

        // TOOD: prob don't need a loop here
        int256 len = int256(vault.epochsLength());
        for (int256 i = len - 1; i >= 0 && i > len - 2; i--) {
            uint256 epochId = vault.epochs(uint256(i));
            if (block.timestamp > vault.idEpochBegin(epochId) && !vault.idEpochEnded(epochId)) {
                return epochId;
            }
        }

        return 0;
    }

    function currentEpoch() external override view returns (uint256) {
        return _currentEpoch();
    }

    function _nextEpoch() internal view returns (uint256) {
        uint256 len = vault.epochsLength();
        if (len == 0) return 0;
        uint256 epochId = vault.epochs(len - 1);
        if (block.timestamp > vault.idEpochBegin(epochId)) return 0;
        return epochId;
    }

    function nextEpoch() external override view returns (uint256) {
        return _nextEpoch();
    }

    function isNextEpochPurchasable() external override view returns (bool) {
        uint256 id = _nextEpoch();
        return id > 0 && block.timestamp <= vault.idEpochBegin(id);
    }

    function nextEpochPurchased(address who) external returns (uint256) {
        return vault.balanceOf(who, _nextEpoch());
    }

    function currentEpochPurchased(address who) external returns (uint256) {
        return vault.balanceOf(who, _currentEpoch());
    }

    function purchaseForNextEpoch(address beneficiary, uint256 amountPremium) external override {
        paymentToken.safeTransferFrom(msg.sender, address(this), amountPremium);
        paymentToken.approve(address(vault), 0);
        paymentToken.approve(address(vault), amountPremium);
        vault.deposit(_nextEpoch(), amountPremium, beneficiary);
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
