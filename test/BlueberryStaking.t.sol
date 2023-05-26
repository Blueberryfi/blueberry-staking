// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../lib/forge-std/src/Test.sol";
import "../src/BlueberryStaking.sol";

contract bdBLBTest is Test {
    BlueberryStaking blueberryStaking;
    BLB blb;

    IERC20 mockbToken = IERC20(address(0x1));

    address minter = address(0x1);
    
    function setUp() public {
        blb = new BLB(minter, minter, 0);
        blueberryStaking = new BlueberryStaking(blb, 1_209_600, [mockbToken, mockbToken2, mockbToken3]);
    }
}
