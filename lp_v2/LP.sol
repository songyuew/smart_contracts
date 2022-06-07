// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

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
    
    // set reward tiers
    initRwdTiers();
  }

  // UA balance
  uint256 public tokenBal;

  // ETH stakers' rights
  uint256 public stakerRights;

  // emergency switch for unstake operation
  bool public withdrawlPaused = false;

  // in case of a bank-run, this address will be used to inject ETH into LP
  // ETH deposit from this address will not be recorded as staking, no reward issued
  address emergencyInjectionAddr;

  function setEIA(address _newEIA) public onlyParamAdmin {
    emergencyInjectionAddr = _newEIA;
  }

  event adminTokenTxn(string txnType, uint256 amt);
  event userStakeTxn(address userAddress, uint256 amt, uint256 rewardTier);
  event userUnstakeTxn(address userAddress, uint256 amt, uint256 reward);
  event transferETH(address to, uint256 amt);

  struct staking {
    uint256 balance;
    uint256 rte;
    uint256 period;
    uint256 begTime;
  }

  struct StakingAccount {
    uint256 index;
    mapping(uint256 => staking) portfolio;
  }

  mapping(address => StakingAccount) public accounts;

  struct RewardTier {
    uint256 rewardRte; // wei UA per second per ETH staked
    uint256 stakePeriod; // in seconds
  }

  mapping(uint256 => RewardTier) public rewardTiers;

  function initRwdTiers() private {
    // all APY calculations above are based on assumption of 1ETH = 3000USDT, 1UA = 3USDT
    rewardTiers[1].rewardRte = 3.1709792 * 10 ** 11; // approx. 1% APY
    rewardTiers[1].stakePeriod = 604800; // 1 week
    rewardTiers[2].rewardRte = 1.5854896 * 10 ** 12; // approx. 5% APY
    rewardTiers[2].stakePeriod = 3024000; // 5 weeks
    rewardTiers[3].rewardRte = 2.85388128 * 10 ** 12; // approx. 9% APY
    rewardTiers[3].stakePeriod = 6048000; // 10 weeks
    rewardTiers[4].rewardRte = 5.70776256 * 10 ** 12; // approx. 18% APY
    rewardTiers[4].stakePeriod = 15120000; // 35 weeks
    rewardTiers[5].rewardRte = 9.5129376 * 10 ** 12; // approx. 30% APY
    rewardTiers[5].stakePeriod = 31449600; // 52 weeks
  }

  function updateRwdTier(uint256 _tierSel, uint256 _newRte, uint256 _newPeriod) public onlyParamAdmin {
    require(_tierSel == 1 || _tierSel == 2 || _tierSel == 3 || _tierSel == 4 || _tierSel == 5, "Invalid tier selection");
    rewardTiers[_tierSel].rewardRte = _newRte;
    rewardTiers[_tierSel].stakePeriod = _newPeriod;
  }

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
  function stake(uint256 _tierSel) external payable {
    require(_tierSel == 1 || _tierSel == 2 || _tierSel == 3 || _tierSel == 4 || _tierSel == 5, "Invalid tier selection");
    address userAddress = msg.sender;
    uint256 etherAmt = msg.value;
    uint256 currentIndex = accounts[userAddress].index;
    stakerRights += etherAmt;
    accounts[userAddress].portfolio[currentIndex].balance = etherAmt;
    accounts[userAddress].portfolio[currentIndex].begTime = block.timestamp;
    accounts[userAddress].portfolio[currentIndex].rte = rewardTiers[_tierSel].rewardRte;
    accounts[userAddress].portfolio[currentIndex].period = rewardTiers[_tierSel].stakePeriod;
    accounts[userAddress].index ++;
    emit userStakeTxn(userAddress,etherAmt,_tierSel);
  }

  // user unstake ETH
  function unstake(uint256 _index) public {
    address userAddress = msg.sender;
    require(accounts[userAddress].portfolio[_index].balance > 0, "No such staking");
    require(block.timestamp >= accounts[userAddress].portfolio[_index].begTime + accounts[userAddress].portfolio[_index].period, "Your staking is in lock period");
    require(withdrawlPaused == false, "Withdrawl suspended");   
    uint256 reward = getReward(userAddress,_index);
    uint256 eth_amt = accounts[userAddress].portfolio[_index].balance;
    require(eth_amt <= address(this).balance && reward <= tokenBal, "Insufficient assets in contract");
    tokenBal -= reward;
    accounts[userAddress].portfolio[_index].balance = 0;
    accounts[userAddress].portfolio[_index].rte = 0;
    accounts[userAddress].portfolio[_index].period = 0;
    accounts[userAddress].portfolio[_index].begTime = 0;
    stakerRights -= eth_amt;

    token.transfer(userAddress, reward);
    payable(userAddress).transfer(eth_amt);
    
    emit userUnstakeTxn(msg.sender, eth_amt, reward);
  }

  function getReward(address _addr,uint256 _index) public view returns(uint256) {
    require(accounts[_addr].portfolio[_index].balance > 0, "No such staking");
    uint256 duration = block.timestamp - accounts[_addr].portfolio[_index].begTime;
    return accounts[_addr].portfolio[_index].rte * duration * accounts[_addr].portfolio[_index].balance / 10 ** 18;
  }

  function getPrincipal(address _addr,uint256 _index) public view returns(uint256) {
    require(accounts[_addr].portfolio[_index].balance > 0, "No such staking");
    return accounts[_addr].portfolio[_index].balance;
  }

  function getDuration(address _addr,uint256 _index) public view returns(uint256) {
    require(accounts[_addr].portfolio[_index].balance > 0, "No such staking");
    return accounts[_addr].portfolio[_index].period;
  }

  function getBegTime(address _addr,uint256 _index) public view returns(uint256) {
    require(accounts[_addr].portfolio[_index].balance > 0, "No such staking");
    return accounts[_addr].portfolio[_index].begTime;
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
      revert();
    }
  }
  
  ///////////////////////////
  // Conversion
  ///////////////////////////

  bool public sellingPaused = false;

  struct uNFT {
    uint256 balance;
    IERC20 tokenContract;
    bool active;
  }

  mapping(uint256 => uNFT) public uNFTList;

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

  // Pull uNFT from the trading user or launch pool
  function receiveuNFT(uint256 _id, uint256 _amt, address _userAddr) public {
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
