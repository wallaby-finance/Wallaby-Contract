// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

library PoolConstant {

    enum PoolTypes {
        wallabyStake, wallabyFlip, mdxStake, FlipToFlip, FlipTomdx
    }

    struct PoolInfo {
        address pool;
        uint balance;
        uint principal;
        uint available;
        uint apyPool;
        uint apywallaby;
        uint tvl;
        uint pUSD;
        uint pHT;
        uint pwallaby;
        uint pmdx;
        uint depositedAt;
        uint feeDuration;
        uint feePercentage;
    }

}
