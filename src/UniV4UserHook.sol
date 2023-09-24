// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {IERC20Minimal} from "@uniswap/v4-core/contracts/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {BaseHook} from "v4-periphery/BaseHook.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "forge-std/console.sol";  

abstract contract UniV4UserHook is BaseHook {
    using CurrencyLibrary for Currency;

    constructor(IPoolManager _manager) BaseHook(_manager) {}


    function modifyPosition(
        PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params,
        address caller
    ) internal returns (BalanceDelta delta) {
        delta = abi.decode(
            poolManager.lock(abi.encodeCall(this.handleModifyPosition, (key, params, caller))), (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(caller, ethBalance);
        }
    }

    function handleModifyPosition(
        PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params,
        address caller
    ) external returns (BalanceDelta delta) {
        //console.log(address(this));
        delta = poolManager.modifyPosition(key, params, new bytes(0));
        if (delta.amount0() > 0) {
            if (key.currency0.isNative()) {
                poolManager.settle{value: uint128(delta.amount0())}(key.currency0);
            } else {
                IERC20Minimal(Currency.unwrap(key.currency0)).transfer(
                    address(poolManager), uint128(delta.amount0())
                );
                poolManager.settle(key.currency0);
            }
        }
        if (delta.amount1() > 0) {
            if (key.currency1.isNative()) {
                poolManager.settle{value: uint128(delta.amount1())}(key.currency1);
            } else {
                IERC20Minimal(Currency.unwrap(key.currency1)).transfer(
                    address(poolManager), uint128(delta.amount1())
                );
                poolManager.settle(key.currency1);
            }
        }

        if (delta.amount0() < 0) {
            poolManager.take(key.currency0, caller, uint128(-delta.amount0()));
        }
        if (delta.amount1() < 0) {
            poolManager.take(key.currency1, caller, uint128(-delta.amount1()));
        }
    }
}
