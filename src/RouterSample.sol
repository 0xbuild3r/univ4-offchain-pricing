// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {IERC20Minimal} from "@uniswap/v4-core/contracts/interfaces/external/IERC20Minimal.sol";

import {ILockCallback} from "@uniswap/v4-core/contracts/interfaces/callback/ILockCallback.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {TestSettings, LiquiditySettings} from "./helpers/SwapTypes.sol";
import "forge-std/console.sol";  

contract RouterSample is ILockCallback {
    using CurrencyLibrary for Currency;

    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        address sender;
        TestSettings testSettings;
        PoolKey key;
        IPoolManager.SwapParams params;
        LiquiditySettings liquiditySettings;
    }



    function swap(
        PoolKey memory key,
        IPoolManager.SwapParams memory params, 
        TestSettings memory testSettings,
        LiquiditySettings memory liquiditySettings
    )
        external
        payable
        returns (BalanceDelta delta)
    {
        delta =
            abi.decode(manager.lock(abi.encode(CallbackData(msg.sender, testSettings, key, params, liquiditySettings))), (BalanceDelta));

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = manager.swap(data.key, data.params, encodeLiquiditySettings(data.liquiditySettings));

        if (data.params.zeroForOne) {
            if (delta.amount0() > 0) {
                if (data.testSettings.settleUsingTransfer) {
                    if (data.key.currency0.isNative()) {
                        manager.settle{value: uint128(delta.amount0())}(data.key.currency0);
                    } else {
                        IERC20Minimal(Currency.unwrap(data.key.currency0)).transferFrom(
                            data.sender, address(manager), uint128(delta.amount0())
                        );
                        manager.settle(data.key.currency0);
                    }
                } else {
                    // the received hook on this transfer will burn the tokens
                    manager.safeTransferFrom(
                        data.sender,
                        address(manager),
                        uint256(uint160(Currency.unwrap(data.key.currency0))),
                        uint128(delta.amount0()),
                        ""
                    );
                }
            }
            if (delta.amount1() < 0) {
                if (data.testSettings.withdrawTokens) {
                    manager.take(data.key.currency1, data.sender, uint128(-delta.amount1()));
                } else {
                    manager.mint(data.key.currency1, data.sender, uint128(-delta.amount1()));
                }
            }
        } else {
            if (delta.amount1() > 0) {
                if (data.testSettings.settleUsingTransfer) {
                    if (data.key.currency1.isNative()) {
                        manager.settle{value: uint128(delta.amount1())}(data.key.currency1);
                    } else {
                        IERC20Minimal(Currency.unwrap(data.key.currency1)).transferFrom(
                            data.sender, address(manager), uint128(delta.amount1())
                        );
                        manager.settle(data.key.currency1);
                    }
                } else {
                    // the received hook on this transfer will burn the tokens
                    manager.safeTransferFrom(
                        data.sender,
                        address(manager),
                        uint256(uint160(Currency.unwrap(data.key.currency1))),
                        uint128(delta.amount1()),
                        ""
                    );
                }
            }
            if (delta.amount0() < 0) {
                if (data.testSettings.withdrawTokens) {
                    manager.take(data.key.currency0, data.sender, uint128(-delta.amount0()));
                } else {
                    manager.mint(data.key.currency0, data.sender, uint128(-delta.amount0()));
                }
            }
        }

        return abi.encode(delta);
    }

    function encodeLiquiditySettings(LiquiditySettings memory settings) internal  returns (bytes memory) {
        bytes memory result = new bytes(32 + 1 + 3); // 32 bytes for uint256, 1 byte for bool, 3 bytes for int24

        // Encode int24
        result[0] = bytes1((uint8(uint24(settings.tickToSet) >> 16) & 0xFF));
        result[1] = bytes1((uint8(uint24(settings.tickToSet) >> 8) & 0xFF));
        result[2] = bytes1((uint8(uint24(settings.tickToSet)) & 0xFF));

        // Encode bool
        result[3] = settings.zeroForOne ? bytes1(0x01) : bytes1(0x00);

        // Encode uint256
        for (uint256 i = 0; i < 32; i++) {
            result[i + 4] = bytes1((uint8(uint256(settings.requiredLiquidity) >> (8 * (31 - i))) & 0xFF));
        }
        return result;
    }

}
