// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

struct TestSettings {
    bool withdrawTokens;
    bool settleUsingTransfer;
}

struct LiquiditySettings {
    int24 tickToSet;
    bool zeroForOne;
    int256 requiredLiquidity;
}