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

    /*//////////////////////////////////////////////////
                        VARIABLES
    //////////////////////////////////////////////////*/

    IERC20 public bdBLB;
    uint256 public totalBTokens;

    mapping(address => uint256) public totalSupply;
    mapping(address => uint256) public rewardPerTokenStored;
    mapping(address => uint256) public lastUpdateTime;
    mapping(address => uint256) public rewardRate;

    mapping(address => bool) public isBToken;

    mapping(address => mapping(address => uint256)) public balanceOf;
    mapping(address => mapping(address => uint256)) public rewards;
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;

    uint256 public rewardDuration;
    uint256 public finishAt;
 
    /**
    * @notice The constructor function, called when the contract is deployed
    * @param _bdBLB The token that will be used as rewards (bdBLB)
    * @param _bTokens An array of tokens that can be staked
    */
    constructor(ERC20 _bdBLB, address[] memory _bTokens) Ownable() {
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
    }

    /*//////////////////////////////////////////////////
                     STAKING FUNCTIONS
    //////////////////////////////////////////////////*/

    modifier updateRewards(address _user, address[] calldata _bTokens) {
        for (uint256 i; i < _bTokens.length;) {
        
            address _bToken = _bTokens[i];

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
            if (!isBToken[address(_bTokens[i])]) {
                revert InvalidBToken();
            }

            IERC20 _bToken = IERC20(_bTokens[i]);
            uint256 _amount = _amounts[i];

            balanceOf[msg.sender][address(_bToken)] += _amount;
            totalSupply[address(_bToken)] += _amount;

            (bool success) = _bToken.transferFrom(msg.sender, address(this), _amount);

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
            if (!isBToken[address(_bTokens[i])]) {
                revert InvalidBToken();
            }

            IERC20 _bToken = IERC20(_bTokens[i]);
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

    /**
    * @notice Gets the rewards for the given bTokens for the caller
    * @param _bTokens An array of the tokens to claim rewards for
    */
    function getReward(address[] calldata _bTokens) external whenNotPaused() updateRewards(msg.sender, _bTokens) {
        uint256 totalRewards;
        for (uint256 i; i < _bTokens.length;) {
            IERC20 _bToken = IERC20(_bTokens[i]);
            uint256 reward = rewards[msg.sender][address(_bToken)];
            totalRewards += reward;

            if (reward > 0) {
                rewards[msg.sender][address(_bToken)] = 0;
                bdBLB.transfer(msg.sender, reward);
            }

            unchecked{
                ++i;
            }
        }

        emit Claimed(msg.sender, totalRewards, block.timestamp);
    }

    /*//////////////////////////////////////////////////
                       VIEW FUNCTIONS
    //////////////////////////////////////////////////*/

    /**
    * @notice returns the total amount of rewards for the given bToken
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

    function changeBdBLB(address _bdBLB) external onlyOwner() {
        bdBLB = IERC20(_bdBLB);
    }

    function pause() external onlyOwner() {
        _pause();
    }

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

            require(isBToken[_bTokens[i]], "Already a BToken");

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
    * @dev 
    * @param _rewardDuration An array of the tokens to change the reward rate for
    */
    function setRewardDuration(uint256 _rewardDuration) external onlyOwner() {
        rewardDuration = _rewardDuration;
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