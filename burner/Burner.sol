// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import './Privileges.sol';
import "./IERC20.sol";

contract Burner is FundPrivilege {
    // UA token
    IERC20 token;

    constructor(IERC20 _token) {
        token = _token;
    }

    // UA balance
    uint256 public tokenBal;

    // burnt UA
    uint256 public burntToken;

    // black hole address
    address blackHole = 0x0000000000000000000000000000000000000000;

    event adminTokenTxn(string txnType, uint256 amt);
    event tokenBurnt(uint256 amt);

    // admin withdraw UA in contract
    function withdrawToken(uint256 _amt) external onlyFundAdmin {
        require(_amt <= tokenBal, "Insufficient token balance");
        tokenBal -= _amt;
        token.transfer(msg.sender, _amt);

        emit adminTokenTxn("withdraw", _amt);
    }

    // admin deposit UA into contract
    function depositToken(uint256 _amt) external payable {
        token.transferFrom(msg.sender, address(this), _amt);
        tokenBal += _amt;

        emit adminTokenTxn("deposit", _amt);
    }

    function burnToken(uint256 _amt) external onlyFundAdmin {
        require(_amt <= tokenBal, "Insufficient token balance to burn");
        burntToken += _amt;
        tokenBal -= _amt;

        token.transfer(blackHole, _amt);

        emit tokenBurnt(_amt);
    }
}