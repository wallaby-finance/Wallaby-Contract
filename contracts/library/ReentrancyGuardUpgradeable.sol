// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

// import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

// library AddressUpgradeable {
//     /**
//      * @dev Returns true if `account` is a contract.
//      *
//      * [IMPORTANT]
//      * ====
//      * It is unsafe to assume that an address for which this function returns
//      * false is an externally-owned account (EOA) and not a contract.
//      *
//      * Among others, `isContract` will return false for the following
//      * types of addresses:
//      *
//      *  - an externally-owned account
//      *  - a contract in construction
//      *  - an address where a contract will be created
//      *  - an address where a contract lived, but was destroyed
//      * ====
//      */
//     function isContract(address account) internal view returns (bool) {
//         // This method relies on extcodesize, which returns 0 for contracts in
//         // construction, since the code is only stored at the end of the
//         // constructor execution.

//         uint256 size;
//         // solhint-disable-next-line no-inline-assembly
//         assembly { size := extcodesize(account) }
//         return size > 0;
//     }

//     /**
//      * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
//      * `recipient`, forwarding all available gas and reverting on errors.
//      *
//      * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
//      * of certain opcodes, possibly making contracts go over the 2300 gas limit
//      * imposed by `transfer`, making them unable to receive funds via
//      * `transfer`. {sendValue} removes this limitation.
//      *
//      * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
//      *
//      * IMPORTANT: because control is transferred to `recipient`, care must be
//      * taken to not create reentrancy vulnerabilities. Consider using
//      * {ReentrancyGuard} or the
//      * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
//      */
//     function sendValue(address payable recipient, uint256 amount) internal {
//         require(address(this).balance >= amount, "Address: insufficient balance");

//         // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
//         (bool success, ) = recipient.call{ value: amount }("");
//         require(success, "Address: unable to send value, recipient may have reverted");
//     }

//     /**
//      * @dev Performs a Solidity function call using a low level `call`. A
//      * plain`call` is an unsafe replacement for a function call: use this
//      * function instead.
//      *
//      * If `target` reverts with a revert reason, it is bubbled up by this
//      * function (like regular Solidity function calls).
//      *
//      * Returns the raw returned data. To convert to the expected return value,
//      * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
//      *
//      * Requirements:
//      *
//      * - `target` must be a contract.
//      * - calling `target` with `data` must not revert.
//      *
//      * _Available since v3.1._
//      */
//     function functionCall(address target, bytes memory data) internal returns (bytes memory) {
//       return functionCall(target, data, "Address: low-level call failed");
//     }

//     /**
//      * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
//      * `errorMessage` as a fallback revert reason when `target` reverts.
//      *
//      * _Available since v3.1._
//      */
//     function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
//         return functionCallWithValue(target, data, 0, errorMessage);
//     }

//     /**
//      * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
//      * but also transferring `value` wei to `target`.
//      *
//      * Requirements:
//      *
//      * - the calling contract must have an ETH balance of at least `value`.
//      * - the called Solidity function must be `payable`.
//      *
//      * _Available since v3.1._
//      */
//     function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
//         return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
//     }

//     /**
//      * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
//      * with `errorMessage` as a fallback revert reason when `target` reverts.
//      *
//      * _Available since v3.1._
//      */
//     function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
//         require(address(this).balance >= value, "Address: insufficient balance for call");
//         require(isContract(target), "Address: call to non-contract");

//         // solhint-disable-next-line avoid-low-level-calls
//         (bool success, bytes memory returndata) = target.call{ value: value }(data);
//         return _verifyCallResult(success, returndata, errorMessage);
//     }

//     /**
//      * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
//      * but performing a static call.
//      *
//      * _Available since v3.3._
//      */
//     function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
//         return functionStaticCall(target, data, "Address: low-level static call failed");
//     }

//     /**
//      * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
//      * but performing a static call.
//      *
//      * _Available since v3.3._
//      */
//     function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
//         require(isContract(target), "Address: static call to non-contract");

//         // solhint-disable-next-line avoid-low-level-calls
//         (bool success, bytes memory returndata) = target.staticcall(data);
//         return _verifyCallResult(success, returndata, errorMessage);
//     }

//     function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
//         if (success) {
//             return returndata;
//         } else {
//             // Look for revert reason and bubble it up if present
//             if (returndata.length > 0) {
//                 // The easiest way to bubble the revert reason is using memory via assembly

//                 // solhint-disable-next-line no-inline-assembly
//                 assembly {
//                     let returndata_size := mload(returndata)
//                     revert(add(32, returndata), returndata_size)
//                 }
//             } else {
//                 revert(errorMessage);
//             }
//         }
//     }
// }


// abstract contract Initializable {

//     /**
//      * @dev Indicates that the contract has been initialized.
//      */
//     bool private _initialized;

//     /**
//      * @dev Indicates that the contract is in the process of being initialized.
//      */
//     bool private _initializing;

//     /**
//      * @dev Modifier to protect an initializer function from being invoked twice.
//      */
//     modifier initializer() {
//         require(_initializing || _isConstructor() || !_initialized, "Initializable: contract is already initialized");

//         bool isTopLevelCall = !_initializing;
//         if (isTopLevelCall) {
//             _initializing = true;
//             _initialized = true;
//         }

//         _;

//         if (isTopLevelCall) {
//             _initializing = false;
//         }
//     }

//     /// @dev Returns true if and only if the function is running in the constructor
//     function _isConstructor() private view returns (bool) {
//         return !AddressUpgradeable.isContract(address(this));
//     }
// }


/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuardUpgradeable is Initializable {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    function __ReentrancyGuard_init() internal initializer {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal initializer {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
    uint256[49] private __gap;
}
