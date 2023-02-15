// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "../interfaces/ISelfInsuredVault.sol";

contract SelfInsuredVault is ISelfInsuredVault, ERC20 {
    address public admin;
    address[] public insurances;
    uint256[] public ratios;
    address[] public rewardTokens;

    address public asset;

    modifier onlyAdmin {
        require(msg.sender == admin);
        _;
    }

    constructor(string memory name_,
                string memory symbol_,
                address asset_) ERC20(name_, symbol_) {
        asset = asset_;
    }

    // -- ERC4642: Asset -- //
    /* function asset() external override view returns (address) { */
    /*     return address(0); */
    /* } */

    function totalAssets() external override view returns (uint256) {
        return 0;
    }


    // -- ERC4642: Share conversion -- //
    function convertToShares(uint256 assets) external override view returns (uint256 shares) {
        return 0;
    }

    function convertToAssets(uint256 shares) external override view returns (uint256 assets) {
        return 0;
    }

    // -- ERC4642: Deposit -- //
    function maxDeposit(address receiver) external override view returns (uint256 shares) {
        return 0;
    }

    function previewDeposit(uint256 assets) external override view returns (uint256 shares) {
        return 0;
    }

    function deposit(uint256 assets, address receiver) external override returns (uint256 shares) {
        return 0;
    }

    // -- ERC4642: Mint -- //
    function maxMint(address receiver) external override view returns (uint256 maxShares) {
        return 0;
    }

    function previewMint(uint256 shares) external override view returns (uint256 assets) {
        return 0;
    }

    function mint(uint256 shares, address receiver) external override returns (uint256 assets) {
        return 0;
    }

    // -- ERC4642: Withdraw -- //
    function maxWithdraw(address owner) external override view returns (uint256 maxAssets) {
        return 0;
    }

    function previewWithdraw(uint256 assets) external override view returns (uint256 shares) {
        return 0;
    }

    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256 shares) {
        return 0;
    }

    // -- ERC4642: Redeem -- //
    function maxRedeem(address owner) external override view returns (uint256 maxShares) {
        return 0;
    }

    function previewRedeem(uint256 shares) external override view returns (uint256 assets) {
        return 0;
    }

    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256 assets) {
        return 0;
    }

    // -- Rewards -- //
    function previewClaim() external override returns (uint256[] memory) {
        return new uint256[](0);
    }

    function claim() external override returns (uint256[] memory) {
        return new uint256[](0);
    }

    // -- Admin only -- //
    function setAdmin(address) external override onlyAdmin {
    }

    function setInsurances(address[] calldata, uint256[] calldata) external override onlyAdmin {
    }
}
