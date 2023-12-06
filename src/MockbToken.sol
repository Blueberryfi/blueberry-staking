// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract MockbToken is ERC20, Ownable {
    constructor() ERC20("MockbToken", "MBT") Ownable(msg.sender) {
        _mint(msg.sender, 1_000 ** decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}