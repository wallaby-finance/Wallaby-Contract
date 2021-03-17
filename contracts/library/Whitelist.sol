// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Whitelist is OwnableUpgradeable {
    mapping (address => bool) private _whitelist;

    event Whitelisted(address indexed _address, bool whitelist);

    modifier onlyWhitelisted {
        require(_whitelist[msg.sender], "Whitelist: caller is not on the whitelist");
        _;
    }

    function __Whitelist_init() internal initializer {
        __Ownable_init();
    }

    function isWhitelist(address _address) public view returns(bool) {
        return _whitelist[_address];
    }

    function setWhitelist(address _address, bool _on) external onlyOwner {
        _whitelist[_address] = _on;

        emit Whitelisted(_address, _on);
    }

    uint256[50] private __gap;
}
