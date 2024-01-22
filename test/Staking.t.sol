// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "../lib/forge-std/src/Test.sol";
import "../src/BlueberryStaking.sol";
import "../src/BlueberryToken.sol";
import "./mocks/MockbToken.sol";
import "./mocks/MockUSDC.sol";

contract BlueberryStakingTest is Test {
    BlueberryStaking public blueberryStaking;
    BlueberryToken public blb;
    IERC20 public mockbToken1;
    IERC20 public mockbToken2;
    IERC20 public mockbToken3;

    IERC20 public mockUSDC;

    address public treasury = address(0x1);

    address[] public existingBTokens;

    address public bob = address(1);
    address public sally = address(2);
    address public dan = address(4);
    address public owner = address(3);

    uint256 public bobInitialBalance = 1e18 * 200;
    uint256 public sallyInitialBalance = 1e18 * 200;
    uint256 public ownerInitialBalance;

    function isCloseEnough(uint256 a, uint256 b) public pure returns (bool) {
        if (a > b) {
            return a - b <= 1e6;
        } else {
            return b - a <= 1e6;
        }
    }

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

        blueberryStaking =
            new BlueberryStaking(address(blb), address(mockUSDC), address(treasury), 1_209_600, existingBTokens);

        blb.transfer(address(blueberryStaking), 1e20);

        mockbToken1.transfer(bob, 1e18 * 200);
        mockbToken2.transfer(bob, 1e18 * 200);
        mockbToken3.transfer(bob, 1e18 * 200);

        mockbToken1.transfer(sally, 1e18 * 200);
        mockbToken2.transfer(sally, 1e18 * 200);
        mockbToken3.transfer(sally, 1e18 * 200);

        mockbToken1.transfer(dan, 1e18 * 200);
        mockbToken2.transfer(dan, 1e18 * 200);
        mockbToken3.transfer(dan, 1e18 * 200);

        mockUSDC.transfer(bob, 1e10);
        mockUSDC.transfer(sally, 1e10);
        mockUSDC.transfer(dan, 1e10);

        vm.stopPrank();
    }

    function testVestYieldsRewardsCorrectlyForSingleStaker() public {
        // Temporary variables

        uint256[] memory rewardAmounts = new uint256[](1);
        uint256[] memory stakeAmounts = new uint256[](1);
        address[] memory bTokens = new address[](1);

        // 1. Notify the new rewards amount (1e18 * 20) for the first epoch

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 20;

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

        console2.log("bob earned: %s", blueberryStaking.earned(address(bob), address(mockbToken1)));

        assertEq(isCloseEnough(blueberryStaking.earned(address(bob), address(mockbToken1)), rewardAmounts[0] / 2), true);

        // 4. Start vesting

        blueberryStaking.startVesting(bTokens);

        // 5. 1 year passes, all rewards should be fully vested

        skip(365 days);

        // 6. Complete vesting

        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 0;

        blueberryStaking.completeVesting(indexes);
    }

    function testMultiStake() public {
        vm.startPrank(owner);
        blueberryStaking.setRewardDuration(28 days);

        uint256[] memory rewardAmounts = new uint256[](1);
        rewardAmounts[0] = 1e18 * 1000;

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = 1e18 * 50;

        address[] memory bTokens = new address[](1);
        bTokens[0] = address(mockbToken1);

        blueberryStaking.notifyRewardAmount(bTokens, rewardAmounts);
        vm.stopPrank();

        vm.startPrank(bob);

        mockbToken1.approve(address(blueberryStaking), stakeAmounts[0]);
        blueberryStaking.stake(bTokens, stakeAmounts);

        skip(7 days);

        console2.log("earned: %s", blueberryStaking.earned(address(bob), address(mockbToken1)));

        mockbToken1.approve(address(blueberryStaking), stakeAmounts[0]);
        blueberryStaking.stake(bTokens, stakeAmounts);

        skip(7 days);

        console2.log("earned: %s", blueberryStaking.earned(address(bob), address(mockbToken1)));

        mockbToken1.approve(address(blueberryStaking), stakeAmounts[0]);
        blueberryStaking.stake(bTokens, stakeAmounts);

        skip(7 days);

        console2.log("earned: %s", blueberryStaking.earned(address(bob), address(mockbToken1)));

        mockbToken1.approve(address(blueberryStaking), stakeAmounts[0]);
        blueberryStaking.stake(bTokens, stakeAmounts);
    }

    function testVestYieldsRewardsCorrectlyForMultipleStakers() public {
        // Temporary variables

        uint256[] memory rewardAmounts = new uint256[](1);
        uint256[] memory stakeAmounts = new uint256[](1);
        address[] memory bTokens = new address[](1);

        // 1. Notify the new rewards amount (1e18 * 20) for the first epoch

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 20;

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

        vm.startPrank(dan);

        mockbToken1.approve(address(blueberryStaking), stakeAmounts[0]);

        blueberryStaking.stake(bTokens, stakeAmounts);

        vm.stopPrank();

        // 3. The entire epoch passes thus all rewards are claimable

        skip(14 days);

        // 3.5 Ensure that the rewards distributed 50/50 between bob and sally

        assertEq(isCloseEnough(blueberryStaking.earned(address(bob), address(mockbToken1)), rewardAmounts[0] / 3), true);

        assertEq(
            isCloseEnough(blueberryStaking.earned(address(sally), address(mockbToken1)), rewardAmounts[0] / 3), true
        );

        assertEq(isCloseEnough(blueberryStaking.earned(address(dan), address(mockbToken1)), rewardAmounts[0] / 3), true);

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
        // Temporary variables

        uint256[] memory rewardAmounts = new uint256[](1);
        uint256[] memory stakeAmounts = new uint256[](1);
        address[] memory bTokens = new address[](1);

        // 1. Notify the new rewards amount 20 tokens for the first epoch

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 20;

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
}
