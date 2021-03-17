// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./openzeppelin/contracts/math/SafeMath.sol";
import "./openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IMdexRouter.sol";
import "./interfaces/IMdxFactory.sol";
import "./interfaces/IRocketWallaby.sol";
import "./interfaces/IRocketBeneficiary.sol";
import "./interfaces/IMasterChef.sol";
import "./interfaces/legacy/IStakingRewards.sol";

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

contract PresaleMdxWallaby is IRocketBeneficiary, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IMdexRouter public router; 
    IMdxFactory public factory; 

    address public rocket;
    address public token;

    address public masterChef;
    address public stakingRewards;

    uint public totalBalance;
    uint public totalFlipBalance;

    mapping (address => uint) private balance;
    address[] public users;

    modifier onlyRocket {
        require(msg.sender == rocket, '!auth');
        _;
    }

    constructor(
        address _rocket,
        IMdexRouter _router,
        IMdxFactory _factory
    ) public {
        rocket = _rocket;
        router = _router;
        factory = _factory;
    }

    receive() payable external {

    }

    function balanceOf(address account) view external returns(uint) {
        return balance[account];
    }

    function flipToken() view public returns(address) {
        return factory.getPair(token, router.WHT());
    }

    function notifyCreate(uint256, address _token) override external onlyRocket {
        token = _token;
    }

    function notifyEngage(uint256 auctionId, address user, uint256 amount) override external onlyRocket {
        users.push(user);
        amount = IRocketWallaby(rocket).swapTokenAmount(auctionId, amount);
        balance[user] = balance[user].add(amount);
        totalBalance = totalBalance.add(amount);
    }

    function notifyArchive(uint256, address _token, uint256 amount) override external onlyRocket {
        require(IERC20(_token).balanceOf(address(this)) >= totalBalance, "less token");
        require(address(this).balance >= amount, "less balance");

        uint tokenAmount = totalBalance.div(2);
        IERC20(_token).safeApprove(address(router), 0);
        IERC20(_token).safeApprove(address(router), tokenAmount);
        router.addLiquidityETH{value: amount.div(2)}(_token, tokenAmount, 0, 0, address(this), block.timestamp);

        address lp = flipToken();
        totalFlipBalance = IERC20(lp).balanceOf(address(this));
    }

    function notifyClaim(uint256, address, uint256) override external {
        // do nothing. go to https://panmdxwallaby.finance
        // admin of panmdxwallaby will execute distributeTokens for participants before launching Panmdxwallaby.
    }

    function setMasterChef(address _masterChef) external onlyOwner {
        masterChef = _masterChef;
    }

    function setStakingRewards(address _rewards) external onlyOwner {
        stakingRewards = _rewards;
    }

    function distributeTokens(uint index, uint length, uint _pid) external onlyOwner {
        address lpToken = flipToken();
        require(lpToken != address(0), 'not set flip');
        require(masterChef != address (0), 'not set masterChef');
        require(stakingRewards != address(0), 'not set stakingRewards');

        IERC20(lpToken).safeApprove(masterChef, 0);
        IERC20(lpToken).safeApprove(masterChef, totalFlipBalance);

        IERC20(token).safeApprove(stakingRewards, 0);
        IERC20(token).safeApprove(stakingRewards, totalBalance.div(2));

        for(uint i=index; i<length; i++) {
            address user = users[i];
            uint share = shareOf(user);

            _distributeFlip(user, share, _pid);
            _distributeToken(user, share);

            delete balance[user];
        }
    }

    function _distributeFlip(address user, uint share, uint pid) private {
        uint remaining = IERC20(flipToken()).balanceOf(address(this));
        uint amount = totalFlipBalance.mul(share).div(1e18);
        if (amount == 0) return;

        if (remaining < amount) {
            amount = remaining;
        }
        IMasterChef(masterChef).depositTo(pid, amount, user);
    }

    function _distributeToken(address user, uint share) private {
        uint remaining = IERC20(token).balanceOf(address(this));
        uint amount = totalBalance.div(2).mul(share).div(1e18);
        if (amount == 0) return;

        if (remaining < amount) {
            amount = remaining;
        }
        IStakingRewards(stakingRewards).stakeTo(amount, user);
    }

    function shareOf(address _user) view private returns(uint) {
        return balance[_user].mul(1e18).div(totalBalance);
    }

    function finalize() external onlyOwner {
        // will go to the wallaby pool as reward
        payable(owner()).transfer(address(this).balance);

        // will burn unsold tokens
        uint tokenBalance = IERC20(token).balanceOf(address(this));
        if (tokenBalance > 0) {
            IERC20(token).transfer(owner(), tokenBalance);
        }
    }
}