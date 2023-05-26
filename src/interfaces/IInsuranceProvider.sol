//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

abstract contract IInsuranceProvider is Ownable {
    // ---- Token specification ---- //
    function insuredToken() external view virtual returns (IERC20);

    function paymentToken() external view virtual returns (IERC20);

    function rewardToken() external view virtual returns (IERC20);

    // ---- Epoch management ---- //
    function currentEpoch() external view virtual returns (uint256);

    function followingEpoch(uint256) external view virtual returns (uint256);

    function nextEpoch() external view virtual returns (uint256);

    function isNextEpochPurchasable() external view virtual returns (bool);

    function epochDuration() external view virtual returns (uint256);

    function nextEpochPurchased() external view virtual returns (uint256);

    function currentEpochPurchased() external view virtual returns (uint256);

    function purchaseForNextEpoch(uint256 amountPremium) external virtual;

    // ---- Payout management ---- //
    function pendingPayouts() external view virtual returns (uint256);

    function claimPayouts() external virtual returns (uint256);

    function pendingRewards() external view virtual returns (uint256);

    function claimRewards() external virtual returns (uint256);
}
