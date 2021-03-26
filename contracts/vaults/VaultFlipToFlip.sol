// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IMdexRouter.sol";
import "../interfaces/IMdxPair.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IMasterChef.sol";
import "../interfaces/IWallabyMinter.sol";
import "../interfaces/ISwapMining.sol";
import "./VaultController.sol";
import {PoolConstant} from "../library/PoolConstant.sol";


contract VaultFlipToFlip is VaultController, IStrategy {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* ========== CONSTANTS ============= */

    IMdexRouter private constant ROUTER = IMdexRouter(0xED7d5F38C79115ca12fe6C0041abb22F0A06C300);
    IERC20 private constant mdx = IERC20(0x25D2e80cB6B86881Fd7e07dd263Fb79f4AbE033c);
    IERC20 private constant WHT = IERC20(0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F);
    IMasterChef private constant MDEX_MASTER_CHEF = IMasterChef(0xFB03e11D93632D97a8981158A632Dd5986F5E909);
    PoolConstant.PoolTypes public constant override poolType = PoolConstant.PoolTypes.FlipToFlip;
    ISwapMining private constant SwapMing = ISwapMining(0x7373c42502874C88954bDd6D50b53061F018422e);

    /* ========== STATE VARIABLES ========== */

    uint public override pid;

    address private _token0;
    address private _token1;

    uint public totalShares;
    uint public totalSwapRewards;
    mapping (address => uint) private _shares;
    mapping (address => uint) private _principal;
    mapping (address => uint) private _depositedAt;

    /* ========== INITIALIZER ========== */

    function initialize(uint _pid) external initializer {
        require(_pid != 0, "VaultFlipToFlip: pid must not be zero");

        (address _token,,,) = MDEX_MASTER_CHEF.poolInfo(_pid);
        __VaultController_init(IERC20(_token));
        setFlipToken(_token);
        pid = _pid;

        mdx.safeApprove(address(ROUTER), 0);
        mdx.safeApprove(address(ROUTER), uint(~0));
    }

    /* ========== VIEW FUNCTIONS ========== */

    function swapRwards() public view returns (uint){
        return totalSwapRewards;
    }

    function balance() override public view returns (uint) {
        (uint amount,) = MDEX_MASTER_CHEF.userInfo(pid, address(this));
        return _stakingToken.balanceOf(address(this)).add(amount);
    }

    function balanceOf(address account) public view override returns(uint) {
        if (totalShares == 0) return 0;
        return balance().mul(sharesOf(account)).div(totalShares);
    }

    function withdrawableBalanceOf(address account) public view override returns (uint) {
        return balanceOf(account);
    }

    function sharesOf(address account) public view override returns (uint) {
        return _shares[account];
    }

    function principalOf(address account) override public view returns (uint) {
        return _principal[account];
    }

    function earned(address account) override public view returns (uint) {
        if (balanceOf(account) >= principalOf(account)) {
            return balanceOf(account).sub(principalOf(account));
        } else {
            return 0;
        }
    }

    function depositedAt(address account) external view override returns (uint) {
        return _depositedAt[account];
    }

    function rewardsToken() external view override returns (address) {
        return address(_stakingToken);
    }

    function priceShare() external view override returns(uint) {
        if (totalShares == 0) return 1e18;
        return balance().mul(1e18).div(totalShares);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function deposit(uint _amount) public override {
        _depositTo(_amount, msg.sender);
    }

    function depositAll() external override {
        deposit(_stakingToken.balanceOf(msg.sender));
    }

    function withdrawAll() external override {
        uint _withdraw = balanceOf(msg.sender);

        totalShares = totalShares.sub(_shares[msg.sender]);
        delete _shares[msg.sender];

        uint _before = _stakingToken.balanceOf(address(this));
        MDEX_MASTER_CHEF.withdraw(pid, _withdraw);
        uint _after = _stakingToken.balanceOf(address(this));
        _withdraw = _after.sub(_before);

        uint principal = _principal[msg.sender];
        uint depositTimestamp = _depositedAt[msg.sender];
        delete _principal[msg.sender];
        delete _depositedAt[msg.sender];

        uint withdrawalFee;
        if (canMint() && _withdraw > principal) {
            uint profit = _withdraw.sub(principal);
            withdrawalFee = _minter.withdrawalFee(_withdraw, depositTimestamp);
            uint performanceFee = _minter.performanceFee(profit);

            _minter.mintFor(address(_stakingToken), withdrawalFee, performanceFee, msg.sender, depositTimestamp);
            emit ProfitPaid(msg.sender, profit, performanceFee);

            _withdraw = _withdraw.sub(withdrawalFee).sub(performanceFee);
        }

        _stakingToken.safeTransfer(msg.sender, _withdraw);
        emit Withdrawn(msg.sender, _withdraw, withdrawalFee);
    }

    function harvest() external override onlyKeeper {
        MDEX_MASTER_CHEF.withdraw(pid, 0);
        getSwapRewards();
        uint mdxAmount = mdx.balanceOf(address(this));
        uint mdxForToken0 = mdxAmount.div(2);
        mdxToToken(_token0, mdxForToken0);
        mdxToToken(_token1, mdxAmount.sub(mdxForToken0));
        uint liquidity = generateFlipToken();
        MDEX_MASTER_CHEF.deposit(pid, liquidity);
        emit Harvested(liquidity);
    }

    function withdraw(uint256 shares) external override onlyWhitelisted {
        uint _withdraw = balance().mul(shares).div(totalShares);

        totalShares = totalShares.sub(shares);
        _shares[msg.sender] = _shares[msg.sender].sub(shares);

        uint _before = _stakingToken.balanceOf(address(this));
        MDEX_MASTER_CHEF.withdraw(pid, _withdraw);
        uint _after = _stakingToken.balanceOf(address(this));
        _withdraw = _after.sub(_before);

        _stakingToken.safeTransfer(msg.sender, _withdraw);
        emit Withdrawn(msg.sender, _withdraw, 0);
    }

    function getReward() external override {
        revert("N/A");
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function setFlipToken(address _token) private {
        _token0 = IMdxPair(_token).token0();
        _token1 = IMdxPair(_token).token1();

        _stakingToken.safeApprove(address(MDEX_MASTER_CHEF), uint(~0));

        IERC20(_token0).safeApprove(address(ROUTER), 0);
        IERC20(_token0).safeApprove(address(ROUTER), uint(~0));
        IERC20(_token1).safeApprove(address(ROUTER), 0);
        IERC20(_token1).safeApprove(address(ROUTER), uint(~0));
    }

    function _depositTo(uint _amount, address _to) private notPaused {
        uint _pool = balance();
        uint _before = _stakingToken.balanceOf(address(this));
        _stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint _after = _stakingToken.balanceOf(address(this));
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
        _depositedAt[_to] = block.timestamp;

        MDEX_MASTER_CHEF.deposit(pid, _amount);
        emit Deposited(_to, _amount);
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

    
    function getSwapRewards() private {
        uint getSwapping = mdx.balanceOf(address(this));
        SwapMing.takerWithdraw();
        uint getSwapped = mdx.balanceOf(address(this));
        totalSwapRewards = totalSwapRewards.add(getSwapped).sub(getSwapping);
    } 
 
    // function withdrawSwapRewards(address _dev) external onlyOwner{
    //     require(mdx.balanceOf(address(this)) > 0, 'Not Have SwapRewards.');
    //     mdx.safeTransfer(_dev,mdx.balanceOf(address(this)));
    // }
    /* ========== SALVAGE PURPOSE ONLY ========== */

    function recoverToken(address tokenAddress, uint tokenAmount) external override onlyOwner {
        require(tokenAddress != address(_stakingToken) && tokenAddress != address(mdx), "VaultFlipToFlip: cannot recover underlying token");
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}
