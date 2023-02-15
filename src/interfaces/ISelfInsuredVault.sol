// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ISelfInsuredVault {
    // -- Fields -- //
    function admin() public returns (address);
    function underlying() public returns (address);
    function insurances() public returns (address[]);
    function ratios() public returns (uint256[]);

    // -- Vault entry and exit -- //
    function deposit(uint256 amount) external virtual;
    function withdraw(uint256 amount) external virtual;
    function claim() external virtual;

    // -- Admin only -- //
    function setAdmin(address) external virtual;
    function setInsurances(address[] calldata, uint256[] calldata) external virtual;
}
