// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import { Ownable } from "openzeppelin/access/Ownable.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { ERC1155Holder } from "openzeppelin/token/ERC1155/utils/ERC1155Holder.sol";
import { Vault } from  "y2k-earthquake/src/Vault.sol";

import { IInsuranceProvider } from  "../interfaces/IInsuranceProvider.sol";

contract Y2KEarthquakeV1InsuranceProvider is IInsuranceProvider, Ownable, ERC1155Holder {
    using SafeERC20 for IERC20;

    Vault public vault;

    IERC20 public override insuredToken;
    IERC20 public override paymentToken;
    IERC20 public override constant rewardToken = IERC20(0x65c936f008BC34fE819bce9Fa5afD9dc2d49977f);  // Y2K token

    address public immutable beneficiary;

    uint256 public claimedEpochIndex;

    constructor(address vault_, address beneficiary_) {
        setInsuranceVault(vault_);
        beneficiary = beneficiary_;

        claimedEpochIndex = 0;
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
            // TODO: if current epoch is manually ended, should still return it's id
            // vault.idEpochEnded(epochId) --> 
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
        // TODO: what if there are two non-started epochs? handle it with a loop
        if (block.timestamp > vault.idEpochBegin(epochId)) return 0;
        return epochId;
    }

    function followingEpoch(uint256 epochId) external view returns (uint256) {
        for (uint256 i = 1; i < vault.epochsLength(); i++) {
            if (vault.epochs(i - 1) == epochId) {
                return vault.epochs(i);
            }
        }
        return 0;
    }

    function nextEpoch() external override view returns (uint256) {
        return _nextEpoch();
    }

    function epochDuration() external override view returns (uint256) {
        uint256 id = _nextEpoch();
        return id - vault.idEpochBegin(id);
    }

    function isNextEpochPurchasable() external override view returns (bool) {
        uint256 id = _nextEpoch();
        return id > 0 && block.timestamp <= vault.idEpochBegin(id);
    }

    function nextEpochPurchased() external view returns (uint256) {
        return vault.balanceOf(address(this), _nextEpoch());
    }

    function currentEpochPurchased() external view returns (uint256) {
        return vault.balanceOf(address(this), _currentEpoch());
    }

    function purchaseForNextEpoch(uint256 amountPremium) external override {
        paymentToken.safeTransferFrom(msg.sender, address(this), amountPremium);
        paymentToken.safeApprove(address(vault), amountPremium);
        vault.deposit(_nextEpoch(), amountPremium, address(this));
    }

    function _pendingPayoutForEpoch(uint256 epochId) internal view returns (uint256) {
        if (vault.idFinalTVL(epochId) == 0) return 0;
        uint256 assets = vault.balanceOf(address(this), epochId);
        uint256 entitledShares = vault.previewWithdraw(epochId, assets);
        // Mirror Y2K Vault logic for deducting fee
        if (entitledShares > assets) {
            uint256 premium = entitledShares - assets;
            uint256 feeValue = vault.calculateWithdrawalFeeValue(premium, epochId);
            entitledShares = entitledShares - feeValue;
        }
        return entitledShares;
    }

    function pendingPayouts() external override view returns (uint256) {
        uint256 pending = 0;
        uint256 len = vault.epochsLength();
        for (uint256 i = claimedEpochIndex; i < len; i++) {
            pending += _pendingPayoutForEpoch(vault.epochs(i));
        }
        return pending;
    }

    function _claimPayoutForEpoch(uint256 epochId) internal returns (uint256) {
        uint256 assets = vault.balanceOf(address(this), epochId);
        uint256 amount = vault.withdraw(epochId, assets, address(this), address(this));
        console.log("claim for epoch gave:", epochId, assets);
        console.log("claim for epoch gave:", epochId, amount);
        claimedEpochIndex = vault.epochsLength();
        return amount;
    }

    function claimPayouts() external override returns (uint256) {
        console.log("claimPayouts");

        uint256 amount = 0;
        uint256 len = vault.epochsLength();
        // TODO: double check this logic, as it may not be 100% right.
        // Does it correctly handle the current epoch?
        for (uint256 i = claimedEpochIndex; i < len; i++) {
            console.log("--> claiming", i);
            uint256 a = _claimPayoutForEpoch(vault.epochs(i));
            console.log("--> ", a);
            amount += a;
        }

        console.log("The paymentToken is:", address(paymentToken));

        paymentToken.safeTransfer(beneficiary, amount);
        return amount;
    }

    function pendingRewards() external override view returns (uint256) {
        return 0;
    }

    function claimRewards() external override returns (uint256) {
        return 0;
    }
}
