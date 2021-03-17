
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;


import "./openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin/contracts/math/SafeMath.sol";

import "./library/SafeDecimal.sol";
import "./library/OwnableWithKeeper.sol";
import "./interfaces/IMasterChef.sol";
import "./interfaces/IMdxPair.sol";
import "./interfaces/IMdxFactory.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IWallabyMinter.sol";
import "./vaults/WallabyPool.sol";
import "./vaults/WallabyHTPool.sol";
import "./vaults/legacy/StrategyCompoundFLIP.sol";
import "./vaults/legacy/StrategyCompoundMdx.sol";
import "./vaults/legacy/MdxFlipVault.sol";
import "./vaults/VaultFlipToMdx.sol";
import {PoolConstant} from "./library/PoolConstant.sol";

/*
____    __    ____  ___       __       __          ___      .______   ____    ____ 
\   \  /  \  /   / /   \     |  |     |  |        /   \     |   _  \  \   \  /   / 
 \   \/    \/   / /  ^  \    |  |     |  |       /  ^  \    |  |_)  |  \   \/   /  
  \            / /  /_\  \   |  |     |  |      /  /_\  \   |   _  <    \_    _/   
   \    /\    / /  _____  \  |  `----.|  `----./  _____  \  |  |_)  |     |  |     
    \__/  \__/ /__/     \__\ |_______||_______/__/     \__\ |______/      |__|     

*
* MIT License
* ===========
*
* Copyright (c) 2020 WallabyFinance
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/   
contract Dashboard is OwnableWithKeeper {
    using SafeMath for uint;
    using SafeDecimal for uint;

    uint private constant BLOCK_PER_YEAR = 10512000;

    IERC20 private constant WHT = IERC20(0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F);
    IERC20 private constant HUSD = IERC20(0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047);
    IERC20 private constant Mdx = IERC20(0x25D2e80cB6B86881Fd7e07dd263Fb79f4AbE033c);
    IERC20 private constant Wallaby = IERC20(0x793CF59D2C4586D599165ca86Cc96c1B405d34C4);

    address private constant HT_HUSD_POOL = 0x3375afF2CAcF683b8FC34807B9443EB32e7Afff6;
    IMasterChef private constant master = IMasterChef(0xFB03e11D93632D97a8981158A632Dd5986F5E909);
    IMdxFactory private constant factory = IMdxFactory(0xb0b670fc1F7724119963018DB0BfA86aDb22d941);

    WallabyPool private constant wallabyPool = WallabyPool(0xf3A05A2668cd78f305C68DdcfF4BB96F8093Bb97);
    WallabyHTPool private constant wallabyHTPool = WallabyHTPool(0x43919D31506e351B80C0117eDFcEDbE5acaACC28);

    IWallabyMinter private constant wallabyMinter = IWallabyMinter(0x7A631cAa46a451E1844f83114cd74CD1DE07D86F);
    mapping(address => address) private pairAddresses;
    mapping(address => PoolConstant.PoolTypes) private poolTypes;
    mapping(address => uint) private poolIds;
    mapping(address => bool) private legacyPools;
    mapping(address => address) private linkedPools;

    /* ========== Restricted Operation ========== */

    function setPairAddress(address asset, address pair) external onlyAuthorized {
        pairAddresses[asset] = pair;
    }

    function setPoolType(address pool, PoolConstant.PoolTypes poolType) external onlyAuthorized {
        poolTypes[pool] = poolType;
    }

    function setPoolId(address pool, uint pid) external onlyAuthorized {
        poolIds[pool] = pid;
    }

    function setLegacyPool(address pool, bool legacy) external onlyAuthorized {
        legacyPools[pool] = legacy;
    }

    function setLinkedPool(address pool, address linked) external onlyAuthorized {
        linkedPools[pool] = linked;
    }

    /* ========== Value Calculation ========== */

    function priceOfHT() view public returns (uint) {
        return HUSD.balanceOf(HT_HUSD_POOL).mul(1e28).div(WHT.balanceOf(HT_HUSD_POOL));
    }

    function priceOfwallaby() view public returns (uint) {
        (, uint wallabyPriceInUSD) = valueOfAsset(address(Wallaby), 1e18);
        return wallabyPriceInUSD;
    }

    function valueOfAsset(address asset, uint amount) public view returns (uint valueInHT, uint valueInUSD) {
        if (asset == address(0) || asset == address(WHT)) {
            valueInHT = amount;
            valueInUSD = amount.mul(priceOfHT()).div(1e18);
        } else if (keccak256(abi.encodePacked(IMdxPair(asset).symbol())) == keccak256("HMDX")) {
            if (IMdxPair(asset).token0() == address(WHT) || IMdxPair(asset).token1() == address(WHT)) {
                valueInHT = amount.mul(WHT.balanceOf(address(asset))).mul(2).div(IMdxPair(asset).totalSupply());
                valueInUSD = valueInHT.mul(priceOfHT()).div(1e18);
            } else {
                uint balanceToken0 = IERC20(IMdxPair(asset).token0()).balanceOf(asset);
                (uint token0PriceInHT,) = valueOfAsset(IMdxPair(asset).token0(), 1e18);

                valueInHT = amount.mul(balanceToken0).mul(2).mul(token0PriceInHT).div(1e18).div(IMdxPair(asset).totalSupply());
                valueInUSD = valueInHT.mul(priceOfHT()).div(1e18);
            }
        } else {
            address pairAddress = pairAddresses[asset];
            if (pairAddress == address(0)) {
                pairAddress = address(WHT);
            }

            address pair = factory.getPair(asset, pairAddress);
            valueInHT = IERC20(pairAddress).balanceOf(pair).mul(amount).div(IERC20(asset).balanceOf(pair));
            if (pairAddress != address(WHT)) {
                (uint pairValueInHT,) = valueOfAsset(pairAddress, 1e18);
                valueInHT = valueInHT.mul(pairValueInHT).div(1e18);
            }
            valueInUSD = valueInHT.mul(priceOfHT()).div(1e18);
        }
    }

    /* ========== APY Calculation ========== */

    function basicCompound(uint pid, uint compound) private view returns (uint) {
        (address token, uint allocPoint,,) = master.poolInfo(pid);
        (uint valueInHT,) = valueOfAsset(token, IERC20(token).balanceOf(address(master)));

        (uint mdxPriceInHT,) = valueOfAsset(address(Mdx), 1e18);
        uint mdxPerYearOfPool = master.mdxPerBlock().mul(BLOCK_PER_YEAR).mul(allocPoint).div(master.totalAllocPoint());
        uint apr = mdxPriceInHT.mul(mdxPerYearOfPool).div(valueInHT);
        return apr.div(compound).add(1e18).power(compound).sub(1e18);
    }

    function compoundingAPY(uint pid, uint compound, PoolConstant.PoolTypes poolType) private view returns (uint) {
        if (poolType == PoolConstant.PoolTypes.wallabyStake) {
            (uint wallabyPriceInHT,) = valueOfAsset(address(Wallaby), 1e18);
            (uint rewardsPriceInHT,) = valueOfAsset(address(wallabyPool.rewardsToken()), 1e18);

            uint poolSize = wallabyPool.totalSupply();
            if (poolSize == 0) {
                poolSize = 1e18;
            }

            uint rewardsOfYear = wallabyPool.rewardRate().mul(1e18).div(poolSize).mul(365 days);
            return rewardsOfYear.mul(rewardsPriceInHT).div(wallabyPriceInHT);
        } else if (poolType == PoolConstant.PoolTypes.wallabyFlip) {
            (uint flipPriceInHT,) = valueOfAsset(address(wallabyHTPool.token()), 1e18);
            (uint wallabyPriceInHT,) = valueOfAsset(address(Wallaby), 1e18);

            IWallabyMinter minter = IWallabyMinter(address(wallabyHTPool.minter()));
            uint mintPerYear = minter.amountwallabyToMintForwallabyHT(1e18, 365 days);
            return mintPerYear.mul(wallabyPriceInHT).div(flipPriceInHT);
        } else if (poolType == PoolConstant.PoolTypes.mdxStake || poolType == PoolConstant.PoolTypes.FlipToFlip) {
            return basicCompound(pid, compound);
        } else if (poolType == PoolConstant.PoolTypes.FlipTomdx) {
            // https://en.wikipedia.org/wiki/Geometric_series
            uint dailyApyOfPool = basicCompound(pid, 1).div(compound);
            uint dailyApyOfmdx = basicCompound(0, 1).div(compound);
            uint mdxAPY = basicCompound(0, 365);
            return dailyApyOfPool.mul(mdxAPY).div(dailyApyOfmdx);
        }
        return 0;
    }

    function apyOfPool(address pool, uint compound) public view returns (uint apyPool, uint apywallaby) {
        PoolConstant.PoolTypes poolType = poolTypes[pool];
        uint _apy = compoundingAPY(poolIds[pool], compound, poolType);
        apyPool = _apy;
        apywallaby = 0;

        if (poolType == PoolConstant.PoolTypes.wallabyStake || poolType == PoolConstant.PoolTypes.wallabyFlip) {

        } else {
            if (legacyPools[pool]) {
                IWallabyMinter minter = wallabyMinter;
                if (minter.isMinter(pool)) {
                    uint compounding = _apy.mul(70).div(100);
                    uint inflation = priceOfwallaby().mul(1e18).div(priceOfHT().mul(1e18).div(minter.wallabyPerProfitHT()));
                    uint wallabyIncentive = _apy.mul(30).div(100).mul(inflation).div(1e18);

                    apyPool = compounding;
                    apywallaby = wallabyIncentive;
                }
            } else {
                IStrategy strategy = IStrategy(pool);
                if (strategy.minter() != address(0)) {
                    uint compounding = _apy.mul(70).div(100);
                    uint inflation = priceOfwallaby().mul(1e18).div(priceOfHT().mul(1e18).div(IWallabyMinter(strategy.minter()).wallabyPerProfitHT()));
                    uint wallabyIncentive = _apy.mul(30).div(100).mul(inflation).div(1e18);

                    apyPool = compounding;
                    apywallaby = wallabyIncentive;
                }
            }
        }
    }

    /* ========== Profit Calculation ========== */

    function profitOfPool_legacy(address pool, address account) public view returns (uint usd, uint HT, uint wallaby, uint mdx) {
        usd = 0;
        HT = 0;
        wallaby = 0;
        mdx = 0;

        if (poolTypes[pool] == PoolConstant.PoolTypes.wallabyStake) {
            (uint profitInHT,) = valueOfAsset(address(wallabyPool.rewardsToken()), wallabyPool.earned(account));
            HT = profitInHT;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.wallabyFlip) {
            IWallabyMinter minter = wallabyHTPool.minter();
            if (address(minter) != address(0) && minter.isMinter(pool)) {
                wallaby = minter.amountwallabyToMintForwallabyHT(wallabyHTPool.balanceOf(account), block.timestamp.sub(wallabyHTPool.depositedAt(account)));
            }
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.mdxStake) {
            StrategyCompoundMdx strategyCompoundmdx = StrategyCompoundMdx(pool);
            if (strategyCompoundmdx.balanceOf(account) > strategyCompoundmdx.principalOf(account)) {
                (, uint mdxInUSD) = valueOfAsset(address(Mdx), strategyCompoundmdx.balanceOf(account).sub(strategyCompoundmdx.principalOf(account)));

                IWallabyMinter minter = strategyCompoundmdx.minter();
                if (address(minter) != address(0) && minter.isMinter(pool)) {
                    uint performanceFee = minter.performanceFee(mdxInUSD);
                    uint performanceFeeInHT = performanceFee.mul(1e18).div(priceOfHT());
                    usd = mdxInUSD.sub(performanceFee);
                    wallaby = minter.amountwallabyToMint(performanceFeeInHT);
                } else {
                    usd = mdxInUSD;
                }
            }
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.FlipToFlip) {
            StrategyCompoundFLIP strategyCompoundFlip = StrategyCompoundFLIP(pool);
            if (strategyCompoundFlip.balanceOf(account) > strategyCompoundFlip.principalOf(account)) {
                (, uint flipInUSD) = valueOfAsset(address(strategyCompoundFlip.token()), strategyCompoundFlip.balanceOf(account).sub(strategyCompoundFlip.principalOf(account)));

                IWallabyMinter minter = strategyCompoundFlip.minter();
                if (address(minter) != address(0) && minter.isMinter(pool)) {
                    uint performanceFee = minter.performanceFee(flipInUSD);
                    uint performanceFeeInHT = performanceFee.mul(1e18).div(priceOfHT());
                    usd = flipInUSD.sub(performanceFee);
                    wallaby = minter.amountwallabyToMint(performanceFeeInHT);
                } else {
                    usd = flipInUSD;
                }
            }
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.FlipTomdx) {
            MdxFlipVault flipVault = MdxFlipVault(pool);
            uint profitInmdx = flipVault.earned(account).mul(flipVault.rewardsToken().priceShare()).div(1e18);

            IWallabyMinter minter = flipVault.minter();
            if (address(minter) != address(0) && minter.isMinter(pool)) {
                uint performanceFeeInmdx = minter.performanceFee(profitInmdx);
                (uint performanceFeeInHT,) = valueOfAsset(address(Mdx), performanceFeeInmdx);
                mdx = profitInmdx.sub(performanceFeeInmdx);
                wallaby = minter.amountwallabyToMint(performanceFeeInHT);
            } else {
                mdx = profitInmdx;
            }
        }
    }

    function profitOfPool_v2(address pool, address account) public view returns (uint usd, uint HT, uint wallaby, uint mdx) {
        usd = 0;
        HT = 0;
        wallaby = 0;
        mdx = 0;

        if (poolTypes[pool] == PoolConstant.PoolTypes.wallabyStake) {
            (uint profitInHT,) = valueOfAsset(address(wallabyPool.rewardsToken()), wallabyPool.earned(account));
            HT = profitInHT;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.wallabyFlip) {
            IWallabyMinter minter = wallabyHTPool.minter();
            if (address(minter) != address(0) && minter.isMinter(pool)) {
                wallaby = minter.amountwallabyToMintForwallabyHT(wallabyHTPool.balanceOf(account), block.timestamp.sub(wallabyHTPool.depositedAt(account)));
            }
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.mdxStake || poolTypes[pool] == PoolConstant.PoolTypes.FlipToFlip) {
            IStrategy strategy = IStrategy(pool);
            if (strategy.earned(account) > 0) {
                (, uint profitInUSD) = valueOfAsset(strategy.stakingToken(), strategy.balanceOf(account).sub(strategy.principalOf(account)));
                if (strategy.minter() != address(0)) {
                    IWallabyMinter minter = IWallabyMinter(strategy.minter());
                    uint performanceFee = minter.performanceFee(profitInUSD);
                    uint performanceFeeInHT = performanceFee.mul(1e18).div(priceOfHT());
                    usd = profitInUSD.sub(performanceFee);
                    wallaby = minter.amountwallabyToMint(performanceFeeInHT);
                } else {
                    usd = profitInUSD;
                }
            }
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.FlipTomdx) {
            IStrategy strategy = IStrategy(pool);
            if (strategy.earned(account) > 0) {
                uint profitInmdx = strategy.earned(account).mul(IStrategy(strategy.rewardsToken()).priceShare()).div(1e18);
                if (strategy.minter() != address(0)) {
                    IWallabyMinter minter = IWallabyMinter(strategy.minter());
                    uint performanceFeeInmdx = minter.performanceFee(profitInmdx);
                    (uint performanceFeeInHT,) = valueOfAsset(address(Mdx), performanceFeeInmdx);
                    mdx = profitInmdx.sub(performanceFeeInmdx);
                    wallaby = minter.amountwallabyToMint(performanceFeeInHT);
                } else {
                    mdx = profitInmdx;
                }
            }
        }
    }

    function profitOfPool(address pool, address account) public view returns (uint usd, uint HT, uint wallaby, uint mdx) {
        return legacyPools[pool] ? profitOfPool_legacy(pool, account) : profitOfPool_v2(pool, account);
    }

    /* ========== TVL Calculation ========== */

    function tvlOfPool_legacy(address pool) public view returns (uint) {
        if (pool == address(0)) {
            return 0;
        }

        if (poolTypes[pool] == PoolConstant.PoolTypes.wallabyStake) {
            (, uint tvlInUSD) = valueOfAsset(address(wallabyPool.stakingToken()), wallabyPool.balance());
            return tvlInUSD;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.wallabyFlip) {
            (, uint tvlInUSD) = valueOfAsset(address(wallabyHTPool.token()), wallabyHTPool.balance());
            return tvlInUSD;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.mdxStake) {
            (, uint tvlInUSD) = valueOfAsset(address(Mdx), IStrategyLegacy(pool).balance());
            return tvlInUSD;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.FlipToFlip) {
            StrategyCompoundFLIP strategyCompoundFlip = StrategyCompoundFLIP(pool);

            (, uint tvlInUSD) = valueOfAsset(address(strategyCompoundFlip.token()), strategyCompoundFlip.balance());
            return tvlInUSD;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.FlipTomdx) {
            MdxFlipVault flipVault = MdxFlipVault(pool);
            IStrategy rewardsToken = IStrategy(address(flipVault.rewardsToken()));

            (, uint tvlInUSD) = valueOfAsset(address(flipVault.stakingToken()), flipVault.totalSupply());

            uint rewardsInmdx = rewardsToken.balanceOf(pool).mul(rewardsToken.priceShare()).div(1e18);
            (, uint rewardsInUSD) = valueOfAsset(address(Mdx), rewardsInmdx);
            return tvlInUSD.add(rewardsInUSD);
        }
        return 0;
    }

    function tvlOfPool_v2(address pool) public view returns (uint) {
        if (pool == address(0)) {
            return 0;
        }

        if (poolTypes[pool] == PoolConstant.PoolTypes.wallabyStake) {
            (, uint tvlInUSD) = valueOfAsset(address(wallabyPool.stakingToken()), wallabyPool.balance());
            return tvlInUSD;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.wallabyFlip) {
            (, uint tvlInUSD) = valueOfAsset(address(wallabyHTPool.token()), wallabyHTPool.balance());
            return tvlInUSD;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.mdxStake || poolTypes[pool] == PoolConstant.PoolTypes.FlipToFlip) {
            IStrategy strategy = IStrategy(pool);
            (, uint tvlInUSD) = valueOfAsset(strategy.stakingToken(), strategy.balance());
            return tvlInUSD;
        } else if (poolTypes[pool] == PoolConstant.PoolTypes.FlipTomdx) {
            IStrategy strategy = IStrategy(pool);
            (, uint tvlInUSD) = valueOfAsset(strategy.stakingToken(), strategy.balance());

            IStrategy rewardsToken = IStrategy(strategy.rewardsToken());
            uint rewardsInmdx = rewardsToken.balanceOf(pool).mul(rewardsToken.priceShare()).div(1e18);
            (, uint rewardsInUSD) = valueOfAsset(address(Mdx), rewardsInmdx);
            return tvlInUSD.add(rewardsInUSD);
        }
        return 0;
    }

    function tvlOfPool(address pool) public view returns (uint) {
        if (legacyPools[pool]) {
            return tvlOfPool_legacy(pool);
        }

        address linked = linkedPools[pool];
        return linked != address(0) ? tvlOfPool_v2(pool).add(tvlOfPool_legacy(linked)) : tvlOfPool_v2(pool);
    }

    /* ========== Pool Information ========== */

    function infoOfPool_legacy(address pool, address account) public view returns (PoolConstant.PoolInfo memory) {
        PoolConstant.PoolInfo memory poolInfo;
        if (pool == address(0)) {
            return poolInfo;
        }

        IStrategyLegacy strategy = IStrategyLegacy(pool);
        (uint profitUSD, uint profitHT, uint profitwallaby, uint profitmdx) = profitOfPool(pool, account);
        (uint apyPool, uint apywallaby) = apyOfPool(pool, 365);

        poolInfo.pool = pool;
        poolInfo.balance = strategy.balanceOf(account);
        poolInfo.principal = strategy.principalOf(account);
        poolInfo.available = strategy.withdrawableBalanceOf(account);
        poolInfo.apyPool = apyPool;
        poolInfo.apywallaby = apywallaby;
        poolInfo.tvl = tvlOfPool(pool);
        poolInfo.pUSD = profitUSD;
        poolInfo.pHT = profitHT;
        poolInfo.pwallaby = profitwallaby;
        poolInfo.pmdx = profitmdx;

        if (poolTypes[pool] != PoolConstant.PoolTypes.wallabyStake) {
            IWallabyMinter minter = wallabyMinter;
            poolInfo.depositedAt = StrategyCompoundMdx(pool).depositedAt(account);
            poolInfo.feeDuration = minter.WITHDRAWAL_FEE_FREE_PERIOD();
            poolInfo.feePercentage = minter.WITHDRAWAL_FEE();
        }
        return poolInfo;
    }

    function infoOfPool_v2(address pool, address account) public view returns (PoolConstant.PoolInfo memory) {
        PoolConstant.PoolInfo memory poolInfo;
        if (pool == address(0)) {
            return poolInfo;
        }

        IStrategy strategy = IStrategy(pool);
        (uint profitUSD, uint profitHT, uint profitwallaby, uint profitmdx) = profitOfPool(pool, account);
        (uint apyPool, uint apywallaby) = apyOfPool(pool, 365);

        poolInfo.pool = pool;
        poolInfo.balance = strategy.balanceOf(account);
        poolInfo.principal = strategy.principalOf(account);
        poolInfo.available = strategy.withdrawableBalanceOf(account);
        poolInfo.apyPool = apyPool;
        poolInfo.apywallaby = apywallaby;
        poolInfo.tvl = tvlOfPool(pool);
        poolInfo.pUSD = profitUSD;
        poolInfo.pHT = profitHT;
        poolInfo.pwallaby = profitwallaby;
        poolInfo.pmdx = profitmdx;

        if (strategy.minter() != address(0)) {
            IWallabyMinter minter = IWallabyMinter(strategy.minter());
            poolInfo.depositedAt = strategy.depositedAt(account);
            poolInfo.feeDuration = minter.WITHDRAWAL_FEE_FREE_PERIOD();
            poolInfo.feePercentage = minter.WITHDRAWAL_FEE();
        }

        return poolInfo;
    }

    function infoOfPool(address pool, address account) public view returns (PoolConstant.PoolInfo memory) {
        return legacyPools[pool] ? infoOfPool_legacy(pool, account) : infoOfPool_v2(pool, account);
    }
}
