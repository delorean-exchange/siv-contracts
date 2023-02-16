//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./TestToken.sol";
import "../interfaces/IYieldSource.sol";

contract TestYieldSource {
    uint256 public immutable yieldPerBlock;
    uint256 public immutable startBlockNumber;
    mapping(address => uint256) public lastHarvestBlockNumber;
    /* mapping(address => uint256) public harvested; */

    TestToken public yieldToken;
    TestToken public generatorToken;

    constructor(uint256 yieldPerBlock_) {
        startBlockNumber = block.number;
        yieldPerBlock = yieldPerBlock_;

        yieldToken = new TestToken("TestYS: Yield Token", "YS:Y", 0);
        generatorToken = new TestToken("TestYS: Generator Token", "YS:G", 0);
    }

    function mintGenerator(address who, uint256 amount) external {
        require(generatorToken.balanceOf(who) == 0, "TYS: non-zero mint");
        generatorToken.publicMint(who, amount);
        lastHarvestBlockNumber[who] = block.number;
    }

    function harvest() external {
        uint256 amount = this.amountPending(msg.sender);
        yieldToken.publicMint(msg.sender, amount);
        lastHarvestBlockNumber[msg.sender] = block.number;
        /* harvested[msg.sender] = amount; */
    }

    function amountPending(address who) external virtual view returns (uint256) {
        uint256 start = lastHarvestBlockNumber[who] == 0
            ? startBlockNumber
            : lastHarvestBlockNumber[who];
        uint256 deltaBlocks = block.number - start;
        uint256 total = generatorToken.balanceOf(who) * deltaBlocks * yieldPerBlock;
        return total;
    }
}
