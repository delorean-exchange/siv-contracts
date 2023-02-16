//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./TestToken.sol";
import "../interfaces/IYieldSource.sol";

contract TestYieldSource is IYieldSource {
    uint256 public yieldPerBlock;
    uint256 public immutable startBlockNumber;
    mapping(address => uint256) public lastHarvestBlockNumber;
    mapping(address => uint256) public pending;

    address public yieldToken;
    address public generatorToken;
    address[] public holders;

    constructor(uint256 yieldPerBlock_) {
        startBlockNumber = block.number;
        yieldPerBlock = yieldPerBlock_;

        yieldToken = address(new TestToken("TestYS: Yield Token", "YS:Y", 0));
        generatorToken = address(new TestToken("TestYS: Generator Token", "YS:G", 0));
    }

    function setYieldPerBlock(uint256 yieldPerBlock_) public {
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            pending[holder] += amountPending(holder);
            lastHarvestBlockNumber[holder] = block.number;
        }
        yieldPerBlock = yieldPerBlock_;
    }

    function mintGenerator(address who, uint256 amount) public {
        require(TestToken(generatorToken).balanceOf(who) == 0, "TYS: non-zero mint");
        TestToken(generatorToken).publicMint(who, amount);
        lastHarvestBlockNumber[who] = block.number;
        holders.push(who);
    }

    function harvest() public {
        uint256 amount = this.amountPending(msg.sender);
        TestToken(yieldToken).publicMint(msg.sender, amount);
        lastHarvestBlockNumber[msg.sender] = block.number;
        pending[msg.sender] = 0;
    }

    function amountPending(address who) public virtual view returns (uint256) {
        uint256 start = lastHarvestBlockNumber[who] == 0
            ? startBlockNumber
            : lastHarvestBlockNumber[who];
        uint256 deltaBlocks = block.number - start;
        uint256 total = TestToken(generatorToken).balanceOf(who) * deltaBlocks * yieldPerBlock;
        return total + pending[who];
    }
}
