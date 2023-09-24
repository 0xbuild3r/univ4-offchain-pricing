// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";  
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {TestERC20} from "@uniswap/v4-core/contracts/test/TestERC20.sol";
import {IERC20Minimal} from "@uniswap/v4-core/contracts/interfaces/external/IERC20Minimal.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolIdLibrary,PoolId} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";
import {PoolDonateTest} from "@uniswap/v4-core/contracts/test/PoolDonateTest.sol";
import {Deployers} from "@uniswap/v4-core/test/foundry-tests/utils/Deployers.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {OffchainPricing} from "../src/OffchainPricing.sol";
import {RouterSample} from "../src/RouterSample.sol";
import {OffchainPricingImplementation} from "../src/implementation/OffchainPricingImplementation.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {TestSettings, LiquiditySettings} from "../src/helpers/SwapTypes.sol";
import {Tick} from "../src/helpers/TickPriceConversion.sol";

contract OffchainPricingTest is Test, Deployers, GasSnapshot {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    //OffchainPricing hook;
    OffchainPricing hook =
        OffchainPricing(
            address(
                uint160(Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG)
            )
        );
    OffchainPricingImplementation impl;
    PoolManager manager;
    RouterSample router;
    TestERC20 _tokenA;
    TestERC20 _tokenB;
    TestERC20 token0;
    TestERC20 token1;
    PoolKey poolKey;
    PoolId poolId;

    function setUp() public {
        
        _tokenA = new TestERC20(2**128);
        _tokenB = new TestERC20(2**128);

        if (address(_tokenA) < address(_tokenB)) {
            token0 = _tokenA;
            token1 = _tokenB;
        } else {
            token0 = _tokenB;
            token1 = _tokenA;
        }
        
        manager = new PoolManager(500000);

        // testing environment requires our contract to override `validateHookAddress`
        // well do that via the Implementation contract to avoid deploying the override with the production contract
        
        impl = new OffchainPricingImplementation(manager, hook);
        
        (, bytes32[] memory writes) = vm.accesses(address(impl));
        
        vm.etch(address(hook), address(impl).code);
        // for each storage key that was written during the hook implementation, copy the value over
        unchecked {
            for (uint256 i = 0; i < writes.length; i++) {
                bytes32 slot = writes[i];
                vm.store(address(hook), slot, vm.load(address(impl), slot));
            }
        }
        
        // Create the pool with tick spacing 1, and no fee 
        // fees and profits will be earned through spread
        poolKey =
            PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 0, 1, IHooks(hook));
        poolId = poolKey.toId();
        manager.initialize(poolKey, SQRT_RATIO_1_1, new bytes(0));

        // Helpers for interacting with the pool
        router = new RouterSample(IPoolManager(address(manager)));

        // Provide liquidity to the pool
        //token0.approve(address(impl), 100 ether);
        //token1.approve(address(impl), 100 ether);
        token0.approve(address(hook), 10000 ether);
        token1.approve(address(hook), 10000 ether);
        token0.mint(address(this), 100000 ether);
        token1.mint(address(this), 100000 ether);
        
    
        // Approve for swapping
        token0.approve(address(router), 10000 ether);
        token1.approve(address(router), 10000 ether);

        hook.deposit(address(token0),10000 ether);
        hook.deposit(address(token1),10000 ether);
    }
    function test() public {
        impl.whitelist(address(router));
        int24 tick = Tick.priceToTick(uint256(1500));

        // configure inputs for the test
        PoolKey memory key = PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 0, 1, IHooks(hook));
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: 1e18,
                sqrtPriceLimitX96: TickMath.MAX_SQRT_RATIO - 1
            });
        TestSettings memory testSettings = TestSettings({
                withdrawTokens: true, 
                settleUsingTransfer: true
            });
        LiquiditySettings memory liquiditySettings = LiquiditySettings({
                tickToSet: tick, 
                zeroForOne: true,
                requiredLiquidity: 1e18
            });
        
        // swap request with inputs
        router.swap(key, params, testSettings, liquiditySettings);
    }

    
    // -- Allow the test contract to receive ERC1155 tokens -- //
    receive() external payable {}

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));
    }
}
