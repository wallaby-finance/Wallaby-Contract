// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../openzeppelin/contracts/math/SafeMath.sol";
import "../openzeppelin/contracts/access/Ownable.sol";
import "../openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IWallabyMinter.sol";
import "../interfaces/legacy/IStakingRewards.sol";
import "./MdexSwap.sol";
import "../interfaces/legacy/IStrategyHelper.sol";

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

contract WallabyMinter is IWallabyMinter, Ownable, MdexSwap {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    uint public override WITHDRAWAL_FEE_FREE_PERIOD = 3 days;
    uint public override WITHDRAWAL_FEE = 50;
    uint public constant FEE_MAX = 10000;

    uint public PERFORMANCE_FEE = 3000; // 30%

    uint public override wallabyPerProfitHT;
    uint public wallabyPerwallabyHTFlip;


    ERC20 public wallaby;
    address public dev;
    IERC20 public WHT;
    address public wallabyPool;
    IStrategyHelper public helper;

    mapping (address => bool) private _minters;

    modifier onlyMinter {
        require(isMinter(msg.sender) == true, "not minter");
        _;
    }

    constructor(
        ERC20 _wallaby,
        IERC20 _WHT,
        address _dev,
        address _wallabyPool,
        IStrategyHelper _helper
    ) public {
        wallaby = _wallaby;
        WHT = _WHT;
        dev = _dev;
        wallabyPool = _wallabyPool;
        helper = _helper;
        
        wallabyPerProfitHT = 10e18;
        wallabyPerwallabyHTFlip = 6e18;
        wallaby.approve(wallabyPool, uint(~0));
    }

    function transferwallabyOwner(address _owner) external onlyOwner {
        Ownable(address(wallaby)).transferOwnership(_owner);
    }

    function setWithdrawalFee(uint _fee) external onlyOwner {
        require(_fee < 500, "wrong fee");   // less 5%
        WITHDRAWAL_FEE = _fee;
    }

    function setPerformanceFee(uint _fee) external onlyOwner {
        require(_fee < 5000, "wrong fee");
        PERFORMANCE_FEE = _fee;
    }

    function setWithdrawalFeeFreePeriod(uint _period) external onlyOwner {
        WITHDRAWAL_FEE_FREE_PERIOD = _period;
    }

    function setMinter(address minter, bool canMint) external override onlyOwner {
        if (canMint) {
            _minters[minter] = canMint;
        } else {
            delete _minters[minter];
        }
    }

    function setwallabyPerProfitHT(uint _ratio) external onlyOwner {
        wallabyPerProfitHT = _ratio;
    }

    function setwallabyPerwallabyHTFlip(uint _wallabyPerwallabyHTFlip) external onlyOwner {
        wallabyPerwallabyHTFlip = _wallabyPerwallabyHTFlip;
    }

    function setHelper(IStrategyHelper _helper) external onlyOwner {
        require(address(_helper) != address(0), "zero address");
        helper = _helper;
    }

    function isMinter(address account) override view public returns(bool) {
        if (wallaby.getOwner() != address(this)) {
            return false;
        }

        if (block.timestamp < 1616414400) {
            return false;
        }
        return _minters[account];
    }

    function amountwallabyToMint(uint HTProfit) override view public returns(uint) {
        return HTProfit.mul(wallabyPerProfitHT).div(1e18);
    }

    function amountwallabyToMintForwallabyHT(uint amount, uint duration) override view public returns(uint) {
        return amount.mul(wallabyPerwallabyHTFlip).mul(duration).div(365 days).div(1e18);
    }

    function withdrawalFee(uint amount, uint depositedAt) override view external returns(uint) {
        if (depositedAt.add(WITHDRAWAL_FEE_FREE_PERIOD) > block.timestamp) {
            return amount.mul(WITHDRAWAL_FEE).div(FEE_MAX);
        }
        return 0;
    }

    function performanceFee(uint profit) override view public returns(uint) {
        return profit.mul(PERFORMANCE_FEE).div(FEE_MAX);
    }

    function mintFor(address flip, uint _withdrawalFee, uint _performanceFee, address to, uint) override external onlyMinter {
        uint feeSum = _performanceFee.add(_withdrawalFee);
        IERC20(flip).safeTransferFrom(msg.sender, address(this), feeSum);

        uint wallabyHTAmount = tokenTowallabyHT(flip, IERC20(flip).balanceOf(address(this)));
        address flipToken = wallabyHTFlipToken();
        IERC20(flipToken).safeTransfer(wallabyPool, wallabyHTAmount);
        IStakingRewards(wallabyPool).notifyRewardAmount(wallabyHTAmount);

        uint contribution = helper.tvlInHT(flipToken, wallabyHTAmount).mul(_performanceFee).div(feeSum);
        uint mintwallaby = amountwallabyToMint(contribution);
        mint(mintwallaby, to);
    }

    function mintForwallabyHT(uint amount, uint duration, address to) override external onlyMinter {
        uint mintwallaby = amountwallabyToMintForwallabyHT(amount, duration);
        if (mintwallaby == 0) return;
        mint(mintwallaby, to);
    }

    function mint(uint amount, address to) private {
        wallaby.mint(amount);
        wallaby.transfer(to, amount);

        uint wallabyForDev = amount.mul(15).div(100);
        wallaby.mint(wallabyForDev);
        IStakingRewards(wallabyPool).stakeTo(wallabyForDev, dev);
    }
}