// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./IERC20.sol";

contract Staking is Ownable {
  IERC20 token;

  constructor(IERC20 _token) {
    token = _token;
  }

  uint256 public tokenBal;

  // reward per second per ether staked
  uint256 public rwdRte;

  bool public withdrawlPaused = false;
  uint256 public timeLock;

  event adminTokenTxn(string txnType, uint256 amt);
  event userStakeTxn(address userAddress, uint256 amt);
  event userUnstakeTxn(address userAddress, uint256 amt, uint256 reward);

  struct StakingAccount {
    uint256 balance;
    uint256 reward;
    uint256 lastRwd;
    uint256 begTime;
  }

  mapping(address => StakingAccount) public accounts;
  address[] private addresses;

  function withdrawToken(uint256 _amt) external onlyOwner {
    require(_amt <= tokenBal, "Insufficient token balance");
    tokenBal -= _amt;
    token.transfer(msg.sender, _amt);
    emit adminTokenTxn("withdraw", _amt);
  }

  function depositToken(uint256 _amt) external payable onlyOwner {
    token.transferFrom(msg.sender, address(this), _amt);
    tokenBal += _amt;
    emit adminTokenTxn("deposit", _amt);
  }

  function stake() public payable {
    require(accounts[msg.sender].balance == 0, "You are already staking");
    address userAddress = msg.sender;
    uint256 etherAmt = msg.value;
    addresses.push(userAddress);
    accounts[userAddress].balance += etherAmt;
    accounts[userAddress].lastRwd = block.timestamp;
    accounts[userAddress].begTime = block.timestamp;
    emit userStakeTxn(userAddress,etherAmt);
  }

  function unstake() public {
    require(accounts[msg.sender].balance > 0, "You are not staking");
    require(block.timestamp - accounts[msg.sender].begTime > timeLock,"You staking is time-locked");
    require(withdrawlPaused == false, "Withdrawl suspended");
    issueRwd(msg.sender);
    address userAddress = msg.sender;
    uint256 eth_amt = accounts[userAddress].balance;
    uint256 rwd = accounts[userAddress].reward;
    require(eth_amt <= address(this).balance && rwd <= tokenBal, "Insufficient assets in contract");
    tokenBal -= rwd;
    accounts[userAddress].balance = 0;
    accounts[userAddress].reward = 0;
    accounts[userAddress].lastRwd = 0;
    accounts[userAddress].begTime = 0;
    token.transfer(userAddress, rwd);
    payable(userAddress).transfer(eth_amt);
    
    emit userUnstakeTxn(msg.sender, eth_amt, rwd);
  }

  function adminIssueRwd() public onlyOwner {
    for (uint256 i=0; i < addresses.length; i++) {
      issueRwd(addresses[i]);
    }
  }

  function issueRwd(address _addr) private {
    accounts[_addr].reward += calcReward(accounts[_addr].lastRwd,accounts[_addr].balance);
    accounts[_addr].lastRwd = block.timestamp;
  }

  function viewRwd(address _addr) public view returns(uint256) {
    uint256 totalRwd = accounts[_addr].reward + calcReward(accounts[_addr].lastRwd, accounts[_addr].balance);
    return totalRwd;
  }

  function calcReward(uint256 _lastRwd, uint256 _amt) private view returns(uint256) {
    return (block.timestamp - _lastRwd) * rwdRte * (_amt / (10 ** 18));
  }

  function updateRwdRte(uint256 _newRwdRte) public onlyOwner {
    rwdRte = _newRwdRte;
  }

  function updateTimelock(uint256 _newTimelock) public onlyOwner {
    timeLock = _newTimelock;
  }

  function pauseWithdrawl(bool _op) public onlyOwner {
    withdrawlPaused = _op;
  }

  function balanceOf() public view returns(uint256) {
    return address(this).balance;
  }

  function withdrawETH(address payable _to, uint _amt) external onlyOwner{
    require(_amt <= balanceOf(), "Insufficient ETH balance");
    _to.transfer(_amt);
  }

  receive() external payable {
    stake();
  }
}
