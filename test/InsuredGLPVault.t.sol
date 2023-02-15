// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/vaults/InsuredGLPVault.sol";

contract InsuredGLPVaultTest is Test {
    InsuredGLPVault public vault;

    function setUp() public {
        vault = new InsuredGLPVault("Self Insured GLP Vault", "siGLP");
    }

    function testBasic() public {
        assertEq(uint256(1), 1);
    }
}
