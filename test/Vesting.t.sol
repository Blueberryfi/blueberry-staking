// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../lib/forge-std/src/Test.sol";
import "../src/BlueberryStaking.sol";
import "../src/BlueberryToken.sol";
import "../src/MockbToken.sol";
import "../src/MockUSDC.sol";

contract BlueberryStakingTest is Test {
    BlueberryStaking public blueberryStaking;
    BlueberryToken public blb;
    IERC20 public mockbToken1;
    IERC20 public mockbToken2;
    IERC20 public mockbToken3;

    IERC20 public mockUSDC;

    address public treasury = address(0x1);

    address[] public existingBTokens;


    uint256[] public rewardAmounts = new uint256[](1);
    uint256[] public stakeAmounts = new uint256[](1);
    address[] public bTokens = new address[](1);

    address public bob = address(1);
    address public sally = address(2);
    address public owner = address(3);

    uint256 public bobInitialBalance = 1e18 * 200;
    uint256 public sallyInitialBalance = 1e18 * 200;
    uint256 public ownerInitialBalance;
    
    function setUp() public {

        // 0. Deploy the contracts

        vm.startPrank(owner);

        mockbToken1 = new MockbToken();
        mockbToken2 = new MockbToken();
        mockbToken3 = new MockbToken();

        mockUSDC = new MockUSDC();

        blb = new BlueberryToken(owner, owner, block.timestamp + 30);

        existingBTokens = new address[](3);

        existingBTokens[0] = address(mockbToken1);
        existingBTokens[1] = address(mockbToken2);
        existingBTokens[2] = address(mockbToken3);

        blueberryStaking = new BlueberryStaking(address(blb), address(mockUSDC), address(treasury), 1_209_600, existingBTokens);

        blb.transfer(address(blueberryStaking), 1e20);

        mockbToken1.transfer(bob, 1e18 * 200);
        mockbToken2.transfer(bob, 1e18 * 200);
        mockbToken3.transfer(bob, 1e18 * 200);

        mockbToken1.transfer(sally, 1e18 * 200);
        mockbToken2.transfer(sally, 1e18 * 200);
        mockbToken3.transfer(sally, 1e18 * 200);

        vm.stopPrank();
        
    }


    function testVestYieldsRewardsCorrectlyForSingleStaker() public {

        // 1. Notify the new rewards amount (1e18 * 1_000) for the first epoch

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 1_000;

        stakeAmounts[0] = 1e18 * 10;

        bTokens[0] = address(mockbToken1);

        blueberryStaking.notifyRewardAmount(bTokens, rewardAmounts);

        vm.stopPrank();

        // 2. bob stakes 10 bToken1

        vm.startPrank(bob);
        
        mockbToken1.approve(address(blueberryStaking), stakeAmounts[0]);

        blueberryStaking.stake(bTokens, stakeAmounts);

        // 3. Half an epoch passes and it becomes claimable

        skip(7 days);

        // 3.5 Ensure that the rewards are half of the total rewards given that half of an epoch has passed

        console2.log("Earned after 7 days: %s", blueberryStaking.earned(address(this), bTokens[0]));

        assertEq(blueberryStaking.earned(address(this), address(mockbToken1)), rewardAmounts[0] / 2);

        // 4. Start vesting

        blueberryStaking.startVesting(bTokens);


        // 5. 1 year passes, all rewards should be fully vested

        skip(365 days);


        // 6. Complete vesting

        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 0;

        blueberryStaking.completeVesting(indexes);
    }

    function testVestYieldsRewardsCorrectlyForMultipleStakers() public {

        // 1. Notify the new rewards amount (1e18 * 1_000) for the first epoch

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 1_000;

        stakeAmounts[0] = 1e18 * 10;

        bTokens[0] = address(mockbToken1);

        blueberryStaking.notifyRewardAmount(bTokens, rewardAmounts);

        vm.stopPrank();

        // 2. Stake 10 bToken1 each

        vm.startPrank(bob);
        
        mockbToken1.approve(address(blueberryStaking), stakeAmounts[0]);

        blueberryStaking.stake(bTokens, stakeAmounts);

        vm.stopPrank();

        vm.startPrank(sally);

        mockbToken1.approve(address(blueberryStaking), stakeAmounts[0]);

        blueberryStaking.stake(bTokens, stakeAmounts);

        vm.stopPrank();

        // 3. The entire epoch passes thus all rewards are claimable

        skip(14 days);

        // 3.5 Ensure that the rewards distributed 50/50 between bob and sally

        assertEq(blueberryStaking.earned(bob, address(mockbToken1)), rewardAmounts[0] / 2);

        assertEq(blueberryStaking.earned(sally, address(mockbToken1)), rewardAmounts[0] / 2);


        // 4. Start vesting

        vm.startPrank(bob);

        blueberryStaking.startVesting(bTokens);

        vm.stopPrank();

        vm.startPrank(sally);

        blueberryStaking.startVesting(bTokens);

        vm.stopPrank();

        // 5. 1 year passes, all rewards should be fully vested

        skip(365 days);

        // 6. Complete vesting

        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 0;

        vm.startPrank(bob);

        blueberryStaking.completeVesting(indexes);

        vm.stopPrank();

        vm.startPrank(sally);

        blueberryStaking.completeVesting(indexes);

        vm.stopPrank();
    }

    function testUnstake() public {

        // 1. Notify the new rewards amount 1_000 tokens for the first epoch

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 1_000;

        stakeAmounts[0] = 1e18 * 10;

        bTokens[0] = address(mockbToken1);

        blueberryStaking.notifyRewardAmount(bTokens, rewardAmounts);

        vm.stopPrank();

        // 2. bob stakes 10 bToken1

        vm.startPrank(bob);
        
        mockbToken1.approve(address(blueberryStaking), stakeAmounts[0]);

        blueberryStaking.stake(bTokens, stakeAmounts);

        // 3. Bob unstakes 5 bToken1

        blueberryStaking.unstake(bTokens, stakeAmounts);

        // 3.5 ensure that all tokens have been unstaked

        assertEq(mockbToken1.balanceOf(bob), bobInitialBalance);

        // 3.6 ensure that bob can still start vesting

        blueberryStaking.startVesting(bTokens);
    }

    function testAccelerateVestingMultipleTokens() public {

        // 1. Notify the new rewards amount 4_000 of each token for the epoch

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 4_000;
        rewardAmounts[1] = 1e18 * 4_000;
        rewardAmounts[2] = 1e18 * 4_000;

        stakeAmounts[0] = 1e18 * 10;
        stakeAmounts[1] = 1e18 * 10;
        stakeAmounts[2] = 1e18 * 10;

        blueberryStaking.notifyRewardAmount(existingBTokens, rewardAmounts);

        vm.stopPrank();

        // 2. bob stakes 10 of each bToken

        vm.startPrank(bob);

        mockbToken1.approve(address(blueberryStaking), stakeAmounts[0]);
        mockbToken2.approve(address(blueberryStaking), stakeAmounts[1]);
        mockbToken3.approve(address(blueberryStaking), stakeAmounts[2]);

        blueberryStaking.stake(existingBTokens, stakeAmounts);

        console.log("BLB balance before: %s", blb.balanceOf(address(this)));

        skip(14 days);

        blueberryStaking.startVesting(existingBTokens);

        // 3. 1/2 a year has now passed, bob decides to accelerate his vesting

        vm.warp(120 days);
        
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 0;
        indexes[1] = 1;
        indexes[2] = 2;

        mockUSDC.approve(address(blueberryStaking), 1e6 * 10_000);

        console.log("USDC balance before acceleration 1/2 year: %s", mockUSDC.balanceOf(bob));

        blueberryStaking.accelerateVesting(indexes);

        console.log("USDC balance after acceleration 1/2 year: %s", mockUSDC.balanceOf(bob));

        console.log("BLB balance after acceleration: %s", blb.balanceOf(address(this)));
    }

    function testGetEarlyUnlockPenaltyRatio() public {

        // 1. Notify the new rewards amount 1_000 tokens for the first epoch

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 1_000;

        stakeAmounts[0] = 1e18 * 10;

        bTokens[0] = address(mockbToken1);

        blueberryStaking.notifyRewardAmount(bTokens, rewardAmounts);

        vm.stopPrank();

        // 2. bob stakes 10 bToken1

        vm.startPrank(bob);
        
        mockbToken1.approve(address(blueberryStaking), stakeAmounts[0]);

        blueberryStaking.stake(bTokens, stakeAmounts);

        skip(14 days);

        blueberryStaking.startVesting(bTokens);

        console2.log("Unlock penalty ratio right away: %s", blueberryStaking.getEarlyUnlockPenaltyRatio(address(this), 0));

        skip(10 days);

        console2.log("Unlock penalty ratio after 10 days: %s", blueberryStaking.getEarlyUnlockPenaltyRatio(address(this), 0));

        skip(10 days);

        console2.log("Unlock penalty ratio after 20 days: %s", blueberryStaking.getEarlyUnlockPenaltyRatio(address(this), 0));

        skip(10 days);

        console2.log("Unlock penalty ratio after 30 days: %s", blueberryStaking.getEarlyUnlockPenaltyRatio(address(this), 0));

        skip(334 days);

        console2.log("Unlock penalty ratio after 364 days: %s", blueberryStaking.getEarlyUnlockPenaltyRatio(address(this), 0));
    }
}
