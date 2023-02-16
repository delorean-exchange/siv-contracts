//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IYieldSource {
    function yieldToken() external view returns (address);
    function generatorToken() external view returns (address);
    function harvest() external;
    function amountPending() external view returns (uint256);
    function amountGenerator() external view returns (uint256);
}
