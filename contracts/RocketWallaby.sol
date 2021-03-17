// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./openzeppelin/contracts/math/SafeMath.sol";
import "./openzeppelin/contracts/access/Ownable.sol";


import "./interfaces/IRocketWallaby.sol";
import "./interfaces/IRocketBeneficiary.sol";
import "./library/ReentrancyGuard.sol";

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

contract RocketWallaby is IRocketWallaby, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    uint8 public constant ALLOWED_MAX_DECIMALS = 18;

    uint public constant swapBase = 10000;
    uint public constant swapMax = 100000000;
    uint public constant swapMin = 1;

    uint public constant ALLOWED_MAX_SERVICE_FEE = 10000;
    uint public serviceFee = 0;

    address public governance;
    address payable public treasury;

    uint public auctionCount;
    AuctionInfo[] public auctions;
    mapping(uint => mapping(address => UserInfo)) public users;

    /* ========== EVENTS ========== */

    event Create(uint indexed id, address indexed token);
    event Archive(uint indexed id, address indexed token, uint amount);
    event Engage(uint indexed id, address indexed participant, uint amount);
    event Claim(uint indexed id, address indexed participant, uint amount);

    /* ========== MODIFIERS ========== */

    modifier onlyGovernance {
        require(msg.sender == governance, "onlyGovernance");
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(address _governance, address payable _treasury) public {
        governance = _governance;
        treasury = _treasury;
    }

    /* ========== RESTRICTED ========== */

    function setGovernance(address _governance) public onlyGovernance {
        require(_governance != address(0), "!governance");
        governance = _governance;
    }

    function setTreasury(address payable _treasury) public onlyGovernance {
        require(_treasury != address(0), "!treasury");
        treasury = _treasury;
    }

    function setServiceFee(uint256 _serviceFee) public onlyGovernance {
        serviceFee = _serviceFee;
    }

    /* ========== VIEWS ========== */

    function swapTokenAmount(uint id, uint amount) override public view returns (uint) {
        AuctionInfo memory auction = auctions[id];
        uint decimals = ERC20(auction.token).decimals();
        uint decimalCompensation = 10 ** (ALLOWED_MAX_DECIMALS - decimals);
        return amount.mul(auction.swapRatio).div(swapBase).div(decimalCompensation);
    }

    function getAuctions(uint page, uint resultPerPage) external view returns (AuctionInfo[] memory, uint) {
        uint index = page.mul(resultPerPage);
        uint limit = page.add(1).mul(resultPerPage);
        uint next = page.add(1);

        if (limit > auctionCount) {
            limit = auctionCount;
            next = 0;
        }

        if (auctionCount == 0 || index > auctionCount - 1) {
            return (new AuctionInfo[](0), 0);
        }

        uint cursor = 0;
        AuctionInfo[] memory segment = new AuctionInfo[](limit.sub(index));
        for (index; index < limit; index++) {
            if (index < auctionCount) {
                segment[cursor] = auctions[index];
            }
            cursor++;
        }

        return (segment, next);
    }

    function getAuction(uint id) override external view returns (AuctionInfo memory) {
        return auctions[id];
    }

    function getUserInfo(uint id, address user) override external view returns (UserInfo memory) {
        return users[id][user];
    }

    /* ========== FOR BENEFICIARIES ========== */

    function create(AuctionInfo memory request) external payable {
        require(request.deadline > now, "!deadline");
        require(request.allocation > 0, "!allocation");
        require(request.beneficiary != address(0), "!beneficiary");
        require(request.swapRatio >= swapMin && request.swapRatio <= swapMax, "!swapRatio");

        require(request.token != address(0), "!token");
        require(request.tokenSupply > 0, "!tokenSupply");

        uint decimals = ERC20(request.token).decimals();
        require(decimals <= ALLOWED_MAX_DECIMALS, "!decimals");

        uint decimalCompensation = 10 ** (ALLOWED_MAX_DECIMALS - decimals);
        uint capacity = request.tokenSupply.mul(decimalCompensation).mul(swapBase).div(request.swapRatio);

        uint fee = capacity.mul(serviceFee).div(ALLOWED_MAX_SERVICE_FEE);
        require(msg.value >= fee, "!fee");
        if (msg.value > 0) {
            treasury.transfer(msg.value);
        }

        IERC20 token = IERC20(request.token);
        require(token.balanceOf(msg.sender) >= request.tokenSupply, "!tokenSupply");

        uint preBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), request.tokenSupply);
        uint balanceDiff = token.balanceOf(address(this)).sub(preBalance);
        require(balanceDiff == request.tokenSupply, "!tokenSupply");

        request.tokenRemain = request.tokenSupply;
        request.capacity = capacity;
        request.engaged = 0;
        auctions.push(request);
        auctionCount++;

        if (request.option == AuctionOpts.Callback) {
            IRocketBeneficiary(request.beneficiary).notifyCreate(auctionCount, request.token);
        }
        emit Create(auctionCount, request.token);
    }

    function archive(uint id) external nonReentrant {
        AuctionInfo memory auction = auctions[id];
        require(!auction.archived, "!archived");
        require(now >= auction.deadline, "!deadline");

        if (auction.option == AuctionOpts.Callback) {
            IERC20(auction.token).safeTransfer(auction.beneficiary, auction.tokenSupply);
        } else {
            IERC20(auction.token).safeTransfer(auction.beneficiary, auction.tokenRemain);
        }

        uint totalEngaged = auction.engaged;
        auction.archived = true;
        auctions[id] = auction;

        if (totalEngaged > 0) {
            auction.beneficiary.transfer(totalEngaged);
        }

        if (auction.option == AuctionOpts.Callback) {
            IRocketBeneficiary(auction.beneficiary).notifyArchive(id, auction.token, auction.engaged);
        }
        emit Archive(id, auction.token, totalEngaged);
    }

    /* ========== FOR USERS ========== */

    function engage(uint id) external payable {
        AuctionInfo memory auction = auctions[id];
        require(!auction.archived, "!archived");
        require(now < auction.deadline, "!deadline");

        uint available = auction.capacity.sub(auction.engaged);
        require(available >= 0 && msg.value <= available, "!remain");

        UserInfo memory user = users[id][msg.sender];
        require(user.engaged.add(msg.value) <= auction.allocation, "!allocation");

        user.engaged = user.engaged.add(msg.value);
        users[id][msg.sender] = user;

        uint tokenAmount = swapTokenAmount(id, msg.value);
        auction.tokenRemain = auction.tokenRemain.sub(tokenAmount);
        auction.engaged = auction.engaged.add(msg.value);
        auctions[id] = auction;

        if (auction.option == AuctionOpts.Callback) {
            IRocketBeneficiary(auction.beneficiary).notifyEngage(id, msg.sender, msg.value);
        }
        emit Engage(id, msg.sender, msg.value);
    }

    function claim(uint id) external nonReentrant {
        AuctionInfo memory auction = auctions[id];
        require(auction.archived, "!archived");
        require(now >= auction.deadline, "!deadline");

        UserInfo memory user = users[id][msg.sender];
        require(user.engaged > 0 && !user.claim, "!engaged");

        user.claim = true;
        users[id][msg.sender] = user;

        if (auction.option == AuctionOpts.Callback) {
            IRocketBeneficiary(auction.beneficiary).notifyClaim(id, msg.sender, user.engaged);
        } else {
            uint tokenAmount = swapTokenAmount(id, user.engaged);
            require(tokenAmount >= 0, "!tokenAmount");

            IERC20(auction.token).safeTransfer(msg.sender, tokenAmount);
        }

        emit Claim(id, msg.sender, user.engaged);
    }
}