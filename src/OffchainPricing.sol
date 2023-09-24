// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ERC1155} from "solmate/tokens/ERC1155.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {BaseHook} from "v4-periphery/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";

import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {UniV4UserHook} from "./UniV4UserHook.sol";
//import {PoolIdLibrary, PoolId} from "./PoolIdLibrary.sol";
import {PoolIdLibrary, PoolId} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import {TestSettings, LiquiditySettings} from "./helpers/SwapTypes.sol";
/**
* @title OffchainPricing hooks for Uniswap V4
* @notice This implementation is purely for hackathon and not ready for production.
*/

contract OffchainPricing is UniV4UserHook, Test {
    using FixedPointMathLib for uint256;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    address admin;
    mapping(bytes32 poolId => int24 tickLower) public tickLowerLasts;
    mapping(bytes32 poolId => mapping(int24 tick => mapping(bool zeroForOne => int256 amount))) public stopLossPositions;
    mapping(address => bool) public isWhitelisted;

    // constants for sqrtPriceLimitX96 which allow for unlimited impact
    // (stop loss *should* market sell regardless of market depth 🥴)
    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_RATIO + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_RATIO - 1;

    modifier adminOnly() {
        require(msg.sender == admin, "only pool manager");
        _;
    }

    constructor(IPoolManager _poolManager) UniV4UserHook(_poolManager) {}

    function getHooksCalls() public pure override returns (Hooks.Calls memory) {
        return Hooks.Calls({
            beforeInitialize: false,
            afterInitialize: false,
            beforeModifyPosition: true,
            afterModifyPosition: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false
        });
    }

    function deposit(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    function beforeModifyPosition(
        address, 
        PoolKey calldata, 
        IPoolManager.ModifyPositionParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        require(msg.sender == address(poolManager), "position cannot be modified by anyone");
        return OffchainPricing.beforeModifyPosition.selector;
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata liquiditySettings
    ) external override returns (bytes4) {
        // only allow whitelisted addresses to call this function
        require(isWhitelisted[sender], "sender not whitelisted");

        // restore liquidity info from bytes calldata
        LiquiditySettings memory settings = bytesToLiquiditySettings(liquiditySettings);
        
        // Withdraw liquidity from lending protocol and deploy to pool
        // zeroForOne = true = sell token 0 for token 1, and vice versa
        if(settings.zeroForOne){
            withdrawFromLending(Currency.unwrap(key.currency0), settings.requiredLiquidity);
            modifyPosition(
                key, 
                IPoolManager.ModifyPositionParams({
                    tickLower: settings.tickToSet - key.tickSpacing,
                    tickUpper: settings.tickToSet,
                    liquidityDelta: settings.requiredLiquidity
                }),
                address(this)
            );
        } else {
            withdrawFromLending(Currency.unwrap(key.currency1), settings.requiredLiquidity);
            modifyPosition(
                key, 
                IPoolManager.ModifyPositionParams({
                    tickLower: settings.tickToSet,
                    tickUpper: settings.tickToSet + key.tickSpacing,
                    liquidityDelta: settings.requiredLiquidity
                }),
                address(this)
            );
        }
 
        return OffchainPricing.beforeSwap.selector;
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta,
        bytes calldata liquiditySettings
    ) external override returns (bytes4) {

        // Calculate the token amounts
        LiquiditySettings memory settings = bytesToLiquiditySettings(liquiditySettings);
        uint128 liquidity = poolManager.getLiquidity(key.toId());

        int24 tickLower;
        int24 tickUpper;
        if(settings.zeroForOne){
            tickLower = settings.tickToSet; 
            tickUpper = settings.tickToSet + key.tickSpacing;
        } else {
            tickLower = settings.tickToSet - key.tickSpacing;
            tickUpper = settings.tickToSet;
        }
        
        uint160 sqrtPriceLower = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        //withdraw liquidity and deposit to lending protocol
        if(settings.zeroForOne){
            withdrawFromLending(Currency.unwrap(key.currency0), settings.requiredLiquidity);
            modifyPosition(
                key, 
                IPoolManager.ModifyPositionParams({
                    tickLower: settings.tickToSet - key.tickSpacing,
                    tickUpper: settings.tickToSet,
                    liquidityDelta: int128(liquidity)
                }),
                address(this)
            );
        } else {
            withdrawFromLending(Currency.unwrap(key.currency1), settings.requiredLiquidity);
            modifyPosition(
                key, 
                IPoolManager.ModifyPositionParams({
                    tickLower: settings.tickToSet,
                    tickUpper: settings.tickToSet + key.tickSpacing,
                    liquidityDelta: int128(liquidity)
                }),
                address(this)
            );
        }

        depositToLending(Currency.unwrap(key.currency0));
        depositToLending(Currency.unwrap(key.currency1));
        
        return OffchainPricing.afterSwap.selector;
    }
    // -- lending interaction -- //

    function depositToLending(address token) internal {
        // do something here (out of scope for this hackathon)
    }

    function withdrawFromLending(address token, int amount) internal {
        // do something here (out of scope for this hackathon)
    }

    // -- admin functions -- //
    function whitelist(address executor) external adminOnly {
        isWhitelisted[executor] = true;
    }

    function setAdmin(address adminAddress) external {
        require(admin == address(0), "admin already set");
        admin = adminAddress;
    }
    
    function bytesToLiquiditySettings(bytes memory encodedSettings) public pure returns (LiquiditySettings memory) {
        require(encodedSettings.length == 36, "Invalid encodedSettings length");
        
        int24 tickToSet;
        bool zeroForOne;
        int256 requiredLiquidity;
                
        // Decode int24
        int256 decodedTick = (int256(uint256(uint8(encodedSettings[0]))) << 16) |
                            (int256(uint256(uint8(encodedSettings[1]))) << 8) |
                            int256(uint256(uint8(encodedSettings[2])));

        // Check if the sign bit is set (23rd bit from the right, 0-indexed)
        if (decodedTick & (1 << 23) != 0) {
            // If the sign bit is set, adjust the value to make it negative
            decodedTick = decodedTick - (1 << 24);
        }

        // Cast the result back to int24
        tickToSet = int24(decodedTick);

        // Decode bool
        zeroForOne = encodedSettings[3] != bytes1(0x00);
        
        // Decode uint256
        uint256 magnitude = 0;
        for (uint256 i = 0; i < 32; i++) {
            magnitude |= uint256(uint8(encodedSettings[i + 4])) << (8 * (31 - i));
        }
        // Determine the sign of requiredLiquidity
        requiredLiquidity = magnitude & (1 << 255) != 0 ? -int256(magnitude) : int256(magnitude);
        
        return LiquiditySettings({
            tickToSet: tickToSet,
            zeroForOne: zeroForOne,
            requiredLiquidity: requiredLiquidity
        });
    }
    
}
