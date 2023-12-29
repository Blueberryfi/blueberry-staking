// SPDX-License-Identifier: BUSL-1.1    
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/
pragma solidity 0.8.22;

import './IBlueberryToken.sol';

interface IBlueberryStaking {

    /*//////////////////////////////////////////////////
                         ERRORS
    //////////////////////////////////////////////////*/

    error NotOwner();

    error AddressZero();

    error InvalidStartTime();

    error InvalidBalance();

    error InvalidDuration();

    error NothingToAccelerate();

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

    error InvalidBToken();

    error InvalidLength();

    error InvalidRewardRate();

    error InvalidRewardDuration();

    error InvalidPenaltyRatio();

    error InvalidObservationTime();

    error BTokenAlreadyExists();

    error AlreadyClaimed();

    error NothingToUpdate();

    error VestingIncomplete();

    error LockdropIncomplete();

    error BTokenDoesNotExist();

    /*//////////////////////////////////////////////////
                         EVENTS
    //////////////////////////////////////////////////*/

    event Staked(address indexed user, address[] bTokens, uint256[] amounts, uint256 timestamp);

    event Unstaked(address indexed user, address[] bTokens, uint256[] amounts, uint256 timestamp);

    event Claimed(address indexed user, uint256 amount, uint256 timestamp);

    event BTokensAdded(address[] indexed bTokens, uint256 timestamp);

    event BTokensRemoved(address[] indexed bTokens, uint256 timestamp);

    event RewardAmountNotified(address[] indexed bTokens, uint256[] amounts, uint256 timestamp);

    event Accelerated(address indexed user, uint256 tokensClaimed, uint256 redistributedBLB);

    event VestingCompleted(address indexed user, uint256 amount, uint256 timestamp);

    event EpochLengthUpdated(uint256 epochLength, uint256 timestamp);

    event BasePenaltyRatioChanged(uint256 basePenaltyRatio, uint256 timestamp);

    event RewardDurationUpdated(uint256 rewardDuration, uint256 timestamp);

    event TreasuryUpdated(address treasury, uint256 timestamp);

    event UsdcAddressUpdated(address usdc, uint256 decimals, uint256 timestamp);

    event VestLengthUpdated(uint256 vestLength, uint256 timestamp);

    event BLBUpdated(address blb, uint256 timestamp);

    /*//////////////////////////////////////////////////
                         FUNCTIONS
    //////////////////////////////////////////////////*/

    /**
    * @notice stakes a given amount of each token
    * @dev The amount of tokens must be approved by the user before calling this function
    * @param _bTokens An array of the tokens to stake
    * @param _amounts An array of the amounts of each token to stake
    */
    function stake(address[] calldata _bTokens, uint256[] calldata _amounts) external;

    /**
    * @notice unstakes a given amount of each token
    * @dev does not claim rewards
    * @param _bTokens An array of the tokens to unstake
    * @param _amounts An array of the amounts of each token to unstake
    */
    function unstake(address[] calldata _bTokens, uint256[] calldata _amounts) external;

    /**
    * @notice starts the vesting process for a given array of tokens
    * @param _bTokens An array of the tokens to start vesting for the caller
    */
    function startVesting(address[] calldata _bTokens) external;

    /**
    * @notice Claims the tokens that have completed their vesting schedule for the caller.
    * @param _vestIndexes The indexes of the vesting schedule to claim.
    */
    function completeVesting(uint256[] calldata _vestIndexes) external;

    /**
     * @notice Accelerates the vesting of the calling user, unlocking tokens by paying the acceleration fee for the given vesting schedule.
     * @dev User must have have given this contract allowance to transfer the acceleration fee.
     * Penalty ratio linearly decreases over the course of the vesting period.
     * @param _vestIndexes The indexes of the vests of the user to accelerate.
     * 1 +        
     *   | .      
     *   |    .   
     *   |       .
     *   |          .
     * 0 +------+-----> 1 year
     */
    function accelerateVesting(uint256[] calldata _vestIndexes) external;

    /*//////////////////////////////////////////////////
                       VIEW FUNCTIONS
    //////////////////////////////////////////////////*/

    /**
     * @notice gets the TWAP price for BLB in USDC
     * @param _secondsInPast The amount of seconds in the past to get the TWAP for
     * @return The TWAP price
     */
    function fetchTWAP(uint32 _secondsInPast) external view returns (uint256);

    /**
     * @notice gets the current price for BLB in USDC
     * @return _price The current price using 6 decimal points
     */
    function getPrice() external view returns (uint256 _price);

