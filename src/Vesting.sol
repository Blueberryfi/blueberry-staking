// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.19;

import { IERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { UD60x18 } from "../lib/prb-math/src/UD60x18.sol";

error NotOwner();
error AddressZero();
error InvalidStartTime();
error InvalidBalance();
error InvalidDuration();
error InvalidEpoch();
error LockDropActive();
error LockDropInactive();
error NotKeeper();
error InvalidIndex();
error InvalidAmount();
error InvalidbToken();
error ZeroEmissionSchedules();
error TransferFailed();
error VestingNotCompleted();

contract Vesting is Ownable {

    event Distributed(address indexed user, uint256 amount, uint256 epoch);

    event Accelerated(address indexed user, uint256 unlockedAmount, uint256 accelerationFee, uint256 redistributedAmount);

    event Locked(address indexed user, uint256 amount);

    event Withdrawn(address indexed user, uint256 vestingIndex, uint256 amount, uint256 feeAmount);

    /// @notice The `BLB` token contract.
    IERC20 public constant BLB = IERC20(0x904f36d74bED2Ef2729Eaa1c7A5B70dEA2966a02);

    /// @notice USDC token contract.
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    /// @notice The address of the treasury, where acceleration fees are sent.
    address public treasury;

    /// @notice The address of the keeper for automation.
    address public keeper;

    /// @notice The ratio of `bdBLB` tokens at the beginning of vest that are withdrawable (70% in this case).
    uint256 public BASE_UNLOCK_PENALTY_RATIO = 700_000_000_000_000_000;

    /// @notice The precision used for ratio calculations.
    uint256 constant public RATIO_PRECISION = 1_000_000_000_000_000_000;

    /// @notice The timestamp when the lockdrop starts.
    uint16 public startTime;

    /// @notice The duration of each epoch (14 days in this case).
    uint64 public epochDuration = 14 days;

    /// @notice The duration of the vesting period (365 days in this case).
    uint256 public vestingDuration = 365 days;

    /// @notice The duration of the lockdrop (60 days in this case).
    uint256 public lockDropDuration = 60 days;

    /// @notice The amount of USDC collected by withdrawal fees.
    uint256 public feesWithdrawable;

    /// @notice The whitelist of bTokens that can be used to participate in the lockdrop.
    mapping (address => bool) public bTokenWhitelist;

    /// @notice The total amount of `bdBLB` tokens distributed during the lockdrop.
    mapping (address => uint256) public allocations;

    /// @notice The vesting schedules for each user.
    mapping(address => VestingSchedule[]) public vestingSchedules;

    mapping(address => uint256) public lockedBalance;

    struct VestingSchedule {
        uint256 claimableBalanceBLB;
        uint256 lockedBalanceUSDC;
        uint64 epoch;
        uint64 startTime;
    }

    struct VestingMonth {
        uint256 fdv;
        uint256 tokenPrice;
    }

    struct EmissionSchedule {
        address bToken;
        uint256 bdBLBAmount;
    }

    /// @notice The emission schedules for each bToken.
    EmissionSchedule[] public emissionSchedules;

    /// @notice The vesting months for the lockdrop.
    VestingMonth[2] internal _vestingMonths = [
        // $40M FDV at $0.04 BLB
        VestingMonth({fdv: 40_000_000, tokenPrice: 4e16}),
        // $80M FDV at $0.08 BLB
        VestingMonth({fdv: 80_000_000, tokenPrice: 8e16})
    ];

    /// @notice ensures that the lockdrop is inactive.
    modifier ensureLockDropInactive() {
        if (startTime + lockDropDuration < block.timestamp){
            revert LockDropActive();
        }
        _;
    }

    /// @notice ensures that the lockdrop is active.
    modifier ensureLockDropActive() {
        if (block.timestamp < startTime + lockDropDuration){
            revert LockDropInactive();
        }
        _;
    }

    /// @notice ensures that the caller is the keeper.
    modifier onlyKeeper() {
        if (msg.sender != keeper){
            revert NotKeeper();
        }
        _;
    }

    /// @param _startTime The start time of the token distribution.
    /// @param _keeper The address of the keeper for automation.
    /// @param _emissionSchedules The emission schedules for each bToken.
    constructor(uint16 _startTime, address _keeper, EmissionSchedule[] memory _emissionSchedules) Ownable() {
        if (_startTime >= block.timestamp){
            revert InvalidStartTime();
        }
        if (_emissionSchedules.length == 0){
            revert ZeroEmissionSchedules();
        }
        if (_keeper == address(0)){
            revert AddressZero();
        }

        startTime = _startTime;
        keeper = _keeper;
        emissionSchedules = _emissionSchedules;

        // Update the whitelist for bTokens

        // bWETH
        bTokenWhitelist[0x8E09cC1d00c9bd67f99590E1b2433bF4Db5309C3] = true;

        // bDAI
        bTokenWhitelist[0xcB5C1909074C7ac1956DdaFfA1C2F1cbcc67b932] = true;

        // bWBTC
        bTokenWhitelist[0x506c190340F786c65548C0eE17c5EcDbba7807e0] = true;

        // bUSDC
        bTokenWhitelist[0xdfd54ac444eEffc121E3937b4EAfc3C27d39Ae64] = true;

        // bICHI
        bTokenWhitelist[0xBDf1431c153A2A48Ee05C1F24b9Dc476C93F75aE] = true;

        // bSUSHI
        bTokenWhitelist[0x8644e2126776daFE02C661939075740EC378Db00] = true;

        // bCRV
        bTokenWhitelist[0x23ED643A4C4542E223e7c7815d420d6d42556006] = true;
    }

    /// @notice Accelerates the vesting of the calling user, unlocking tokens by paying the acceleration fee for the given vesting schedule.
    /// @notice User must have have given this contract allowance to transfer the acceleration fee.
    /// @dev Penalty ratio linearly decreases over the course of the vesting period.
    /// 1 +        
    ///   | \      
    ///   |    \   
    ///   |       \
    ///   |          \
    /// 0 +------+-----> 1 year
    /// @param _vestingScheduleIndex The index of the vesting schedule to accelerate.
    function accelerateVesting(uint256 _vestingScheduleIndex) external ensureLockDropInactive {
        // index must exist
        require(vestingSchedules[msg.sender].length > _vestingScheduleIndex, InvalidIndex());

        uint256 _earlyUnlockPenaltyRatio = getEarlyUnlockPenaltyRatio(msg.sender, vestingSchedules[msg.sender][_vestingScheduleIndex]);

        // get acceleration fee
        uint256 _accelerationFee = getAccelerationFee(msg.sender, vestingSchedules[msg.sender][_vestingScheduleIndex]);

        // transfer the fee to the treasury
        (bool success,) = USDC.transferFrom(msg.sender, treasury, _accelerationFee);
        require(success, TransferFailed());

        //uint256 _totalClaimable = claimable(msg.sender, _epoch);

        // only claim 90% of the tokens
        //uint256 _unlockedAmount = _totalClaimable * accelerationRatioWithdrawable / ACCELERATION_RATIO_PRECISION;


        // the rest is redistributed 
        //uint256 _redistributedAmount = _totalClaimable - _unlockedAmount;

        //emit Accelerated(msg.sender, _unlockedAmount, _accelerationFee, _redistributedAmount);
    }

    /// @dev Claims the tokens that have completed their vesting schedule for the caller.
    /// @param _vestingScheduleIndex The index of the vesting schedule to claim.
    function claim(uint256 _vestingScheduleIndex) external {
        // index must exist
        require(vestingSchedules[msg.sender].length > _vestingScheduleIndex, InvalidIndex());

        // Retrieve the vesting schedule for the caller and specified index
        VestingSchedule _vestingSchedule = vestingSchedules[msg.sender][_vestingScheduleIndex];

        // make sure the vesting has completed
        require(block.timestamp >= _vestingSchedule.startTime + 1 years, VestingNotCompleted());

        // get the claimable amount
        uint256 _claimable = getClaimableBeforeFees(msg.sender, _vestingSchedule);

        // update the vesting schedule and prep for removal
        vestingSchedules[msg.sender][_vestingScheduleIndex] = vestingSchedules[msg.sender][vestingSchedules[msg.sender].length - 1];    
        vestingSchedules[msg.sender].pop();

        // transfer the tokens
        bdBLB.transfer(msg.sender, _claimable);

        emit Claimed(msg.sender, _claimable);
    }


    function getCurrentEpoch() public view returns (uint64 _currentEpoch) {
        require(block.timestamp >= startTime, InvalidStartTime());
        _currentEpoch = (block.timestamp - startTime) / epochDuration;
    }

    /**
     * @dev Gets the current unlock penalty ratio, which linearly decreases from 70% to 0% over the vesting period.
     * This is done by calculating the ratio of the time that has passed since the start of the vesting period to the total vesting period.
     * @param _user The user's address.
     * @param _vestingScheduleIndex The index of the vesting schedule.
     * @return _earlyUnlockPenaltyRatio The current unlock penalty ratio multiplied by 1e15.
     */
    function getEarlyUnlockPenaltyRatio(address _user, uint256 _vestingScheduleIndex) public view returns (uint256 _earlyUnlockPenaltyRatio){
        // Retrieve the vesting schedule for the user and specified index
        VestingSchedule _vestingSchedule = vestingSchedules[_user][_vestingScheduleIndex];
        // Get the current timestamp
        uint256 _blockTimestamp = block.timestamp;
        // Calculate the vesting end time by adding 1 year to the vesting start time
        uint256 _vestEndTime = _vestingSchedule.startTime + 1 years;
        // Calculate the early unlock penalty ratio based on the time passed and total vesting period
        _earlyUnlockPenaltyRatio = (_vestEndTime - _blockTimestamp) * 1e15 / 1 years;
    }

    function calculatebdBLBAmount(uint256 _lockedUSDC) public view returns (uint256 _amount){
        //uint256 _currentPrice = getCurrentTokenPrice();
        //uint256 _bdBLBAmount = _lockedUSDC * _currentPrice;
        //return _bdBLBAmount;
    }

    function changeTreasury(address _newTreasury) onlyOwner external {
        treasury = _newTreasury;
    }

    function updateBTokenWhitelist(address _bToken, bool _status) onlyOwner public {
        bTokenWhitelist[_bToken] = _status;
    }

    function withdrawFees() onlyOwner external {
        feesWithdrawable = 0;
        USDC.transfer(msg.sender, feesWithdrawable);        
    }

    /**
     * @dev Returns the current time.
     * @return the current timestamp in seconds.
     */
    function _getCurrentTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /**
     * @dev Returns the specified user's vesting schedules.
     */
    function getVestingSchedules(address _user) public view returns (VestingSchedule[] memory _vestingSchedules){
        _vestingSchedules = vestingSchedules[_user];
    }

    /**
     * @dev This function is called for plain Ether transfers, i.e. for every call with empty calldata.
     */
    receive() external payable {}

    /**
     * @dev Fallback function is executed if none of the other functions match the function
     * identifier or no data was provided with the function call.
     */
    fallback() external payable {}
    
}
