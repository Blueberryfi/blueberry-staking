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

    address public treasury = address(99);

    address[] public existingBTokens;

    address public bob = address(1);
    address public sally = address(2);
    address public owner = address(3);

    uint256 public bobInitialBalance = 1e18 * 200;
    uint256 public sallyInitialBalance = 1e18 * 200;
    uint256 public ownerInitialBalance;

    uint256[] public rewardAmounts = new uint256[](1);
    uint256[] public stakeAmounts = new uint256[](1);
    address[] public bTokens = new address[](1);

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

        blueberryStaking = new BlueberryStaking(address(blb), address(mockUSDC), address(treasury), 1_209_600, existingBTokens);

        blb.transfer(address(blueberryStaking), 1e20);

        mockbToken1.transfer(bob, 1e18 * 200);
        mockbToken2.transfer(bob, 1e18 * 200);
        mockbToken3.transfer(bob, 1e18 * 200);

        mockbToken1.transfer(sally, 1e18 * 200);
        mockbToken2.transfer(sally, 1e18 * 200);
        mockbToken3.transfer(sally, 1e18 * 200);

        mockUSDC.transfer(bob, 1e10);
        mockUSDC.transfer(sally, 1e10);

        vm.stopPrank();

        // 1. Notify the new rewards amount 4_000 of each token for the epoch

        vm.startPrank(owner);

        rewardAmounts[0] = 1e18 * 20;

        stakeAmounts[0] = 1e18 * 5;

        bTokens[0] = existingBTokens[0];

        blueberryStaking.notifyRewardAmount(bTokens, rewardAmounts);

        vm.stopPrank();

        // 2. bob stakes 10 of each bToken

        vm.startPrank(bob);

        mockbToken1.approve(address(blueberryStaking), stakeAmounts[0]);

        blueberryStaking.stake(bTokens, stakeAmounts);

        console.log("BLB balance before: %s", blb.balanceOf(address(this)));

        skip(14 days);

        blueberryStaking.startVesting(bTokens);
        
    }


    function testAccelerateVestingMonthOne() public {

        // 3. 1/2 a year has now passed, bob decides to accelerate his vesting

        vm.warp(180 days);
        
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 0;

        mockUSDC.approve(address(blueberryStaking), 1e6 * 10_000);

        uint256 _usdcBefore = mockUSDC.balanceOf(bob);

        console.log("USDC balance before acceleration 1/2 year in: $%s", mockUSDC.balanceOf(bob) / 1e6);
        console.log("Acceleration Ratio: %s%", blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0) / 1e15);

        (uint256 vestAmount,, uint256 underlyingCost) = blueberryStaking.vesting(bob, 0);
        uint256 _earlyUnlockRatio = (blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0));
        uint256 _expectedCost = (_earlyUnlockRatio * ((underlyingCost * vestAmount) / 1e18) / 1e18) / 1e12;
        uint256 _accelerationFee = (blueberryStaking.getAccelerationFeeUSDC(bob, 0));

        console.log("expected cost: $0.%s", _expectedCost);
        console.log("real cost: $%s", _accelerationFee);

        blueberryStaking.accelerateVesting(indexes);

        console.log("USDC balance after acceleration 1/2 year: $%s", mockUSDC.balanceOf(bob) / 1e6);

        require(isCloseEnough(_usdcBefore - (_expectedCost / 1e46), mockUSDC.balanceOf(bob)));

        console.log("BLB balance after acceleration: %s", blb.balanceOf(address(this)));
    }

    function testEnsureEarlyUnlockRatioLinear() public {

        blueberryStaking.startVesting(bTokens);

        console2.log("Unlock penalty ratio right away: %s%", blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0) / 1e15);

        assertEq(blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0) / 1e15, 35);

        skip(10 days);

        console2.log("Unlock penalty ratio after 10 days: %s%", blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0) / 1e15);

        skip(155 days);

        console2.log("Unlock penalty ratio after 165 days: %s%", blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0) / 1e15);

        skip(200 days);

        console2.log("Unlock penalty ratio after 365 days: %s%", blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0) / 1e15);
    
        assertEq(blueberryStaking.getEarlyUnlockPenaltyRatio(bob, 0), 0);
    }
}
