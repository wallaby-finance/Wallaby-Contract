// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IMasterChef {
    function mdxPerBlock() view external returns(uint);
    function totalAllocPoint() view external returns(uint);

    function poolInfo(uint _pid) view external returns(address lpToken, uint allocPoint, uint lastRewardBlock, uint accmdxPerShare);
    function userInfo(uint _pid, address _account) view external returns(uint amount, uint rewardDebt);

    function deposit(uint256 _pid, uint256 _amount) external;
    function depositTo(uint256 _pid, uint256 _amount,address _user) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;

    function enterStaking(uint256 _amount) external;
    function leaveStaking(uint256 _amount) external;
}