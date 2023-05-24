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

error NotOwner();
error AddressZero();
error InvalidStartTime();
error InvalidBalance();
error InvalidDuration();
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

library StakingEvents {
    event Staked(address indexed user, uint256 timestamp, address bToken, uint256 amount);
    event Unstaked(address indexed user, uint256 timestamp, address bToken, uint256 amount);
}