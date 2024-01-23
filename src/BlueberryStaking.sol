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
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import "v3-core/libraries/TickMath.sol";
import "v3-core/libraries/FullMath.sol";
import "v3-core/libraries/FixedPoint96.sol";

import {IBlueberryToken, IERC20} from "./interfaces/IBlueberryToken.sol";
import {IBlueberryStaking} from "./interfaces/IBlueberryStaking.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

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
    /// @notice The USDC token contract
    IERC20 public usdc;

    /// @notice The treasury address
    address public treasury;

    /// @notice The Uniswap V3 pool address
    address public uniswapV3Pool;

    /// @notice The Uniswap V3 factory address
    address public uniswapV3Factory =
        address(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    /// @notice The observation period for Uniswap V3
    uint32 public observationPeriod = 3600;

    /// @notice The total number of B tokens
    uint256 public totalBTokens;

    /// @notice The total supply of tokens for each address
    mapping(address => uint256) public totalSupply;

    /// @notice The stored reward per token for each address
    mapping(address => uint256) public rewardPerTokenStored;

    /// @notice The last update time for each address
    mapping(address => uint256) public lastUpdateTime;

    /// @notice The reward rate for each address
    mapping(address => uint256) public rewardRate;

    /// @notice The last claimed epoch for each address
    mapping(address => uint256) public lastClaimedEpoch;

    /// @notice The B token status for each address
    mapping(address => bool) public isBToken;

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

    /// @notice The finish time for rewards
    uint256 public finishAt;

    /// @notice The length of the vesting period
    uint256 public vestLength = 52 weeks;

    /// @notice The deployment time of the contract
    uint256 public deployedAt;

    // 25% at the start of each vesting period
    uint256 public basePenaltyRatioPercent = 0.25e18;

    // USDC has 6 decimals- but this can be changed in case of depeg and new token set
    uint256 private _usdcDecimals = 6;

    mapping(uint256 => Epoch) public epochs;

    /**
     * @notice the length of an epoch in seconds
     * @dev 14 days by default
     */
    uint256 public epochLength = 1_209_600;

    /*//////////////////////////////////////////////////
                        CONSTRUCTOR
    //////////////////////////////////////////////////*/
    constructor() {}

    /*//////////////////////////////////////////////////
                     FUNCTIONS
    //////////////////////////////////////////////////*/

    /**
     * @notice The constructor function, called when the contract is deployed
     * @param _blb The token that will be used as rewards
     * @param _usdc The usdc token address
     * @param _treasury The treasury address
     * @param _rewardDuration The duration of the reward period
     * @param _bTokens An array of the bTokens that can be staked
     */
    function initialize(
        address _blb,
        address _usdc,
        address _treasury,
        uint256 _rewardDuration,
        address[] memory _bTokens,
        address _admin
    ) public initializer {
        __Ownable2Step_init();
        __Pausable_init();
        _transferOwnership(_admin);

        if (
            _blb == address(0) || _usdc == address(0) || _treasury == address(0)
        ) {
            revert AddressZero();
        }

        if (_bTokens.length == 0) {
            revert InvalidBToken();
        }

        for (uint256 i; i < _bTokens.length; ++i) {
            if (_bTokens[i] == address(0)) {
                revert AddressZero();
            }

            isBToken[_bTokens[i]] = true;
        }

        if (_rewardDuration == 0) {
            revert InvalidRewardDuration();
        }

        blb = IBlueberryToken(_blb);
        usdc = IERC20(_usdc);
        treasury = _treasury;
        totalBTokens = _bTokens.length;
        rewardDuration = _rewardDuration;
        finishAt = block.timestamp + _rewardDuration;
        deployedAt = block.timestamp;
    }

    /**
     * @notice updates the rewards for a given user and a given array of tokens
     * @param _user The user to update the rewards for
     * @param _bTokens An array of tokens to update the rewards for
     */
    modifier updateRewards(address _user, address[] calldata _bTokens) {
        for (uint256 i; i < _bTokens.length; ++i) {
            address _bToken = _bTokens[i];

            _updateReward(_user, _bToken);
        }
        _;
    }

    /// Contains the logic for updateReward function
    function _updateReward(address _user, address _bToken) internal {
        if (!isBToken[_bToken]) {
            revert InvalidBToken();
        }

        rewardPerTokenStored[_bToken] = rewardPerToken(_bToken);
        lastUpdateTime[_bToken] = lastTimeRewardApplicable();

        if (_user != address(0)) {
            rewards[_user][_bToken] = _earned(_user, _bToken);
            userRewardPerTokenPaid[_user][_bToken] = rewardPerTokenStored[
                _bToken
            ];
        }
    }

    /// @inheritdoc IBlueberryStaking
    function stake(
        address[] calldata _bTokens,
        uint256[] calldata _amounts
    ) external whenNotPaused updateRewards(msg.sender, _bTokens) {
        if ((_amounts.length) != _bTokens.length) {
            revert InvalidLength();
        }

        for (uint256 i; i < _bTokens.length; ++i) {
            address _bToken = _bTokens[i];

            if (!isBToken[_bToken]) {
                revert InvalidBToken();
            }

            uint256 _amount = _amounts[i];

            balanceOf[msg.sender][_bToken] += _amount;
            totalSupply[_bToken] += _amount;

            IERC20(_bToken).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }

        emit Staked(msg.sender, _bTokens, _amounts, block.timestamp);
    }

    /// @inheritdoc IBlueberryStaking
    function unstake(
        address[] calldata _bTokens,
        uint256[] calldata _amounts
    ) external whenNotPaused updateRewards(msg.sender, _bTokens) {
        if (_amounts.length != _bTokens.length) {
            revert InvalidLength();
        }

        for (uint256 i; i < _bTokens.length; ++i) {
            address _bToken = _bTokens[i];

            if (!isBToken[address(_bToken)]) {
                revert InvalidBToken();
            }

            uint256 _amount = _amounts[i];

            balanceOf[msg.sender][address(_bToken)] -= _amount;
            totalSupply[address(_bToken)] -= _amount;

            IERC20(_bToken).safeTransfer(msg.sender, _amount);
        }

        emit Unstaked(msg.sender, _bTokens, _amounts, block.timestamp);
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

            uint256 _vestEpoch = (vest.startTime - deployedAt) / epochLength;

            if (epochs[_vestEpoch].redistributedBLB > 0) {
                vest.amount =
                    (vest.amount * epochs[_vestEpoch].redistributedBLB) /
                    epochs[_vestEpoch].totalBLB;
            }
        }

        _;
    }

    /// @inheritdoc IBlueberryStaking
    function startVesting(
        address[] calldata _bTokens
    ) external whenNotPaused updateRewards(msg.sender, _bTokens) {
        if (!canClaim(msg.sender)) {
            revert AlreadyClaimed();
        }

        uint256 _currentEpoch = currentEpoch();

        lastClaimedEpoch[msg.sender] = _currentEpoch;

        uint256 totalRewards;
        for (uint256 i; i < _bTokens.length; ++i) {
            if (!isBToken[address(_bTokens[i])]) {
                revert InvalidBToken();
            }

            IERC20 _bToken = IERC20(_bTokens[i]);
            uint256 reward = rewards[msg.sender][address(_bToken)];

            if (reward > 0) {
                totalRewards += reward;
                rewards[msg.sender][address(_bToken)] = 0;

                // month 1: $0.02 / blb
                uint256 _priceUnderlying = getPrice();

                vesting[msg.sender].push(
                    Vest(reward, block.timestamp, _priceUnderlying)
                );
            }
        }

        epochs[_currentEpoch].totalBLB += totalRewards;

        emit Claimed(msg.sender, totalRewards, block.timestamp);
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

            totalbdblb += v.amount;
            delete vests[_vestIndexes[i]];
        }

        if (totalbdblb > 0) {
            blb.transfer(msg.sender, totalbdblb);
        }

        emit VestingCompleted(msg.sender, totalbdblb, block.timestamp);
    }

    /// @inheritdoc IBlueberryStaking
    function accelerateVesting(
        uint256[] calldata _vestIndexes
    ) external whenNotPaused updateVests(msg.sender, _vestIndexes) {
        // index must exist
        if (vesting[msg.sender].length < _vestIndexes.length) {
            revert InvalidLength();
        }

        // lockdrop period must be complete i.e 2 months
        if (block.timestamp <= deployedAt + 60 days) {
            revert LockdropIncomplete();
        }

        Vest[] storage vests = vesting[msg.sender];

        uint256 totalbdblb;
        uint256 totalRedistributedAmount;
        uint256 totalAccelerationFee;
        for (uint256 i; i < _vestIndexes.length; ++i) {
            uint256 _vestIndex = _vestIndexes[i];
            Vest storage _vest = vests[_vestIndex];
            uint256 _vestAmount = _vest.amount;

            if (_vestAmount <= 0) {
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
            uint256 _accelerationFee = getAccelerationFeeUSDC(
                msg.sender,
                _vestIndex
            );
            totalAccelerationFee += _accelerationFee;

            // calculate the amount of the vest that will be redistributed
            uint256 _redistributionAmount = (_vestAmount *
                _earlyUnlockPenaltyRatio) / 1e18;

            // get current epoch and redistribute to it
            uint256 _epoch = currentEpoch();
            epochs[_epoch].redistributedBLB += _redistributionAmount;

            // log it for the event
            totalRedistributedAmount += _redistributionAmount;

            // remove it from the recieved vest
            _vestAmount -= _redistributionAmount;

            // the remainder is withdrawable by the user
            totalbdblb += _vestAmount;

            // delete the vest
            delete vests[_vestIndex];
        }

        if (totalAccelerationFee > 0) {
            // transfer the acceleration fee to the treasury
            usdc.safeTransferFrom(msg.sender, treasury, totalAccelerationFee);
        }

        if (totalbdblb > 0) {
            blb.transfer(msg.sender, totalbdblb);
        }

        emit Accelerated(msg.sender, totalbdblb, totalRedistributedAmount);
    }

    /*//////////////////////////////////////////////////
                       VIEW FUNCTIONS
    //////////////////////////////////////////////////*/

    /// @inheritdoc IBlueberryStaking
    function fetchTWAP(uint32 _secondsInPast) public view returns (uint256) {
        IUniswapV3Pool _pool = IUniswapV3Pool(uniswapV3Pool);

        // max 5 days
        if (_secondsInPast > 432_000) {
            revert InvalidObservationTime();
        }

        uint32[] memory _secondsArray = new uint32[](2);

        _secondsArray[0] = _secondsInPast;
        _secondsArray[1] = 0;

        (int56[] memory tickCumulatives, ) = _pool.observe(_secondsArray);

        int56 _tickDifference = tickCumulatives[1] - tickCumulatives[0];
        int56 _timeDifference = int32(_secondsInPast);

        int24 _twapTick = int24(_tickDifference / _timeDifference);

        uint160 _sqrtPriceX96 = TickMath.getSqrtRatioAtTick(_twapTick);

        // Decode the square root price
        uint256 _priceX96 = FullMath.mulDiv(
            _sqrtPriceX96,
            _sqrtPriceX96,
            FixedPoint96.Q96
        );

        uint256 _decimalsBLB = 18;
        uint256 _decimalsUSDC = _usdcDecimals;

        // Adjust for decimals
        if (_decimalsBLB > _decimalsUSDC) {
            _priceX96 /= 10 ** (_decimalsBLB - _decimalsUSDC);
        } else if (_decimalsUSDC > _decimalsBLB) {
            _priceX96 *= 10 ** (_decimalsUSDC - _decimalsBLB);
        }

        // Now priceX96 is the price of blb in terms of usdc, multiplied by 2^96.
        // To convert this to a human-readable format, you can divide by 2^96:

        uint256 _price = _priceX96 / 2 ** 96;

        // Now 'price' is the price of blb in terms of usdc, in the correct decimal places.
        return _price;
    }

    /// @inheritdoc IBlueberryStaking
    function getPrice() public view returns (uint256 _price) {
        // during the lockdrop period the underlying blb token price is locked
        uint256 _month = (block.timestamp - deployedAt) / 30 days;
        // month 1: $0.02 / blb
        if (_month <= 1) {
            _price = 0.02e18;
        }
        // month 2: $0.04 / blb
        else if (_month <= 2 || uniswapV3Pool == address(0)) {
            _price = 0.04e18;
        }
        // month 3+
        else {
            // gets the price of BLB in USD averaged over the last hour
            _price = fetchTWAP(observationPeriod);
        }
    }

    /// @inheritdoc IBlueberryStaking
    function canClaim(address _user) public view returns (bool) {
        uint256 _currentEpoch = currentEpoch();
        return lastClaimedEpoch[_user] <= _currentEpoch;
    }

    function currentEpoch() public view returns (uint256) {
        return (block.timestamp - deployedAt) / epochLength;
    }

    function getBLB() public view returns (address) {
        return address(blb);
    }

    function getUSDC() public view returns (address) {
        return address(usdc);
    }

    /// @inheritdoc IBlueberryStaking
    function isVestingComplete(
        address _user,
        uint256 _vestIndex
    ) public view returns (bool) {
        return
            vesting[_user][_vestIndex].startTime + vestLength <=
            block.timestamp;
    }

    /// @inheritdoc IBlueberryStaking
    function rewardPerToken(address _bToken) public view returns (uint256) {
        if (totalSupply[_bToken] == 0) {
            return rewardPerTokenStored[_bToken];
        }

        /* if the reward period has finished, that timestamp is used to calculate the reward per token. */

        if (block.timestamp > finishAt) {
            return
                rewardPerTokenStored[_bToken] +
                ((rewardRate[_bToken] *
                    (finishAt - lastUpdateTime[_bToken]) *
                    1e18) / totalSupply[_bToken]);
        } else {
            return
                rewardPerTokenStored[_bToken] +
                ((rewardRate[_bToken] *
                    (block.timestamp - lastUpdateTime[_bToken]) *
                    1e18) / totalSupply[_bToken]);
        }
    }

    /// @inheritdoc IBlueberryStaking
    function earned(
        address _account,
        address _bToken
    ) public view returns (uint256 earnedAmount) {
        return _earned(_account, _bToken);
    }

    function _earned(
        address _account,
        address _bToken
    ) internal view returns (uint256 earnedAmount) {
        uint256 _balance = balanceOf[_account][_bToken];
        uint256 _rewardPerToken = rewardPerToken(_bToken);
        uint256 _rewardPaid = userRewardPerTokenPaid[_account][_bToken];
        earnedAmount =
            (_balance * (_rewardPerToken - _rewardPaid)) /
            1e18 +
            rewards[_account][_bToken];
    }

    /// @inheritdoc IBlueberryStaking
    function lastTimeRewardApplicable() public view returns (uint256) {
        if (block.timestamp > finishAt) {
            return finishAt;
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
            _balance += vesting[_user][i].amount;
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
        else if (_vestTimeElapsed < vestLength) {
            penaltyRatio =
                ((vestLength - _vestTimeElapsed).divWad(vestLength) *
                    basePenaltyRatioPercent) /
                1e18;
        }
        // If the vesting period is over, return 0
        else {
            return 0;
        }
    }

    /// @inheritdoc IBlueberryStaking
    function getAccelerationFeeUSDC(
        address _user,
        uint256 _vestingScheduleIndex
    ) public view returns (uint256 accelerationFee) {
        Vest storage _vest = vesting[_user][_vestingScheduleIndex];
        uint256 _earlyUnlockPenaltyRatio = getEarlyUnlockPenaltyRatio(
            _user,
            _vestingScheduleIndex
        );

        accelerationFee =
            ((((_vest.priceUnderlying * _vest.amount) / 1e18) *
                _earlyUnlockPenaltyRatio) / 1e18) /
            (10 ** (18 - _usdcDecimals));
    }

    /*//////////////////////////////////////////////////
                         MANAGEMENT
    //////////////////////////////////////////////////*/

    /// @inheritdoc IBlueberryStaking
    function changeBLB(address _blb) external onlyOwner {
        if (_blb == address(0)) {
            revert AddressZero();
        }
        blb = IBlueberryToken(_blb);

        emit BLBUpdated(_blb, block.timestamp);
    }

    /// @inheritdoc IBlueberryStaking
    function changeEpochLength(uint256 _epochLength) external onlyOwner {
        if (_epochLength == 0) {
            revert EpochLengthZero();
        }
        epochLength = _epochLength;

        emit EpochLengthUpdated(_epochLength, block.timestamp);
    }

    /// @inheritdoc IBlueberryStaking
    function addBTokens(address[] calldata _bTokens) external onlyOwner {
        totalBTokens += _bTokens.length;
        for (uint256 i; i < _bTokens.length; ++i) {
            if (_bTokens[i] == address(0)) {
                revert AddressZero();
            }

            if (isBToken[_bTokens[i]]) {
                revert BTokenAlreadyExists();
            }

            isBToken[_bTokens[i]] = true;
        }

        emit BTokensAdded(_bTokens, block.timestamp);
    }

    /// @inheritdoc IBlueberryStaking
    function removeBTokens(address[] calldata _bTokens) external onlyOwner {
        totalBTokens -= _bTokens.length;
        for (uint256 i; i < _bTokens.length; ++i) {
            if (_bTokens[i] == address(0)) {
                revert AddressZero();
            }

            if (!isBToken[_bTokens[i]]) {
                revert BTokenDoesNotExist();
            }

            isBToken[_bTokens[i]] = false;
        }

        emit BTokensRemoved(_bTokens, block.timestamp);
    }

    /// @inheritdoc IBlueberryStaking
    function notifyRewardAmount(
        address[] calldata _bTokens,
        uint256[] calldata _amounts
    ) external onlyOwner updateRewards(address(0), _bTokens) {
        if (_amounts.length != _bTokens.length) {
            revert InvalidLength();
        }

        for (uint256 i; i < _bTokens.length; ++i) {
            address _bToken = _bTokens[i];
            uint256 _amount = _amounts[i];

            if (block.timestamp > finishAt) {
                rewardRate[_bToken] = _amount / rewardDuration;
            } else {
                uint256 remaining = finishAt - block.timestamp;
                uint256 leftover = remaining * rewardRate[_bToken];
                rewardRate[_bToken] = (_amount + leftover) / rewardDuration;
            }

            if (rewardRate[_bToken] == 0) {
                revert InvalidRewardRate();
            }

            finishAt = block.timestamp + rewardDuration;
            lastUpdateTime[_bToken] = block.timestamp;
        }

        emit RewardAmountNotified(_bTokens, _amounts, block.timestamp);
    }

    /// @inheritdoc IBlueberryStaking
    function setRewardDuration(uint256 _rewardDuration) external onlyOwner {
        rewardDuration = _rewardDuration;

        emit RewardDurationUpdated(_rewardDuration, block.timestamp);
    }

    /// @inheritdoc IBlueberryStaking
    function setVestLength(uint256 _vestLength) external onlyOwner {
        vestLength = _vestLength;

        emit VestLengthUpdated(_vestLength, block.timestamp);
    }

    /// @inheritdoc IBlueberryStaking
    function setbasePenaltyRatioPercent(uint256 _ratio) external onlyOwner {
        if (_ratio > 1e18) {
            revert InvalidPenaltyRatio();
        }
        basePenaltyRatioPercent = _ratio;

        emit BasePenaltyRatioChanged(_ratio, block.timestamp);
    }

    /**
     * @notice Changes the address of stable asset to an alternative in the event of a depeg
     * @param _usdc The new stable asset address
     * @param _decimals The decimals of the new usdc
     */
    function changeusdcAddress(
        address _usdc,
        uint256 _decimals
    ) external onlyOwner {
        if (_usdc == address(0)) {
            revert AddressZero();
        }
        usdc = IERC20(_usdc);
        _usdcDecimals = _decimals;

        emit UsdcAddressUpdated(_usdc, _decimals, block.timestamp);
    }

    /// @inheritdoc IBlueberryStaking
    function changeTreasuryAddress(address _treasury) external onlyOwner {
        if (_treasury == address(0)) {
            revert AddressZero();
        }
        treasury = _treasury;

        emit TreasuryUpdated(_treasury, block.timestamp);
    }

    /// @inheritdoc IBlueberryStaking
    function changeUniswapInformation(
        address _uniswapPool,
        address _uniswapFactory,
        uint32 _observationPeriod
    ) external onlyOwner {
        if (_uniswapPool == address(0) || _uniswapFactory == address(0)) {
            revert AddressZero();
        }
        if (_observationPeriod == 0) {
            revert InvalidObservationTime();
        }

        uniswapV3Pool = _uniswapPool;
        uniswapV3Factory = _uniswapFactory;
        observationPeriod = _observationPeriod;
    }

    /// @inheritdoc IBlueberryStaking
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IBlueberryStaking
    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}

    fallback() external payable {}
}
