// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;


interface IStrategyLegacy {
    struct Profit {
        uint usd;
        uint wallaby;
        uint HT;
    }

    struct APY {
        uint usd;
        uint wallaby;
        uint HT;
    }

    struct UserInfo {
        uint balance;
        uint principal;
        uint available;
        Profit profit;
        uint poolTVL;
        APY poolAPY;
    }

    function deposit(uint _amount) external;
    function depositAll() external;
    function withdraw(uint256 _amount) external;    // wallaby STAKING POOL ONLY
    function withdrawAll() external;
    function getReward() external;                  // wallaby STAKING POOL ONLY
    function harvest() external;

    function balance() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function principalOf(address account) external view returns (uint);
    function withdrawableBalanceOf(address account) external view returns (uint);   // wallaby STAKING POOL ONLY
    function profitOf(address account) external view returns (uint _usd, uint _wallaby, uint _HT);
//    function earned(address account) external view returns (uint);
    function tvl() external view returns (uint);    // in USD
    function apy() external view returns (uint _usd, uint _wallaby, uint _HT);

    /* ========== Strategy Information ========== */
//    function pid() external view returns (uint);
//    function poolType() external view returns (PoolTypes);
//    function isMinter() external view returns (bool, address);
//    function getDepositedAt(address account) external view returns (uint);
//    function getRewardsToken() external view returns (address);

    function info(address account) external view returns (UserInfo memory);
}
