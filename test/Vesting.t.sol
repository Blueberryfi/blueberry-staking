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
    address public alice = makeAddr("alice");

    uint256 public bobInitialBalance = 1e18 * 200;
    uint256 public sallyInitialBalance = 1e18 * 200;
    uint256 public danInitialBalance = 1e18 * 200;
    uint256 public aliceInitialBalance = 1e18 * 200;
    uint256 public ownerInitialBalance;

    uint256[] public rewardAmounts = new uint256[](1);
    uint256[] public stakeAmounts = new uint256[](1);
    address[] public bTokens = new address[](1);

    function setUp() public {
        // 0. Deploy the contracts

        vm.startPrank(owner);

        mockbToken1 = new MockbToken();
        mockbToken2 = new MockbToken();
        mockbToken3 = new MockbToken();

        mockUSDC = new MockUSDC();

        blb = new BlueberryToken(owner, owner, block.timestamp);

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
        
        blb.mint(address(owner), 1e20);

        mockbToken1.transfer(bob, 1e18 * 200);
        mockbToken2.transfer(bob, 1e18 * 200);
        mockbToken3.transfer(bob, 1e18 * 200);

        mockbToken1.transfer(sally, 1e18 * 200);
        mockbToken2.transfer(sally, 1e18 * 200);
        mockbToken3.transfer(sally, 1e18 * 200);

        mockbToken1.transfer(dan, 1e18 * 200);
        mockbToken2.transfer(dan, 1e18 * 200);
        mockbToken3.transfer(dan, 1e18 * 200);

        mockbToken1.transfer(alice, 1e18 * 200);
        mockbToken2.transfer(alice, 1e18 * 200);
        mockbToken3.transfer(alice, 1e18 * 200);

        mockUSDC.transfer(bob, 1e10);
        mockUSDC.transfer(sally, 1e10);
        mockUSDC.transfer(dan, 1e10);
        mockUSDC.transfer(alice, 1e10);

        vm.stopPrank();

        // 1. Notify the new rewards amount 4_000 of each token for the reward period

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 20;

        stakeAmounts[0] = 1e18 * 5;

        bTokens[0] = existingBTokens[0];

        blb.approve(address(blueberryStaking), UINT256_MAX);
        blueberryStaking.modifyRewardAmount(bTokens, rewardAmounts);

        vm.stopPrank();

        // 2. bob, sally, dan, and alice each stake 10 of each bToken

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

        vm.startPrank(alice);
        mockbToken1.approve(address(blueberryStaking), stakeAmounts[0]);
        blueberryStaking.stake(bTokens, stakeAmounts);
        vm.stopPrank();

        console.log("BLB balance before: %s", blb.balanceOf(address(this)));
    }

    function testAccelerateVestingMonthOne() public {
        vm.startPrank(bob);

        // 3. bob starts vesting after 14 days of rewards accrual
        skip(14 days);
        blueberryStaking.startVesting(bTokens);

        // 4. 1/2 a year has now passed, bob decides to accelerate his vesting

        vm.warp(180 days);

        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 0;

        mockUSDC.approve(address(blueberryStaking), 1e6 * 10_000);

        uint256 _usdcBefore = mockUSDC.balanceOf(bob);

        console.log("USDC balance before acceleration 1/2 year in: $%s", mockUSDC.balanceOf(bob) / 1e6);
        console.log("Acceleration Ratio: %s%", blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0) / 1e15);

        (uint256 vestAmount, , , uint256 underlyingCost) = blueberryStaking.vesting(bob, 0);
        uint256 _earlyUnlockRatio = (blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0));
        uint256 _expectedCost = (_earlyUnlockRatio * ((underlyingCost * vestAmount) / 1e18) / 1e18) / 1e12;
        uint256 _accelerationFee = (blueberryStaking.getAccelerationFeeStableAsset(bob, 0));

        console.log("expected cost: $0.%s", _expectedCost);
        console.log("real cost: $%s", _accelerationFee);

        blueberryStaking.accelerateVesting(indexes);

        console.log("USDC balance after acceleration 1/2 year: $%s", mockUSDC.balanceOf(bob) / 1e6);

        assertApproxEqAbs(mockUSDC.balanceOf(bob), _usdcBefore - (_expectedCost / 1e46), 1e6);

        console.log("BLB balance after acceleration: %s", blb.balanceOf(address(this)));

        vm.stopPrank();
    }

    function testEnsureEarlyUnlockRatioLinear() public {
        // 3. bob starts vesting after 14 days of rewards accrual
        skip(14 days);
        vm.prank(bob);
        blueberryStaking.startVesting(bTokens);

        // To start, the penalty is 25%. After 364 days (52 weeks), the penalty will be 0%.

        // 0/364 days: 100% of original penalty => 25%.
        console2.log("Unlock penalty ratio right away: %s%", blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0) / 1e16);
        assertEq(blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0), 25e16);

        // 10/364 days: 97% of original penalty => ~24%.
        skip(10 days);
        console2.log(
            "Unlock penalty ratio after 10 days: %s%", blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0) / 1e16
        );
        assertApproxEqAbs(blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0), 24e16, 1e16);

        // 165/364 days: 55% of original penalty => ~14%.
        skip(155 days);
        console2.log(
            "Unlock penalty ratio after 165 days: %s%", blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0) / 1e16
        );
        assertApproxEqAbs(blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0), 14e16, 1e16);

        // 364/364 days: 0% of original penalty => 0%.
        skip(199 days);
        console2.log(
            "Unlock penalty ratio after 364 days: %s%", blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0) / 1e16
        );
        assertEq(blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0), 0);
    }

    function testAccelerateVestingTwoUsersSequential() public {
        vm.startPrank(bob);

        // 3. bob starts vesting after 14 days of rewards accrual
        skip(14 days);
        blueberryStaking.startVesting(bTokens);
        (uint256 bobVestAmount, , , ) = blueberryStaking.vesting(bob, 0);

        // Wait 30 days to guarantee lockdrop completes.
        skip(30 days);

        // Bob accelerates, paying an early unlock penalty and acceleration fee.
        uint256[] memory indexes = new uint256[](1);
        uint256 bobPenalty = blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0);
        mockUSDC.approve(address(blueberryStaking), 1e6 * 10_000);
        blueberryStaking.accelerateVesting(indexes);

        // Bob should have received his vest amount minus the early unlock penalty.
        uint256 redistributedBLB = bobPenalty * bobVestAmount / 1e18;
        uint256 bobBLB = blb.balanceOf(bob);
        console2.log("Bob's vest amount was: %s", bobVestAmount);
        console2.log("Bob's penalty amount was: %s", redistributedBLB);
        console2.log("Bob received: %s", bobBLB);
        assertEq(bobBLB, bobVestAmount - redistributedBLB);

        vm.stopPrank();

        vm.startPrank(sally);

        // Sally now starts vesting.
        blueberryStaking.startVesting(bTokens);
        (uint256 sallyVestAmount, , , ) = blueberryStaking.vesting(sally, 0);

        // Wait 52 weeks to enable Sally to complete her vesting.
        skip(52 weeks);

        // Sally completes her vesting. She should have received her vest amount plus Bob's redistributed BLB.
        blueberryStaking.completeVesting(indexes);
        uint256 sallyBLB = blb.balanceOf(sally);
        console2.log("Sally's vest amount was: %s", sallyVestAmount);
        console2.log("Sally received: %s", sallyBLB);
        assertEq(sallyBLB, sallyVestAmount + redistributedBLB);

        vm.stopPrank();

        // In total, Bob and Sally should have received all of the vested rewards.
        uint256 totalVestAmount = bobVestAmount + sallyVestAmount;
        uint256 totalBLB = bobBLB + sallyBLB;
        console2.log("Together, Bob and Sally earned: %s", totalVestAmount);
        console2.log("Together, Bob and Sally received: %s", totalBLB);
        assertEq(totalBLB, totalVestAmount);
    }

    function testAccelerateVestingTwoUsersSimultaneous() public {
        vm.startPrank(bob);

        // Wait 30 days to guarantee lockdrop completes.
        skip(30 days + 1);

        // Bob starts vesting.
        blueberryStaking.startVesting(bTokens);
        (uint256 bobVestAmount, , , ) = blueberryStaking.vesting(bob, 0);

        // Bob immediately accelerates, paying the full early unlock penalty and acceleration fee.
        uint256[] memory indexes = new uint256[](1);
        uint256 bobPenalty = blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0);
        mockUSDC.approve(address(blueberryStaking), 1e6 * 10_000);
        blueberryStaking.accelerateVesting(indexes);

        // Bob should have received his vest amount minus the early unlock penalty.
        uint256 redistributedBLB = bobPenalty * bobVestAmount / 1e18;
        uint256 bobBLB = blb.balanceOf(bob);
        console2.log("Bob's vest amount was: %s", bobVestAmount);
        console2.log("Bob's penalty amount was: %s", redistributedBLB);
        console2.log("Bob received: %s", bobBLB);
        assertEq(bobBLB, bobVestAmount - redistributedBLB);

        vm.stopPrank();

        vm.startPrank(sally);

        // Sally now starts vesting.
        blueberryStaking.startVesting(bTokens);
        (uint256 sallyVestAmount, , , ) = blueberryStaking.vesting(sally, 0);

        // Wait 52 weeks to enable Sally to complete her vesting.
        skip(52 weeks);

        // Sally completes her vesting. She should have received her vest amount plus Bob's redistributed BLB.
        blueberryStaking.completeVesting(indexes);
        uint256 sallyBLB = blb.balanceOf(sally);
        console2.log("Sally's vest amount was: %s", sallyVestAmount);
        console2.log("Sally received: %s", sallyBLB);
        assertEq(sallyBLB, sallyVestAmount + redistributedBLB);

        vm.stopPrank();

        // In total, Bob and Sally should have received all of the vested rewards.
        uint256 totalVestAmount = bobVestAmount + sallyVestAmount;
        uint256 totalBLB = bobBLB + sallyBLB;
        console2.log("Together, Bob and Sally earned: %s", totalVestAmount);
        console2.log("Together, Bob and Sally received: %s", totalBLB);
        assertEq(totalBLB, totalVestAmount);
    }

    function testAccelerateVestingStaggered() public {
        // Wait 30 days to guarantee lockdrop completes.
        skip(30 days + 1);

        // Bob starts vesting.
        vm.startPrank(bob);
        blueberryStaking.startVesting(bTokens);
        (uint256 bobVestAmount, , , ) = blueberryStaking.vesting(bob, 0);
        vm.stopPrank();

        // Sally also starts vesting at the same time.
        vm.startPrank(sally);
        blueberryStaking.startVesting(bTokens);
        (uint256 sallyVestAmount, , , ) = blueberryStaking.vesting(sally, 0);
        vm.stopPrank();

        uint256[] memory indexes = new uint256[](1);

        // Bob immediately accelerates, paying the full early unlock penalty and acceleration fee.
        vm.startPrank(bob);
        mockUSDC.approve(address(blueberryStaking), 1e6 * 10_000);
        blueberryStaking.accelerateVesting(indexes);
        uint256 bobBLB = blb.balanceOf(bob);
        vm.stopPrank();

        // Sally also accelerates, paying the full early unlock penalty and acceleration fee.
        vm.startPrank(sally);
        mockUSDC.approve(address(blueberryStaking), 1e6 * 10_000);
        blueberryStaking.accelerateVesting(indexes);
        uint256 sallyBLB = blb.balanceOf(sally);
        vm.stopPrank();

        // Dan starts his vesting.
        vm.startPrank(dan);
        blueberryStaking.startVesting(bTokens);
        (uint256 danVestAmount, , , ) = blueberryStaking.vesting(dan, 0);
        vm.stopPrank();

        // Alice also starts her vesting.
        vm.startPrank(alice);
        blueberryStaking.startVesting(bTokens);
        (uint256 aliceVestAmount, , , ) = blueberryStaking.vesting(alice, 0);
        vm.stopPrank();

        // Wait 52 weeks to enable Dan and Alice to complete their vesting.
        skip(52 weeks);

        // Dan completes his vesting.
        vm.startPrank(dan);
        blueberryStaking.completeVesting(indexes);
        uint256 danBLB = blb.balanceOf(dan);
        vm.stopPrank();

        // Alice completes her vesting.
        vm.startPrank(alice);
        blueberryStaking.completeVesting(indexes);
        uint256 aliceBLB = blb.balanceOf(alice);
        vm.stopPrank();

        // In total, all users should have received all of the vested rewards.
        uint256 totalVestAmount = bobVestAmount + sallyVestAmount + danVestAmount + aliceVestAmount;
        uint256 totalBLB = bobBLB + sallyBLB + danBLB + aliceBLB;
        console2.log("Together, all users earned: %s", totalVestAmount);
        console2.log("Together, all users received: %s", totalBLB);
        assertEq(totalBLB, totalVestAmount);
    }

    function testGetPrice() public {
        // Period 1: 0.02e18 USDC/BLB
        assertEq(blueberryStaking.getPrice(), 0.02e18);

        // Period 2: 0.04e18 USDC/BLB
        skip(15 days);
        assertEq(blueberryStaking.getPrice(), 0.04e18);

        // Period 3: Market Price (because we dont have a Uniswap Pool set up, price = 0.04e18 USDC/BLB)
        skip(15 days);
        assertEq(blueberryStaking.getPrice(), 0.04e18);
    }
}
