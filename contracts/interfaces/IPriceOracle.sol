// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IPriceOracle {
    function getPriceInHT(address token) external view returns (uint price ,uint lastUpadte);
}