// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../lib/forge-std/src/Test.sol";
import "../src/BlueberryStaking.sol";
import "../src/BlueberryToken.sol";
import "../src/MockbToken.sol";

contract BlueberryStakingTest is Test {
    BlueberryStaking blueberryStaking;
    BlueberryToken blb;
    IERC20 mockbToken1;
    IERC20 mockbToken2;
    IERC20 mockbToken3;

    address public endUser = address(0x1);

    address[] public existingBTokens;
    
    function setUp() public {
        mockbToken1 = new MockbToken();
        mockbToken2 = new MockbToken();
        mockbToken3 = new MockbToken();

        blb = new BlueberryToken(address(this), address(this), block.timestamp + 30);

        existingBTokens = new address[](3);

        existingBTokens[0] = address(mockbToken1);
        existingBTokens[1] = address(mockbToken2);
        existingBTokens[2] = address(mockbToken3);

        blueberryStaking = new BlueberryStaking(address(blb), 1_209_600, existingBTokens);

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

    function testStake() public {
        uint256[] memory amounts = new uint256[](3);

        amounts[0] = 1e16;
        amounts[1] = 1e16 * 4;
        amounts[2] = 1e16 * 4;

        blueberryStaking.notifyRewardAmount(existingBTokens, amounts);

        mockbToken1.approve(address(blueberryStaking), amounts[0]);
        mockbToken2.approve(address(blueberryStaking), amounts[1]);
        mockbToken3.approve(address(blueberryStaking), amounts[2]);

        blueberryStaking.stake(existingBTokens, amounts);

        assertEq(blueberryStaking.balanceOf(address(this), address(mockbToken1)), 1e16);

        assertEq(blueberryStaking.balanceOf(address(this), address(mockbToken2)), 1e16 * 4);

        assertEq(blueberryStaking.balanceOf(address(this), address(mockbToken3)), 1e16 * 4);
    }

    function testUnstake() public {
        uint256[] memory amounts = new uint256[](3);

        amounts[0] = 1e16;
        amounts[1] = 1e16 * 4;
        amounts[2] = 1e16 * 4;

        blueberryStaking.notifyRewardAmount(existingBTokens, amounts);

        mockbToken1.approve(address(blueberryStaking), amounts[0]);
        mockbToken2.approve(address(blueberryStaking), amounts[1]);
        mockbToken3.approve(address(blueberryStaking), amounts[2]);

        blueberryStaking.stake(existingBTokens, amounts);

        blueberryStaking.unstake(existingBTokens, amounts);

        assertEq(blueberryStaking.balanceOf(address(this), address(mockbToken1)), 0);

        assertEq(blueberryStaking.balanceOf(address(this), address(mockbToken2)), 0);

        assertEq(blueberryStaking.balanceOf(address(this), address(mockbToken3)), 0);
    }

    function testFullyVest() public {
        uint256[] memory rewardAmounts = new uint256[](3);

        rewardAmounts[0] = 1e25;
        rewardAmounts[1] = 1e25;
        rewardAmounts[2] = 1e25;

        uint256[] memory stakeAmounts = new uint256[](3);

        stakeAmounts[0] = 1e25;
        stakeAmounts[1] = 1e25;
        stakeAmounts[2] = 1e25;

        blueberryStaking.notifyRewardAmount(existingBTokens, amounts);

        mockbToken1.approve(address(blueberryStaking), amounts[0]);

        blueberryStaking.stake(existingBTokens, amounts);

        // The epoch passes and it becomes claimable
        vm.warp(block.timestamp + 7 days);

        // check how much is earned

        console.log("Earned first week: %s", blueberryStaking.earned(address(this), address(mockbToken1)));

        vm.warp(block.timestamp + 7 days);

        // check how much is earned

        console.log("Earned second week: %s", blueberryStaking.earned(address(this), address(mockbToken1)));

        blueberryStaking.startVesting(existingBTokens);

        console.log("BLB balance before: %s", blb.balanceOf(address(this)));

        // 1 year passes, all rewards should be fully vested
        vm.warp(block.timestamp + 180 days);

        console.log("Earned: after starting vest %s", blueberryStaking.earned(address(this), address(mockbToken1)));
        
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 0;
        indexes[1] = 1;
        indexes[2] = 2;

        blueberryStaking.completeVesting(indexes);

        console.log("BLB balance after: %s", blb.balanceOf(address(this)));
    }

    function testAccelerateVesting() public {

        uint256[] memory amounts = new uint256[](3);

        amounts[0] = 1e16;
        amounts[1] = 1e16 * 4;
        amounts[2] = 1e16 * 4;

        blueberryStaking.notifyRewardAmount(existingBTokens, amounts);

        mockbToken1.approve(address(blueberryStaking), amounts[0]);
        mockbToken2.approve(address(blueberryStaking), amounts[1]);
        mockbToken3.approve(address(blueberryStaking), amounts[2]);

        blueberryStaking.stake(existingBTokens, amounts);

        console.log("BLB balance before: %s", blb.balanceOf(address(this)));

        // The epoch passes and it becomes claimable
        vm.warp(block.timestamp + 14 days);

        blueberryStaking.startVesting(existingBTokens);

        // half a year passes, early unlock penalty should be 50%
        vm.warp(block.timestamp + 120 days);
        
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 0;
        indexes[1] = 1;
        indexes[2] = 2;

        blueberryStaking.accelerateVesting(indexes);

        console.log("BLB balance after acceleration: %s", blb.balanceOf(address(this)));
    }

    function testGetEarlyUnlockPenaltyRatio() public {
        uint256[] memory amounts = new uint256[](1);

        amounts[0] = 1e16;

        address[] memory bTokens = new address[](1);
        bTokens[0] = address(mockbToken1);

        blueberryStaking.notifyRewardAmount(bTokens, amounts);

        mockbToken1.approve(address(blueberryStaking), amounts[0]);

        blueberryStaking.stake(bTokens, amounts);

        // The epoch passes and it becomes claimable
        vm.warp(block.timestamp + 14 days);

        blueberryStaking.startVesting(bTokens);

        console.log("Unlock penalty ratio right away: %s", blueberryStaking.getEarlyUnlockPenaltyRatio(address(this), 0));

        // 10 days pass
        vm.warp(block.timestamp + 10 days);

        console.log("Unlock penalty ratio after 10 days: %s", blueberryStaking.getEarlyUnlockPenaltyRatio(address(this), 0));

        // 20 days pass
        vm.warp(block.timestamp + 10 days);

        console.log("Unlock penalty ratio after 20 days: %s", blueberryStaking.getEarlyUnlockPenaltyRatio(address(this), 0));

        // 30 days pass
        vm.warp(block.timestamp + 10 days);

        console.log("Unlock penalty ratio after 30 days: %s", blueberryStaking.getEarlyUnlockPenaltyRatio(address(this), 0));

        // 1/2 year passes
        vm.warp(block.timestamp + 365 days);

        console.log("Unlock penalty ratio after 1/2 year: %s", blueberryStaking.getEarlyUnlockPenaltyRatio(address(this), 0));
    }
}
