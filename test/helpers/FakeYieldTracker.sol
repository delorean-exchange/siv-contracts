//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/console.sol";

import { FakeToken } from  "./FakeToken.sol";
import { IYieldTracker } from "../../src/interfaces/IYieldTracker.sol";


contract CallbackFakeToken is FakeToken {
    address public callback;

    constructor(string memory name, string memory symbol, uint256 initialSupply, address callback_) FakeToken(name, symbol, initialSupply) {
        callback = callback_;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        FakeYieldTracker(callback).callback(to);
        super._transfer(from, to, amount);
    }
}


contract FakeYieldTracker is IYieldTracker {
    uint256 public yieldPerBlock;
    uint256 public immutable startBlockNumber;
    mapping(address => uint256) public lastHarvestBlockNumber;
    mapping(address => uint256) public pending;

    address public yieldToken;
    address public sourceToken;
    address[] public holders;

    constructor(uint256 yieldPerBlock_) {
        startBlockNumber = block.number;
        yieldPerBlock = yieldPerBlock_;

        yieldToken = address(new FakeToken("TestYS: Yield Token", "YS:Y", 0));
        sourceToken = address(new CallbackFakeToken("TestYS: Generator Token", "YS:G", 0, address(this)));
    }

    function callback(address who) public {
        updateHolders(who);
        checkpointPending();
    }

    function updateHolders(address who) public {
        bool exists = false;
        for (uint256 i = 0; i < holders.length; i++) {
            exists = exists || holders[i] == who;
        }
        if (!exists) holders.push(who);
    }

    function checkpointPending() public {
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            pending[holder] += pendingYield(holder);
            lastHarvestBlockNumber[holder] = block.number;
        }
    }

    function setYieldPerBlock(uint256 yieldPerBlock_) public {
        checkpointPending();
        yieldPerBlock = yieldPerBlock_;
    }

    function mintGenerator(address who, uint256 amount) public {
        require(FakeToken(sourceToken).balanceOf(who) == 0, "TYS: non-zero mint");
        FakeToken(sourceToken).publicMint(who, amount);
        lastHarvestBlockNumber[who] = block.number;
        holders.push(who);
    }

    function mintYield(address who, uint256 amount) public {
        require(FakeToken(yieldToken).balanceOf(who) == 0, "TYS: non-zero mint");
        FakeToken(yieldToken).publicMint(who, amount);
        lastHarvestBlockNumber[who] = block.number;
        holders.push(who);
    }

    function harvest() public {
        uint256 amount = this.pendingYield(msg.sender);
        FakeToken(yieldToken).publicMint(msg.sender, amount);
        lastHarvestBlockNumber[msg.sender] = block.number;
        pending[msg.sender] = 0;
    }

    function pendingYield() public virtual view returns (uint256) {
        return 0;
    }

    function pendingYield(address who) public virtual view returns (uint256) {
        uint256 start = lastHarvestBlockNumber[who] == 0
            ? startBlockNumber
            : lastHarvestBlockNumber[who];
        uint256 deltaBlocks = block.number - start;
        uint256 total = FakeToken(sourceToken).balanceOf(who) * deltaBlocks * yieldPerBlock;
        return total + pending[who];
    }
}
