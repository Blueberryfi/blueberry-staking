// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20, IERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Pausable } from '../lib/openzeppelin-contracts/contracts/security/Pausable.sol';
import { Ownable } from "../lib/openzeppelin-contracts/contracts//access/Ownable.sol";
import './BlueberryLib.sol';

/**
 *  ██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
 *  ██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
 *  ██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
 *  ██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
 *  ██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
 *  ╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
 * @title Blueberry's staking contract for bdBLB distribution
 * @author haruxe
 */
contract BlueberryStaking is Ownable, Pausable {

    /*//////////////////////////////////////////////////
                         EVENTS
    //////////////////////////////////////////////////*/

    event Staked(address indexed user, address[] bTokens, uint256[] amounts, uint256 timestamp);

    event Unstaked(address indexed user, address[] bTokens, uint256[] amounts, uint256 timestamp);

    event Claimed(address indexed user, uint256 amount, uint256 timestamp);

    event BTokensAdded(address[] indexed bTokens, uint256 timestamp);

    event BTokensRemoved(address[] indexed bTokens, uint256 timestamp);

    event RewardAmountNotified(address[] indexed bTokens, uint256[] amounts, uint256 timestamp);

    event Accelerated(address indexed user, uint256 unlockedAmount, uint256 accelerationFee, uint256 redistributedAmount);

    event VestingCompleted(address indexed user, uint256 amount, uint256 timestamp);

    /*//////////////////////////////////////////////////
                        VARIABLES
    //////////////////////////////////////////////////*/

    IERC20 public bdBLB;
    uint256 public totalBTokens;

    mapping(address => uint256) public totalSupply;
    mapping(address => uint256) public rewardPerTokenStored;
    mapping(address => uint256) public lastUpdateTime;
    mapping(address => uint256) public rewardRate;
    mapping(address => uint256) public lastClaimed;

    mapping(address => bool) public isBToken;

    mapping(address => Vest[]) public vesting;

    mapping(address => mapping(address => uint256)) public balanceOf;
    mapping(address => mapping(address => uint256)) public rewards;
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;

    uint256 public rewardDuration;
    uint256 public finishAt;
    uint256 public vestLength;

    /**
     * @notice the length of an epoch in seconds
     * @dev 14 days by default
     */
    uint256 public epochLength = 1_209_600;

    struct Vest {
        uint256 amount;
        uint256 startTime;
    }
 
    /**
    * @notice The constructor function, called when the contract is deployed
    * @param _bdBLB The token that will be used as rewards (bdBLB)
    * @param _bTokens An array of tokens that can be staked
    */
    constructor(ERC20 _bdBLB, uint256 _rewardDuration, address[] memory _bTokens) Ownable() {
        if (address(_bdBLB) == address(0)){
            revert AddressZero();
        }

        if (_bTokens.length <= 0){
            revert AddressZero();
        }

        bdBLB = _bdBLB;

        for (uint256 i; i < _bTokens.length;) {
            if (_bTokens[i] == address(0)){
                revert AddressZero();
            }

            isBToken[_bTokens[i]] = true;

            unchecked{
                ++i;
            }
        }

        totalBTokens = _bTokens.length;

        require(_rewardDuration > 0, "Invalid reward duration");

        rewardDuration = _rewardDuration;
        finishAt = block.timestamp + _rewardDuration;
    }

    /*//////////////////////////////////////////////////
                     STAKING FUNCTIONS
    //////////////////////////////////////////////////*/

    /**
    * @notice updates the rewards for a given user and a given array of tokens
    * @param _user The user to update the rewards for
    * @param _bTokens An array of tokens to update the rewards for
    */
    modifier updateRewards(address _user, address[] calldata _bTokens) {
        for (uint256 i; i < _bTokens.length;) {
            address _bToken = _bTokens[i];

            if (!isBToken[address(_bToken)]) {
                revert InvalidBToken();
            }

            rewardPerTokenStored[address(_bToken)] = rewardPerToken(address(bdBLB));
            lastUpdateTime[address(_bToken)] = lastTimeRewardApplicable();

            if (_user != address(0)) {
                rewards[_user][address(_bToken)] = earned(_user, _bToken);
                userRewardPerTokenPaid[_user][address(_bToken)] = rewardPerTokenStored[address(_bToken)];
            }

            unchecked{
                ++i;
            }
        }
        _;
    }

    /**
    * @notice stakes a given amount of each token
    * @dev The amount of tokens must be approved by the user before calling this function
    * @param _amounts An array of the amounts of each token to stake
    * @param _bTokens An array of the tokens to stake
    */
    function stake(uint256[] calldata _amounts, address[] calldata _bTokens) external whenNotPaused() updateRewards(msg.sender, _bTokens) {
        require(_amounts.length == _bTokens.length, "Invalid length");

        for (uint256 i; i < _bTokens.length;) {
            address _bToken = _bTokens[i];

            if (!isBToken[address(_bToken)]) {
                revert InvalidBToken();
            }

            uint256 _amount = _amounts[i];

            balanceOf[msg.sender][address(_bToken)] += _amount;
            totalSupply[address(_bToken)] += _amount;

            (bool success) = IERC20(_bToken).transferFrom(msg.sender, address(this), _amount);

            if (!success) {
                revert TransferFailed();
            }
            
            unchecked{
                ++i;
            }
        }

        emit Staked(msg.sender, _bTokens, _amounts, block.timestamp);
    }

    /**
    * @notice unstakes a given amount of each token
    * @dev does not claim rewards
    * @param _bTokens An array of the tokens to unstake
    * @param _amounts An array of the amounts of each token to unstake
    */
    function unstake(address[] calldata _bTokens, uint256[] calldata _amounts) external whenNotPaused() updateRewards(msg.sender, _bTokens) {
        require(_amounts.length == _bTokens.length, "Invalid length");

        for (uint256 i; i < _bTokens.length;) {
            address _bToken = _bTokens[i];

            if (!isBToken[address(_bToken)]) {
                revert InvalidBToken();
            }

            uint256 _amount = _amounts[i];

            balanceOf[msg.sender][address(_bToken)] -= _amount;
            totalSupply[address(_bToken)] -= _amount;

            (bool success) = IERC20(_bToken).transfer(msg.sender, _amount);

            if (!success) {
                revert TransferFailed();
            }

            unchecked{
                ++i;
            }
        }

        emit Unstaked(msg.sender, _bTokens, _amounts, block.timestamp);
    }    

    /*//////////////////////////////////////////////////
                     VESTING FUNCTIONS
    //////////////////////////////////////////////////*/

    /**
    * @notice starts the vesting process for a given array of tokens
    * @param _bTokens An array of the tokens to start vesting for the caller
    */
    function startVesting(address[] calldata _bTokens) external whenNotPaused() updateRewards(msg.sender, _bTokens) {
        require(canClaim(msg.sender), "Cannot claim yet");
        lastClaimed[msg.sender] = block.timestamp;

        uint256 totalRewards;
        for (uint256 i; i < _bTokens.length;) {
            if (!isBToken[address(_bTokens[i])]) {
                revert InvalidBToken();
            }

            IERC20 _bToken = IERC20(_bTokens[i]);
            uint256 reward = rewards[msg.sender][address(_bToken)];

            if (reward > 0) {
                totalRewards += reward;
                rewards[msg.sender][address(_bToken)] = 0;
                vesting[msg.sender].push(Vest(block.timestamp, reward));
            }

            unchecked{
                ++i;
            }
        }

        emit Claimed(msg.sender, totalRewards, block.timestamp);
    }

    /**
    * @notice Claims the tokens that have completed their vesting schedule for the caller.
    * @param _indexes The indexes of the vesting schedule to claim.
    */
    function completeVesting(uint256[] calldata _indexes) external whenNotPaused() {
        require(vesting[msg.sender].length >= _indexes.length, "Invalid length");

        Vest[] storage vests = vesting[msg.sender];


        uint256 totalbdBLB;
        for (uint256 i; i < _indexes.length;) {
            Vest storage v = vests[_indexes[i]];

            require(v.startTime >= block.timestamp + vestLength, "Vesting is not yet complete");

            totalbdBLB += v.amount;
            delete vests[_indexes[i]];

            unchecked{
                ++i;
            }
        }

        if (totalbdBLB > 0) {
            (bool success) = IERC20(address(bdBLB)).transfer(msg.sender, totalbdBLB);

            if (!success) {
                revert TransferFailed();
            }
        }

        emit VestingCompleted(msg.sender, totalbdBLB, block.timestamp);
    }

    /*//////////////////////////////////////////////////
                       VIEW FUNCTIONS
    //////////////////////////////////////////////////*/

    /**
    * @notice ensures the user can only claim once per epoch
    * @param _user the user to check
    */
    function canClaim(address _user) public view returns (bool) {
        uint256 currentEpoch = block.timestamp / epochLength;
        return lastClaimed[_user] < currentEpoch;
    }

    /**
    * @return returns the total amount of rewards for the given bToken
    */
    function rewardPerToken(address _bToken) public view returns (uint256) {

        if (totalSupply[_bToken] == 0) {
            return rewardPerTokenStored[_bToken];
        }

        /* if the reward period has finished, that timestamp is used to calculate the reward per token. */

        if (block.timestamp > finishAt){
            return rewardPerTokenStored[_bToken] + (rewardRate[_bToken] * (finishAt - lastUpdateTime[_bToken]) * 1e18 / totalSupply[_bToken]);
        } else {
            return rewardPerTokenStored[_bToken] + (rewardRate[_bToken] * (block.timestamp - lastUpdateTime[_bToken]) * 1e18 / totalSupply[_bToken]);
        }
    }

    function earned(address _account, address _bToken) public view returns (uint256 earnedAmount) {
        earnedAmount += (balanceOf[_account][_bToken] * (rewardPerToken(_bToken) - userRewardPerTokenPaid[_account][_bToken])) / 1e18 + rewards[_account][_bToken];
    }

    /**
    * @return the timestamp of the last time rewards were updated
    */
    function lastTimeRewardApplicable() public view returns (uint256) {
        if (block.timestamp > finishAt){
            return finishAt;
        } else {
            return block.timestamp;
        }
    }

    /*//////////////////////////////////////////////////
                         MANAGEMENT
    //////////////////////////////////////////////////*/

    /**
    * @notice Change the bdBLB token address (in case of migration)
    */
    function changeBdBLB(address _bdBLB) external onlyOwner() {
        bdBLB = IERC20(_bdBLB);
    }

    function changeEpochLength(uint256 _epochLength) external onlyOwner() {
        epochLength = _epochLength;
    }

    /**
    * @notice Pauses the contract
    */
    function pause() external onlyOwner() {
        _pause();
    }

    /**
    * @notice Unpauses the contract
    */
    function unpause() external onlyOwner() {
        _unpause();
    }

    /**
    * @notice Adds the given tokens to the list of bTokens
    * @param _bTokens An array of the tokens to add
    */
    function addBTokens(address[] calldata _bTokens) external onlyOwner() {
        totalBTokens += _bTokens.length;
        for (uint256 i; i < _bTokens.length;) {
            if (_bTokens[i] == address(0)){
                revert AddressZero();
            }

            require(isBToken[_bTokens[i]], "Already a bToken");

            isBToken[_bTokens[i]] = true;
            
            
            unchecked{
                ++i;
            }
        }

        emit BTokensAdded(_bTokens, block.timestamp);
    }

    /**
    * @notice Removes the given tokens from the list of bTokens
    * @param _bTokens An array of the tokens to remove
    */
    function removeBTokens(address[] calldata _bTokens) external onlyOwner() {
        totalBTokens -= _bTokens.length;
        for (uint256 i; i < _bTokens.length;) {
            if (_bTokens[i] == address(0)){
                revert AddressZero();
            }

            require(isBToken[_bTokens[i]], "Not a bToken");

            isBToken[_bTokens[i]] = false;
            
            
            unchecked{
                ++i;
            }
        }

        emit BTokensRemoved(_bTokens, block.timestamp);
    }

    /**
    * @notice Called by the owner to change the reward rate for a given token(s)
    * @dev uses address(0) as to not change the reward rate for any user
    * @param _bTokens An array of the tokens to change the reward rate for
    * @param _amounts An array of the amounts to change the reward rate to for each token
    */
    function notifyRewardAmount(address[] calldata _bTokens, uint256[] calldata _amounts) external onlyOwner() updateRewards(address(0), _bTokens) {
        require(_amounts.length == _bTokens.length, "Invalid length");

        for (uint256 i; i < _bTokens.length;) {
            if (!isBToken[address(_bTokens[i])]) {
                revert InvalidBToken();
            }

            address _bToken = _bTokens[i];
            uint256 _amount = _amounts[i];

            if (block.timestamp > finishAt){
                rewardRate[_bToken] = _amount / rewardDuration;
            } else {
                uint256 remaining = finishAt - block.timestamp;
                uint256 leftover = remaining * rewardRate[_bToken];
                rewardRate[_bToken] = (_amount + leftover) / rewardDuration;
            }

            require(rewardRate[_bToken] > 0, "Invalid reward rate");
            require(rewardRate[_bToken] * rewardDuration <= bdBLB.balanceOf(address(this)), "Insufficient balance for reward rate");

            finishAt = block.timestamp + rewardDuration;
            lastUpdateTime[_bToken] = block.timestamp;

            unchecked {
                ++i;
            }
        }

        emit RewardAmountNotified(_bTokens, _amounts, block.timestamp);
    }

    /**
    * @notice Called by the owner to change the reward duration in seconds
    * @dev This will not change the reward rate for any tokens
    * @param _rewardDuration The new reward duration in seconds
    */
    function setRewardDuration(uint256 _rewardDuration) external onlyOwner() {
        rewardDuration = _rewardDuration;
    }

    /**
    * @notice Called by the owner to change the vest length in seconds
    * @dev Will effect all users who are vesting
    * @param _vestLength The new vest length in seconds
    */
    function setVestLength(uint256 _vestLength) external onlyOwner() {
        vestLength = _vestLength;
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