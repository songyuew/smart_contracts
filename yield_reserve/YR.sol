// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Privileges.sol";
import "./IERC20.sol";
import "./CompoundIR.sol";

contract YR is FundPrivilege, ParamPrivilege, CompoundIR {
  // UA token
  IERC20 token;

  constructor(IERC20 _token) {
    token = _token;
  }

  // UA balance
  uint256 public tokenBal;

  // UA staking reward rate parameter (see project reference)
  uint256 public rwdRteParam = 1000000017000000000000000000; // 70% APY

  // emergency switch for unstake operation
  bool public withdrawlPaused = false;

  event adminTokenTxn(string txnType, uint256 amt);
  event userStakeTxn(address userAddress, uint256 amt);
  event userUnstakeTxn(address userAddress, uint256 amt, uint256 reward);
  event transferETH(address to, uint256 amt);

  struct StakingAccount {
    uint256 balance;
    uint256 reward;
    uint256 lastRwd;
    uint256 begTime;
  }

  mapping(address => StakingAccount) public accounts;
  address[] private addresses;

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

  // user stake UA
  function stake(uint256 _amt) public payable {
    require(accounts[msg.sender].balance == 0, "You are already staking");
    address userAddress = msg.sender;

    token.transferFrom(userAddress, address(this), _amt);
    tokenBal += _amt;

    addresses.push(userAddress);
    accounts[userAddress].balance += _amt;
    accounts[userAddress].lastRwd = block.timestamp;
    accounts[userAddress].begTime = block.timestamp;

    emit userStakeTxn(userAddress, _amt);
  }

  // user unstake UA
  function unstake() public {
    require(accounts[msg.sender].balance > 0, "You are not staking");
    require(withdrawlPaused == false, "Withdrawl suspended");
    address userAddress = msg.sender;

    issueRwd(userAddress);
    uint256 amt = accounts[userAddress].balance;
    uint256 rwd = accounts[userAddress].reward;
    uint256 payout = amt + rwd;
    require(payout <= tokenBal, "Insufficient assets in contract");
    
    tokenBal -= payout;
    accounts[userAddress].balance = 0;
    accounts[userAddress].reward = 0;
    accounts[userAddress].lastRwd = 0;
    accounts[userAddress].begTime = 0;

    token.transfer(userAddress, payout);
    
    emit userUnstakeTxn(userAddress, amt, rwd);
  }

  function calcReward(uint256 _lastRwd, uint256 _amt) public view returns(uint256) {
    uint256 duration = block.timestamp - _lastRwd;
    uint256 total = accrueInterest(_amt, rwdRteParam, duration);
    uint256 rwd = total - _amt;
    return rwd;
  }
  
  function viewRwd(address _addr) public view returns(uint256) {
    uint256 totalRwd = accounts[_addr].reward + calcReward(accounts[_addr].lastRwd, accounts[_addr].balance);
    return totalRwd;
  }

  function issueRwd(address _addr) private {
    accounts[_addr].reward += calcReward(accounts[_addr].lastRwd,accounts[_addr].balance);
    accounts[_addr].lastRwd = block.timestamp;
  }

  // write reward earned for all staking users (required before reward rate update)
  function adminIssueRwd() public onlyParamAdmin {
    for (uint256 i=0; i < addresses.length; i++) {
      issueRwd(addresses[i]);
    }
  }

  // admin update reward rate
  function updateRwdRteParam(uint256 _newRwdRteParam) public onlyParamAdmin {
    rwdRteParam = _newRwdRteParam;
  }

  function pauseWithdrawl(bool _op) public onlyParamAdmin {
    withdrawlPaused = _op;
  }

  // ETH balance in LP
  function balanceOf() public view returns(uint256) {
    return address(this).balance;
  }

  // admin withdraw ETH in LP
  function withdrawETH(address payable _to, uint _amt) external onlyFundAdmin {
    require(_amt <= balanceOf(), "Insufficient ETH balance");
    _to.transfer(_amt);
    
    emit transferETH(_to, _amt);
  }

  receive() external payable {

  }


}