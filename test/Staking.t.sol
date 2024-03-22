// SPDX-License-Identifier: MIT
pragma solidity >=0.4.0 <0.9.0;

import "../lib/forge-std/src/Test.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BlueberryStaking} from "../src/BlueberryStaking.sol";
import {BlueberryToken} from "../src/BlueberryToken.sol";
import {MockbToken} from "./mocks/MockbToken.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract BlueberryStakingTest is Test {
    BlueberryStaking public blueberryStaking;
    BlueberryToken public blb;
    IERC20 public mockbToken1;
    IERC20 public mockbToken2;
    IERC20 public mockbToken3;

    IERC20 public mockUSDC;

    address public treasury = makeAddr("treasury");

    address[] public existingBTokens;

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

        mockbToken1 = new MockbToken();
        mockbToken2 = new MockbToken();
        mockbToken3 = new MockbToken();

        mockUSDC = new MockUSDC();

        blb = new BlueberryToken(owner, owner, block.timestamp + 30);

        existingBTokens = new address[](3);

        existingBTokens[0] = address(mockbToken1);
        existingBTokens[1] = address(mockbToken2);
        existingBTokens[2] = address(mockbToken3);

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
                    existingBTokens,
                    owner
                )
            )
        );

        blueberryStaking = BlueberryStaking(payable(address(proxy)));

        blb.transfer(address(blueberryStaking), 1e20);

        mockbToken1.transfer(bob, 1e8 * 200);
        mockbToken2.transfer(bob, 1e8 * 200);
        mockbToken3.transfer(bob, 1e8 * 200);

        mockbToken1.transfer(sally, 1e8 * 200);
        mockbToken2.transfer(sally, 1e8 * 200);
        mockbToken3.transfer(sally, 1e8 * 200);

        mockbToken1.transfer(dan, 1e8 * 200);
        mockbToken2.transfer(dan, 1e8 * 200);
        mockbToken3.transfer(dan, 1e8 * 200);

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

        // 1. Notify the new rewards amount (1e18 * 20) for the reward period

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 20;

        stakeAmounts[0] = 1e8 * 10;

        bTokens[0] = address(mockbToken1);

        blueberryStaking.modifyRewardAmount(bTokens, rewardAmounts);

        vm.stopPrank();

        // 2. bob stakes 10 bToken1

        vm.startPrank(bob);

        mockbToken1.approve(address(blueberryStaking), stakeAmounts[0]);

        blueberryStaking.stake(bTokens, stakeAmounts);

        // 3. Half the reward period passes and it becomes claimable

        skip(7 days);

        // 3.5 Ensure that the rewards are half of the total rewards given that half of the reward period has passed

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
        stakeAmounts[0] = 1e8 * 50;

        address[] memory bTokens = new address[](1);
        bTokens[0] = address(mockbToken1);

        blueberryStaking.modifyRewardAmount(bTokens, rewardAmounts);
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

        // 1. Notify the new rewards amount (1e18 * 20) for the reward period

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 20;

        stakeAmounts[0] = 1e8 * 10;

        bTokens[0] = address(mockbToken1);

        blueberryStaking.modifyRewardAmount(bTokens, rewardAmounts);

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

        // 3. The entire reward period passes thus all rewards are claimable

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

        // 1. Notify the new rewards amount 20 tokens for the reward period

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 20;

        stakeAmounts[0] = 1e8 * 10;

        bTokens[0] = address(mockbToken1);

        blueberryStaking.modifyRewardAmount(bTokens, rewardAmounts);

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
    
    function testRewardAccumulation() public {
        // Temporary variables
        uint256[] memory rewardAmounts = new uint256[](2);
        uint256[] memory stakeAmounts = new uint256[](2);
        address[] memory bTokens = new address[](2);

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

        bTokens[0] = address(mockbToken1);
        bTokens[1] = address(mockbToken2);
        sallybTokens[0] = address(mockbToken1);

        blueberryStaking.setIbTokenArray(bTokens);
        blueberryStaking.modifyRewardAmount(bTokens, rewardAmounts);

        vm.stopPrank();

        // 2. bob stakes 10 bToken1

        vm.startPrank(bob);

        mockbToken1.approve(address(blueberryStaking), stakeAmounts[0]);
        mockbToken2.approve(address(blueberryStaking), stakeAmounts[1]);

        blueberryStaking.stake(bTokens, stakeAmounts);

        blueberryStaking.getAccumulatedRewards(owner);

        vm.startPrank(sally);

        mockbToken1.approve(address(blueberryStaking), sallyStakeAmounts[0]);
        blueberryStaking.stake(sallybTokens, sallyStakeAmounts);

        vm.stopPrank();

        skip(14 days);

        assertEq(isCloseEnough(blueberryStaking.getAccumulatedRewards(bob), rewardAmounts[0] / 2 + rewardAmounts[1]), true);    
    
    }
}
