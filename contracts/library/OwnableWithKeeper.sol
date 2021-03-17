// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../openzeppelin/contracts/GSN/Context.sol";

contract OwnableWithKeeper is Context {
    address private _owner;
    address private _keeper;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event KeeperTransferred(address indexed previousKeeper, address indexed newKeeper);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner and keeper.
     */
    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        _keeper = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
        emit KeeperTransferred(address(0), msgSender);
    }

    /**
      * @dev Returns the address of the current owner.
      */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Returns the address of the current keeper.
     */
    function keeper() public view returns (address) {
        return _keeper;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "OwnableWithKeeper: caller is not the owner");
        _;
    }

    /**
     * @dev Throws if called by any account other than the owner or keeper.
     */
    modifier onlyAuthorized() {
        require(_owner == _msgSender() || _keeper == _msgSender(), "OwnableWithKeeper: caller is not the owner or keeper");
        _;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "OwnableWithKeeper: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    /**
     * @dev Transfers keeper of the contract to a new account (`newKeeper`).
     * Can only be called by the current owner or keeper.
     */
    function transferKeeper(address newKeeper) public virtual onlyAuthorized {
        require(newKeeper != address(0), "OwnableWithKeeper: new keeper is the zero address");
        emit KeeperTransferred(_owner, newKeeper);
        _keeper = newKeeper;
    }
}
