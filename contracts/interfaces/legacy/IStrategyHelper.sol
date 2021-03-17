// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../IWallabyMinter.sol";

interface IStrategyHelper {
    function tokenPriceInHT(address _token) view external returns(uint);
    function mdxPriceInHT() view external returns(uint);
    function HTPriceInUSD() view external returns(uint);

    // function flipPriceInHT(address _flip) view external returns(uint);
    // function flipPriceInUSD(address _flip) view external returns(uint);

    function profitOf(IWallabyMinter minter, address _flip, uint amount) external view returns (uint _usd, uint _wallaby, uint _HT);

    function tvl(address _flip, uint amount) external view returns (uint);    // in USD
    function tvlInHT(address _flip, uint amount) external view returns (uint);    // in HT
    function apy(IWallabyMinter minter, uint pid) external view returns(uint _usd, uint _wallaby, uint _HT);
    function compoundingAPY(uint pid, uint compoundUnit) view external returns(uint);
}