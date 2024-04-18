// SPDX-License-Identifier: BUSL-1.1
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/
pragma solidity ^0.8.0;

import {IBlueberryToken} from "./IBlueberryToken.sol";

interface IBlueberryStaking {
    /*//////////////////////////////////////////////////
                         ERRORS
    //////////////////////////////////////////////////*/

    /// @notice Emitted if a zero address is used.
    error AddressZero();

    /// @notice Emitted if a token is not an ibToken.
    error InvalidIbToken();

    /// @notice Emitted if the length of arrays do not pass the requirements.
    error InvalidLength();

    /// @notice Emitted if the calculated RewardRate is 0.
    error InvalidRewardRate();

    /// @notice Emitted if the reward duration is 0.
    error InvalidRewardDuration();

    /// @notice Emitted if the base penalty ratio is greater than 50%.
    error InvalidPenaltyRatio();

    /// @notice Emitted if the observation time on the uniswap pool is greater than 432,000 seconds.
    error InvalidObservationTime();

    /// @notice Emitted if the stable asset is not in the uniswap pool.
    error InvalidStableAsset();

    /// @notice Emitted if a bToken being added already exists.
    error IBTokenAlreadyExists();

    /// @notice Emitted if the user has no vesting schedules and is trying to accelerate or update one.
    error NothingToUpdate();

    /// @notice Emitted if the user is trying to complete a vest that has finished vesting.
    error VestingIncomplete();

    /// @notice Emitted if the user is trying to accelerate a vest before the 30 day lockdrop is complete.
    error LockdropIncomplete();

    /*//////////////////////////////////////////////////
                         EVENTS
    //////////////////////////////////////////////////*/

    /// @notice Emitted when a user stakes their ibTokens.
    event Staked(address indexed user, address ibToken, uint256 amount);

    /// @notice Emitted when a user unstakes their ibTokens.
    event Unstaked(address indexed user, address ibToken, uint256 amount);

    /// @notice Emitted when a user starts vesting their rewards on their ibTokens.
    event VestStarted(address indexed user, uint256 amount);

    /// @notice Emitted when the admin adds an ibToken that is eligible for rewards.
    event IbTokenAdded(address indexed ibToken, uint256 amount);

    /// @notice Emitted when the admin updates the amount of rewards available for a reward period for a given ibToken.
    event RewardAmountModified(address indexed ibToken, uint256 amount);

    /// @notice Emitted when a user accelerates their vesting schedule.
    event VestingAccelerated(
        address indexed user,
        uint256 tokensClaimed,
        uint256 redistributedBLB
    );

    /// @notice Emitted when a user completes their vesting schedule.
    event VestingCompleted(address indexed user, uint256 amount);

    /// @notice Emitted when the admin updates the BasePenaltyRatio.
    event BasePenaltyRatioUpdated(uint256 basePenaltyRatio);

    /// @notice Emitted when the admin updates the global reward duration.
    event RewardDurationUpdated(uint256 rewardDuration);

    /// @notice Emitted when the admin updates the treasury address.
    event TreasuryUpdated(address treasury);

    /// @notice Emitted when the admin updates the uniswap pool.
    event UniswapV3PoolUpdated(
        address _uniswapPool,
        address _stableAsset,
        uint8 decimals,
        uint256 _observationPeriod
    );

