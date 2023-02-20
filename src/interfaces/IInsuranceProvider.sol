//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IInsuranceProvider {
    // ---- Token specification ---- //
    // insuredToken is the token covered by the insurance policy.
    function insuredToken() external view returns (address);

    // paymentToken is the token used to purchase insurance and pay out in the case
    // of a claim.
    function paymentToken() external view returns (address);

    // rewardToken is the incentive rewards token.
    function rewardToken()  external view returns (address);


    // ---- Epoch management ---- //
    // activeEpoch is the active insurance policy's epoch.
    function activeEpoch() external view returns (uint256);

    // nextEpoch is the next insurance epoch.
    function nextEpoch() external view returns (uint256);

    // isNextEpochOpen returns true if the next epoch is open for purchasing insurance.
    function isNextEpochOpen() external view returns (bool);

    // purchaseInsurance purchases the specified amount of insurance. The insurnace
    // policy is assigned to the specified address.
    function purchaseInsurance(address beneficiary, uint256 amountPremium) external;


    // ---- Payout management ---- //
    // pendingPayout returns the amount of payment due to the specified address.
    function pendingPayout(address who, uint256 epochId) external view returns (uint256);

    // claimPayout sends the caller's pending payouts for an epoch to the specified address.
    function claimPayout(address receiver, uint256 epochId) external returns (uint256);

    // pendingRewards returns the amount of pending incentives.
    function pendingRewards(address who) external view returns (uint256);

    // claimRewards sends the caller's pending rewareds to the specified address.
    function claimRewards(address receiver) external returns (uint256);
}
