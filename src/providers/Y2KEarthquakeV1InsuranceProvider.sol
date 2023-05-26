// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ERC1155Holder} from "openzeppelin/token/ERC1155/utils/ERC1155Holder.sol";
import {Vault} from "y2k-earthquake/src/legacy_v1/Vault.sol";

import {IInsuranceProvider} from "../interfaces/IInsuranceProvider.sol";

/// @title Insurance Provider for Y2k Earthquake v1
/// @author Delorean Exchange x Y2K Finance
/// @dev All function calls are currently implemented without side effects
contract Y2KEarthquakeV1InsuranceProvider is
    IInsuranceProvider,
    ERC1155Holder
{
    using SafeERC20 for IERC20;

    /// @notice Earthquake vault
    Vault public vault;

    /// @notice Token for insurance
    IERC20 public override insuredToken;

    /// @notice Token for payment of insurance
    IERC20 public override paymentToken;

    /// @notice Y2k reward token
    IERC20 public constant override rewardToken =
        IERC20(0x65c936f008BC34fE819bce9Fa5afD9dc2d49977f); // Y2K token

    /// @notice Last claimed epoch index
    uint256 public nextEpochIndexToClaim;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor
     * @param _vault Address of Earthquake vault.
     */
    constructor(address _vault) {
        _setInsuranceVault(_vault);
    }

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set vault address. Only owner can call do this.
     * @param _vault Address of Earthquake vault.
     */
    function setInsuranceVault(address _vault) public onlyOwner {
        _setInsuranceVault(_vault);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current epoch.
     * @dev If epoch iteration takes long, then we can think of binary search
     */
    function currentEpoch() public override view returns (uint256) {
        uint256 len = vault.epochsLength();
        if (len > 0) {
            for (uint256 i = len - 1; i >= 0; i--) {
                uint256 epochId = vault.epochs(i);
                if (block.timestamp > epochId) {
                    break;
                }

                uint256 epochBegin = vault.idEpochBegin(epochId);
                if (
                    block.timestamp > epochBegin &&
                    block.timestamp <= epochId &&
                    !vault.idEpochEnded(epochId)
                ) {
                    return epochId;
                }
            }
        }
        return 0;
    }

    /**
     * @notice Returns the next epoch.
     * @dev We assum last epoch is always next epoch
     *   should we handle the sitaution where there are two epochs at the end,
     *   both of which are not started? it is unlikely but may happen if there is a
     *   misconfiguration on Y2K side
     */
    function nextEpoch() public override view returns (uint256) {
        uint256 len = vault.epochsLength();
        if (len == 0) return 0;
        uint256 epochId = vault.epochs(len - 1);
        if (block.timestamp > vault.idEpochBegin(epochId)) return 0;
        return epochId;
    }

    // TODO: BAD ITERATION, remove by rearchitect
    /**
     * @notice Returns the following epoch id.
     * @param epochId Epoch Id
     */
    function followingEpoch(uint256 epochId) external override view returns (uint256) {
        uint256 len = vault.epochsLength();
        for (uint256 i = 1; i < len; i++) {
            if (vault.epochs(i - 1) == epochId) {
                return vault.epochs(i);
            }
        }
        return 0;
    }

    /**
     * @notice Returns the duration of the current epoch.
     */
    function epochDuration() external view override returns (uint256) {
        uint256 id = currentEpoch();
        return id - vault.idEpochBegin(id);
    }

    /**
     * @notice Is next epoch purchasable.
     */
    function isNextEpochPurchasable() external view override returns (bool) {
        uint256 id = nextEpoch();
        return id > 0 && block.timestamp <= vault.idEpochBegin(id);
    }

    /**
     * @notice Returns if next epoch is purchased.
     */
    function nextEpochPurchased() external override view returns (uint256) {
        return vault.balanceOf(address(this), nextEpoch());
    }

    /**
     * @notice Returns if current epoch is purchased.
     */
    function currentEpochPurchased() external override view returns (uint256) {
        return vault.balanceOf(address(this), currentEpoch());
    }

    /**
     * @notice Pending payouts.
     */
    function pendingPayouts() external view override returns (uint256) {
        uint256 pending = 0;
        uint256 len = vault.epochsLength();
        for (uint256 i = nextEpochIndexToClaim + 1; i < len; i++) {
            pending += _pendingPayoutForEpoch(vault.epochs(i));
        }
        return pending;
    }

    /**
     * @notice Pending rewards, zero for now.
     */
    function pendingRewards() external view override returns (uint256) {
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                                OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Purchase next epoch.
     * @param amountPremium Premium amount for insurance
     */
    function purchaseForNextEpoch(
        uint256 amountPremium
    ) external override onlyOwner {
        paymentToken.safeTransferFrom(msg.sender, address(this), amountPremium);
        paymentToken.safeApprove(address(vault), amountPremium);
        vault.deposit(nextEpoch(), amountPremium, address(this));
    }

    /**
     * @notice Claim payouts.
     */
    function claimPayouts() external override returns (uint256 amount) {
        uint256 len = vault.epochsLength();
        uint256 i = nextEpochIndexToClaim;
        for (; i < len; i++) {
            uint256 epochId = vault.epochs(i);
            if (
                block.timestamp <= epochId ||
                !vault.idEpochEnded(epochId)
            ) {
                break;
            }

            uint256 assets = vault.balanceOf(address(this), epochId);
            amount += vault.withdraw(
                epochId,
                assets,
                address(this),
                address(this)
            );
        }
        nextEpochIndexToClaim = i;
        if (amount > 0) {
            paymentToken.safeTransfer(msg.sender, amount);
        }
    }

    /**
     * @notice Claim rewards, zero for now.
     */
    function claimRewards() external override returns (uint256) {
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set vault address.
     * @dev Last claimed epoch index is also updated to 0.
     * @param _vault Address of Earthquake vault.
     */
    function _setInsuranceVault(address _vault) internal {
        require(_vault != address(vault), "Vault already set");
        vault = Vault(_vault);
        insuredToken = IERC20(address(vault.tokenInsured()));
        paymentToken = IERC20(address(vault.asset()));
        nextEpochIndexToClaim = 0;
    }

    /**
     * @notice Returns pending payouts for specifc epoch.
     * @param epochId Epoch Id
     * @return entitledShares Payout amount
     */
    function _pendingPayoutForEpoch(
        uint256 epochId
    ) internal view returns (uint256 entitledShares) {
        if (vault.idFinalTVL(epochId) == 0) return 0;
        uint256 assets = vault.balanceOf(address(this), epochId);
        entitledShares = vault.previewWithdraw(epochId, assets);
        // Mirror Y2K Vault logic for deducting fee
        if (entitledShares > assets) {
            uint256 premium = entitledShares - assets;
            uint256 feeValue = vault.calculateWithdrawalFeeValue(
                premium,
                epochId
            );
            entitledShares = entitledShares - feeValue;
        }
        return entitledShares;
    }
}
