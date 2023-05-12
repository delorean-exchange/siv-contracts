// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

abstract contract IYieldSource {
    function yieldToken() external virtual view returns (IERC20);
    function sourceToken() external virtual view returns (IERC20);
    function pendingYield() external virtual view returns (uint256);
    function totalDeposit() external virtual view returns (uint256);
    function deposit(uint256 amount) external virtual;
    function withdraw(uint256 amount, bool claim, address to) external virtual;
    function harvestAndConvert(IERC20 outToken, uint256 amount) external virtual returns (uint256, uint256);
}
