// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IMasterChef.sol";
import "../interfaces/IWallabyMinter.sol";
import "../interfaces/legacy/IStrategyHelper.sol";
import "../interfaces/legacy/IStrategyLegacy.sol";

contract WallabyHTPool is IStrategyLegacy, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public Wallaby;
    IERC20 public mdx;
    IERC20 public WHT;
    IERC20 public token;

    address PresalContract;
    uint public totalShares;
    mapping (address => uint) private _shares;
    mapping (address => uint) public depositedAt;

    IWallabyMinter public minter;
    IStrategyHelper public helper;

    constructor(
        IERC20 _Wallaby,
        IERC20 _mdx,
        IERC20 _WHT,
        IStrategyHelper _helper,
        address _presalecontract
    ) public {
        Wallaby = _Wallaby;
        mdx = _mdx;
        WHT = _WHT;
        helper = _helper;
        PresalContract = _presalecontract;
    }

    function setFlipToken(address _token) public onlyOwner {
        require(address(token) == address(0), "flip token set already");
        token = IERC20(_token);
    }

    function setMinter(IWallabyMinter _minter) external onlyOwner {
        minter = _minter;
        if (address(_minter) != address(0)) {
            token.safeApprove(address(_minter), 0);
            token.safeApprove(address(_minter), uint(~0));
        }
    }

    function setHelper(IStrategyHelper _helper) external onlyOwner {
        require(address(_helper) != address(0), "zero address");
        helper = _helper;
    }

    function balance() override public view returns (uint) {
        return token.balanceOf(address(this));
    }

    function balanceOf(address account) override public view returns(uint) {
        return _shares[account];
    }

    function withdrawableBalanceOf(address account) override public view returns (uint) {
        return _shares[account];
    }

    function sharesOf(address account) public view returns (uint) {
        return _shares[account];
    }

    function principalOf(address account) override public view returns (uint) {
        return _shares[account];
    }

    function profitOf(address account) override public view returns (uint _usd, uint _wallaby, uint _HT) {
        if (address(minter) == address(0) || !minter.isMinter(address(this))) {
            return (0, 0, 0);
        }
        return (0, minter.amountwallabyToMintForwallabyHT(balanceOf(account), block.timestamp.sub(depositedAt[account])), 0);
    }

    function tvl() override public view returns (uint) {
        return helper.tvl(address(token), balance());
    }

    function apy() override public view returns(uint _usd, uint _wallaby, uint _HT) {
        if (address(minter) == address(0) || !minter.isMinter(address(this))) {
            return (0, 0, 0);
        }

        uint amount = 1e18;
        uint wallaby = minter.amountwallabyToMintForwallabyHT(amount, 365 days);
        uint _tvl = helper.tvlInHT(address(token), amount);
        uint wallabyPrice = helper.tokenPriceInHT(address(Wallaby));

        return (wallaby.mul(wallabyPrice).div(_tvl), 0, 0);
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

    function depositTo(uint256, uint256 _amount, address _to) external {
        require(msg.sender == PresalContract || msg.sender == owner(), "not presale contract");
        _depositTo(_amount, _to);
    }

    function _depositTo(uint _amount, address _to) private {
        token.safeTransferFrom(msg.sender, address(this), _amount);

        uint amount = _shares[_to];
        if (amount != 0 && depositedAt[_to] != 0) {
            uint duration = block.timestamp.sub(depositedAt[_to]);
            mintwallaby(amount, duration);
        }

        totalShares = totalShares.add(_amount);
        _shares[_to] = _shares[_to].add(_amount);
        depositedAt[_to] = block.timestamp;
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
        uint depositTimestamp = depositedAt[msg.sender];
        delete depositedAt[msg.sender];

        mintwallaby(_withdraw, block.timestamp.sub(depositTimestamp));
        token.safeTransfer(msg.sender, _withdraw);
    }

    function mintwallaby(uint amount, uint duration) private {
        if (address(minter) == address(0) || !minter.isMinter(address(this))) {
            return;
        }

        minter.mintForwallabyHT(amount, duration, msg.sender);
    }

    function harvest() override external {

    }

    function withdraw(uint256) override external {
        revert("Use withdrawAll");
    }

    function getReward() override external {
        revert("Use withdrawAll");
    }
}