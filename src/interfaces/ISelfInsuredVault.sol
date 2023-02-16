// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

/* interface ISelfInsuredVault is IERC4626 { */
interface ISelfInsuredVault  {
    // -- ERC20 -- //
    /* function totalSupply() external view returns (uint256); */
    /* function balanceOf(address account) external view returns (uint256); */
    /* function transfer(address to, uint256 amount) external returns (bool); */
    /* function allowance(address owner, address spender) external view returns (uint256); */
    /* function approve(address spender, uint256 amount) external returns (bool); */
    /* function transferFrom(address from, address to, uint256 amount) external returns (bool); */

    /* // -- ERC4642 -- // */
    /* function asset() external view returns (address); */
    /* function totalAssets() external view returns (uint256); */
    /* function convertToShares(uint256 assets) external view returns (uint256 shares); */
    /* function convertToAssets(uint256 shares) external view returns (uint256 assets); */
    /* function maxDeposit(address receiver) external view returns (uint256); */

    /* function previewDeposit(uint256 assets) external view returns (uint256 shares); */
    /* function deposit(uint256 assets, address receiver) external returns (uint256 shares); */

    /* function maxMint(address receiver) external view returns (uint256 maxShares); */
    /* function previewMint(uint256 shares) external view returns (uint256 assets); */
    /* function mint(uint256 shares, address receiver) external returns (uint256 assets); */

    /* function maxWithdraw(address owner) external view returns (uint256 maxAssets); */
    /* function previewWithdraw(uint256 assets) external view returns (uint256 shares); */
    /* function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares); */

    /* function maxRedeem(address owner) external view returns (uint256 maxShares); */
    /* function previewRedeem(uint256 shares) external view returns (uint256 assets); */
    /* function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets); */

    /* // -- Fields -- // */
    /* function admin() external view returns (address); */
    /* /\* function insurances() external view returns (address[] memory); *\/ */
    /* /\* function ratios() external view returns (uint256[] memory); *\/ */

    /* // -- Rewards -- // */
    /* /\* function rewardTokens() external returns (address[] memory); *\/ */
    /* function previewClaim() external returns (uint256[] memory); */
    /* function claim() external returns (uint256[] memory); */

    /* // -- Admin only -- // */
    /* function setAdmin(address) external; */
    /* function setInsurances(address[] calldata, uint256[] calldata) external; */
}
