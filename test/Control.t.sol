// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../lib/forge-std/src/Test.sol";
import "../src/BlueberryStaking.sol";
import "../src/BlueberryToken.sol";
import "../src/MockbToken.sol";
import "../src/MockUSDC.sol";

contract Control is Test {
    BlueberryStaking blueberryStaking;
    BlueberryToken blb;
    IERC20 mockbToken1;
    IERC20 mockbToken2;
    IERC20 mockbToken3;

    IERC20 mockUSDC;

    address public treasury = address(0x1);

    address[] public existingBTokens;
    
    // Initialize the contract and deploy necessary instances
    function setUp() public {
        // Deploy mock tokens and BlueberryToken
        mockbToken1 = new MockbToken();
        mockbToken2 = new MockbToken();
        mockbToken3 = new MockbToken();
        mockUSDC = new MockUSDC();
        blb = new BlueberryToken(address(this), address(this), block.timestamp + 30);

        // Initialize existingBTokens array
        existingBTokens = new address[](3);

        // Assign addresses of mock tokens to existingBTokens array
        existingBTokens[0] = address(mockbToken1);
        existingBTokens[1] = address(mockbToken2);
        existingBTokens[2] = address(mockbToken3);

        // Deploy BlueberryStaking contract and transfer BLB tokens
        blueberryStaking = new BlueberryStaking(address(blb), address(mockUSDC), address(treasury), 1_209_600, existingBTokens);
        blb.transfer(address(blueberryStaking), 1e27);
    }

    // Test setting the vesting length
    function testSetVestLength() public {
        blueberryStaking.setVestLength(69_420);
        assertEq(blueberryStaking.vestLength(), 69_420);
    }

    // Test setting the reward duration
    function testSetRewardDuration() public {
        blueberryStaking.setRewardDuration(5_318_008);
        assertEq(blueberryStaking.rewardDuration(), 5_318_008);
    }

    // Test adding new bTokens to the contract
    function testAddBTokens() public {
        // Deploy new mock tokens
        IERC20 mockbToken4 = new MockbToken();
        IERC20 mockbToken5 = new MockbToken();
        IERC20 mockbToken6 = new MockbToken();

        // Create an array of addresses representing the new bTokens
        address[] memory bTokens = new address[](3);
        bTokens[0] = address(mockbToken4);
        bTokens[1] = address(mockbToken5);
        bTokens[2] = address(mockbToken6);

        // Add the new bTokens to the BlueberryStaking contract
        blueberryStaking.addBTokens(bTokens);

        // Check if the new bTokens were added successfully
        assertEq(blueberryStaking.isBToken(address(mockbToken4)), true);
        assertEq(blueberryStaking.isBToken(address(mockbToken5)), true);
        assertEq(blueberryStaking.isBToken(address(mockbToken6)), true);
    }

    // Test removing existing bTokens from the contract
    function testRemoveBTokens() public {
        // Check if existing bTokens are initially present
        assertEq(blueberryStaking.isBToken(address(existingBTokens[0])), true);
        assertEq(blueberryStaking.isBToken(address(existingBTokens[1])), true);
        assertEq(blueberryStaking.isBToken(address(existingBTokens[2])), true);

        // Remove existing bTokens from the BlueberryStaking contract
        blueberryStaking.removeBTokens(existingBTokens);

        // Check if existing bTokens were removed successfully
        assertEq(blueberryStaking.isBToken(address(existingBTokens[0])), false);
        assertEq(blueberryStaking.isBToken(address(existingBTokens[1])), false);
        assertEq(blueberryStaking.isBToken(address(existingBTokens[2])), false);
    }

    // Test pausing and unpausing the BlueberryStaking contract
    function testPausing() public {
        // Pause the contract and verify the paused state
        blueberryStaking.pause();
        assertEq(blueberryStaking.paused(), true);

        // Unpause the contract and verify the resumed state
        blueberryStaking.unpause();
        assertEq(blueberryStaking.paused(), false);
    }

    // Test notifying reward amounts for existing bTokens
    function testNotifyRewardAmount() public {
        // Set reward amounts for existing bTokens
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1e19;
        amounts[1] = 1e19 * 4;
        amounts[2] = 1e23 * 4;
        blueberryStaking.notifyRewardAmount(existingBTokens, amounts);

        // Check if the reward rates were set correctly
        assertEq(blueberryStaking.rewardRate(existingBTokens[0]), 1e19 / blueberryStaking.rewardDuration());
        assertEq(blueberryStaking.rewardRate(existingBTokens[1]), 1e19 * 4 / blueberryStaking.rewardDuration());
        assertEq(blueberryStaking.rewardRate(existingBTokens[2]), 1e23 * 4 / blueberryStaking.rewardDuration());
    }

    // Test changing the epoch length
    function testChangeEpochLength() public {
        // Change the epoch length and verify the updated value
        blueberryStaking.changeEpochLength(70_420_248_412);
        assertEq(blueberryStaking.epochLength(), 70_420_248_412);
    }

    // Test changing the BLB token address
    function testChangeBLB() public {
        // Deploy a new BLB token
        BlueberryToken newBLB = new BlueberryToken(address(this), address(this), block.timestamp + 30);

        // Change the BLB token address to the new BLB contract
        blueberryStaking.changeBLB(address(newBLB));

        // Check if the BLB token address was updated correctly
        assertEq(blueberryStaking.getBLB(), address(newBLB));
    }
}
