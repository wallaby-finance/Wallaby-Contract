// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IUnitroller {
    function claimComp(address holder,address[] memory cTokens) external;
}