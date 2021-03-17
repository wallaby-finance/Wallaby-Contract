// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../openzeppelin/contracts/access/Ownable.sol";
import "../openzeppelin/contracts/math/SafeMath.sol";
import "../openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IMdxPair.sol";
import "../interfaces/IMdexRouter.sol";
import "../interfaces/ISwapMining.sol";

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

contract Zap is Ownable {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    address public WHT;

    IERC20 private constant swaprewardsToken = IERC20(0x25D2e80cB6B86881Fd7e07dd263Fb79f4AbE033c);
    ISwapMining private constant SwapMing = ISwapMining(0x7373c42502874C88954bDd6D50b53061F018422e);
    IMdexRouter public ROUTER;

    uint public totalSwapRewards;
    mapping(address => bool) private notFlip;
    address[] public tokens;

    receive() external payable {}

    constructor(
        IMdexRouter _router,
        address _WHT
    ) public {
       ROUTER = _router;
       WHT = _WHT;
    }

    function isFlip(address _address) public view returns(bool) {
        return !notFlip[_address];
    }

    function zapInToken(address _from, uint amount, address _to) external {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from);

        if (isFlip(_to)) {
            IMdxPair pair = IMdxPair(_to);
            address token0 = pair.token0();
            address token1 = pair.token1();
            if (_from == token0 || _from == token1) {
                // swap half amount for other
                address other = _from == token0 ? token1 : token0;
                _approveTokenIfNeeded(other);
                uint sellAmount = amount.div(2);
                uint otherAmount = _swap(_from, sellAmount, other, address(this));
                ROUTER.addLiquidity(_from, other, amount.sub(sellAmount), otherAmount, 0, 0, msg.sender, block.timestamp);
            } else {
                uint HTAmount = _swapTokenForHT(_from, amount, address(this));
                _HTToFlip(_to, HTAmount, msg.sender);
            }
        } else {
            _swap(_from, amount, _to, msg.sender);
        }
    }

    function zapIn(address _to) external payable {
        _HTToFlip(_to, msg.value, msg.sender);
    }

    function _HTToFlip(address flip, uint amount, address receiver) private {
        if (!isFlip(flip)) {
            _swapHTForToken(flip, amount, receiver);
        } else {
            // flip
            IMdxPair pair = IMdxPair(flip);
            address token0 = pair.token0();
            address token1 = pair.token1();
            if (token0 == WHT || token1 == WHT) {
                address token = token0 == WHT ? token1 : token0;
                uint swapValue = amount.div(2);
                uint tokenAmount = _swapHTForToken(token, swapValue, address(this));

                _approveTokenIfNeeded(token);
                ROUTER.addLiquidityETH{ value: amount.sub(swapValue) }(token, tokenAmount, 0, 0, receiver, block.timestamp);
            } else {
                uint swapValue = amount.div(2);
                uint token0Amount = _swapHTForToken(token0, swapValue, address(this));
                uint token1Amount = _swapHTForToken(token1, amount.sub(swapValue), address(this));
                _approveTokenIfNeeded(token0);
                _approveTokenIfNeeded(token1);
                ROUTER.addLiquidity(token0, token1, token0Amount, token1Amount, 0, 0, receiver, block.timestamp);
            }
        }
    }

    function zapOut(address _from, uint amount) external {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from);

        if (!isFlip(_from)) {
            _swapTokenForHT(_from, amount, msg.sender);
        } else {
            IMdxPair pair = IMdxPair(_from);
            address token0 = pair.token0();
            address token1 = pair.token1();
            if (token0 == WHT || token1 == WHT) {
                ROUTER.removeLiquidityETH(token0!=WHT?token0:token1, amount, 0, 0, msg.sender, block.timestamp);
            } else {
                ROUTER.removeLiquidity(token0, token1, amount, 0, 0, msg.sender, block.timestamp);
            }
        }
    }

    function _approveTokenIfNeeded(address token) private {
        if (IERC20(token).allowance(address(this), address(ROUTER)) == 0) {
            IERC20(token).safeApprove(address(ROUTER), uint(~0));
        }
    }

    function _swapHTForToken(address token, uint value, address receiver) private returns (uint){
        address[] memory path = new address[](2);
        path[0] = WHT;
        path[1] = token;
        uint[] memory amounts = ROUTER.swapExactETHForTokens{ value: value }(0, path, receiver, block.timestamp);
        return amounts[1];
    }

    function _swap(address _from, uint amount, address _to, address receiver) private returns(uint) {
        if (_from == WHT) {
            return _swapWHTForToken(_to, amount, receiver);
        } else if (_to == WHT) {
            return _swapTokenForWHT(_from, amount, receiver);
        } else {
            return _swapTokenForToken(_from, amount, _to, receiver);
        }
    }

    function _swapWHTForToken(address token, uint amount, address receiver) private returns (uint){
        address[] memory path = new address[](2);
        path[0] = WHT;
        path[1] = token;
        uint[] memory amounts = ROUTER.swapExactTokensForTokens(amount, 0, path, receiver, block.timestamp);
        return amounts[1];
    }

    function _swapTokenForHT(address token, uint amount, address receiver) private returns (uint) {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WHT;
        uint[] memory amounts = ROUTER.swapExactTokensForETH(amount, 0, path, receiver, block.timestamp);
        return amounts[1];
    }

    function _swapTokenForWHT(address token, uint amount, address receiver) private returns (uint) {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WHT;

        uint[] memory amounts = ROUTER.swapExactTokensForTokens(amount, 0, path, receiver, block.timestamp);
        return amounts[1];
    }

    function _swapTokenForToken(address from, uint amount, address to, address receiver) private returns(uint) {
        address[] memory path = new address[](3);
        path[0] = from;
        path[1] = WHT;
        path[2] = to;

        uint[] memory amounts = ROUTER.swapExactTokensForTokens(amount, 0, path, receiver, block.timestamp);
        return amounts[2];
    }

    function swapRwards() public view returns (uint){
        return totalSwapRewards;
    }
    // ------------------------------------------ RESTRICTED
    function getSwapRewards() public onlyOwner {
        uint getSwapping = swaprewardsToken.balanceOf(address(this));
        SwapMing.takerWithdraw();
        uint getSwapped = swaprewardsToken.balanceOf(address(this));
        totalSwapRewards = totalSwapRewards.add(getSwapped).sub(getSwapping);
    } 
    function withdrawSwapRewards(address _dev) external onlyOwner{
        require(swaprewardsToken.balanceOf(address(this)) > 0, 'Not Have SwapRewards.');
        swaprewardsToken.safeTransfer(_dev,swaprewardsToken.balanceOf(address(this)));
    }
    function setNotFlip(address token) public onlyOwner {
        bool needPush = notFlip[token] == false;
        notFlip[token] = true;
        if (needPush) {
            tokens.push(token);
        }
    }

    function removeToken(uint i) external onlyOwner {
        address token = tokens[i];
        notFlip[token] = false;
        tokens[i] = tokens[tokens.length-1];
        tokens.pop();
    }

    function sweep() external onlyOwner {
        for (uint i=0; i<tokens.length; i++) {
            address token = tokens[i];
            if (token == address(0)) continue;
            uint amount = IERC20(token).balanceOf(address(this));
            if (amount > 0) {
                _swapTokenForHT(token, amount, owner());
            }
        }
    }

    function withdraw(address token) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }

        IERC20(token).transfer(owner(), IERC20(token).balanceOf(address(this)));
    }
}