    /// @notice Emitted when the treasury collects fees from the acceleration of vesting schedules.
    event FeeCollected(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////
                         STRUCTS
    //////////////////////////////////////////////////*/

    /**
     * @dev Struct to store info related to a vesting schedule
     * @param amount The amount of tokens vested
     * @param extra The extra amount of tokens to be redistributed to this vesting schedule
     * @param startTime The start time of the vesting schedule
     * @param priceUnderlying The underlying token Price
     */
    struct Vest {
        uint256 amount;
        uint256 extra;
        uint256 startTime;
        uint256 priceUnderlying;
    }

    /**
     * @notice Struct to store data related to the Uniswap V3 pool
     * @dev This is used to fetch the price of BLB in the stable asset
     * @param pool The address of the Uniswap V3 pool
     * @param observationPeriod The observation period for the Uniswap V3 pool
     * @param blbIsToken0 True if BLB is token0 in the pool, false if BLB is token1
     */
    struct UniswapV3PoolInfo {
        address pool;
        uint32 observationPeriod;
        bool blbIsToken0;
    }

    /*//////////////////////////////////////////////////
                         FUNCTIONS
    //////////////////////////////////////////////////*/

    /**
     * @notice stakes a given amount of each token
     * @dev The amount of tokens must be approved by the user before calling this function
     * @param _ibTokens An array of the tokens to stake
     * @param _amounts An array of the amounts of each token to stake
     */
    function stake(
        address[] calldata _ibTokens,
        uint256[] calldata _amounts
    ) external;

    /**
     * @notice unstakes a given amount of each token
     * @dev does not claim rewards
     * @param _ibTokens An array of the tokens to unstake
     * @param _amounts An array of the amounts of each token to unstake
     */
    function unstake(
        address[] calldata _ibTokens,
        uint256[] calldata _amounts
    ) external;

    /**
     * @notice starts the vesting process for a given array of tokens
     * @param _ibTokens An array of the tokens to start vesting for the caller
     */
    function startVesting(address[] calldata _ibTokens) external;

    /**
     * @notice Claims the tokens that have completed their vesting schedule for the caller.
     * @param _vestIndexes The indexes of the vesting schedule to claim.
     */
    function completeVesting(uint256[] calldata _vestIndexes) external;

    /**
     * @notice Accelerates the vesting of the calling user, unlocking tokens by paying the acceleration fee for the
     * given vesting schedule.
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
     * @notice gets the current price for BLB in StableAsset
     * @dev Uses the Uniswap V3 TWAP pricing method after the 30 day lockdrop period in complete
     * @return _price The current price scaled to an 18 decimal fixed point number
     */
    function getPrice() external view returns (uint256 _price);

    /**
     * @return returns true if the vesting schedule is complete for the given user and vesting index
     */
    function isVestingComplete(
        address _user,
        uint256 _vestIndex
    ) external view returns (bool);

    /**
     * @return returns the total amount of rewards for the given ibToken
     */
    function rewardPerToken(address _ibToken) external view returns (uint256);

    /**
     * @return earnedAmount the amount of rewards the given user has earned for the given ibToken
     */
    function earned(
        address _account,
        address _ibToken
    ) external view returns (uint256 earnedAmount);

    /**
     * @return the timestamp of the last time rewards were updated
     */
    function lastTimeRewardApplicable(
        address ibToken
    ) external view returns (uint256);

    /**
     * @dev Gets the current unlock penalty ratio, which linearly decreases from 70% to 0% over the vesting period.
     * This is done by calculating the ratio of the time that has passed since the start of the vesting period to the
     * total vesting period.
     * @param _user The user's address.
     * @param _vestingScheduleIndex The index of the vesting schedule.
     * @return penaltyRatio The current unlock penalty ratio in wei.
     */
    function getEarlyUnlockPenaltyRatio(
        address _user,
        uint256 _vestingScheduleIndex
    ) external view returns (uint256 penaltyRatio);

    /**
     * @dev Gets the current acceleration fee ratio, which linearly decreases over the vesting period.
     * This is done by getting the early unlock penalty ratio, multiplying it by the overall underlying $blb price of
     * the vest
     * @param _user The user's address.
     * @param _vestingScheduleIndex The index of the vesting schedule.
     * @return accelerationFee The current acceleration fee ratio.
     */
    function getAccelerationFeeStableAsset(
        address _user,
        uint256 _vestingScheduleIndex
    ) external view returns (uint256 accelerationFee);

    /**
     * @notice Fetches the total accumulated rewards for a given user
     * @param _user The user's address to check for accumulated bdBLB rewards
     * @return The total accumulated rewards for the user in terms of bdBLB (18 decimals)
     */
    function getAccumulatedRewards(address _user) external returns (uint256);
}
