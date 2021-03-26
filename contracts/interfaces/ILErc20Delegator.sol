// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface ILErc20Delegator {
   function mint(uint mintAmount) external returns (uint);
   function redeem(uint redeemTokens) external returns (uint);

   function balanceOf(address owner) external view returns (uint);
   //function exchangeRateCurrent() public nonReentrant returns (uint);
   function exchangeRateStored() external view returns (uint);
   //function redeemUnderlying(uint redeemAmount) external returns (uint);
}