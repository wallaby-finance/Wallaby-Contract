// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../interfaces/IMdexRouter.sol";
import "../interfaces/IMdxPair.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IMasterChef.sol";
import "../interfaces/IWallabyMinter.sol";
import "../library/PausableUpgradeable.sol";
import "../library/Whitelist.sol";


abstract contract VaultController is IVaultController, PausableUpgradeable, Whitelist {
    using SafeERC20 for IERC20;

    /* ========== CONSTANT VARIABLES ========== */
    ERC20 private constant Wallaby = ERC20(0x7A631cAa46a451E1844f83114cd74CD1DE07D86F);

    /* ========== STATE VARIABLES ========== */

    address public keeper;
    IERC20 internal _stakingToken;
    IWallabyMinter internal _minter;


    /* ========== Event ========== */

    event Recovered(address token, uint amount);


    /* ========== MODIFIERS ========== */

    modifier onlyKeeper {
        require(msg.sender == keeper || msg.sender == owner(), 'VaultController: caller is not the owner or keeper');
        _;
    }

    /* ========== INITIALIZER ========== */

    function __VaultController_init(IERC20 token) internal initializer {
        __PausableUpgradeable_init();
        __Whitelist_init();

        keeper = 0x1F0Bcd4dD90b59A96eFDA60E24E54B198dA975B5;
        _stakingToken = token;
    }

    /* ========== VIEWS FUNCTIONS ========== */

    function minter() external view override returns (address) {
        return canMint() ? address(_minter) : address(0);
    }

    function canMint() internal view returns (bool) {
        return address(_minter) != address(0) && _minter.isMinter(address(this));
    }

    function stakingToken() external view override returns (address) {
        return address(_stakingToken);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setKeeper(address _keeper) external onlyKeeper {
        require(_keeper != address(0), 'VaultController: invalid keeper address');
        keeper = _keeper;
    }

    function setMinter(IWallabyMinter newMinter) virtual public onlyOwner {
        // can zero
        _minter = newMinter;
        if (address(newMinter) != address(0)) {
            require(address(newMinter) == Wallaby.getOwner(), 'VaultController: not Wallaby minter');
            _stakingToken.safeApprove(address(newMinter), 0);
            _stakingToken.safeApprove(address(newMinter), uint(~0));
        }
    }

    /* ========== SALVAGE PURPOSE ONLY ========== */

    function recoverToken(address _token, uint amount) virtual external onlyOwner {
        require(_token != address(_stakingToken), 'VaultController: cannot recover underlying token');
        IERC20(_token).safeTransfer(owner(), amount);
    }

    /* ========== VARIABLE GAP ========== */

    uint256[50] private __gap;
}
