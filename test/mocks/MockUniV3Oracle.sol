// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import "v3-core/libraries/TickMath.sol";
import "v3-core/libraries/FullMath.sol";
import "v3-core/libraries/FixedPoint96.sol";

contract MockUniV3Oracle {

    address public pool;
    address public token0;
    address public token1;
    uint32 observationPeriod;
    bool public targetIsToken0;

    /// @notice The denominator for the Uniswap pricing calculations
    uint256 private constant UNISWAP_PRICING_DENOMINATOR = 2 ** 96;

    function setPool(
        address _pool,
        uint32 _observationPeriod,
        address _targetToken
    ) public {
        pool = _pool;
        token0 = IUniswapV3Pool(_pool).token0();
        token1 = IUniswapV3Pool(_pool).token1();
        observationPeriod = _observationPeriod;
        targetIsToken0 = _targetToken == token0;
    }

    function getPrice() public view returns (uint256) {
        IUniswapV3Pool _pool = IUniswapV3Pool(pool);

        uint32[] memory _secondsArray = new uint32[](2);

        _secondsArray[0] = observationPeriod;
        _secondsArray[1] = 0;

        (int56[] memory tickCumulatives, ) = _pool.observe(_secondsArray);

        int56 _tickDifference = tickCumulatives[1] - tickCumulatives[0];
        int56 _timeDifference = int32(observationPeriod);

        int24 _twapTick = int24(_tickDifference / _timeDifference);

        uint160 _sqrtPriceX96 = TickMath.getSqrtRatioAtTick(_twapTick);

        // Decode the square root price
        uint256 _priceX96 = FullMath.mulDiv(
            _sqrtPriceX96,
            _sqrtPriceX96,
            FixedPoint96.Q96
        );

        uint256 token0Decimals = ERC20(token0).decimals();
        uint256 token1Decimals = ERC20(token1).decimals();

        if (targetIsToken0) {
            return
                FullMath.mulDiv(_priceX96, 10**(18 + token0Decimals - token1Decimals), UNISWAP_PRICING_DENOMINATOR);
        } else {
            uint256 inversePrice = FullMath.mulDiv(
                _priceX96,
                10**(18 - token1Decimals + token0Decimals),
                UNISWAP_PRICING_DENOMINATOR
            );
            return 10 ** 36 / inversePrice;
        }
    }
}