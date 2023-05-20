// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/
pragma solidity 0.8.19;

import { ERC20, IERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "../lib/openzeppelin-contracts/contracts//access/Ownable.sol";

error AddressZero();
error InvalidBToken();
error TransferFailed();

contract BlueberryStaking is Ownable {
    IERC20 public rewardToken;
    address[] public bTokens;

    mapping(address => bool) public isBToken;
    mapping(address => uint256) public totalDesposits;

    mapping(address => mapping(address => UserDeposit)) public deposits;

    struct UserDeposit {
        uint256 amount;
        uint256 rewardDebt;
    }
 
    /**
    * @notice The constructor function, called when the contract is deployed
    * @param _rewardToken The token that will be used as rewards
    * @param _bTokens An array of tokens that can be staked
    */
    constructor(ERC20 _rewardToken, address[] memory _bTokens) Ownable() {
        if (address(_rewardToken) == address(0)){
            revert AddressZero();
        }

        if (_bTokens.length <= 0){
            revert AddressZero();
        }

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

    /**
    * @notice A function for users to stake tokens
    * @param _amount An array of the amounts of each token to stake
    * @param _bToken An array of the tokens to stake
    */
    function stake(uint256[] calldata _amount, IERC20[] calldata _bToken) external {
        require(_amount.length == _bToken.length, "Invalid length");

        for (uint256 i; i < _bToken.length;) {

            if (!isBToken[address(_bToken[i])]) {
                revert InvalidBToken();
            }

            (bool success) = _bToken[i].transferFrom(msg.sender, address(this), _amount[i]);

            if (!success) {
                revert TransferFailed();
            }

            UserDeposit storage _userDeposit = deposits[msg.sender][address(_bToken[i])];
            _userDeposit.amount += _amount[i];
            totalDesposits[address(_bToken[i])] += _amount[i];
            
            unchecked{
                ++i;
            }
        }
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