contract Randao {
  struct Participant {
      uint256   secret;
      bytes32   commitment;
      uint256   reward;
      bool      revealed;
      bool      rewarded;
  }

  struct Consumer {
    address caddr;
    uint256 bountypot;
  }

  struct Campaign {
      uint32    bnum;
      uint96    deposit;
      uint8     commitBalkline;
      uint8     commitDeadline;

      uint16    revealsNum;
      uint256   random;
      bool      settled;
      uint256   bountypot;
      uint32    commitNum;

      mapping (address => Consumer) consumers;
      mapping (address => Participant) participants;
  }

  uint256 public numCampaigns;
  Campaign[] public campaigns;
  address public founder;

  uint256 public bounty          = 1 ether;
  uint8  public constant version = 1;

  event CampaignAdded(uint256 campaignID, uint32 bnum, uint96 deposit, uint8 commitBalkline, uint8 commitDeadline, uint256 bountypot);
  event Commit(uint256 CampaignId, address from, bytes32 commitment);
  event Reveal(uint256 CampaignId, address from, uint256 secret);
  event Follow(uint256 CampaignId, address from, uint256 bountypot);

  modifier timeLineCheck(uint32 _bnum, uint8 _commitBalkline, uint8 _commitDeadline) {
      if (block.number >= _bnum) throw;
      if (_commitBalkline <= 0) throw;
      if (_commitDeadline <= 0) throw;
      if (_commitDeadline >= _commitBalkline) throw;
      if (block.number >= _bnum - _commitBalkline) throw;
      _
  }

  // Prevents methods from perfoming any value transfer
  modifier noEther() { if (msg.value > 0) throw; _}

  modifier checkBounty { if (msg.value < bounty) throw; _}

  modifier moreThanZero(uint256 _deposit) { if (_deposit <= 0) throw; _}

  function Randao() {
      founder = msg.sender;
  }

  function newCampaign(
      uint32 _bnum,
      uint96 _deposit,
      uint8 _commitBalkline,
      uint8 _commitDeadline
  ) timeLineCheck(_bnum, _commitBalkline, _commitDeadline)
    checkBounty moreThanZero(_deposit) external returns (uint256 _campaignID) {
      _campaignID = campaigns.length++;
      Campaign c = campaigns[_campaignID];
      numCampaigns++;
      c.bnum = _bnum;
      c.deposit = _deposit;
      c.commitBalkline = _commitBalkline;
      c.commitDeadline = _commitDeadline;
      c.bountypot = msg.value;
      c.consumers[msg.sender] = Consumer(msg.sender, msg.value);
      CampaignAdded(_campaignID, _bnum, _deposit, _commitBalkline, _commitDeadline, msg.value);
  }

  function follow(uint256 _campaignID) checkBounty external returns (bool) {
      Campaign c = campaigns[_campaignID];
      if (block.number < c.bnum - c.commitDeadline) {
          Consumer consumer = c.consumers[msg.sender];
          if (consumer.caddr != 0) throw;
          c.bountypot += msg.value;
          c.consumers[msg.sender] = Consumer(msg.sender, msg.value);
          Follow(_campaignID, msg.sender, msg.value);
          return true;
      }
  }

  function commit(uint256 _campaignID, bytes32 _hs) external {
      Campaign c = campaigns[_campaignID];
      if (msg.value != c.deposit) throw;

      if (block.number >= c.bnum - c.commitBalkline
          && block.number < c.bnum - c.commitDeadline){
          if (_hs != "" && c.participants[msg.sender].commitment == ""){
              c.participants[msg.sender] = Participant(0, _hs, 0, false, false);
              c.commitNum++;
              Commit(_campaignID, msg.sender, _hs);
          } else {
              throw;
          }
      } else {
          throw;
      }
  }

  function getCommitment(uint256 _campaignID) noEther external returns (bytes32) {
      Campaign c = campaigns[_campaignID];
      Participant p = c.participants[msg.sender];
      return p.commitment;
  }

  function reveal(uint256 _campaignID, uint256 _s) noEther external {
      Campaign c = campaigns[_campaignID];
      if (block.number < c.bnum
          && block.number >= c.bnum - c.commitDeadline) {
          Participant p = c.participants[msg.sender];
          if (sha3(_s) == p.commitment && !p.revealed) {
              c.revealsNum++;
              p.secret = _s;
              p.revealed = true;
              c.random ^= p.secret;
              Reveal(_campaignID, msg.sender, _s);
        }
      }
  }

  function getRandom(uint256 _campaignID) noEther external returns (uint256) {
      Campaign c = campaigns[_campaignID];
      if (block.number >= c.bnum) {
          if (!c.settled) { c.settled = true; }
          if (c.revealsNum == c.commitNum) {
              return c.random;
          }
      }
  }

  function getMyBounty(uint256 _campaignID) noEther external {
      Campaign c = campaigns[_campaignID];
      if (c.settled == true) {
          Participant p = c.participants[msg.sender];
          if (!p.rewarded) {
              if (p.revealed) {
                  uint256 share;
                  if (c.commitNum > c.revealsNum) {
                      share = fines(c) / c.revealsNum;
                  } else {
                      share = c.bountypot / c.revealsNum;
                  }
                  transferBounty(c, p, share);
              } else {
                  if (c.revealsNum == 0) {
                      transferBounty(c, p, 0);
                  }
              }
          }
      }
  }

  function transferBounty(Campaign _c, Participant _p, uint256 _share) internal {
      _p.reward = _share;
      _p.rewarded = true;
      if (!msg.sender.send(_share + _c.deposit)) {
          _p.reward = 0;
          _p.rewarded = false;
      }
  }

  function fines(Campaign _c) internal returns (uint256) {
      return (_c.commitNum - _c.revealsNum) * _c.deposit;
  }

  function refundBounty(uint256 _campaignID) noEther external {
      Campaign c = campaigns[_campaignID];
      if (c.settled
          && c.consumers[msg.sender].caddr != msg.sender
          && c.revealsNum < c.commitNum
          && c.consumers[msg.sender].bountypot > 0) {
          uint256 bountypot = c.consumers[msg.sender].bountypot;
          c.consumers[msg.sender].bountypot = 0;
          if (!msg.sender.send(bountypot)) {
              c.consumers[msg.sender].bountypot = bountypot;
          }
      }
  }
}
