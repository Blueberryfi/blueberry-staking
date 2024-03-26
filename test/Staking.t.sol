// SPDX-License-Identifier: MIT
pragma solidity >=0.4.0 <0.9.0;

import "../lib/forge-std/src/Test.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BlueberryStaking} from "../src/BlueberryStaking.sol";
import {BlueberryToken} from "../src/BlueberryToken.sol";
import {MockIbToken} from "./mocks/MockIbToken.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract BlueberryStakingTest is Test {
    BlueberryStaking public blueberryStaking;
    BlueberryToken public blb;
    IERC20 public mockIbToken1;
    IERC20 public mockIbToken2;
    IERC20 public mockIbToken3;

    IERC20 public mockUSDC;

    address public treasury = makeAddr("treasury");

    address[] public existingiBTokens;

    address public bob = makeAddr("bob");
    address public sally = makeAddr("sally");
    address public owner = makeAddr("owner");
    address public dan = makeAddr("dan");

    uint256 public bobInitialBalance = 1e8 * 200;
    uint256 public sallyInitialBalance = 1e8 * 200;
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

        mockIbToken1 = new MockIbToken();
        mockIbToken2 = new MockIbToken();
        mockIbToken3 = new MockIbToken();

        mockUSDC = new MockUSDC();

        blb = new BlueberryToken(owner, owner, block.timestamp);

        existingiBTokens = new address[](3);

        existingiBTokens[0] = address(mockIbToken1);
        existingiBTokens[1] = address(mockIbToken2);
        existingiBTokens[2] = address(mockIbToken3);

        blueberryStaking = new BlueberryStaking();

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(blueberryStaking),
            address(treasury),
            abi.encodeCall(
                BlueberryStaking.initialize,
                (
                    address(blb),
                    address(mockUSDC),
                    address(treasury),
                    1_209_600,
                    existingiBTokens,
                    owner
                )
            )
        );

        blueberryStaking = BlueberryStaking(payable(address(proxy)));

        blb.mint(address(owner), 1e20);
        blb.approve(address(blueberryStaking), UINT256_MAX);

        mockIbToken1.transfer(bob, 1e8 * 200);
        mockIbToken2.transfer(bob, 1e8 * 200);
        mockIbToken3.transfer(bob, 1e8 * 200);

        mockIbToken1.transfer(sally, 1e8 * 200);
        mockIbToken2.transfer(sally, 1e8 * 200);
        mockIbToken3.transfer(sally, 1e8 * 200);

        mockIbToken1.transfer(dan, 1e8 * 200);
        mockIbToken2.transfer(dan, 1e8 * 200);
        mockIbToken3.transfer(dan, 1e8 * 200);

        mockUSDC.transfer(bob, 1e10);
        mockUSDC.transfer(sally, 1e10);
        mockUSDC.transfer(dan, 1e10);

        vm.stopPrank();
    }

    function testVestYieldsRewardsCorrectlyForSingleStaker() public {
        // Temporary variables

        uint256[] memory rewardAmounts = new uint256[](1);
        uint256[] memory stakeAmounts = new uint256[](1);
        address[] memory ibTokens = new address[](1);

        // 1. Notify the new rewards amount (1e18 * 20) for the reward period

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 20;

        stakeAmounts[0] = 1e8 * 10;

        ibTokens[0] = address(mockIbToken1);

        blueberryStaking.modifyRewardAmount(ibTokens, rewardAmounts);

        vm.stopPrank();

        // 2. bob stakes 10 bToken1

        vm.startPrank(bob);

        mockIbToken1.approve(address(blueberryStaking), stakeAmounts[0]);

        blueberryStaking.stake(ibTokens, stakeAmounts);

        // 3. Half the reward period passes and it becomes claimable

        skip(7 days);

        // 3.5 Ensure that the rewards are half of the total rewards given that half of the reward period has passed

        console2.log("bob earned: %s", blueberryStaking.earned(address(bob), address(mockIbToken1)));

        assertEq(isCloseEnough(blueberryStaking.earned(address(bob), address(mockIbToken1)), rewardAmounts[0] / 2), true);

        // 4. Start vesting

        blueberryStaking.startVesting(ibTokens);

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
        stakeAmounts[0] = 1e8 * 50;

        address[] memory ibTokens = new address[](1);
        ibTokens[0] = address(mockIbToken1);

        blueberryStaking.modifyRewardAmount(ibTokens, rewardAmounts);
        vm.stopPrank();

        vm.startPrank(bob);

        mockIbToken1.approve(address(blueberryStaking), stakeAmounts[0]);
        blueberryStaking.stake(ibTokens, stakeAmounts);

        skip(7 days);

        console2.log("earned: %s", blueberryStaking.earned(address(bob), address(mockIbToken1)));

        mockIbToken1.approve(address(blueberryStaking), stakeAmounts[0]);
        blueberryStaking.stake(ibTokens, stakeAmounts);

        skip(7 days);

        console2.log("earned: %s", blueberryStaking.earned(address(bob), address(mockIbToken1)));

        mockIbToken1.approve(address(blueberryStaking), stakeAmounts[0]);
        blueberryStaking.stake(ibTokens, stakeAmounts);

        skip(7 days);

        console2.log("earned: %s", blueberryStaking.earned(address(bob), address(mockIbToken1)));

        mockIbToken1.approve(address(blueberryStaking), stakeAmounts[0]);
        blueberryStaking.stake(ibTokens, stakeAmounts);
    }

    function testVestYieldsRewardsCorrectlyForMultipleStakers() public {
        // Temporary variables

        uint256[] memory rewardAmounts = new uint256[](1);
        uint256[] memory stakeAmounts = new uint256[](1);
        address[] memory ibTokens = new address[](1);

        // 1. Notify the new rewards amount (1e18 * 20) for the reward period

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 20;

        stakeAmounts[0] = 1e8 * 10;

        ibTokens[0] = address(mockIbToken1);

        blueberryStaking.modifyRewardAmount(ibTokens, rewardAmounts);

        vm.stopPrank();

        // 2. Stake 10 bToken1 each

        vm.startPrank(bob);

        mockIbToken1.approve(address(blueberryStaking), stakeAmounts[0]);

        blueberryStaking.stake(ibTokens, stakeAmounts);

        vm.stopPrank();

        vm.startPrank(sally);

        mockIbToken1.approve(address(blueberryStaking), stakeAmounts[0]);

        blueberryStaking.stake(ibTokens, stakeAmounts);

        vm.stopPrank();

        vm.startPrank(dan);

        mockIbToken1.approve(address(blueberryStaking), stakeAmounts[0]);

        blueberryStaking.stake(ibTokens, stakeAmounts);

        vm.stopPrank();

        // 3. The entire reward period passes thus all rewards are claimable

        skip(14 days);

        // 3.5 Ensure that the rewards distributed 50/50 between bob and sally

        assertEq(isCloseEnough(blueberryStaking.earned(address(bob), address(mockIbToken1)), rewardAmounts[0] / 3), true);

        assertEq(
            isCloseEnough(blueberryStaking.earned(address(sally), address(mockIbToken1)), rewardAmounts[0] / 3), true
        );

        assertEq(isCloseEnough(blueberryStaking.earned(address(dan), address(mockIbToken1)), rewardAmounts[0] / 3), true);

        // 4. Start vesting

        vm.startPrank(bob);

        blueberryStaking.startVesting(ibTokens);

        vm.stopPrank();

        vm.startPrank(sally);

        blueberryStaking.startVesting(ibTokens);

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
        address[] memory ibTokens = new address[](1);

        // 1. Notify the new rewards amount 20 tokens for the reward period

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 20;

        stakeAmounts[0] = 1e8 * 10;

        ibTokens[0] = address(mockIbToken1);

        blueberryStaking.modifyRewardAmount(ibTokens, rewardAmounts);

        vm.stopPrank();

        // 2. bob stakes 10 bToken1

        vm.startPrank(bob);

        mockIbToken1.approve(address(blueberryStaking), stakeAmounts[0]);

        blueberryStaking.stake(ibTokens, stakeAmounts);

        // 3. Bob unstakes 5 bToken1

        blueberryStaking.unstake(ibTokens, stakeAmounts);

        // 3.5 ensure that all tokens have been unstaked

        assertEq(mockIbToken1.balanceOf(bob), bobInitialBalance);

        // 3.6 ensure that bob can still start vesting

        blueberryStaking.startVesting(ibTokens);
    }
    
    function testRewardAccumulation() public {
        // Temporary variables
        uint256[] memory rewardAmounts = new uint256[](2);
        uint256[] memory stakeAmounts = new uint256[](2);
        address[] memory ibTokens = new address[](2);

        uint256[] memory sallyRewardAmounts = new uint256[](1);
        uint256[] memory sallyStakeAmounts = new uint256[](1);
        address[] memory sallybTokens = new address[](1);

        // 1. Notify the new rewards amount 20 tokens for the reward period

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 20;
        rewardAmounts[1] = 1e18 * 20;
        sallyRewardAmounts[0] = 1e18 * 20;

        stakeAmounts[0] = 1e8 * 10;
        stakeAmounts[1] = 1e8 * 10;
        sallyStakeAmounts[0] = 1e8 * 10;

        ibTokens[0] = address(mockIbToken1);
        ibTokens[1] = address(mockIbToken2);
        sallybTokens[0] = address(mockIbToken1);

        blueberryStaking.modifyRewardAmount(ibTokens, rewardAmounts);

        vm.stopPrank();

        // 2. bob stakes 10 bToken1

        vm.startPrank(bob);

        mockIbToken1.approve(address(blueberryStaking), stakeAmounts[0]);
        mockIbToken2.approve(address(blueberryStaking), stakeAmounts[1]);

        blueberryStaking.stake(ibTokens, stakeAmounts);

        blueberryStaking.getAccumulatedRewards(owner);

        vm.startPrank(sally);

        mockIbToken1.approve(address(blueberryStaking), sallyStakeAmounts[0]);
        blueberryStaking.stake(sallybTokens, sallyStakeAmounts);

        vm.stopPrank();

        skip(14 days);

        uint256 bobsExpectedAccumulatedRewards = rewardAmounts[0] / 2 + rewardAmounts[1];
        assertEq(isCloseEnough(blueberryStaking.getAccumulatedRewards(bob), bobsExpectedAccumulatedRewards), true);    
    }
}
