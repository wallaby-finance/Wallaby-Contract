// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../openzeppelin/contracts/math/SafeMath.sol";

import "../interfaces/IMdexRouter.sol";
import "../interfaces/IMdxPair.sol";
import "../interfaces/IMdxFactory.sol";

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

abstract contract MdexSwap {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IMdexRouter private constant ROUTER = IMdexRouter(0xED7d5F38C79115ca12fe6C0041abb22F0A06C300);
    IMdxFactory private constant factory = IMdxFactory(0xb0b670fc1F7724119963018DB0BfA86aDb22d941);

    address internal constant mdx = 0x25D2e80cB6B86881Fd7e07dd263Fb79f4AbE033c;
    address private constant _wallaby = 0x793CF59D2C4586D599165ca86Cc96c1B405d34C4;
    address private constant _WHT = 0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F;

    function wallabyHTFlipToken() internal view returns(address) {
        return factory.getPair(_wallaby, _WHT);
    }

    function tokenTowallabyHT(address token, uint amount) internal returns(uint flipAmount) {
        if (token == mdx) {
            flipAmount = _mdxTowallabyHTFlip(amount);
        } else {
            // flip
            flipAmount = _flipTowallabyHTFlip(token, amount);
        }
    }

    function _mdxTowallabyHTFlip(uint amount) private returns(uint flipAmount) {
        swapToken(mdx, amount.div(2), _wallaby);
        swapToken(mdx, amount.sub(amount.div(2)), _WHT);

        flipAmount = generateFlipToken();
    }

    function _flipTowallabyHTFlip(address token, uint amount) private returns(uint flipAmount) {
        IMdxPair pair = IMdxPair(token);
        address _token0 = pair.token0();
        address _token1 = pair.token1();
        IERC20(token).safeApprove(address(ROUTER), 0);
        IERC20(token).safeApprove(address(ROUTER), amount);
        ROUTER.removeLiquidity(_token0, _token1, amount, 0, 0, address(this), block.timestamp);
        if (_token0 == _WHT) {
            swapToken(_token1, IERC20(_token1).balanceOf(address(this)), _wallaby);
            flipAmount = generateFlipToken();
        } else if (_token1 == _WHT) {
            swapToken(_token0, IERC20(_token0).balanceOf(address(this)), _wallaby);
            flipAmount = generateFlipToken();
        } else {
            swapToken(_token0, IERC20(_token0).balanceOf(address(this)), _wallaby);
            swapToken(_token1, IERC20(_token1).balanceOf(address(this)), _WHT);
            flipAmount = generateFlipToken();
        }
    }

    function swapToken(address _from, uint _amount, address _to) private {
        if (_from == _to) return;

        address[] memory path;
        if (_from == _WHT || _to == _WHT) {
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            path = new address[](3);
            path[0] = _from;
            path[1] = _WHT;
            path[2] = _to;
        }

        IERC20(_from).safeApprove(address(ROUTER), 0);
        IERC20(_from).safeApprove(address(ROUTER), _amount);
        ROUTER.swapExactTokensForTokens(_amount, 0, path, address(this), block.timestamp);
    }

    function generateFlipToken() private returns(uint liquidity) {
        uint amountADesired = IERC20(_wallaby).balanceOf(address(this));
        uint amountBDesired = IERC20(_WHT).balanceOf(address(this));

        IERC20(_wallaby).safeApprove(address(ROUTER), 0);
        IERC20(_wallaby).safeApprove(address(ROUTER), amountADesired);
        IERC20(_WHT).safeApprove(address(ROUTER), 0);
        IERC20(_WHT).safeApprove(address(ROUTER), amountBDesired);

        (,,liquidity) = ROUTER.addLiquidity(_wallaby, _WHT, amountADesired, amountBDesired, 0, 0, address(this), block.timestamp);

        // send dust
        IERC20(_wallaby).transfer(msg.sender, IERC20(_wallaby).balanceOf(address(this)));
        IERC20(_WHT).transfer(msg.sender, IERC20(_WHT).balanceOf(address(this)));
    }
}