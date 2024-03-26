// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BlueberryStaking} from "../src/BlueberryStaking.sol";
import {BlueberryToken} from "../src/BlueberryToken.sol";
import {MockIbToken} from "./mocks/MockIbToken.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Control is Test {
    BlueberryStaking blueberryStaking;
    BlueberryToken blb;
    IERC20 mockIbToken1;
    IERC20 mockIbToken2;
    IERC20 mockIbToken3;

    IERC20 mockUSDC;

    address public treasury = makeAddr("treasury");
    address public owner = makeAddr("owner");

    address[] public existingIbTokens;

    // Initial reward duration
    uint256 public constant REWARD_DURATION = 1_209_600;

    // Initialize the contract and deploy necessary instances
    function setUp() public {
        vm.startPrank(owner);
        // Deploy mock tokens and BlueberryToken
        mockIbToken1 = new MockIbToken();
        mockIbToken2 = new MockIbToken();
        mockIbToken3 = new MockIbToken();
        mockUSDC = new MockUSDC();

        blb = new BlueberryToken(address(this), owner, block.timestamp);

        // Initialize existingIbTokens array
        existingIbTokens = new address[](3);

        // Assign addresses of mock tokens to existingIbTokens array
        existingIbTokens[0] = address(mockIbToken1);
        existingIbTokens[1] = address(mockIbToken2);
        existingIbTokens[2] = address(mockIbToken3);

        // Deploy BlueberryStaking contract and transfer BLB tokens
        blueberryStaking = new BlueberryStaking();

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(blueberryStaking),
            address(treasury),
            abi.encodeCall(
                BlueberryStaking.initialize,
                (
                    address(blb),
                    address(mockUSDC),
                    address(treasury),
                    REWARD_DURATION,
                    0.25e18,
                    existingIbTokens,
                    owner
                )
            )
        );

        blueberryStaking = BlueberryStaking(payable(address(proxy)));
        blb.approve(address(blueberryStaking), UINT256_MAX);

        skip(300);
        blb.mint(address(owner), 10_000_000e18);
    }

    // Test setting the reward duration
    function testSetRewardDuration() public {
        vm.startPrank(owner);
        blueberryStaking.setRewardDuration(5_318_008);
        assertEq(blueberryStaking.rewardDuration(), 5_318_008);
    }

    // Test adding new ibTokens to the contract
    function testaddIbTokens() public {
        vm.startPrank(owner);
        // Deploy new mock tokens
        IERC20 mockIbToken4 = new MockIbToken();
        IERC20 mockIbToken5 = new MockIbToken();
        IERC20 mockIbToken6 = new MockIbToken();

        uint256 rewardAmount = 100e18;
        uint256 expectedRewardPerToken = 100e18 / blueberryStaking.rewardDuration();

        // Create an array of addresses representing the new ibTokens
        address[] memory ibTokens = new address[](3);
        uint256[] memory rewardAmounts = new uint256[](3);

        ibTokens[0] = address(mockIbToken4);
        ibTokens[1] = address(mockIbToken5);
        ibTokens[2] = address(mockIbToken6);

        rewardAmounts[0] = rewardAmount;
        rewardAmounts[1] = rewardAmount;
        rewardAmounts[2] = rewardAmount;

        uint256 blbBalance = blb.balanceOf(address(blueberryStaking));

        // Add the new ibTokens to the BlueberryStaking contract and update the rewards
        blueberryStaking.addIbTokens(ibTokens, rewardAmounts);

        // Check if the proper amount of blb was transfered to the contract
        assertEq(blb.balanceOf(address(blueberryStaking)), blbBalance + (rewardAmount * 3));

        // Check if the new ibTokens were added successfully
        assertEq(blueberryStaking.isIbToken(address(mockIbToken4)), true);
        assertEq(blueberryStaking.isIbToken(address(mockIbToken5)), true);
        assertEq(blueberryStaking.isIbToken(address(mockIbToken6)), true);

        // Validate that the new tokens have reward amounts
        assertEq(blueberryStaking.rewardRate(address(mockIbToken4)), expectedRewardPerToken);
        assertEq(blueberryStaking.rewardRate(address(mockIbToken5)), expectedRewardPerToken);
        assertEq(blueberryStaking.rewardRate(address(mockIbToken6)), expectedRewardPerToken);

        // Skip to after the reward period for all active tokens and add a singlular token
        skip(1209602);

        MockIbToken mockIbToken7 = new MockIbToken();

        address[] memory ibTokens2 = new address[](1);
        ibTokens2[0] = address(mockIbToken7);

        uint256[] memory rewardAmounts2 = new uint256[](1);
        rewardAmounts2[0] = rewardAmount;

        // Validate that the balance of the BlueberryStaking contract is greater after adding the token
        uint256 balanceBefore = blb.balanceOf(address(blueberryStaking));
        blueberryStaking.addIbTokens(ibTokens2, rewardAmounts2);
        assertGt(blb.balanceOf(address(blueberryStaking)), balanceBefore);

        // Validate that the finishAt time for token1 was not updated after adding token7
        console2.log("token1 finishAt: ", blueberryStaking.finishAt(ibTokens[0]));
        console2.log("token7 finish: ", blueberryStaking.finishAt(ibTokens2[0]));
        assertTrue(blueberryStaking.finishAt(ibTokens[0]) != blueberryStaking.finishAt(ibTokens2[0]));
    }

    // Test pausing and unpausing the BlueberryStaking contract
    function testPausing() public {
        vm.startPrank(owner);
        // Pause the contract and verify the paused state
        blueberryStaking.pause();
        assertEq(blueberryStaking.paused(), true);

        // Unpause the contract and verify the resumed state
        blueberryStaking.unpause();
        assertEq(blueberryStaking.paused(), false);
    }

    // Test notifying reward amounts for existing ibTokens
    function testmodifyRewardAmount() public {
        // Set reward amounts for existing ibTokens
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1e19;
        amounts[1] = 1e19 * 4;
        amounts[2] = 1e23 * 4;

        blueberryStaking.modifyRewardAmount(existingIbTokens, amounts);

        // Check if the reward rates were set correctly
        assertEq(
            blueberryStaking.rewardRate(existingIbTokens[0]),
            1e19 / blueberryStaking.rewardDuration()
        );
        assertEq(
            blueberryStaking.rewardRate(existingIbTokens[1]),
            (1e19 * 4) / blueberryStaking.rewardDuration()
        );
        assertEq(
            blueberryStaking.rewardRate(existingIbTokens[2]),
            (1e23 * 4) / blueberryStaking.rewardDuration()
        );

        // Assert that the balance of the BlueberryStaking contract is equal to the sum of the reward amounts
        assertEq(blb.balanceOf(address(blueberryStaking)),(1e19 + (1e19 * 4) + (1e23 * 4)));
    }

    // Test changing the stable token address
    function testChangeStable() public {
        vm.startPrank(owner);

        // Deploy a new stable coin 
        MockToken token = new MockToken(9);
        
        // Change the stable token to be the mock token with 9 decimals instead of the original 6 decimal token
        blueberryStaking.setStableAsset(address(token));

        // Check that the stable token address was updated correctly
        assertEq(address(blueberryStaking.stableAsset()), address(token));
    }

    function testChangeRewardAmount() public {
        vm.startPrank(owner);

        uint256 rewardAmount = REWARD_DURATION * 1e18;
        // Set reward amounts for existing ibTokens
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = rewardAmount;
        amounts[1] = rewardAmount;
        amounts[2] = rewardAmount;

        // Set initial Reward Amounts
        blueberryStaking.modifyRewardAmount(existingIbTokens, amounts);

        uint256 length = existingIbTokens.length;
        for (uint256 i=0; i < length; ++i) {
            uint256 rewardRate = blueberryStaking.rewardRate(existingIbTokens[i]);
            assertEq(rewardRate, 1e18);
        }

        skip(7 days);

        // Add new Reward Amounts in the middle of reward period & expect the reward rate to increase 50%
        blueberryStaking.modifyRewardAmount(existingIbTokens, amounts);

        for (uint256 i=0; i < length; ++i) {
            uint256 rewardRate = blueberryStaking.rewardRate(existingIbTokens[i]);
            assertEq(rewardRate, 1.5e18);
        }
    }
}
