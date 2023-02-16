//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./TestToken.sol";
import "../interfaces/IYieldSource.sol";

contract TestYieldSource is IYieldSource {
    uint256 public immutable yieldPerBlock;
    uint256 public immutable startBlockNumber;
    mapping(address => uint256) public lastHarvestBlockNumber;

    address public yieldToken;
    address public generatorToken;

    constructor(uint256 yieldPerBlock_) {
        startBlockNumber = block.number;
        yieldPerBlock = yieldPerBlock_;

        yieldToken = address(new TestToken("TestYS: Yield Token", "YS:Y", 0));
        generatorToken = address(new TestToken("TestYS: Generator Token", "YS:G", 0));
    }

    function mintGenerator(address who, uint256 amount) external {
        require(TestToken(generatorToken).balanceOf(who) == 0, "TYS: non-zero mint");
        TestToken(generatorToken).publicMint(who, amount);
        lastHarvestBlockNumber[who] = block.number;
    }

    function harvest() external {
        uint256 amount = this.amountPending(msg.sender);
        TestToken(yieldToken).publicMint(msg.sender, amount);
        lastHarvestBlockNumber[msg.sender] = block.number;
        /* harvested[msg.sender] = amount; */
    }

    function amountPending(address who) external virtual view returns (uint256) {
        uint256 start = lastHarvestBlockNumber[who] == 0
            ? startBlockNumber
            : lastHarvestBlockNumber[who];
        uint256 deltaBlocks = block.number - start;
        uint256 total = TestToken(generatorToken).balanceOf(who) * deltaBlocks * yieldPerBlock;
        return total;
    }
}
