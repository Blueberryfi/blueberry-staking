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
    mapping(address => bool) public isBToken;
    mapping(address => uint256) public totalDesposits;
    mapping(address => mapping(address => Stake[])) public staked;
    mapping(address => Withdrawal[]) public withdrawals;

    struct Stake {
        uint256 amount;
        uint256 timestamp;
    }

    struct Withdrawal {
        uint256 bdBLBAmount;
        uint256 quedAt;
    }
 
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

    /**
    * @notice stakes a given amount of each token
    * @dev The amount of tokens must be approved by the user before calling this function
    * @param _amounts An array of the amounts of each token to stake
    * @param _bTokens An array of the tokens to stake
    */
    function stake(uint256[] calldata _amounts, IERC20[] calldata _bTokens) external whenNotPaused() {
        require(_amounts.length == _bTokens.length, "Invalid length");

        for (uint256 i; i < _bTokens.length;) {
            if (!isBToken[address(_bTokens[i])]) {
                revert InvalidBToken();
            }

            IERC20 _bToken = _bTokens[i];
            uint256 _amount = _amounts[i];

            (bool success) = _bToken.transferFrom(msg.sender, address(this), _amount);

            if (!success) {
                revert TransferFailed();
            }

            staked[msg.sender][address(_bToken)].push(Stake(_amount, block.timestamp));
            totalDesposits[address(_bToken)] += _amount;

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
    */
    function unstake(IERC20[] calldata _bTokens) external whenNotPaused() {
        for (uint256 i; i < _bTokens.length;) {
            uint256 _totalWithrawalAmount;

            for (uint256 x; x < staked[msg.sender][bTokens[i]].length;) {
                Stake storage _stake = staked[msg.sender][bTokens[i]][x];
                _totalWithrawalAmount += _stake.amount;
                unchecked{
                    ++x;
                }
            }

            (bool success) = IERC20(bTokens[i]).transfer(msg.sender, _totalWithrawalAmount);

            if (!success) {
                revert TransferFailed();
            }

            unchecked{
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////
                    WITHDRAWAL FUNCTIONS
    //////////////////////////////////////////////////*/

    function getPendingWithdrawals(address _user) public view returns (uint256 pendingBdBLB) {
        for (uint256 i; i < bTokens.length;) {
            UserDeposit storage _userDeposit = users[_user].deposits[bTokens[i]];
            pendingBdBLB += _userDeposit.amount;
            unchecked{
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////
                       VIEW FUNCTIONS
    //////////////////////////////////////////////////*/

    function getBTokens() external view returns (address[] memory) {
        return bTokens;
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
     * @dev This function is called for plain Ether transfers, i.e. for every call with empty calldata.
     */
    receive() external payable {}

    /**
     * @dev Fallback function is executed if none of the other functions match the function
     * identifier or no data was provided with the function call.
     */
    fallback() external payable {}
}