    /**
    * @notice ensures the user can only claim rewards once per epoch
    * @param _user the user to check
    * @return returns true if the user can claim, false otherwise
    */
    function canClaim(address _user) external view returns (bool);

    /**
    * @return returns true if the vesting schedule is complete for the given user and vesting index
    */
    function isVestingComplete(address _user, uint256 _vestIndex) external view returns (bool);

    /**
    * @return returns the total amount of rewards for the given bToken
    */
    function rewardPerToken(address _bToken) external view returns (uint256);

    /**
    * @return earnedAmount the amount of rewards the given user has earned for the given bToken
    */
    function earned(address _account, address _bToken) external view returns (uint256 earnedAmount);

    /**
    * @return the timestamp of the last time rewards were updated
    */
    function lastTimeRewardApplicable() external view returns (uint256);

     /**
     * @dev Gets the current unlock penalty ratio, which linearly decreases from 70% to 0% over the vesting period.
     * This is done by calculating the ratio of the time that has passed since the start of the vesting period to the total vesting period.
     * @param _user The user's address.
     * @param _vestingScheduleIndex The index of the vesting schedule.
     * @return penaltyRatio The current unlock penalty ratio in wei.
     */
    function getEarlyUnlockPenaltyRatio(address _user, uint256 _vestingScheduleIndex) external view returns (uint256 penaltyRatio);

     /**
     * @dev Gets the current acceleration fee ratio, which linearly decreases over the vesting period.
     * This is done by getting the early unlock penalty ratio, multiplying it by the overall underlying $blb price of the vest
     * @param _user The user's address.
     * @param _vestingScheduleIndex The index of the vesting schedule.
     * @return accelerationFee The current acceleration fee ratio.
     */
    function getAccelerationFeeUSDC(address _user, uint256 _vestingScheduleIndex) external view returns (uint256 accelerationFee);

    /**
     * @notice Called by the owner to change the reward rate for a given token(s)
     * @dev uses address(0) in updateRewards as to not change the reward rate for any user but still update each mappings
     * @dev the caller should consider the reward rate for each token before calling this function and total rewards should be less than the total amount of tokens
     * @param _bTokens An array of the tokens to change the reward amounts for
     * @param _amounts An array of the amounts to change the reward amounts to- e.g 1e18 = 1 token per rewardDuration
    */
    function notifyRewardAmount(address[] calldata _bTokens, uint256[] calldata _amounts) external;

    /**
    * @notice Changes the reward duration in seconds
    * @dev This will not change the reward rate for any tokens
    * @param _rewardDuration The new reward duration in seconds
    */
    function setRewardDuration(uint256 _rewardDuration) external;

    /**
    * @notice Changes the vest length in seconds
    * @dev Will effect all users who are vesting
    * @param _vestLength The new vest length in seconds
    */
    function setVestLength(uint256 _vestLength) external;

    /**
    * @notice Changes the base penalty ratio in proportion to 1e18
    * @dev Will effect all users who are vesting
    * @param _ratio The new base penalty ratio in wei
    */
    function setbasePenaltyRatioPercent(uint256 _ratio) external;

    /**
    * @notice Changes the address of the treasury
    * @param _treasury The new treasury address
    */
    function changeTreasuryAddress(address _treasury) external;

    /**
    * @notice Removes the given tokens from the list of bTokens
    * @param _bTokens An array of the tokens to remove
    */
    function removeBTokens(address[] calldata _bTokens) external;

    /**
    * @notice Adds the given tokens to the list of bTokens
    * @param _bTokens An array of the tokens to add
    */
    function addBTokens(address[] calldata _bTokens) external;

    /**
    * @notice Change the epoch length in seconds
    */
    function changeEpochLength(uint256 _epochLength) external;

    /**
    * @notice Change the blb token address (in case of migration)
    */
    function changeBLB(address _blb) external;

    /**
    * @notice Changes the information for the uniswap pool to fetch the price of BLB
    * @param _uniswapPool The new address of the uniswap pool
    * @param _uniswapFactory The new address of the uniswap factory
    * @param _observationPeriod The new observation period for the uniswap pool
    */
    function changeUniswapInformation(address _uniswapPool, address _uniswapFactory, uint32 _observationPeriod) external;

    /**
    * @notice Pauses the contract
    */
    function pause() external;

    /**
    * @notice Unpauses the contract
    */
    function unpause() external;
}