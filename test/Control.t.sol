// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../lib/forge-std/src/Test.sol";
import "../src/BlueberryStaking.sol";
import "../src/BlueberryToken.sol";
import "../src/MockbToken.sol";
import "../src/MockUSDC.sol";

contract Control is Test {
    BlueberryStaking blueberryStaking;
    BlueberryToken blb;
    IERC20 mockbToken1;
    IERC20 mockbToken2;
    IERC20 mockbToken3;

    IERC20 mockUSDC;

    address public treasury = address(0x1);

    address[] public existingBTokens;
    
    function setUp() public {
        mockbToken1 = new MockbToken();
        mockbToken2 = new MockbToken();
        mockbToken3 = new MockbToken();

        mockUSDC = new MockUSDC();

        blb = new BlueberryToken(address(this), address(this), block.timestamp + 30);

        existingBTokens = new address[](3);

        existingBTokens[0] = address(mockbToken1);
        existingBTokens[1] = address(mockbToken2);
        existingBTokens[2] = address(mockbToken3);

        blueberryStaking = new BlueberryStaking(address(blb), address(mockUSDC), address(treasury), 1_209_600, existingBTokens);

        blb.transfer(address(blueberryStaking), 1e27);
    }

    function testSetVestLength() public {
        blueberryStaking.setVestLength(69_420);
        assertEq(blueberryStaking.vestLength(), 69_420);
    }

    function testSetRewardDuration() public {
        blueberryStaking.setRewardDuration(5_318_008);
        assertEq(blueberryStaking.rewardDuration(), 5_318_008);
    }

    function testAddBTokens() public {
        IERC20 mockbToken4 = new MockbToken();
        IERC20 mockbToken5 = new MockbToken();
        IERC20 mockbToken6 = new MockbToken();

        address[] memory bTokens = new address[](3);

        bTokens[0] = address(mockbToken4);
        bTokens[1] = address(mockbToken5);
        bTokens[2] = address(mockbToken6);

        blueberryStaking.addBTokens(bTokens);

        assertEq(blueberryStaking.isBToken(address(mockbToken4)), true);

        assertEq(blueberryStaking.isBToken(address(mockbToken5)), true);

        assertEq(blueberryStaking.isBToken(address(mockbToken6)), true);
    }

    function testRemoveBTokens() public {
        assertEq(blueberryStaking.isBToken(address(existingBTokens[0])), true);

        assertEq(blueberryStaking.isBToken(address(existingBTokens[1])), true);

        assertEq(blueberryStaking.isBToken(address(existingBTokens[2])), true);

        blueberryStaking.removeBTokens(existingBTokens);

        assertEq(blueberryStaking.isBToken(address(existingBTokens[0])), false);

        assertEq(blueberryStaking.isBToken(address(existingBTokens[1])), false);

        assertEq(blueberryStaking.isBToken(address(existingBTokens[2])), false);
    }

    function testPausing() public {
        blueberryStaking.pause();
        assertEq(blueberryStaking.paused(), true);

        blueberryStaking.unpause();
        assertEq(blueberryStaking.paused(), false);
    }

    function testNotifyRewardAmount() public {
        uint256[] memory amounts = new uint256[](3);

        amounts[0] = 1e19;
        amounts[1] = 1e19 * 4;
        amounts[2] = 1e23 * 4;

        blueberryStaking.notifyRewardAmount(existingBTokens, amounts);

        assertEq(blueberryStaking.rewardRate(existingBTokens[0]), 1e19 / blueberryStaking.rewardDuration());
        assertEq(blueberryStaking.rewardRate(existingBTokens[1]), 1e19 * 4 / blueberryStaking.rewardDuration());
        assertEq(blueberryStaking.rewardRate(existingBTokens[2]), 1e23 * 4 / blueberryStaking.rewardDuration());
    }

    function testChangeEpochLength() public {
        blueberryStaking.changeEpochLength(70_420_248_412);
        assertEq(blueberryStaking.epochLength(), 70_420_248_412);
    }

    function testChangeBLB() public {
        BlueberryToken newBLB = new BlueberryToken(address(this), address(this), block.timestamp + 30);
        blueberryStaking.changeBLB(address(newBLB));
        assertEq(blueberryStaking.getBLB(), address(newBLB));
    }
}
