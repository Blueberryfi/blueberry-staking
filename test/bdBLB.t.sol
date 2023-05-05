// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../src/bdBLB.sol";

contract bdBLBTest is Test {
    function setUp() public {
        blb = IERC20(address(this));
        usdc = IERC20(address(this));

        startTime = uint16(block.timestamp + 60);
        epochDuration = 10 minutes;
        vestingDuration = 2 * epochDuration;
        lockDropDuration = 30 minutes;

        owner = address(this);
        treasury = address(this);
        keeper = address(this);
        accelerationRatioWithdrawable = 90000000000;

        vesting = new Vesting(startTime, keeper);
        vesting.transferOwnership(owner);

        vesting.BLB().transfer(address(vesting), 1000000);
        vesting.USDC().transfer(address(vesting), 1000000);

        vesting.changeTreasury(treasury);

        vesting.vestingDuration();
    }

    function testLock() public {
        uint256 amount = 1000;

        usdc.approve(address(vesting), amount);
        vesting.lock(amount);

        assertEq(vesting.lockedBalance(address(this)), amount);
        assertEq(vesting.vestingSchedules(address(this), 0).lockedBalanceUSDC, amount);
        assertEq(vesting.vestingSchedules(address(this), 0).claimableBalanceBLB, amount * 2);
        assertEq(vesting.vestingSchedules(address(this), 0).epoch, 0);

        assertEq(usdc.balanceOf(address(vesting)), amount);
    }

    function testWithdraw() public {
        uint256 amount = 1000;

        usdc.approve(address(vesting), amount);
        vesting.lock(amount);

        uint256 balanceBefore = usdc.balanceOf(address(this));

        vesting.withdraw(0);

        uint256 balanceAfter = usdc.balanceOf(address(this));

        assertEq(balanceAfter, balanceBefore + amount);
        assertEq(vesting.lockedBalance(address(this)), 0);
        assertEq(vesting.vestingSchedules(address(this), 0).lockedBalanceUSDC, 0);
        assertEq(vesting.vestingSchedules(address(this), 0).claimableBalanceBLB, 0);
        assertEq(vesting.vestingSchedules(address(this), 0).epoch, 0);
    }

    function testAccelerateVesting() public {
        uint256 amount = 1000;

        usdc.approve(address(vesting), amount);
        vesting.lock(amount);

        uint256 accelerationFee = vesting.getAccelerationFee(address(this), vesting.vestingSchedules(address(this), 0));

        usdc.approve(address(vesting), accelerationFee);
        vesting.accelerateVesting(0);

        assertEq(vesting.lockedBalance(address(this)), amount * accelerationRatioWithdrawable / ACCELERATION_RATIO_PRECISION);
    }

    function testChangeTreasury() public {
        address newTreasury = address(this);

        vesting.changeTreasury(newTreasury);

        assertEq(vesting.treasury(), newTreasury);
    }
}
