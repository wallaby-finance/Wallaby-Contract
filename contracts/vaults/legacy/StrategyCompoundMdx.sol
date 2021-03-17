// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;


import "../../openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/IMasterChef.sol";
import "../../interfaces/IWallabyMinter.sol";
import "../../interfaces/legacy/IStrategyHelper.sol";
import "../../interfaces/legacy/IStrategyLegacy.sol";

contract StrategyCompoundMdx is IStrategyLegacy, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;


    IERC20 public mdx;
    IMasterChef public mdx_MASTER_CHEF;
    address public keeper;

    uint public constant poolId = 0;

    uint public totalShares;
    mapping (address => uint) private _shares;
    mapping (address => uint) private _principal;
    mapping (address => uint) public depositedAt;

    IWallabyMinter public minter;
    IStrategyHelper public helper;
    constructor(
        IERC20 _mdx,
        IMasterChef _mdx_MASTER_CHEF,
        address _keeper,
        IStrategyHelper _helper
    ) public {
        mdx = _mdx;
        mdx_MASTER_CHEF = _mdx_MASTER_CHEF;
        keeper = _keeper;
        helper = _helper;
        mdx.safeApprove(address(mdx_MASTER_CHEF), uint(~0));
    }

    function setKeeper(address _keeper) external {
        require(msg.sender == _keeper || msg.sender == owner(), "auth");
        require(_keeper != address(0), "zero address");
        keeper = _keeper;
    }

    function setMinter(IWallabyMinter _minter) external onlyOwner {
        // can zero
        minter = _minter;
        if (address(_minter) != address(0)) {
            mdx.safeApprove(address(_minter), 0);
            mdx.safeApprove(address(_minter), uint(~0));
        }
    }

    function setHelper(IStrategyHelper _helper) external {
        require(msg.sender == address(_helper) || msg.sender == owner(), "auth");
        require(address(_helper) != address(0), "zero address");

        helper = _helper;
    }

    function balance() override public view returns (uint) {
        (uint amount,) = mdx_MASTER_CHEF.userInfo(poolId, address(this));
        return mdx.balanceOf(address(this)).add(amount);
    }

    function balanceOf(address account) override public view returns(uint) {
        if (totalShares == 0) return 0;
        return balance().mul(sharesOf(account)).div(totalShares);
    }

    function withdrawableBalanceOf(address account) override public view returns (uint) {
        return balanceOf(account);
    }

    function sharesOf(address account) public view returns (uint) {
        return _shares[account];
    }

    function principalOf(address account) override public view returns (uint) {
        return _principal[account];
    }

    function profitOf(address account) override public view returns (uint _usd, uint _wallaby, uint _HT) {
        uint _balance = balanceOf(account);
        uint principal = principalOf(account);
        if (principal >= _balance) {
            // something wrong...
            return (0, 0, 0);
        }

        return helper.profitOf(minter, address(mdx), _balance.sub(principal));
    }

    function tvl() override public view returns (uint) {
        return helper.tvl(address(mdx), balance());
    }

    function apy() override public view returns(uint _usd, uint _wallaby, uint _HT) {
        return helper.apy(minter, poolId);
    }

    function info(address account) override external view returns(UserInfo memory) {
        UserInfo memory userInfo;

        userInfo.balance = balanceOf(account);
        userInfo.principal = principalOf(account);
        userInfo.available = withdrawableBalanceOf(account);

        Profit memory profit;
        (uint usd, uint wallaby, uint HT) = profitOf(account);
        profit.usd = usd;
        profit.wallaby = wallaby;
        profit.HT = HT;
        userInfo.profit = profit;

        userInfo.poolTVL = tvl();

        APY memory poolAPY;
        (usd, wallaby, HT) = apy();
        poolAPY.usd = usd;
        poolAPY.wallaby = wallaby;
        poolAPY.HT = HT;
        userInfo.poolAPY = poolAPY;

        return userInfo;
    }

    function priceShare() public view returns(uint) {
        return balance().mul(1e18).div(totalShares);
    }

    function _depositTo(uint _amount, address _to) private {
        uint _pool = balance();
        mdx.safeTransferFrom(msg.sender, address(this), _amount);
        uint shares = 0;
        if (totalShares == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalShares)).div(_pool);
        }

        totalShares = totalShares.add(shares);
        _shares[_to] = _shares[_to].add(shares);
        _principal[_to] = _principal[_to].add(_amount);
        depositedAt[_to] = block.timestamp;

        uint balanceOfmdx = mdx.balanceOf(address(this));
        mdx_MASTER_CHEF.enterStaking(balanceOfmdx);
    }

    function deposit(uint _amount) override public {
        _depositTo(_amount, msg.sender);
    }

    function depositAll() override external {
        deposit(mdx.balanceOf(msg.sender));
    }

    function withdrawAll() override external {
        uint _withdraw = balanceOf(msg.sender);

        totalShares = totalShares.sub(_shares[msg.sender]);
        delete _shares[msg.sender];
        mdx_MASTER_CHEF.leaveStaking(_withdraw.sub(mdx.balanceOf(address(this))));

        uint principal = _principal[msg.sender];
        uint depositTimestamp = depositedAt[msg.sender];
        delete _principal[msg.sender];
        delete depositedAt[msg.sender];

        if (address(minter) != address(0) && minter.isMinter(address(this)) && _withdraw > principal) {
            uint profit = _withdraw.sub(principal);
            uint withdrawalFee = minter.withdrawalFee(_withdraw, depositTimestamp);
            uint performanceFee = minter.performanceFee(profit);

            minter.mintFor(address(mdx), withdrawalFee, performanceFee, msg.sender, depositTimestamp);

            mdx.safeTransfer(msg.sender, _withdraw.sub(withdrawalFee).sub(performanceFee));
        } else {
            mdx.safeTransfer(msg.sender, _withdraw);
        }

        mdx_MASTER_CHEF.enterStaking(mdx.balanceOf(address(this)));
    }

    function harvest() override external {
        require(msg.sender == keeper || msg.sender == owner(), "auth");

        mdx_MASTER_CHEF.leaveStaking(0);
        uint mdxAmount = mdx.balanceOf(address(this));
        mdx_MASTER_CHEF.enterStaking(mdxAmount);
    }

    // salvage purpose only
    function withdrawToken(address token, uint amount) external {
        require(msg.sender == keeper || msg.sender == owner(), "auth");
        require(token != address(mdx));

        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function withdraw(uint256) override external {
        revert("Use withdrawAll");
    }

    function getReward() override external {
        revert("Use withdrawAll");
    }
}