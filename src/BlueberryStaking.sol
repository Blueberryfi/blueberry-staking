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

import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import "v3-core/libraries/TickMath.sol";
import "v3-core/libraries/FullMath.sol";
import "v3-core/libraries/FixedPoint96.sol";

import {IBlueberryToken, IERC20} from "./interfaces/IBlueberryToken.sol";
import {IBlueberryStaking} from "./interfaces/IBlueberryStaking.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/**
 * @title Blueberry's staking contract with vesting for bdblb distribution
 * @author Blueberry Protocol
 */
contract BlueberryStaking is
    IBlueberryStaking,
    Ownable2StepUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////
                        VARIABLES
    //////////////////////////////////////////////////*/

    /// @notice The Blueberry token contract
    IBlueberryToken public blb;

    /// @notice The  token contract
    /// @notice The stableAsset token contract
    IERC20 public stableAsset;

    /// @notice The treasury address
    address public treasury;

    /// @notice The Uniswap V3 pool data
    UniswapV3PoolInfo private uniswapV3Info;

    /// @notice The total number of iBtokens
    uint256 public totalIbTokens;

    /// @notice The total supply of tokens for each address
    mapping(address => uint256) public totalSupply;

    /// @notice The stored reward per token for each address
    mapping(address => uint256) public rewardPerTokenStored;

    /// @notice The last update time for each address
    mapping(address => uint256) public lastUpdateTime;

    /// @notice The reward rate for each address
    mapping(address => uint256) public rewardRate;

    /// @notice The ibtoken status for each address
    mapping(address => bool) public isIbToken;

    /// @notice A mapping of the ibToken's end time, in seconds, for the current reward period
    mapping(address => uint256) public finishAt;

    /// @notice The vesting schedule for each address
    mapping(address => Vest[]) public vesting;

    /// @notice The balance of tokens for each address
    mapping(address => mapping(address => uint256)) public balanceOf;

    /// @notice The rewards for each address
    mapping(address => mapping(address => uint256)) public rewards;

    /// @notice The paid reward per token for each user
    mapping(address => mapping(address => uint256))
        public userRewardPerTokenPaid;

    /// @notice The reward duration
    uint256 public rewardDuration;

    /// @notice The deployment time of the contract
    uint256 public deployedAt;

    // 25% at the start of each vesting period
    uint256 public basePenaltyRatioPercent;

    // Number of decimals for the stable asset
    uint256 private stableDecimals;

    // Sum of all user vesting positions
    uint256 private totalVestAmount;

    // Amount of BLB marked for redistribution after vest acceleration
    uint256 private redistributedBLB;

    /// @notice A list of all the ibTokens
    address[] public ibTokens;

    /// @notice Duration of the lockdrop period
    uint256 public constant LOCKDROP_DURATION = 30 days;

    /// @notice The vesting length for users
    uint256 public constant VESTING_LENGTH = 52 weeks;

    /// @notice The price of BLB during the 1st period of the lockdrop
    uint256 private constant PERIOD_ONE_BLB_PRICE = 0.02e18;

    /// @notice The price of BLB during the 1st period of the lockdrop
    uint256 private constant PERIOD_TWO_BLB_PRICE = 0.04e18;

    /*//////////////////////////////////////////////////
                        CONSTRUCTOR
    //////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////
                     FUNCTIONS
    //////////////////////////////////////////////////*/

    /**
     * @notice The constructor function, called when the contract is deployed
     * @param _blb The token that will be used as rewards
     * @param _stableAsset The stableAsset address
     * @param _treasury The treasury address
     * @param _rewardDuration The duration of the reward period
     * @param _ibTokens An array of the bTokens that can be staked
     */
    function initialize(
        address _blb,
        address _stableAsset,
        address _treasury,
        uint256 _rewardDuration,
        uint256 _initialBasePenaltyRatioPercent,
        address[] memory _ibTokens,
        address _admin
    ) public initializer {
        __Ownable2Step_init();
        __Pausable_init();
        _transferOwnership(_admin);

        if (
            _blb == address(0) || _stableAsset == address(0) || _treasury == address(0)
        ) {
            revert AddressZero();
        }

        if (_rewardDuration == 0) {
            revert InvalidRewardDuration();
        }

        blb = IBlueberryToken(_blb);
        stableAsset = IERC20(_stableAsset);
        stableDecimals = IERC20Metadata(address(stableAsset)).decimals();
        treasury = _treasury;

        for (uint256 i; i < _ibTokens.length; ++i) {
            if (_ibTokens[i] == address(0)) {
                revert AddressZero();
            }
            isIbToken[_ibTokens[i]] = true;
        }
        
        ibTokens = _ibTokens;
        totalIbTokens = _ibTokens.length;

        rewardDuration = _rewardDuration;
        basePenaltyRatioPercent = _initialBasePenaltyRatioPercent;
        deployedAt = block.timestamp;
    }

    /**
     * @notice updates the rewards for a given user and a given array of tokens
     * @param _user The user to update the rewards for
     * @param _ibTokens An array of tokens to update the rewards for
     */
    modifier updateRewards(address _user, address[] calldata _ibTokens) {
        for (uint256 i; i < _ibTokens.length; ++i) {
            address _ibToken = _ibTokens[i];

            _updateReward(_user, _ibToken);
        }
        _;
    }

    /// Contains the logic for updateReward function
    function _updateReward(address _user, address _ibToken) internal {
        if (!isIbToken[_ibToken]) {
            revert InvalidIbToken();
        }

        rewardPerTokenStored[_ibToken] = rewardPerToken(_ibToken);
        lastUpdateTime[_ibToken] = lastTimeRewardApplicable(_ibToken);

        if (_user != address(0)) {
            rewards[_user][_ibToken] = _earned(_user, _ibToken);
            userRewardPerTokenPaid[_user][_ibToken] = rewardPerTokenStored[
                _ibToken
            ];
        }
    }

    /// @inheritdoc IBlueberryStaking
    function stake(
        address[] calldata _ibTokens,
        uint256[] calldata _amounts
    ) external whenNotPaused updateRewards(msg.sender, _ibTokens) {
        _validateTokenAmountsArray(_ibTokens, _amounts);

        for (uint256 i; i < _ibTokens.length; ++i) {
            address _ibToken = _ibTokens[i];

            if (!isIbToken[_ibToken]) {
                revert InvalidIbToken();
            }

            uint256 _amount = _amounts[i];

            balanceOf[msg.sender][_ibToken] += _amount;
            totalSupply[_ibToken] += _amount;

            IERC20(_ibToken).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );

            emit Staked(msg.sender, _ibToken, _amount);
        }
    }

    /// @inheritdoc IBlueberryStaking
    function unstake(
        address[] calldata _ibTokens,
        uint256[] calldata _amounts
    ) external updateRewards(msg.sender, _ibTokens) {
        _validateTokenAmountsArray(_ibTokens, _amounts);

        for (uint256 i; i < _ibTokens.length; ++i) {
            address _ibToken = _ibTokens[i];

            if (!isIbToken[address(_ibToken)]) {
                revert InvalidIbToken();
            }

            uint256 _amount = _amounts[i];

            balanceOf[msg.sender][address(_ibToken)] -= _amount;
            totalSupply[address(_ibToken)] -= _amount;

            IERC20(_ibToken).safeTransfer(msg.sender, _amount);

            emit Unstaked(msg.sender, _ibToken, _amount);
        }
    }

    /*//////////////////////////////////////////////////
                     VESTING FUNCTIONS
    //////////////////////////////////////////////////*/

    modifier updateVests(address _user, uint256[] calldata _vestIndexes) {
        if (vesting[msg.sender].length < _vestIndexes.length) {
            revert InvalidLength();
        }

        Vest[] storage vests = vesting[msg.sender];

        for (uint256 i; i < _vestIndexes.length; ++i) {
            Vest storage vest = vests[_vestIndexes[i]];

            if (vest.amount == 0) {
                revert NothingToUpdate();
            }

            if (redistributedBLB > 0) {
                vest.extra = (vest.amount * redistributedBLB) / totalVestAmount;
            }
        }

        _;
    }

    /// @inheritdoc IBlueberryStaking
    function startVesting(
        address[] calldata _ibTokens
    ) external whenNotPaused updateRewards(msg.sender, _ibTokens) {
        uint256 totalRewards;
        for (uint256 i; i < _ibTokens.length; ++i) {
            if (!isIbToken[address(_ibTokens[i])]) {
                revert InvalidIbToken();
            }

            IERC20 _ibToken = IERC20(_ibTokens[i]);
            uint256 reward = rewards[msg.sender][address(_ibToken)];

            if (reward > 0) {
                totalRewards += reward;
                rewards[msg.sender][address(_ibToken)] = 0;

                uint256 _priceUnderlying = getPrice();

                vesting[msg.sender].push(
                    Vest(reward, 0, block.timestamp, _priceUnderlying)
                );
            }
        }

        totalVestAmount += totalRewards;

        emit VestStarted(msg.sender, totalRewards);
    }

    /// @inheritdoc IBlueberryStaking
    function completeVesting(
        uint256[] calldata _vestIndexes
    ) external whenNotPaused updateVests(msg.sender, _vestIndexes) {
        Vest[] storage vests = vesting[msg.sender];
        if (vesting[msg.sender].length < _vestIndexes.length) {
            revert InvalidLength();
        }

        uint256 totalbdblb;
        for (uint256 i; i < _vestIndexes.length; ++i) {
            Vest storage v = vests[_vestIndexes[i]];

            if (!isVestingComplete(msg.sender, _vestIndexes[i])) {
                revert VestingIncomplete();
            }

            totalbdblb += v.amount + v.extra;

            // Ensure accurate redistribution accounting for accelerations.
            totalVestAmount -= v.amount;
            redistributedBLB -= v.extra;

            delete vests[_vestIndexes[i]];
        }

        if (totalbdblb > 0) {
            blb.transfer(msg.sender, totalbdblb);
        }

        emit VestingCompleted(msg.sender, totalbdblb);
    }

    /// @inheritdoc IBlueberryStaking
    function accelerateVesting(
        uint256[] calldata _vestIndexes
    ) external whenNotPaused updateVests(msg.sender, _vestIndexes) {
        // index must exist
        if (vesting[msg.sender].length < _vestIndexes.length) {
            revert InvalidLength();
        }

        // lockdrop period must be complete i.e 1 month
        if (block.timestamp <= deployedAt + LOCKDROP_DURATION) {
            revert LockdropIncomplete();
        }

        Vest[] storage vests = vesting[msg.sender];

        uint256 totalbdblb;
        uint256 totalRedistributedAmount;
        uint256 totalAccelerationFee;
        for (uint256 i; i < _vestIndexes.length; ++i) {
            uint256 _vestIndex = _vestIndexes[i];
            Vest storage _vest = vests[_vestIndex];
            uint256 _vestTotal = _vest.amount + _vest.extra;

            if (_vestTotal <= 0) {
                revert NothingToUpdate();
            }

            uint256 _earlyUnlockPenaltyRatio = getEarlyUnlockPenaltyRatio(
                msg.sender,
                _vestIndex
            );

            if (_earlyUnlockPenaltyRatio == 0) {
                revert("Vest complete, nothing to accelerate");
            }

            // calculate acceleration fee and log it to ensure eth value is sent
            uint256 _accelerationFee = getAccelerationFeeStableAsset(
                msg.sender,
                _vestIndex
            );
            totalAccelerationFee += _accelerationFee;

            // calculate the amount of the vest that will be redistributed
            uint256 _redistributionAmount = (_vestTotal *
                _earlyUnlockPenaltyRatio) / 1e18;

            // redistribute the penalty to other users
            redistributedBLB += _redistributionAmount;

            // log it for the event
            totalRedistributedAmount += _redistributionAmount;

            // remove it from the recieved vest
            _vestTotal -= _redistributionAmount;

            // the remainder is withdrawable by the user
            totalbdblb += _vestTotal;

            // Ensure accurate redistribution accounting after this withdrawal.
            totalVestAmount -= _vest.amount;
            redistributedBLB -= _vest.extra;

            // delete the vest
            delete vests[_vestIndex];
        }

        if (totalAccelerationFee > 0) {
            // transfer the acceleration fee to the treasury
            stableAsset.safeTransferFrom(
                msg.sender,
                treasury,
                totalAccelerationFee
            );

            emit FeeCollected(msg.sender, totalAccelerationFee);
        }

        if (totalbdblb > 0) {
            blb.transfer(msg.sender, totalbdblb);
        }

        emit VestingAccelerated(msg.sender, totalbdblb, totalRedistributedAmount);
    }

    /*//////////////////////////////////////////////////
                       VIEW FUNCTIONS
    //////////////////////////////////////////////////*/

    /**
     * @notice Fetches the TWAP price of BLB in terms of the stable asset
     * @dev A default value of $0.04 is returned if the Uniswap V3 pool is not set
     * @return The price of BLB in terms of the stable asset
     */
    function _fetchTWAP() internal view returns (uint256) {
        UniswapV3PoolInfo memory _uniswapV3Info = uniswapV3Info;
        IUniswapV3Pool _pool = IUniswapV3Pool(_uniswapV3Info.pool);
        uint32 _observationPeriod = _uniswapV3Info.observationPeriod;

        if (address(_pool) == address(0) || _observationPeriod == 0) {
            return PERIOD_TWO_BLB_PRICE;
        }

        uint32[] memory _secondsArray = new uint32[](2);

        _secondsArray[0] = _observationPeriod;
        _secondsArray[1] = 0;

        (int56[] memory tickCumulatives, ) = _pool.observe(_secondsArray);

        int56 _tickDifference = tickCumulatives[1] - tickCumulatives[0];
        int56 _timeDifference = int32(_observationPeriod);

        int24 _twapTick = int24(_tickDifference / _timeDifference);

        uint160 _sqrtPriceX96 = TickMath.getSqrtRatioAtTick(_twapTick);

        // Decode the square root price
        uint256 _priceX96 = FullMath.mulDiv(
            _sqrtPriceX96,
            _sqrtPriceX96,
            FixedPoint96.Q96
        );

        uint256 _decimalsBLB = 18;
        uint256 _decimalsStable = stableDecimals;

        // Adjust for decimals
        if (_decimalsBLB > _decimalsStable) {
            _priceX96 /= 10 ** (_decimalsBLB - _decimalsStable);
        } else if (_decimalsStable > _decimalsBLB) {
            _priceX96 *= 10 ** (_decimalsStable - _decimalsBLB);
        }

        // Now priceX96 is the price of blb in terms of stableAsset, multiplied by 2^96.
        // To convert this to a human-readable format, you can divide by 2^96:

        uint256 _price = _priceX96 / 2 ** 96;

        // Now 'price' is the price of blb in terms of stableAsset, in the correct decimal places.
        return _price;
    }

    /// @inheritdoc IBlueberryStaking
    function getPrice() public view returns (uint256 _price) {
        // during the lockdrop period the underlying blb token price is locked
        uint256 _period = (block.timestamp - deployedAt) / (LOCKDROP_DURATION / 2);
        // period 1: $0.02 / blb
        if (_period < 1) {
            _price = PERIOD_ONE_BLB_PRICE;
        }
        // period 2: $0.04 / blb
        else if (_period < 2) {
            _price = PERIOD_TWO_BLB_PRICE;
        }
        // period 3+
        else {
            // gets the price of BLB in USD averaged over the last hour
            _price = _fetchTWAP();
        }
    }

    /// @inheritdoc IBlueberryStaking
    function isVestingComplete(
        address _user,
        uint256 _vestIndex
    ) public view returns (bool) {
        return
            vesting[_user][_vestIndex].startTime + VESTING_LENGTH <=
            block.timestamp;
    }

    /// @inheritdoc IBlueberryStaking
    function rewardPerToken(address _ibToken) public view returns (uint256) {
        if (totalSupply[_ibToken] == 0) {
            return rewardPerTokenStored[_ibToken];
        }

        return
            rewardPerTokenStored[_ibToken] +
            ((rewardRate[_ibToken] *
                (lastTimeRewardApplicable(_ibToken) - lastUpdateTime[_ibToken]) *
                1e18) / totalSupply[_ibToken]);
    }

    /// @inheritdoc IBlueberryStaking
    function earned(
        address _account,
        address _ibToken
    ) public view returns (uint256 earnedAmount) {
        return _earned(_account, _ibToken);
    }

    function _earned(
        address _account,
        address _ibToken
    ) internal view returns (uint256 earnedAmount) {
        uint256 _balance = balanceOf[_account][_ibToken];
        uint256 _rewardPerToken = rewardPerToken(_ibToken);
        uint256 _rewardPaid = userRewardPerTokenPaid[_account][_ibToken];
        earnedAmount =
            (_balance * (_rewardPerToken - _rewardPaid)) /
            1e18 +
            rewards[_account][_ibToken];
    }

    /// @inheritdoc IBlueberryStaking
    function lastTimeRewardApplicable(address ibToken) public view returns (uint256) {
        if (block.timestamp > finishAt[ibToken]) {
            return finishAt[ibToken];
        } else {
            return block.timestamp;
        }
    }

    /**
     * @return the total amount of vesting tokens (bdblb)
     */
    function bdblbBalance(address _user) public view returns (uint256) {
        uint256 _balance;
        for (uint256 i; i < vesting[_user].length; ++i) {
            _balance += vesting[_user][i].amount + vesting[_user][i].extra;
        }
        return _balance;
    }

    /// @inheritdoc IBlueberryStaking
    function getEarlyUnlockPenaltyRatio(
        address _user,
        uint256 _vestingScheduleIndex
    ) public view returns (uint256 penaltyRatio) {
        uint256 _vestStartTime = vesting[_user][_vestingScheduleIndex]
            .startTime;
        uint256 _vestTimeElapsed = block.timestamp - _vestStartTime;

        // Calculate the early unlock penalty ratio based on the time passed and total vesting period

        // If the vesting period has occured the same block, the penalty ratio is 100% of the base penalty ratio
        if (_vestTimeElapsed <= 0) {
            penaltyRatio = basePenaltyRatioPercent;
        }
        // If the vesting period is mid-acceleration, calculate the penalty ratio based on the time passed
        else if (_vestTimeElapsed < VESTING_LENGTH) {
            penaltyRatio =
                ((VESTING_LENGTH - _vestTimeElapsed).divWad(VESTING_LENGTH) *
                    basePenaltyRatioPercent) /
                1e18;
        }
        // If the vesting period is over, return 0
        else {
            return 0;
        }
    }

    /// @inheritdoc IBlueberryStaking
    function getAccelerationFeeStableAsset(
        address _user,
        uint256 _vestingScheduleIndex
    ) public view returns (uint256 accelerationFee) {
        Vest storage _vest = vesting[_user][_vestingScheduleIndex];
        uint256 _vestTotal = _vest.amount + _vest.extra;

        uint256 _earlyUnlockPenaltyRatio = getEarlyUnlockPenaltyRatio(
            _user,
            _vestingScheduleIndex
        );

        accelerationFee =
            ((((_vest.priceUnderlying * _vestTotal) / 1e18) *
                _earlyUnlockPenaltyRatio) / 1e18) /
            (10 ** (18 - stableDecimals));
    }

    /// @inheritdoc IBlueberryStaking
    function getAccumulatedRewards(address _user) external view returns (uint256 _totalRewards) {
        address[] memory cachedTokens = ibTokens;
        uint256 cachedLength = cachedTokens.length;

        for (uint256 i; i < cachedLength; ++i) {
            if (isIbToken[cachedTokens[i]]) {
                _totalRewards += _earned(_user, cachedTokens[i]);
            }
        }
    }

    /*//////////////////////////////////////////////////
                         MANAGEMENT
    //////////////////////////////////////////////////*/

    /// @inheritdoc IBlueberryStaking
    function addIbTokens(
        address[] calldata _ibTokens,
        uint256[] calldata _amounts
    ) public onlyOwner {
        _validateTokenAmountsArray(_ibTokens, _amounts);

        uint256 _totalRewardsAdded;
        uint256 _rewardDuration = rewardDuration;
        
        uint256 _newTokensLength = _ibTokens.length;
        totalIbTokens += _newTokensLength;

        for (uint256 i; i < _newTokensLength; ++i) {
            address _ibToken = _ibTokens[i];
            uint256 _amount = _amounts[i];

            if (_ibTokens[i] == address(0)) {
                revert AddressZero();
            }

            if (isIbToken[_ibToken]) {
                revert IBTokenAlreadyExists();
            }

            isIbToken[_ibToken] = true;
            ibTokens.push(_ibToken);
            
            finishAt[_ibToken] = block.timestamp + _rewardDuration;
            _totalRewardsAdded += _amount;

            _setRewardRate(_ibToken, _amount, _rewardDuration);

            emit IbTokenAdded(_ibToken, _amount);
        }

        blb.transferFrom(msg.sender, address(this), _totalRewardsAdded);
    }

    /// @inheritdoc IBlueberryStaking
    function modifyRewardAmount(
        address[] calldata _ibTokens,
        uint256[] calldata _amounts
    ) external onlyOwner updateRewards(address(0), _ibTokens) {
        _validateTokenAmountsArray(_ibTokens, _amounts);

        uint256 _totalRewardsAdded;
        uint256 _rewardDuration = rewardDuration;
        uint256 _ibTokensLength = _ibTokens.length;

        for (uint256 i; i < _ibTokensLength; ++i) {
            address _ibToken = _ibTokens[i];
            uint256 _amount = _amounts[i];
            _totalRewardsAdded += _amount;

            if (block.timestamp <= finishAt[_ibToken]) {
                uint256 _timeRemaining = finishAt[_ibToken] - block.timestamp;
                uint256 _leftoverRewards = _timeRemaining * rewardRate[_ibToken];
                _amount += _leftoverRewards;                
            }

            _setRewardRate(_ibToken, _amount, _rewardDuration);
            lastUpdateTime[_ibToken] = block.timestamp;
            finishAt[_ibToken] = block.timestamp + rewardDuration;

            emit RewardAmountModified(_ibToken, _amount);
        }

        blb.transferFrom(msg.sender, address(this), _totalRewardsAdded);
    }

    /// @inheritdoc IBlueberryStaking
    function setRewardDuration(uint256 _rewardDuration) external onlyOwner {
        rewardDuration = _rewardDuration;

        emit RewardDurationUpdated(_rewardDuration);
    }

    /// @inheritdoc IBlueberryStaking
    function setBasePenaltyRatioPercent(uint256 _ratio) external onlyOwner {
        if (_ratio > 0.5e18) {
            revert InvalidPenaltyRatio();
        }
        basePenaltyRatioPercent = _ratio;

        emit BasePenaltyRatioUpdated(_ratio);
    }

    /**
     * @notice Sets the  stable asset to an alternative in the event of a depeg
     * @param _stableAsset The new stable asset address
     */
    function setStableAsset(address _stableAsset) external onlyOwner {
        if (_stableAsset == address(0)) {
            revert AddressZero();
        }
        stableAsset = IERC20(_stableAsset);
        uint8 decimals = IERC20Metadata(_stableAsset).decimals(); 

        stableDecimals = decimals;

        emit StableAssetUpdated(_stableAsset, decimals);
    }

    /// @inheritdoc IBlueberryStaking
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) {
            revert AddressZero();
        }
        treasury = _treasury;

        emit TreasuryUpdated(_treasury);
    }

    /// @inheritdoc IBlueberryStaking
    function setUniswapV3Pool(
        address _uniswapPool,
        uint32 _observationPeriod
    ) external onlyOwner {
        if (_uniswapPool == address(0)) {
            revert AddressZero();
        }
        if (_observationPeriod == 0 || _observationPeriod > 432_000) {
            revert InvalidObservationTime();
        }

        uniswapV3Info = UniswapV3PoolInfo(_uniswapPool, _observationPeriod);
    }

    /// @inheritdoc IBlueberryStaking
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IBlueberryStaking
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Sets the reward rate for a given token
     * @param _token Address of the token that the rewardRate will be set for
     * @param _amount The amount of tokens that will be distributed over the course
     *        of the reward duration
     * @param _duration The duration, in seconds, that the rewards will be distributed over
     */
    function _setRewardRate(address _token, uint256 _amount, uint256 _duration) internal {
        if (_token == address(0)) revert AddressZero();
        uint256 _rewardRate = _amount / _duration;
        if (_rewardRate == 0) revert InvalidRewardRate();
        rewardRate[_token] = _rewardRate;
    }

    /**
     * @notice Validates that the lengths of two arrays are equal
     * @param tokens An array of addresses
     * @param amounts An array of unsigned 256-bit integers
     */
    function _validateTokenAmountsArray(address[] memory tokens, uint256[] memory amounts) internal pure {
        if (tokens.length != amounts.length) {
            revert InvalidLength();
        }
    }
}
