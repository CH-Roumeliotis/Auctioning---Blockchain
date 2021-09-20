pragma solidity >=0.4.22 <0.9.0;

contract SmartAuctioning {

    enum Status{Pending, Ended, PaidOut, NotDelivered}
    event newAuction(address indexed _seller, uint indexed _auctionID);
	event bidMade(address indexed _seller, address indexed _bidder, uint indexed _auctionID, uint _numBids, uint _value);
	event bidFailed(address indexed _seller, address indexed _bidder, uint indexed _auctionID, bytes32 _reason);
	event auctionEnded(address indexed _seller, address indexed _buyer, uint indexed _auctionID, uint _value);
	event fundsReleased(address indexed _seller, address indexed _buyer, uint indexed _auctionID, uint _value);

    //@notice time in second, insures that auction will end up in a reasonable amount of time
	uint constant maximumDuration = 1000000;

	struct Bid{
        address payable maker;
        uint amount;
    }

    struct Auction{
        bytes32 itemName;
		bytes32 releaseHash;
		address payable seller;
		uint deliveryDeadline;
		uint auctionEndTime;
		uint category;
		Status status;
		uint numBids;
		uint highestBid;
		mapping (uint => Bid) bids;
		mapping (address => uint) bidders;
    }

    struct Seller{
        uint numAuctions;
		mapping(uint => uint) auctions;
    }

    uint public numAuctions = 0;
	mapping (uint => Auction) public auctions;
	mapping (address => Seller) public sellers;
    bool allowAuctions = true;
	address owner;

    modifier hasValue {
        if(msg.value > 0) 
        _; 
    }

	//@notice Set the owner in order to close the auction. 
	function DBayContract() public {
		owner = msg.sender;
	}

    //@title add new auction
    //@param _auctionEndTime end time of an auction in order to check the duration
    function createAuction(bytes32 _itemName, uint _auctionEndTime, uint _category) public returns (uint auctionID){
		if (allowAuctions && _auctionEndTime > block.timestamp) {
            auctionID = numAuctions++; 
			Auction storage a = auctions[auctionID];
			a.itemName = _itemName;
			a.seller = msg.sender;
			a.auctionEndTime = _auctionEndTime;
			a.category = _category;
			a.status = Status.Pending;
			a.highestBid = 0;
			a.numBids = 0;
			Seller storage s = sellers[msg.sender];
			uint seller_auctionID = s.numAuctions++;
			s.auctions[seller_auctionID] = auctionID;
			emit newAuction(msg.sender, auctionID);
		}
	}

	function placeBid(uint _auctionID, bytes memory _releaseSecret) public payable hasValue {
		Auction storage a = auctions[_auctionID];

		if (a.seller != address(0x0)) {
			if (a.status == Status.Pending) {
				if (a.auctionEndTime >= block.timestamp) {
					if (a.seller != msg.sender) {
						Bid storage currentHighest = a.bids[a.highestBid];
						if (msg.value > currentHighest.amount) {
							uint bidID = a.numBids++;
							Bid storage b = a.bids[bidID];
							b.maker = msg.sender;
							b.amount = msg.value;
							a.highestBid = bidID;
							currentHighest.maker.transfer(currentHighest.amount);
							a.releaseHash = keccak256(_releaseSecret);
							a.bidders[b.maker] = bidID;
							emit bidMade(a.seller, msg.sender, _auctionID, a.numBids, b.amount);
							return;

						} else {
							emit bidFailed(a.seller, msg.sender, _auctionID, 'bid is less than the highest');

						}
					} else {
						emit bidFailed(a.seller, msg.sender, _auctionID, 'seller can\'t bid');

					}
				} else {
					emit bidFailed(a.seller, msg.sender, _auctionID, 'auction has just ended');
					endAuction(_auctionID);

				}
			} else {
				emit bidFailed(a.seller, msg.sender, _auctionID, 'auction has been closed');

			}
		} else {
			emit bidFailed(address(0x0), msg.sender, _auctionID, 'auction could not be found');

		}

		msg.sender.transfer(msg.value);
	}

	function endAuction(uint _auctionID) public {
		Auction storage a = auctions[_auctionID];
		if (a.seller != address(0x0)) {
			// allow the auction to be ended if the time limit has passed
			if (a.status == Status.Pending && block.timestamp >= a.auctionEndTime) {
				Bid storage highestBid = a.bids[a.highestBid];
				emit auctionEnded(a.seller, msg.sender, _auctionID, highestBid.amount);
				a.status = Status.Ended;
			}
		} else {
			emit bidFailed(address(0x0), msg.sender, _auctionID, 'Auction not found');
		}
	}

	function releaseFunds(uint _auctionID, bytes memory _releaseSecret) public payable {
		Auction storage a = auctions[_auctionID];
		if (a.seller != address(0x0)) {
			// allow the funds to be released to the seller if they can prove that they have received a matching secret from the buyer in exchange for handing the item over
			if (a.status == Status.Ended && keccak256(_releaseSecret) == a.releaseHash) {
				Bid storage highestBid = a.bids[a.highestBid];
				a.seller.transfer(highestBid.amount);
				a.status = Status.PaidOut;
			}
		} else {
			emit bidFailed(address(0x0), msg.sender, _auctionID, 'Auction not found');
		}
	}

	function notDelivered(uint _auctionID) public {
		Auction storage a = auctions[_auctionID];
		if (a.seller != address(0x0)) {
			// contract exists
			Bid storage highestBid = a.bids[a.highestBid];
			// allow the highest bidder to reclaim bid if seller has not yet delivered, and the delivery deadline has passed
			if (a.status == Status.Ended && block.timestamp >= a.auctionEndTime + a.deliveryDeadline && msg.sender == highestBid.maker) {
				highestBid.maker.transfer(highestBid.amount);
				a.status = Status.NotDelivered;
			}
		} else {
			emit bidFailed(address(0x0), msg.sender, _auctionID, 'Auction not found');
		}
	}
}