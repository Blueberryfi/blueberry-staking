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

    event Staked(address indexed user, uint256 timestamp, address bToken, uint256 amount);

    event Unstaked(address indexed user, uint256 timestamp, address bToken, uint256 amount);

    /*//////////////////////////////////////////////////
                        VARIABLES
    //////////////////////////////////////////////////*/

    IERC20 public bdBLB;
    address[] public bTokens;

    mapping(address => uint256) public totalSupply;
    mapping(address => uint256) public rewardPerTokenStored;
    mapping(address => bool) public isBToken;
    mapping(address => uint256) public lastUpdateTime;

    mapping(address => mapping(address => uint256)) public balanceOf;
    mapping(address => mapping(address => uint256)) public rewards;
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;

    uint256 public rewardRate;
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
            bTokens.push(_bTokens[i]);
            isBToken[_bTokens[i]] = true;
            unchecked{
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////
                     STAKING FUNCTIONS
    //////////////////////////////////////////////////*/

    modifier updateRewards(address _user, IERC20[] _bTokens) {
        for (uint256 i; i < _bTokens.length;) {
        
            IERC20 _bToken = _bTokens[i];

            rewardPerTokenStored[address(_bToken)] = rewardPerToken(address(bdBLB));
            lastUpdateTime[address(_bToken)] = lastTimeRewardApplicable(address(bdBLB));

            if (_user != address(0)) {
                rewards[_user][address(_bToken)] = earned(_user, address(_bToken));
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
    function stake(uint256[] calldata _amounts, IERC20[] calldata _bTokens) external whenNotPaused() updateRewards(msg.sender, _bTokens) {
        require(_amounts.length == _bTokens.length, "Invalid length");

        for (uint256 i; i < _bTokens.length;) {
            if (!isBToken[address(_bTokens[i])]) {
                revert InvalidBToken();
            }

            IERC20 _bToken = _bTokens[i];
            uint256 _amount = _amounts[i];

            balanceOf[msg.sender][address(_bToken)] += _amount;
            totalSupply[address(_bToken)] += _amount;

            (bool success) = _bToken.transferFrom(msg.sender, address(this), _amount);

            if (!success) {
                revert TransferFailed();
            }

            emit Staked(msg.sender, address(_bToken), _amount);
            
            unchecked{
                ++i;
            }
        }
    }

    /**
    * @notice unstakes a given amount of each token
    * @dev does not claim rewards
    * @param _bTokens An array of the tokens to unstake
    * @param _amounts An array of the amounts of each token to unstake
    */
    function unstake(IERC20[] calldata _bTokens, uint256[] calldata _amounts) external whenNotPaused() updateRewards(msg.sender, _bTokens) {
        require(_amounts.length == _bTokens.length, "Invalid length");

        for (uint256 i; i < _bTokens.length;) {
            if (!isBToken[address(_bTokens[i])]) {
                revert InvalidBToken();
            }

            IERC20 _bToken = _bTokens[i];
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
    }

    /**
    * @notice Gets the rewards for the given bTokens for the caller
    * @param _bTokens An array of the tokens to claim rewards for
    */
    function getReward(IERC20[] calldata _bTokens) external whenNotPaused() updateRewards(msg.sender, _bTokens) {
        for (uint256 i; i < _bTokens.length;) {
            IERC20 _bToken = _bTokens[i];
            uint256 reward = rewards[msg.sender][address(_bToken)];

            if (reward > 0) {
                rewards[msg.sender][address(_bToken)] = 0;
                bdBLB.transfer(msg.sender, reward);
            }

            unchecked{
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////
                    WITHDRAWAL FUNCTIONS
    //////////////////////////////////////////////////*/



    /*//////////////////////////////////////////////////
                       VIEW FUNCTIONS
    //////////////////////////////////////////////////*/

    /**
    * @notice returns an array of the bTokens that can be staked
    */
    function getBTokens() external view returns (address[] memory) {
        return bTokens;
    }

    /**
    * @notice returns the total amount of rewards for the given bToken
    */
    function rewardPerToken(address _bTokens) public view returns (uint256) {

        for (uint256 i; i < _bTokens.length;) {
            if (!isBToken[address(_bTokens[i])]) {
                revert InvalidBToken();
            }

            IERC20 _bToken = _bTokens[i];

            if (totalSupply[_bToken] == 0) {
                return rewardPerTokenStored[_bToken];
            }

            /* if the reward period has finished, that timestamp is used to calculate the reward per token. */

            if (block.timestamp > finishAt){
                return rewardPerTokenStored[_bToken] + (rewardRate[_bToken] * (finishAt - lastUpdateTime[_bToken]) * 1e18 / totalSupply[_bToken]);
            } else {
                return rewardPerTokenStored[_bToken] + (rewardRate[_bToken] * (block.timestamp - lastUpdateTime[_bToken]) * 1e18 / totalSupply[_bToken]);
            }

            unchecked{
                ++i;
            }
        }
    }

    function earned(address _account) public view returns (uint256 earnedAmount) {
        for (uint256 i; i < bTokens.length;) {
            
            earnedAmount += (balanceOf[_account][bTokens[i]] * (rewardPerToken(bTokens[i]) - userRewardPerTokenPaid[_account][bTokens[i]])) / 1e18 + rewards[_account][bTokens[i]];

            unchecked{
                ++i;
            }
        }
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

    function addBToken(address _bToken) external onlyOwner() {
        if (_bToken == address(0)){
            revert AddressZero();
        }

        bTokens.push(_bToken);
        isBToken[_bToken] = true;
    }

    /**
    * @notice Called by the owner to change the reward rate for a given token(s)
    * @param _bTokens An array of the tokens to change the reward rate for
    * @param _amounts An array of the amounts to change the reward rate to for each token
    */
    function notifyRewardAmount(IERC20[] calldata _bTokens, uint256[] calldata _amounts) external onlyOwner() updateRewards(address(0), _bTokens) {
        require(_amounts.length == _bTokens.length, "Invalid length");

        for (uint256 i; i < _bTokens.length;) {
            if (!isBToken[address(_bTokens[i])]) {
                revert InvalidBToken();
            }

            IERC20 _bToken = _bTokens[i];
            uint256 _amount = _amounts[i];

            if (block.timestamp > finishAt){
                rewardRate = _amount / rewardDuration;
            } else {
                uint256 remaining = finishAt - block.timestamp;
                uint256 leftover = remaining * rewardRate;
                rewardRate = (_amount + leftover) / rewardDuration;
            }

            require(rewardRate > 0, "Invalid reward rate");
            require(rewardRate * rewardDuration <= bdBLB.balanceOf(address(this)), "Insufficient balance for reward rate");

            finishAt = block.timestamp + rewardDuration;
            lastUpdateTime = block.timestamp;
        }
    }

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