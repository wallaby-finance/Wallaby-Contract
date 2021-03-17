// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

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
interface IRocketBeneficiary {
    /**
     * @dev Executed when the auction is created.
     * @param auctionId Index of auctions array
     * @param token The address of token registered for auction
     */
    function notifyCreate(uint256 auctionId, address token) external;

    /**
     * @notice Keep user data as you like.
     * @dev Executed whenever a participant invokes an engage.
     * @param auctionId Index of auctions array
     * @param user The address of the user invoked the engage
     * @param amount The amount the user participated in the auction (ETH/HT)
     */
    function notifyEngage(uint256 auctionId, address user, uint256 amount) external;

    /**
     * @notice Token and funds raised will be transferred before the call.
     * @dev Executed when the auction is archived.
     * @param auctionId Index of auctions array
     * @param token The address of token registered for auction
     * @param amount The amount raised in auction (ETH/HT)
     */
    function notifyArchive(uint256 auctionId, address token, uint256 amount) external;

    /**
     * @notice You are responsible for distributing rewards to users.
     * @dev Executed whenever a participant invokes a claim.
     * @param auctionId Index of auctions array
     * @param user The address of the user invoked the claim
     * @param amount The amount the user participated in the auction (ETH/HT)
     */
    function notifyClaim(uint256 auctionId, address user, uint256 amount) external;
}
