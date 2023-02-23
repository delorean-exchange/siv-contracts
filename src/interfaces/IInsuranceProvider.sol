//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

interface IInsuranceProvider {
    // ---- Token specification ---- //
    function insuredToken() external view returns (IERC20);
    function paymentToken() external view returns (IERC20);
    function rewardToken()  external view returns (IERC20);

    // ---- Epoch management ---- //
    function currentEpoch() external view returns (uint256);
    function nextEpoch() external view returns (uint256);
    function isNextEpochPurchasable() external view returns (bool);

    function nextEpochPurchased(address who) external returns (uint256);
    function currentEpochPurchased(address who) external returns (uint256);

    function purchaseForNextEpoch(address beneficiary, uint256 amountPremium) external;

    // ---- Payout management ---- //
    function pendingPayout(address who, uint256 epochId) external view returns (uint256);
    function claimPayout(address receiver, uint256 epochId) external returns (uint256);
    function pendingRewards(address who) external view returns (uint256);
    function claimRewards(address receiver) external returns (uint256);
}
