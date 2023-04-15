// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

error NotOwner();
error AddressZero();
error InvalidStartTime();
error InvalidBalance();
error InvalidDuration();
error InvalidEpoch();
error LockDropStillOngoing();

contract Vesting is Ownable {

    event Distributed(address indexed user, uint256 amount, uint256 epoch);

    event Accelerated(address indexed user, uint256 unlockedAmount, uint256 accelerationFee, uint256 redistributedAmount);

    /// @notice The `BLB` token contract.
    IERC20 public constant BLB = IERC20(0x904f36d74bED2Ef2729Eaa1c7A5B70dEA2966a02);

    /// @notice USDC token contract.
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

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

    /// @notice The duration of each epoch (14 days in this case).
    uint16 public epochDuration = 14 days;

    /// @notice The duration of the vesting period (365 days in this case).
    uint256 public vestingDuration = 365 days;

    /// @notice The duration of the lockdrop (60 days in this case).
    uint256 public lockDropDuration = 60 days;

    struct VestingSchedule {
        uint256 claimableBalance;
        uint64 userEpoch;
        uint64 userAccelerationTimestamp;
        uint64 lastClaimedEpoch;
    }

    struct Epoch {
        uint256 fdv;
        uint256 tokenPrice;
    }

    mapping(address => VestingSchedule) internal _vestingSchedules;

    Epoch[] public epochs = [
        Epoch(20000000, 2 * 10 ** 16),
        Epoch(25000000, 25 * 10 ** 15),
        Epoch(30000000, 3 * 10 ** 16),
        Epoch(40000000, 4 * 10 ** 16),
        Epoch(50000000, 5 * 10 ** 16)
    ];

    /// @param _blb The address of the $BLB token.
    /// @param _startTime The start time of the token distribution.
    /// @param _treasury The address of the treasury.
    constructor(address _blb, uint16 _startTime, address _treasury) Ownable {
        require(_blb != address(0), AddressZero());
        require(_treasury != address(0), AddressZero());
        require(_startTime > block.timestamp, InvalidStartTime());

        blb = IERC20(_blb);
        startTime = _startTime;
        treasury = _treasury;
    }

    /// @notice Emits a Distributed event for the specified user, amount, and epoch.
    /// @param _user The address of the user receiving the distribution.
    /// @param _amount The amount of tokens being distributed.
    /// @param _epoch The epoch of the distribution.
    function distribute(address _user, uint256 _amount, uint256 _epoch) external {
        require(block.timestamp >= startTime + lockDropDuration, LockDropStillOngoing());

        VestingSchedule storage v = _vestingSchedules[_user];
        require(v.amount > 0, "Not a participant");
        require(block.timestamp >= v.unlockTime, "Tokens still locked");
        
        emit Distributed(_user, _amount, _epoch);
    }

    /// @notice Accelerates the vesting of the calling user, unlocking tokens by paying current acceleration fee.
    function accelerateVesting() external {
        // pay acceleration fee
        

        // Redistribute the remaining tokens to other users (implementation needed)

        emit Accelerated(msg.sender, unlockedAmount, accelerationFee, redistributedAmount);
}


    /// @notice Claims the $BLB tokens for the calling user.
    function claim() external {
        uint256 _currentEpoch = getCurrentEpoch();
        uint256 _claimableBalance = _claimable(msg.sender, _currentEpoch);
        require(_claimableBalance > 0, InvalidBalance());

        // Update the user's claimable balance
        VestingSchedule storage v = _vestingSchedules[msg.sender];
        v.claimableBalance = 0;
        v.lastClaimedEpoch = _currentEpoch;

        // Transfer the $BLB tokens to the user
        BLB.transfer(msg.sender, _claimableBalance);
    }


    function _claimable(address _address, uint256 _currentEpoch) internal view returns (uint256 _balance) {
        VestingSchedule storage v = _vestingSchedules[msg.sender];

        require(_currentEpoch > v.lastClaimedEpoch, InvalidEpoch());

        if v.userEpoch == _currentEpoch) {
            return v.claimableBalance;
        } else if (v.userEpoch < _currentEpoch) {
            uint256 currentEpochBalance = v.claimableBalance * currentEpochDuration / currentEpochVestingDuration;
            uint256 currentEpochLockDropBalance = v.claimableBalance * currentEpochDuration / currentEpochLockDropDuration;
            return currentEpochBalance + currentEpochLockDropBalance;
        } else {
            return 0;
        }
    }

    function getCurrentEpoch() public view returns (Epoch _epoch) {
        require(block.timestamp >= startTime, InvalidStartTime());
        uint256 currentEpoch = (block.timestamp - startTime) / epochDuration;
        return epochs[currentEpoch];
    }

    function getBaseAccelerationFee() public view returns (uint256 _amount){
        uint256 _currentFDV = getCurrentFDV();
        uint256 _baseAccelerationFee = _currentFDV * accelerationRatioWithdrawable / accelerationRatioPrecision;
        return _baseAccelerationFee;
    }

    /// @notice Calculates the acceleration fee based on the initial BLB price and early unlock penalty ratio.
    /// @return _amount The calculated acceleration fee.
    function getCurrentAccelerationFee() public view returns (uint256 _amount){
        uint256 _baseAccelerationFee = getBaseAccelerationFee();

    }

    function calculateRedistributionAmount(uint256 bdBLBBalance, uint256 earlyUnlockPenaltyRatio) public view returns (uint256 _amount){

    }

    function changeAccelerationRatio(uint256 _newAccelerationRatio) onlyOwner external {
        accelerationRatio = _newAccelerationRatio;
    }

    function changeTreasury(address _newTreasury) onlyOwner external {
        treasury = _newTreasury;
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
