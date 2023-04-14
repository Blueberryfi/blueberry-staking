// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { Ownable } from "openzeppelin/access/Ownable.sol";

error NotOwner();
error AddressZero();
error InvalidStartTime();
error InvalidBalance();
error InvalidDuration();
error InvalidEpoch();

contract Vesting is Ownable {

    /// @notice Event emitted when `bdBLB` tokens are distributed to a user.
    /// @param `user` - Address of the user receiving the tokens.
    /// @param `amount` - Number of `bdBLB` tokens distributed.
    /// @param `epoch` - Epoch number during which the distribution took place.
    event Distributed(address indexed user, uint256 amount, uint256 epoch);

    /// @notice Event emitted when a user accelerates the vesting of their `bdBLB` tokens.
    /// @param `user` - Address of the user who accelerated the vesting.
    /// @param `unlockedAmount` - Number of `bdBLB` tokens that were unlocked during the acceleration.
    /// @param `accelerationFee` - Fee paid by the user for accelerating the vesting.
    /// @param `redistributedAmount` - Amount of `bdBLB` tokens redistributed to other holders as a result of the acceleration.
    event Accelerated(address indexed user, uint256 unlockedAmount, uint256 accelerationFee, uint256 redistributedAmount);

    /// @notice The `BLB` token contract.
    IERC20 public immutable blb;

    /// @notice The address of the treasury, where acceleration fees are sent.
    address public treasury;

    /// @notice The ratio of `bdBLB` tokens that can be withdrawn upon acceleration (90% in this case, represented as a decimal with 12 decimal places).
    uint16 public accelerationRatioWithdrawable = 90_000_000_000;

    /// @notice The precision used for the acceleration ratio calculations (100% in this case, represented as a decimal with 12 decimal places).
    uint16 public accelerationRatioPrecision = 100_000_000_000;

    /// @notice The base acceleration fee for accelerating the vesting of `bdBLB` tokens.
    uint16 public baseAccelerationFee = 0;

    /// @notice The timestamp when the lockdrop starts.
    uint16 public startTime;

    /// @notice The timestamp when the lockdrop ends.
    uint16 public endTime;

    /// @notice The duration of each epoch (14 days in this case).
    uint16 public epochDuration = 14 days;

    /// @notice The duration of the vesting period (365 days in this case).
    uint256 public vestingDuration = 365 days;

    /// @notice The duration of the lockdrop (60 days in this case).
    uint256 public lockDropDuration = 60 days;

    struct Vesting {
        uint256 claimableBalance;
        uint256 userEpoch;
        uint256 userAccelerationTimestamp;
        uint256 lastClaimedEpoch;
    }

    mapping(address => Vesting) public vestingSchedule;
    uint256[] public fdv = [20000000, 25000000, 30000000, 40000000, 50000000];
    uint256[] public tokenPrice = [2 * 10 ** 16, 25 * 10 ** 15, 3 * 10 ** 16, 4 * 10 ** 16, 5 * 10 ** 16];


    /// @param _blb The address of the $BLB token.
    /// @param _startTime The start time of the token distribution.
    /// @param _endTime The end time of the token distribution.
    constructor(address _blb, uint16 _startTime, uint16 _endTime, address _treasury) Ownable {
        require(_blb != address(0), AddressZero());
        require(_treasury != address(0), AddressZero());
        require(_startTime > block.timestamp, InvalidStartTime());
        require(_startTime < _endTime, InvalidDuration());

        blb = IERC20(_blb);
        startTime = _startTime;
        endTime = _endTime;
        treasury = _treasury;
    }

    /// @notice Emits a Distributed event for the specified user, amount, and epoch.
    /// @param user The address of the user receiving the distribution.
    /// @param amount The amount of tokens being distributed.
    /// @param epoch The epoch of the distribution.
    function distribute(address user, uint256 amount, uint256 epoch) external {

        emit Distributed(user, amount, epoch);
    }

    /// @notice Accelerates the vesting of the calling user, unlocking tokens by paying current acceleration fee.
    function accelerateVesting() external {
        uint256 bdBLBBalance = claimable(msg.sender);
        require(bdBLBBalance > 0, InvalidBalance());

        (, uint256 currentTokenPrice) = getCurrentFdvAndTokenPrice();
        uint256 initialAccelerationFee = currentTokenPrice * 7 / 10;
        uint256 accelerationFee = calculateAccelerationFee(initialAccelerationFee, vestingDuration);

        // Transfer the acceleration fee from the user to the treasury
        blb.transferFrom(msg.sender, treasury, accelerationFee);

        uint256 unlockedAmount = bdBLBBalance * accelerationRatioWithdrawable / accelerationRatioPrecision;
        uint256 redistributedAmount = bdBLBBalance - unlockedAmount;

        // Burn the accelerated $bdBLB tokens
        _burn(msg.sender, bdBLBBalance);

        // Transfer the unlocked $BLB tokens to the user
        blb.transfer(msg.sender, unlockedAmount);

        // Redistribute the remaining tokens to other users (implementation needed)

        emit Accelerated(msg.sender, unlockedAmount, accelerationFee, redistributedAmount);
}

    function getCurrentFdvAndTokenPrice() public view returns (uint256 _fdv, uint256 _tokenPrice) {
        uint256 currentEpoch = getCurrentEpoch();
        uint256 fdvIndex = currentEpoch / 4;
        uint256 tokenPriceIndex = currentEpoch % 4;
        return (fdv[fdvIndex], tokenPrice[tokenPriceIndex]);
    }

    /// @notice Claims the $BLB tokens for the calling user.
    function releaseVestedTokens() external {
        uint256 _currentEpoch = getCurrentEpoch();
        uint256 _claimableBalance = _claimable(msg.sender, _currentEpoch);
        require(_claimableBalance > 0, InvalidBalance());

        // Update the user's claimable balance
        Vesting storage v = vestingSchedule[msg.sender];
        v.claimableBalance = 0;
        v.lastClaimedEpoch = _currentEpoch;

        // Transfer the $BLB tokens to the user
        ERC20(blb).transfer(msg.sender, claimableBalance);
    }


    function _claimable(address _address, uint256 _currentEpoch) internal view returns (uint256 _balance) {
        Vesting storage v = vestingSchedule[_address];

        require(_currentEpoch > user.lastClaimedEpoch, InvalidEpoch());

        if (user.userEpoch == _currentEpoch) {
            return user.claimableBalance;
        } else if (user.userEpoch < _currentEpoch) {
            uint256 currentEpochBalance = user.claimableBalance * currentEpochDuration / currentEpochVestingDuration;
            uint256 currentEpochLockDropBalance = user.claimableBalance * currentEpochDuration / currentEpochLockDropDuration;
            return currentEpochBalance + currentEpochLockDropBalance;
        } else {
            return 0;
        }
    }

    function getCurrentEpoch() public view returns (uint256 _epoch) {
        uint256 currentEpoch = (block.timestamp - startTime) / epochDuration;
        return currentEpoch;
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

    function changeTreasury(address _newTreasury) onlyOwner external {
        treasury = _newTreasury;
    }
    
}
