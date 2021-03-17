// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/Math.sol";
import "../../openzeppelin/contracts/math/SafeMath.sol";
import "../../openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../library/ReentrancyGuard.sol";
import "../../library/legacy/RewardsDistributionRecipient.sol";
import "../../library/legacy/Pausable.sol";
import "../../interfaces/legacy/IStrategyHelper.sol";
import "../../interfaces/IMasterChef.sol";
import "../../interfaces/legacy/IMdxVault.sol";
import "../../interfaces/IWallabyMinter.sol";
import "../../interfaces/legacy/IStrategyLegacy.sol";

contract MdxFlipVault is IStrategyLegacy, RewardsDistributionRecipient, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */
    IMdxVault public rewardsToken;
    IERC20 public stakingToken;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 24 hours;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    /* ========== mdx     ============= */
    
    address public mdx;
    IMasterChef public mdx_MASTER_CHEF;

    uint public poolId;
    address public keeper;  
    mapping (address => uint) public depositedAt;

    /* ========== wallaby HELPER / MINTER ========= */
    IStrategyHelper public helper; 
    IWallabyMinter public minter;

    address public rewardsTokenInit;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        uint _pid,
        address _mdx,
        IMasterChef _mdx_MASTER_CHEF,
        address _keeper,
        IStrategyHelper _helper,
        IWallabyMinter _minter,
        address _rewardsTokenInit
    ) public {
        mdx = _mdx;
        mdx_MASTER_CHEF = _mdx_MASTER_CHEF;
        keeper = _keeper;
        helper = _helper;
        minter = _minter;
        rewardsTokenInit = _rewardsTokenInit;

        (address _token,,,) = mdx_MASTER_CHEF.poolInfo(_pid);
        stakingToken = IERC20(_token);
        stakingToken.safeApprove(address(mdx_MASTER_CHEF), uint(~0));
        poolId = _pid;

        rewardsDistribution = msg.sender;
       
        setMinter(minter);
        setRewardsToken(rewardsTokenInit);
    }

    /* ========== VIEWS ========== */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balance() override external view returns (uint) {
        return _totalSupply;
    }

    function balanceOf(address account) override external view returns (uint256) {
        return _balances[account];
    }

    function principalOf(address account) override external view returns (uint256) {
        return _balances[account];
    }

    function withdrawableBalanceOf(address account) override public view returns (uint) {
        return _balances[account];
    }

    // return mdxAmount, wallabyAmount, 0
    function profitOf(address account) override public view returns (uint _usd, uint _wallaby, uint _HT) {
        uint mdxVaultPrice = rewardsToken.priceShare();
        uint _earned = earned(account);
        uint amount = _earned.mul(mdxVaultPrice).div(1e18);

        if (address(minter) != address(0) && minter.isMinter(address(this))) {
            uint performanceFee = minter.performanceFee(amount);
            // mdx amount
            _usd = amount.sub(performanceFee);

            uint HTValue = helper.tvlInHT(mdx, performanceFee);
            // wallaby amount
            _wallaby = minter.amountwallabyToMint(HTValue);
        } else {
            _usd = amount;
            _wallaby = 0;
        }

        _HT = 0;
    }

    function tvl() override public view returns (uint) {
        uint stakingTVL = helper.tvl(address(stakingToken), _totalSupply);

        uint price = rewardsToken.priceShare();
        uint earned = rewardsToken.balanceOf(address(this)).mul(price).div(1e18);
        uint rewardTVL = helper.tvl(mdx, earned);

        return stakingTVL.add(rewardTVL);
    }

    function tvlStaking() external view returns (uint) {
        return helper.tvl(address(stakingToken), _totalSupply);
    }

    function tvlReward() external view returns (uint) {
        uint price = rewardsToken.priceShare();
        uint earned = rewardsToken.balanceOf(address(this)).mul(price).div(1e18);
        return helper.tvl(mdx, earned);
    }

    function apy() override public view returns(uint _usd, uint _wallaby, uint _HT) {
        uint dailyAPY = helper.compoundingAPY(poolId, 365 days).div(365);

        uint mdxAPY = helper.compoundingAPY(0, 1 days);
        uint mdxDailyAPY = helper.compoundingAPY(0, 365 days).div(365);

        // let x = 0.5% (daily flip apr)
        // let y = 0.87% (daily mdx apr)
        // sum of yield of the year = x*(1+y)^365 + x*(1+y)^364 + x*(1+y)^363 + ... + x
        // ref: https://en.wikipedia.org/wiki/Geometric_series
        // = x * (1-(1+y)^365) / (1-(1+y))
        // = x * ((1+y)^365 - 1) / (y)

        _usd = dailyAPY.mul(mdxAPY).div(mdxDailyAPY);
        _wallaby = 0;
        _HT = 0;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
        rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply)
        );
    }

    function earned(address account) public view returns (uint256) {
        return _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function _deposit(uint256 amount, address _to) private nonReentrant notPaused updateReward(_to) {
        require(amount > 0, "amount");
        _totalSupply = _totalSupply.add(amount);
        _balances[_to] = _balances[_to].add(amount);
        depositedAt[_to] = block.timestamp;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        mdx_MASTER_CHEF.deposit(poolId, amount);
        emit Staked(_to, amount);

        _harvest();
    }

    function deposit(uint256 amount) override public {
        _deposit(amount, msg.sender);
    }

    function depositAll() override external {
        deposit(stakingToken.balanceOf(msg.sender));
    }

    function withdraw(uint256 amount) override public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "amount");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        mdx_MASTER_CHEF.withdraw(poolId, amount);

        if (address(minter) != address(0) && minter.isMinter(address(this))) {
            uint _depositedAt = depositedAt[msg.sender];
            uint withdrawalFee = minter.withdrawalFee(amount, _depositedAt);
            if (withdrawalFee > 0) {
                uint performanceFee = withdrawalFee.div(100);
                minter.mintFor(address(stakingToken), withdrawalFee.sub(performanceFee), performanceFee, msg.sender, _depositedAt);
                amount = amount.sub(withdrawalFee);
            }
        }

        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);

        _harvest();
    }

    function withdrawAll() override external {
        uint _withdraw = withdrawableBalanceOf(msg.sender);
        if (_withdraw > 0) {
            withdraw(_withdraw);
        }
        getReward();
    }

    function getReward() override public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.withdraw(reward);
            uint mdxBalance = IERC20(mdx).balanceOf(address(this));

            if (address(minter) != address(0) && minter.isMinter(address(this))) {
                uint performanceFee = minter.performanceFee(mdxBalance);
                minter.mintFor(mdx, 0, performanceFee, msg.sender, depositedAt[msg.sender]);
                mdxBalance = mdxBalance.sub(performanceFee);
            }

            IERC20(mdx).safeTransfer(msg.sender, mdxBalance);
            emit RewardPaid(msg.sender, mdxBalance);
        }
    }

    function harvest() override public {
        mdx_MASTER_CHEF.withdraw(poolId, 0);
        _harvest();
    }

    function _harvest() private {
        uint mdxAmount = IERC20(mdx).balanceOf(address(this));
        uint _before = rewardsToken.sharesOf(address(this));
        rewardsToken.deposit(mdxAmount);
        uint amount = rewardsToken.sharesOf(address(this)).sub(_before);
        if (amount > 0) {
            _notifyRewardAmount(amount);
        }
    }

    function info(address account) override external view returns(UserInfo memory) {
        UserInfo memory userInfo;

        userInfo.balance = _balances[account];
        userInfo.principal = _balances[account];
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

    /* ========== RESTRICTED FUNCTIONS ========== */
    function setKeeper(address _keeper) external {
        require(msg.sender == _keeper || msg.sender == owner(), 'auth');
        require(_keeper != address(0), 'zero address');
        keeper = _keeper;
    }

    function setMinter(IWallabyMinter _minter) public onlyOwner {
        // can zero
        minter = _minter;
        if (address(_minter) != address(0)) {
            IERC20(mdx).safeApprove(address(_minter), 0);
            IERC20(mdx).safeApprove(address(_minter), uint(~0));

            stakingToken.safeApprove(address(_minter), 0);
            stakingToken.safeApprove(address(_minter), uint(~0));
        }
    }

    function setRewardsToken(address _rewardsToken) private onlyOwner {
        require(address(rewardsToken) == address(0), "set rewards token already");

        rewardsToken = IMdxVault(_rewardsToken);

        IERC20(mdx).safeApprove(_rewardsToken, 0);
        IERC20(mdx).safeApprove(_rewardsToken, uint(~0));
    }

    function setHelper(IStrategyHelper _helper) external onlyOwner {
        require(address(_helper) != address(0), "zero address");
        helper = _helper;
    }

    function notifyRewardAmount(uint256 reward) override public onlyRewardsDistribution {
        _notifyRewardAmount(reward);
    }

    function _notifyRewardAmount(uint256 reward) private updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint _balance = rewardsToken.sharesOf(address(this));
        require(rewardRate <= _balance.div(rewardsDuration), "reward");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(stakingToken) && tokenAddress != address(rewardsToken), "tokenAddress");
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(periodFinish == 0 || block.timestamp > periodFinish, "period");
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
}