// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../openzeppelin/contracts/math/SafeMath.sol";
import "../openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IWallabyMinter.sol";
import '../interfaces/ILErc20Delegator.sol';
import '../interfaces/IUnitroller.sol';
import "./VaultController.sol";
import {PoolConstant} from "../library/PoolConstant.sol";

contract VaultMdxToMdx is VaultController, IStrategy {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* ========== CONSTANTS ============= */
    IERC20 private  StakingToken;   // = IERC20(0x25D2e80cB6B86881Fd7e07dd263Fb79f4AbE033c);   //staking and rewards token
    IERC20 private constant LHB = IERC20(0x8F67854497218043E1f72908FFE38D0Ed7F24721);    //rewadrs token
    ILErc20Delegator private  CTokenPool;// = ILErc20Delegator(0x6c4b0a4c19E0a842580dd116A306f297dc28cAC6); //masterchef / hecopool
    address private  ctoken;             // = 0x6c4b0a4c19E0a842580dd116A306f297dc28cAC6;
    IUnitroller private constant UNITROLLER = IUnitroller(0x6537d6307ca40231939985BCF7D83096Dd1B4C09);//
    /* ========== STATE VARIABLES ========== */

    uint public  override pid;
    PoolConstant.PoolTypes public constant override poolType = PoolConstant.PoolTypes.mdxStake;

    uint public totalShares;
    uint public totalSwapRewards;
    mapping (address => uint) private _shares;
    mapping (address => uint) private _principal;
    mapping (address => uint) private _depositedAt;

    /* ========== INITIALIZER ========== */

    function initialize(address _stakingtoken,address _ctoken,uint _pid) external initializer {
        StakingToken = IERC20(_stakingtoken);
        __VaultController_init(IERC20(StakingToken));     //初始化staking token
        ctoken = _ctoken;
        CTokenPool = ILErc20Delegator(ctoken);
        StakingToken.safeApprove(address(CTokenPool), uint(~0));
        pid = _pid;
        setMinter(IWallabyMinter(0x7A631cAa46a451E1844f83114cd74CD1DE07D86F));
    }

    /* ========== VIEW FUNCTIONS ========== */

    function swapRwards() public view returns (uint){
        return totalSwapRewards;
    }

    function balance() override public view returns (uint) {
        uint amount = CTokenPool.balanceOf(address(this));
        return amount;
    }

    function balanceOf(address account) public view override returns(uint) {
        if (totalShares == 0) return 0;
        uint exchangRate = CTokenPool.exchangeRateStored();
        return balance().mul(sharesOf(account)).div(totalShares).mul(exchangRate).div(1e18);
    }

    function balanceOfImdx(address account) public view returns(uint) {
        if (totalShares == 0) return 0;
        return balance().mul(sharesOf(account)).div(totalShares);
    }

    function withdrawableBalanceOf(address account) public view override returns (uint) {
        return balanceOf(account);
    }

    function sharesOf(address account) public view override returns (uint) {
        return _shares[account];
    }

    function principalOf(address account) public view override returns (uint) {
        return _principal[account];
    }

    function earned(address account) public view override returns (uint) {
        if (balanceOf(account) >= principalOf(account)) {
            return balanceOf(account).sub(principalOf(account));
        } else {
            return 0;
        }
    }

    function priceShare() external view override returns(uint) {
        if (totalShares == 0) return 1e18;
        return balance().mul(1e18).div(totalShares);
    }

    function depositedAt(address account) external view override returns (uint) {
        return _depositedAt[account];
    }

    function rewardsToken() external view override returns (address) {
        return address(_stakingToken);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function deposit(uint _amount) public override {
        _deposit(_amount, msg.sender);

        if (isWhitelist(msg.sender) == false) {
            _principal[msg.sender] = _principal[msg.sender].add(_amount);
            _depositedAt[msg.sender] = block.timestamp;
        }
    }

    function depositAll() external override {
        deposit(StakingToken.balanceOf(msg.sender));
    }

    function withdrawAll() external override {
        uint _withdraw = balanceOfImdx(msg.sender);

        totalShares = totalShares.sub(_shares[msg.sender]);
        delete _shares[msg.sender];

        uint _beforeRedeem = StakingToken.balanceOf(address(this));
        CTokenPool.redeem(_withdraw);
        uint _afterRedeem = StakingToken.balanceOf(address(this));

        uint principal = _principal[msg.sender];
        uint depositTimestamp = _depositedAt[msg.sender];
        delete _principal[msg.sender];
        delete _depositedAt[msg.sender];

        uint MdxBalance = _afterRedeem.sub(_beforeRedeem);

        uint withdrawalFee;
        if (canMint() &&  MdxBalance > principal) {
            uint profit = MdxBalance.sub(principal);
            withdrawalFee = _minter.withdrawalFee(MdxBalance, depositTimestamp);
            uint performanceFee = _minter.performanceFee(profit);

            _minter.mintFor(address(StakingToken), withdrawalFee, performanceFee, msg.sender, depositTimestamp);
            emit ProfitPaid(msg.sender, profit, performanceFee);

            MdxBalance = MdxBalance.sub(withdrawalFee).sub(performanceFee);
        }

        StakingToken.safeTransfer(msg.sender, MdxBalance);
        emit Withdrawn(msg.sender, MdxBalance, withdrawalFee);

        harvest();
    }

    function harvest() public override {
        CTokenPool.redeem(CTokenPool.balanceOf( address(this)));

        emit Harvested(StakingToken.balanceOf(address(this)));

        CTokenPool.mint(StakingToken.balanceOf(address(this)));
    }

    function withdraw(uint256 shares) external override onlyWhitelisted {
        uint _withdraw = balance().mul(shares).div(totalShares);
        totalShares = totalShares.sub(shares);
        _shares[msg.sender] = _shares[msg.sender].sub(shares);

        uint _beforeRedeem = StakingToken.balanceOf(address(this));
        CTokenPool.redeem(_withdraw);
        uint _afterRedeem = StakingToken.balanceOf(address(this));

        StakingToken.safeTransfer(msg.sender, _afterRedeem.sub(_beforeRedeem));
        emit Withdrawn(msg.sender, StakingToken.balanceOf(address(this)), 0);

        harvest();
    }

    function getReward() external override {
        revert("N/A");
    }
    function getSwapRewardsByClaim() public onlyOwner {
        address[] memory ctokens = new address[](1);

        ctokens[0] = ctoken;

        UNITROLLER.claimComp(address(this),ctokens);
       
        totalSwapRewards = LHB.balanceOf(address(this));
    }
    
    //withdraw the swaprewards
    function withdrawSwapRewards(address _dev) external onlyOwner{
        require(LHB.balanceOf(address(this)) > 0, 'Not Have SwapRewards.');
        LHB.transfer(_dev,LHB.balanceOf(address(this)));
    }
    /* ========== PRIVATE FUNCTIONS ========== */

    function _deposit(uint _amount, address _to) private notPaused {
        uint exchangRate = CTokenPool.exchangeRateStored();
        uint _pool = balance().mul(exchangRate).div(1e18);

        StakingToken.safeTransferFrom(msg.sender, address(this), _amount);
       
        uint shares = 0;
        if (totalShares == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalShares)).div(_pool);
        }

        totalShares = totalShares.add(shares);
        _shares[_to] = _shares[_to].add(shares);

        CTokenPool.mint(_amount);
        emit Deposited(msg.sender, _amount);

        harvest();
    }
    function recoverToken(address tokenAddress, uint tokenAmount) external override onlyOwner {
        require(tokenAddress != address(_stakingToken), "VaultFlipToFlip: cannot recover underlying token");
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}
