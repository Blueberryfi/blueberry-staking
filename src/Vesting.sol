// SPDX-License-Identifier: MIT
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

    /// @notice The ratio of `bdBLB` tokens that can be withdrawn upon acceleration (90% in this case, represented as a decimal with 12 decimal places).
    uint256 public accelerationRatioWithdrawable = 90_000_000_000;

    /// @notice The precision used for the acceleration ratio calculations (100% in this case, represented as a decimal with 12 decimal places).
    uint256 constant public ACCELERATION_RATIO_PRECISION = 100_000_000_000;

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
    }

    struct VestingMonth {
        uint256 fdv;
        uint256 tokenPrice;
    }

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
    constructor(uint16 _startTime, address _keeper) Ownable() {
        if (_startTime >= block.timestamp){
            revert InvalidStartTime();
        }

        startTime = _startTime;

        if (_keeper == address(0)){
            revert AddressZero();
        }
        keeper = _keeper;

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

    /// @notice Locks the given amount of bTokens for the sender.
    /// @notice User must have have given this contract allowance to transfer the  tokens.
    /// @param _amount The amount of bTokens to lock.
    function lock(uint256 _amount, IERC20 _bToken) external ensureLockDropActive {
        // ensure that the bToken is whitelisted
        if (!bTokenWhitelist[address(_bToken)]){
            revert InvalidbToken();
        }

        if (_amount <= 0){
            revert InvalidAmount();
        }

        // transfer the tokens to this contract
        _bToken.transferFrom(msg.sender, address(this), _amount);

        // add the tokens to the user's locked balance
        lockedBalance[msg.sender] += _amount;

        // calculate the amount of `bdBLB` tokens that will be available for the user to claim
        uint256 _claimableAmount = calculatebdBLBAmount(_amount);

        // get the current epoch
        uint64 _currentEpoch = getCurrentEpoch();

        // create a new vesting schedule
        VestingSchedule memory _newSchedule = VestingSchedule({
            claimableBalanceBLB: _claimableAmount,
            epoch: _currentEpoch,
            lockedBalanceUSDC: _amount
        });

        // add the vesting schedule to the user's list of vesting schedules
        vestingSchedules[msg.sender].push(_newSchedule);

        // emit the Locked event
        emit Locked(msg.sender, _amount);
    }

    /// @notice Withdraws the locked balance of the caller's vesting schedule specified.
    function withdraw(uint256 _vestingScheduleIndex) external {
        // cannot withdraw from a non-existent vesting schedule deposit
        if (vestingSchedules[msg.sender][_vestingScheduleIndex].lockedBalanceUSDC <= 0){
            revert InvalidBalance();
        }

        bool _lockDropActive = block.timestamp < startTime + lockDropDuration;

        // if the lockdrop is active, a 1% fee will be levied on the withdrawal
        uint256 _realWithdrawalAmount = vestingSchedules[msg.sender][_vestingScheduleIndex].lockedBalanceUSDC;
        if (_lockDropActive) {
            uint256 _withdrawalFee = vestingSchedules[msg.sender][_vestingScheduleIndex].lockedBalanceUSDC / 100;
            feesWithdrawable += _withdrawalFee;
            _realWithdrawalAmount -= _withdrawalFee;
        }

        // transfer the tokens to the user
        USDC.transfer(msg.sender, _realWithdrawalAmount);

        // emit the Withdrawn event
        //emit Withdrawn(msg.sender, lockedBalance[msg.sender], _withdrawalFee, );
    }

    /// @notice Accelerates the vesting of the calling user, unlocking tokens by paying the acceleration fee for the given vesting schedule.
    /// @notice User must have have given this contract allowance to transfer the acceleration fee.
    /// @param _vestingScheduleIndex The index of the vesting schedule to accelerate.
    function accelerateVesting(uint256 _vestingScheduleIndex) external ensureLockDropInactive {

        // index must exist
        require(vestingSchedules[msg.sender].length > _vestingScheduleIndex, InvalidIndex());

        // get acceleration fee
        uint256 _accelerationFee = getAccelerationFee(msg.sender, vestingSchedules[msg.sender][_vestingScheduleIndex]);

        // transfer the fee to the treasury
        USDC.transferFrom(msg.sender, treasury, _accelerationFee);

        //uint256 _totalClaimable = claimable(msg.sender, _epoch);

        // only claim 90% of the tokens
        //uint256 _unlockedAmount = _totalClaimable * accelerationRatioWithdrawable / ACCELERATION_RATIO_PRECISION;


        // the rest is redistributed 
        //uint256 _redistributedAmount = _totalClaimable - _unlockedAmount;

        //emit Accelerated(msg.sender, _unlockedAmount, _accelerationFee, _redistributedAmount);
    }

    function getCurrentEpoch() public view returns (uint64 _currentEpoch) {
        require(block.timestamp >= startTime, InvalidStartTime());
        _currentEpoch = (block.timestamp - startTime) / epochDuration;
    }

    /// @notice Calculates the acceleration fee based on the underlying BLB price and early unlock penalty ratio.
    /// @return _amount The calculated acceleration fee.
    function getAccelerationFee() public view returns (uint256 _amount){
        

    }

    function calculateRedistributionAmount(uint256 bdBLBBalance, uint256 earlyUnlockPenaltyRatio) public view returns (uint256 _amount){

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
     * @dev This function is called for plain Ether transfers, i.e. for every call with empty calldata.
     */
    receive() external payable {}

    /**
     * @dev Fallback function is executed if none of the other functions match the function
     * identifier or no data was provided with the function call.
     */
    fallback() external payable {}
    
}
