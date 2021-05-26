// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../openzeppelin/contracts/math/SafeMath.sol";

import "../interfaces/IMdxPair.sol";
import "../interfaces/IMdxFactory.sol";

import "../interfaces/IMasterChef.sol";
import "../interfaces/legacy/IStrategyHelper.sol";
import "../interfaces/legacy/IStrategyLegacy.sol";
import "../interfaces/IPriceOracle.sol";


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

contract StrategyHelperV2 is IStrategyHelper{
    using SafeMath for uint;

    address public mdx_POOL;       
    address public  HT_HUSD_POOL;  
    IERC20 public WHT;
    IERC20 public mdx;
    IERC20 public HUSD;
    IMasterChef public master;
    IMdxFactory public factory;
    IPriceOracle public oracle;

    constructor(
        address _mdx_POOL,
        address _HT_HUSD_POOL,
        IERC20 _WHT,
        IERC20 _mdx,
        IERC20 _HUSD,
        IMasterChef _master,
        IMdxFactory _factory,
        IPriceOracle _oracle
    )public{
        mdx_POOL = _mdx_POOL;
        HT_HUSD_POOL = _HT_HUSD_POOL;
        WHT = _WHT;
        mdx = _mdx;
        HUSD = _HUSD;
        master = _master;
        factory = _factory;
        oracle = _oracle;
    }

    function tokenPriceInHT(address _token) override view public returns(uint) {
        (uint price,uint lastUpdate) = oracle.getPriceInHT(_token);

        require(lastUpdate >= now - 2 days , "StrategyHelperV2:price too stale!");

        address pair = factory.getPair(_token, address(WHT));
        uint decimal = uint(ERC20(_token).decimals());

        uint currPrice = WHT.balanceOf(pair).mul(10**decimal).div(IERC20(_token).balanceOf(pair));

        require(currPrice <= price.mul(120).div(100), "currPrice too high!");
        require(currPrice >= price.mul(80).div(100), "currPrice too low!");
        return currPrice;
    }

    function mdxPriceInHT() override view public returns(uint) {
        (uint price,uint lastUpdate) = oracle.getPriceInHT(address(mdx));
        require(lastUpdate >= now - 2 days , "StrategyHelperV2:price too stale!");

        uint currPrice = WHT.balanceOf(mdx_POOL).mul(1e18).div(mdx.balanceOf(mdx_POOL));

        require(currPrice <= price.mul(120).div(100), "currPrice too high!");
        require(currPrice >= price.mul(80).div(100), "currPrice too low!");
        return currPrice;
    }

    function HTPriceInUSD() override view public returns(uint) {
        (uint price,uint lastUpdate) = oracle.getPriceInHT(address(HUSD));
        require(lastUpdate >= now - 2 days , "StrategyHelperV2:price too stale!");
        uint meta = 1;
        uint staPrice = meta.mul(1e26).div(price);
        uint currPrice = HUSD.balanceOf(HT_HUSD_POOL).mul(1e18).div(WHT.balanceOf(HT_HUSD_POOL));
        require(currPrice <= staPrice.mul(120).div(100), "currPrice too high!");
        require(currPrice >= staPrice.mul(80).div(100), "currPrice too low!");
        
        return currPrice;
    }

    function getUSDInHT() view public returns (uint){
        return HUSD.balanceOf(HT_HUSD_POOL).mul(1e18).div(WHT.balanceOf(HT_HUSD_POOL));
    } 
    function getStaPrice() view public returns (uint){
        (uint price,uint lastUpdate) = oracle.getPriceInHT(address(HUSD));
        require(lastUpdate >= now - 2 days , "StrategyHelperV2:price too stale!");
        uint meta = 1;
        return meta.mul(1e26).div(price);
    }

    function mdxPerYearOfPool(uint pid) view public returns(uint) {
        (, uint allocPoint,,) = master.poolInfo(pid);
        return master.mdxPerBlock().mul(blockPerYear()).mul(allocPoint).div(master.totalAllocPoint());
    }

    function blockPerYear() pure public returns(uint) {
        // 86400 / 3 * 365
        return 10512000;
    }

    function profitOf(IWallabyMinter minter, address flip, uint amount) override external view returns (uint _usd, uint _wallaby, uint _HT) {
        _usd = tvl(flip, amount);
        if (address(minter) == address(0)) {
            _wallaby = 0;
        } else {
            uint performanceFee = minter.performanceFee(_usd);
            _usd = _usd.sub(performanceFee);
            uint HTAmount = performanceFee.mul(1e18).div(HTPriceInUSD());
            _wallaby = minter.amountwallabyToMint(HTAmount);
        }
        _HT = 0;
    }

    // apy() = mdxPrice * (mdxPerBlock * blockPerYear * weight) / PoolValue(=WHT*2)
    function _apy(uint pid) view private returns(uint) {
        (address token,,,) = master.poolInfo(pid);
        uint poolSize = tvl(token, IERC20(token).balanceOf(address(master))).mul(1e18).div(HTPriceInUSD());
        return mdxPriceInHT().mul(mdxPerYearOfPool(pid)).div(poolSize);
    }

    function apy(IWallabyMinter, uint pid) override view public returns(uint _usd, uint _wallaby, uint _HT) {
        _usd = compoundingAPY(pid, 1 days);
        _wallaby = 0;
        _HT = 0;
    }

    function tvl(address _flip, uint amount) override public view returns (uint) {
        if (_flip == address(mdx)) {
            return mdxPriceInHT().mul(HTPriceInUSD()).mul(amount).div(1e36);
        }
        address _token0 = IMdxPair(_flip).token0();
        address _token1 = IMdxPair(_flip).token1();
        if (_token0 == address(WHT) || _token1 == address(WHT)) {
            uint HT = WHT.balanceOf(address(_flip)).mul(amount).div(IERC20(_flip).totalSupply());
            uint price = HTPriceInUSD();
            return HT.mul(price).div(1e18).mul(2);
        }

        uint balanceToken0 = IERC20(_token0).balanceOf(_flip);
        uint price = tokenPriceInHT(_token0);
        return balanceToken0.mul(price).div(1e18).mul(HTPriceInUSD()).div(1e18).mul(2);
    }

    function tvlInHT(address _flip, uint amount) override public view returns (uint) {
        if (_flip == address(mdx)) {
            return mdxPriceInHT().mul(amount).div(1e18);
        }
        address _token0 = IMdxPair(_flip).token0();
        address _token1 = IMdxPair(_flip).token1();
        if (_token0 == address(WHT) || _token1 == address(WHT)) {
            uint HT = WHT.balanceOf(address(_flip)).mul(amount).div(IERC20(_flip).totalSupply());
            return HT.mul(2);
        }

        uint balanceToken0 = IERC20(_token0).balanceOf(_flip);
        uint price = tokenPriceInHT(_token0);
        return balanceToken0.mul(price).div(1e18).mul(2);
    }

    function compoundingAPY(uint pid, uint compoundUnit) view override public returns(uint) {
        uint __apy = _apy(pid);
        uint compoundTimes = 365 days / compoundUnit;
        uint unitAPY = 1e18 + (__apy / compoundTimes);
        uint result = 1e18;

        for(uint i=0; i<compoundTimes; i++) {
            result = (result * unitAPY) / 1e18;
        }

        return result - 1e18;
    }
}