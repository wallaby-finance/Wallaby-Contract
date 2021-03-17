// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;


import "../../openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/IMdexRouter.sol";
import "../../interfaces/IMdxPair.sol";
import "../../interfaces/IMasterChef.sol";
import "../../interfaces/IWallabyMinter.sol";
import "../../interfaces/legacy/IStrategyHelper.sol";
import "../../interfaces/legacy/IStrategyLegacy.sol";

contract StrategyCompoundFLIP is IStrategyLegacy, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    IMdexRouter public ROUTER;
    IERC20  public  mdx;
    IERC20  public  WHT;
    IMasterChef public mdx_MASTER_CHEF;
    address public keeper;

    uint public poolId;
    IERC20 public token;

    address private _token0;
    address private _token1;

    uint public totalShares;
    mapping (address => uint) private _shares;
    mapping (address => uint) private _principal;
    mapping (address => uint) public depositedAt;

    IWallabyMinter public minter;
    IStrategyHelper public helper; 

    constructor(
        uint _pid,
        IMdexRouter _ROUTER,
        IERC20 _mdx,
        IERC20 _WHT,
        IMasterChef _mdx_MASTER_CHEF,
        address     _keeper,
        IStrategyHelper _helper
    ) public {
        ROUTER = _ROUTER;
        mdx = _mdx;
        WHT = _WHT;
        mdx_MASTER_CHEF = _mdx_MASTER_CHEF;
        keeper = _keeper;
        helper = _helper;

        if (_pid != 0) {
            (address _token,,,) = mdx_MASTER_CHEF.poolInfo(_pid);
            setFlipToken(_token);
            poolId = _pid;
        }

        mdx.safeApprove(address(ROUTER), 0);
        mdx.safeApprove(address(ROUTER), uint(~0));
    }

    function setFlipToken(address _token) public onlyOwner {
        require(address(token) == address(0), "flip token set already");
        token = IERC20(_token);
        _token0 = IMdxPair(_token).token0();
        _token1 = IMdxPair(_token).token1();

        token.safeApprove(address(mdx_MASTER_CHEF), uint(~0));

        IERC20(_token0).safeApprove(address(ROUTER), 0);
        IERC20(_token0).safeApprove(address(ROUTER), uint(~0));
        IERC20(_token1).safeApprove(address(ROUTER), 0);
        IERC20(_token1).safeApprove(address(ROUTER), uint(~0));
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
            token.safeApprove(address(_minter), 0);
            token.safeApprove(address(_minter), uint(~0));
        }
    }

    function setHelper(IStrategyHelper _helper) external {
        require(msg.sender == address(_helper) || msg.sender == owner(), "auth");
        require(address(_helper) != address(0), "zero address");

        helper = _helper;
    }

    function balance() override public view returns (uint) {
        (uint amount,) = mdx_MASTER_CHEF.userInfo(poolId, address(this));
        return token.balanceOf(address(this)).add(amount);
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

        return helper.profitOf(minter, address(token), _balance.sub(principal));
    }

    function tvl() override public view returns (uint) {
        return helper.tvl(address(token), balance());
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
        uint _before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint _after = token.balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens
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

        mdx_MASTER_CHEF.deposit(poolId, _amount);
    }

    function deposit(uint _amount) override public {
        _depositTo(_amount, msg.sender);
    }

    function depositAll() override external {
        deposit(token.balanceOf(msg.sender));
    }

    function withdrawAll() override external {
        uint _withdraw = balanceOf(msg.sender);

        totalShares = totalShares.sub(_shares[msg.sender]);
        delete _shares[msg.sender];

        uint _before = token.balanceOf(address(this));
        mdx_MASTER_CHEF.withdraw(poolId, _withdraw);
        uint _after = token.balanceOf(address(this));
        _withdraw = _after.sub(_before);

        uint principal = _principal[msg.sender];
        uint depositTimestamp = depositedAt[msg.sender];
        delete _principal[msg.sender];
        delete depositedAt[msg.sender];

        if (address(minter) != address(0) && minter.isMinter(address(this)) && _withdraw > principal) {
            uint profit = _withdraw.sub(principal);
            uint withdrawalFee = minter.withdrawalFee(_withdraw, depositTimestamp);
            uint performanceFee = minter.performanceFee(profit);

            minter.mintFor(address(token), withdrawalFee, performanceFee, msg.sender, depositTimestamp);

            token.safeTransfer(msg.sender, _withdraw.sub(withdrawalFee).sub(performanceFee));
        } else {
            token.safeTransfer(msg.sender, _withdraw);
        }
    }

    function harvest() override external {
        require(msg.sender == keeper || msg.sender == owner(), "auth");

        mdx_MASTER_CHEF.withdraw(poolId, 0);
        uint mdxAmount = mdx.balanceOf(address(this));
        uint mdxForToken0 = mdxAmount.div(2);
        mdxToToken(_token0, mdxForToken0);
        mdxToToken(_token1, mdxAmount.sub(mdxForToken0));
        uint liquidity = generateFlipToken();
        mdx_MASTER_CHEF.deposit(poolId, liquidity);
    }

    function mdxToToken(address _token, uint amount) private {
        if (_token == address(mdx)) return;
        address[] memory path;
        if (_token == address(WHT)) {
            path = new address[](2);
            path[0] = address(mdx);
            path[1] = _token;
        } else {
            path = new address[](3);
            path[0] = address(mdx);
            path[1] = address(WHT);
            path[2] = _token;
        }

        ROUTER.swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp);
    }

    function generateFlipToken() private returns(uint liquidity) {
        uint amountADesired = IERC20(_token0).balanceOf(address(this));
        uint amountBDesired = IERC20(_token1).balanceOf(address(this));

        (,,liquidity) = ROUTER.addLiquidity(_token0, _token1, amountADesired, amountBDesired, 0, 0, address(this), block.timestamp);

        // send dust
        IERC20(_token0).safeTransfer(msg.sender, IERC20(_token0).balanceOf(address(this)));
        IERC20(_token1).safeTransfer(msg.sender, IERC20(_token1).balanceOf(address(this)));
    }

    function withdraw(uint256) override external {
        revert("Use withdrawAll");
    }

    function getReward() override external {
        revert("Use withdrawAll");
    }
}