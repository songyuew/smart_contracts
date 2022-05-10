// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract SuperAdminPrivilege {
  address public superAdmin;

  constructor() {
    superAdmin = msg.sender;
  }

  modifier onlySuperAdmin() {
    require(msg.sender == superAdmin, "You are not authorized (super admin only)");
    _;
  }

  function transferSuperAdmin(address _newSuperAdmin) public onlySuperAdmin {
    if (_newSuperAdmin != address(0)) {
      superAdmin = _newSuperAdmin;
    }
  }
}

contract FundPrivilege is SuperAdminPrivilege {
  address public fundAdmin;

  constructor() {
    fundAdmin = msg.sender;
  }

  modifier onlyFundAdmin() {
    require(msg.sender == fundAdmin, "You are not authorized (fund admin only)");
    _;
  }

  function transferFundPrivilege(address _newFundAdmin) public onlySuperAdmin {
    if (_newFundAdmin != address(0)) {
      fundAdmin = _newFundAdmin;
    }
  }
}

contract ParamPrivilege is SuperAdminPrivilege {
  address public paramAdmin;

  constructor() {
    paramAdmin = msg.sender;
  }

  modifier onlyParamAdmin() {
    require(msg.sender == paramAdmin, "You are not authorized (param admin only)");
    _;
  }

  function transferParamPrivilege(address _newParamAdmin) public onlySuperAdmin {
    if (_newParamAdmin != address(0)) {
      paramAdmin = _newParamAdmin;
    }
  }
}