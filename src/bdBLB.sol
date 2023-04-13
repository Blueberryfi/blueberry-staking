// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "openzeppelin/access/Ownable.sol";

error NotOwner();

contract bdBLB is Ownable, ERC20, ERC20Burnable {
    event Distributed(address indexed user, uint256 amount, uint256 epoch);
    event Accelerated(address indexed user, uint256 unlockedAmount, uint256 accelerationFee, uint256 redistributedAmount);

    address public immutable blb;

    uint16 public accelerationRatioWithdrawable = 90;
    uint16 public baseAccelerationFee = 
    uint16 public startTime;
    uint16 public endTime;
    uint16 public epochDuration = 14 days;
    uint256 public vestingDuration = 365 days;
    uint256 public lockDropDuration = 60 days;


    uint256[] public fdv = [20000000, 25000000, 30000000, 40000000, 50000000];
    uint256[] public tokenPrice = [2 * 10 ** 16, 25 * 10 ** 15, 3 * 10 ** 16, 4 * 10 ** 16, 5 * 10 ** 16];


    /// @param _blb The address of the $BLB token.
    /// @param _startTime The start time of the token distribution.
    /// @param _endTime The end time of the token distribution.
    constructor(address _blb, uint16 _startTime, uint16 _endTime) Ownable {
        blb = _blb;
        startTime = _startTime;
        endTime = _endTime;
    }

    /// @notice Emits a Distributed event for the specified user, amount, and epoch.
    /// @param user The address of the user receiving the distribution.
    /// @param amount The amount of tokens being distributed.
    /// @param epoch The epoch of the distribution.
    function distribute(address user, uint256 amount, uint256 epoch) external {
        emit Distributed(user, amount, epoch);
    }

    /// @notice Accelerates the vesting of the calling user by the specified amounts.
    /// @param unlockedAmount The amount of tokens being unlocked.
    /// @param accelerationFee The fee paid for accelerating the vesting.
    /// @param redistributedAmount The amount of tokens being redistributed to other users.
    function accelerateVesting() external {
        uint256 bdBLBBalance = balanceOf(msg.sender);
        require(bdBLBBalance > 0, "No $bdBLB balance to accelerate");

        (, uint256 currentTokenPrice) = getCurrentFdvAndTokenPrice();
        uint256 initialAccelerationFee = currentTokenPrice * 7 / 10;
        uint256 accelerationFee = calculateAccelerationFee(initialAccelerationFee, vestingDuration);

        // Transfer the acceleration fee from the user to the treasury
        ERC20(blb).transferFrom(msg.sender, owner(), accelerationFee);

        uint256 unlockedAmount = bdBLBBalance * accelerationRatioWithdrawable / 100;
        uint256 redistributedAmount = bdBLBBalance - unlockedAmount;

        // Burn the accelerated $bdBLB tokens
        _burn(msg.sender, bdBLBBalance);

        // Transfer the unlocked $BLB tokens to the user
        ERC20(blb).transfer(msg.sender, unlockedAmount);

        // Redistribute the remaining tokens to other users (implementation needed)

        emit Accelerated(msg.sender, unlockedAmount, accelerationFee, redistributedAmount);
}

    /// @notice Calculates the acceleration fee based on the initial BLB price and early unlock penalty ratio.
    /// @param initialBLBPrice The initial price of the BLB token.
    /// @param earlyUnlockPenaltyRatio The early unlock penalty ratio.
    /// @return _amount The calculated acceleration fee.
    function calculateAccelerationFee(uint256 initialBLBPrice, uint256 earlyUnlockPenaltyRatio) public view returns (uint256 _amount){

    }

    function calculateRedistributionAmount(uint256 bdBLBBalance, uint256 earlyUnlockPenaltyRatio) public view returns (uint256 _amount){

    }

    function changeAccelerationRatio(uint256 _newAccelerationRatio) onlyOwner external {
        accelerationRatio = _newAccelerationRatio;
    }
    
}
