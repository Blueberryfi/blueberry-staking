// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {MockUniV3Oracle} from "./mocks/MockUniV3Oracle.sol";

contract Control is Test {

    uint256 mainnetFork;
    MockUniV3Oracle mockUniV3Oracle;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        mockUniV3Oracle = new MockUniV3Oracle();
    }

    /// Test get price when WETH is the target token and token0
    function testGetPriceToken0() public {
        mockUniV3Oracle.setPool(
            0x11b815efB8f581194ae79006d24E0d814B7697F6,
            3600,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        );
        console2.log("Price: %s", mockUniV3Oracle.getPrice());
        assertGt(mockUniV3Oracle.getPrice(), 2800e18);
        assertLt(mockUniV3Oracle.getPrice(), 3500e18);
    }

    /// Test get price when WETH is the target token and token1
    function testGetPriceToken1() public {
        mockUniV3Oracle.setPool(
            0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640,
            3600,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        );
        console2.log("Price: %s", mockUniV3Oracle.getPrice());
        assertGt(mockUniV3Oracle.getPrice(), 2800e18);
        assertLt(mockUniV3Oracle.getPrice(), 3500e18);
    }
}