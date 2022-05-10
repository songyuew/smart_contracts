// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Privileges.sol";
import "./IERC20.sol";

contract LP is FundPrivilege, ParamPrivilege {

  ///////////////////////////
  // Staking
  ///////////////////////////

  // UA token
  IERC20 token;

  constructor(IERC20 _token) {
    token = _token;
  }

  // UA balance
  uint256 public tokenBal;

  // Tier 1,2,3 reward rate (wei UA per second per ether staked)
  uint256 public rwdRte1 = 792744799600; // approx. 2.5% APY
  uint256 public rwdRte2 = 1109842719000; // approx. 3.5% APY
  uint256 public rwdRte3 = 1585489599000; // approx. 5% APY
  // all APY calculations above are based on assumption of 1ETH = 3000USDT, 1UA = 3USDT

  // Tier 1,2 reward time (in second)
  uint256 public tierTime1 = 2592000; // 30 days
  uint256 public tierTime2 = 7776000; // 90 days

  // emergency switch for unstake operation
  bool public withdrawlPaused = false;

  // timelock in second
  uint256 public timeLock = 259200; // 3 days

  // in case of a bank-run, this address will be used to inject ETH into LP
  // ETH deposit from this address will not be recorded as staking, no reward issued
  address emergencyInjectionAddr;

  function setEIA(address _newEIA) public onlyParamAdmin {
    emergencyInjectionAddr = _newEIA;
  }

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

  // user stake ETH
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

  // user unstake ETH
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

  // write reward earned for all staking users (required before reward rate update)
  function adminIssueRwd() public onlyParamAdmin {
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
    uint256 duration = block.timestamp - _lastRwd;
    uint256 rwd;
    if (duration < tierTime1) {
      rwd = duration * rwdRte1 * (_amt / (10 ** 18));
    } else if (duration >= tierTime1 && duration < tierTime2) {
      rwd = duration * rwdRte2 * (_amt / (10 ** 18));
    } else if (duration >= tierTime2) {
      rwd = duration * rwdRte3 * (_amt / (10 ** 18));
    }
    return rwd;
  }

  // admin update reward rate
  function updateRwdRte(uint256 _tier, uint256 _newRwdRte) public onlyParamAdmin {
    require(_tier == 1 || _tier == 2 || _tier ==3, "Invalid input");
    if (_tier == 1) {
      rwdRte1 = _newRwdRte;
    } else if (_tier == 2) {
      rwdRte2 = _newRwdRte;
    } else if (_tier == 3) {
      rwdRte3 = _newRwdRte;
    } 
  }

  // admin update time requirements for tiers
  function updateTierTime(uint256 _tier, uint256 _newTierTime) public onlyParamAdmin {
    require(_tier == 1 || _tier == 2, "Invalid input");
    if (_tier == 1) {
      tierTime1 = _newTierTime;
    } else if (_tier == 2) {
      tierTime2 = _newTierTime;
    } 
  }

  // admin update time lock
  function updateTimelock(uint256 _newTimelock) public onlyParamAdmin {
    timeLock = _newTimelock;
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
    if (msg.sender != emergencyInjectionAddr) {
      stake();
    }
  }
  
  ///////////////////////////
  // Conversion
  ///////////////////////////

  address public launchPool;

  bool public sellingPaused = false;

  function setLaunchPool(address _launchPoolAddr) public onlyParamAdmin {
    launchPool = _launchPoolAddr;
  }

  struct uNFT {
    uint256 balance;
    IERC20 tokenContract;
    bool active;
  }

  mapping(uint256 => uNFT) public uNFTList;

  event adminuNFTTxn(uint256 id, string txnType, uint256 amt);
  event uNFTTxn(uint256 id, string txnType, address userAddr, uint256 amt);

  // list new uNFT product
  function adduNFT(uint256 _id, IERC20 _tokenContract) public onlyParamAdmin {
    require(uNFTList[_id].active == false, "This ID is used by another uNFT token");
    uNFTList[_id].tokenContract = _tokenContract;
    uNFTList[_id].active = true;
  }

  // deactive and reactivate uNFT product
  function delistNFT(uint256 _id, bool _op) public onlyParamAdmin {
    uNFTList[_id].active = _op;
  }

  function pauseUserSelling(bool _op) public onlyParamAdmin {
    sellingPaused = _op;
  }
  
  // Receive uNFT from launch pool
  function receiveuNFTFrontend(uint256 _id, uint256 _amt) public {
    require(msg.sender == launchPool, "This transaction is not from the launch pool");
    require(uNFTList[_id].active, "This uNFT product does not exist");
    uNFTList[_id].tokenContract.transferFrom(msg.sender, address(this), _amt);
    uNFTList[_id].balance += _amt;

    emit adminuNFTTxn(_id, "deposit", _amt);
    
  }

  // Pull uNFT from the trading user by backend
  function receiveuNFTBackend(uint256 _id, uint256 _amt, address _userAddr) public {
    require(uNFTList[_id].active, "This uNFT product does not exist");
    require(sellingPaused == false, "uNFT to ETH conversion suspended");
    uNFTList[_id].tokenContract.transferFrom(_userAddr, address(this), _amt);
    uNFTList[_id].balance += _amt;

    emit uNFTTxn(_id, "received", _userAddr, _amt);
  }

  // send uNFT to user
  function senduNFT(uint256 _id, address payable _userAddr, uint256 _amt) public onlyFundAdmin {
    require(uNFTList[_id].active, "This uNFT product does not exist");
    require(_amt <= uNFTList[_id].balance, "Insufficient uNFT balance");
    uNFTList[_id].balance -= _amt;
    uNFTList[_id].tokenContract.transfer(_userAddr, _amt);

    emit uNFTTxn(_id, "sent", _userAddr, _amt);
  }


}
