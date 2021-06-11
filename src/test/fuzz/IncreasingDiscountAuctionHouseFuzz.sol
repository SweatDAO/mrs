pragma solidity ^0.6.7;

import "./mocks/CollateralAuctionHouseMock.sol";
// import "ds-test/test.sol";

contract SAFEEngineMock {
    mapping (address => uint) public receivedCoin;
    mapping (address => uint) public sentCollateral;


    function transferInternalCoins(address,address to,uint256 val) public {
        receivedCoin[to] += val;
    }
    function transferCollateral(bytes32,address from,address,uint256 val) public {
        sentCollateral[from] += val;
    }
}
contract OracleRelayerMock {
    function redemptionPrice() public returns (uint256) {
        return 3.14 ether;
    }
}
contract LiquidationEngineMock {
    uint public removedCoinsFromAfuction;
    function removeCoinsFromAuction(uint256 val) public {
        removedCoinsFromAfuction += val;
    }
}

contract Feed {
    address public priceSource;
    uint256 public priceFeedValue;
    bool public hasValidValue;
    constructor(bytes32 initPrice, bool initHas) public {
        priceFeedValue = uint(initPrice);
        hasValidValue = initHas;
    }
    function set_val(uint newPrice) external {
        priceFeedValue = newPrice;
    }
    function set_price_source(address priceSource_) external {
        priceSource = priceSource_;
    }
    function set_has(bool newHas) external {
        hasValidValue = newHas;
    }
    function getResultWithValidity() external returns (uint256, bool) {
        return (priceFeedValue, hasValidValue);
    }
}

// @notice Fuzz the whole thing, assess the results to see if failures make sense
contract GeneralFuzz is IncreasingDiscountCollateralAuctionHouseMock {

    constructor() public
        IncreasingDiscountCollateralAuctionHouseMock(
            address(0x1),
            address(0x2),
            "ETH-A"
        ){}


}

// @notice Will create an auction, to enable fuzzing the bidding function
contract FuzzBids is IncreasingDiscountCollateralAuctionHouseMock{
    address auctionIncomeRecipient = address(0xfab);
    address _forgoneCollateralReceiver = address(0xacab);
    uint _amountToRaise = 50 * 10 ** 45;
    uint _amountToSell = 100 ether;

    constructor() public IncreasingDiscountCollateralAuctionHouseMock(
            address(new SAFEEngineMock()),
            address(new LiquidationEngineMock()),
            "ETH-A"
        ) {
            setUp();
        }

    function setUp() public
       {
            // creating feeds
            collateralFSM = OracleLike(address(new Feed(bytes32(uint256(3.14 ether)), true)));
            oracleRelayer = OracleRelayerLike(address(new OracleRelayerMock()));

            // starting an auction
            startAuction({ amountToSell: 100 ether
                                        , amountToRaise: _amountToRaise
                                        , forgoneCollateralReceiver: _forgoneCollateralReceiver
                                        , auctionIncomeRecipient: auctionIncomeRecipient
                                        , initialBid: 0
                                        });

            // auction initiated
            assert(bids[1].amountToRaise > 0);

        }

    // properties
    function echidna_auctionsStarted() public returns (bool) {
        return auctionsStarted == 1;
    }

    function echidna_collateralType() public returns (bool) {
        return collateralType == "ETH-A";
    }

    function echidna_minimumBid() public returns (bool) {
        return minimumBid == 5* 10**18;
    }

    function echidna_lastReadRedemptionPrice() public returns (bool) {
        return lastReadRedemptionPrice == 0 || lastReadRedemptionPrice == 3.14 ether;
    }

    function echidna_lowerCollateralMedianDeviation() public returns (bool) {
        return lowerCollateralMedianDeviation == 0.90E18;
    }

    function echidna_upperCollateralMedianDeviation() public returns (bool) {
        return upperCollateralMedianDeviation == 0.95E18;
    }

    function echidna_lowerSystemCoinMedianDeviation() public returns (bool) {
        return lowerSystemCoinMedianDeviation == 10 ** 18;
    }

    function echidna_upperSystemCoinMedianDeviation() public returns (bool) {
        return upperSystemCoinMedianDeviation == 10 ** 18;
    }

    function echidna_minSystemCoinMedianDeviation() public returns (bool) {
        return minSystemCoinMedianDeviation == 0.999E18;
    }

    function echidna_bids() public returns (bool) {

        // auction settled, auctionHouse deletes the bid
        if (bids[1].maxDiscount == 0) return true;
        uint raisedAmount = _amountToRaise - bids[1].amountToRaise;
        uint soldAmount   = _amountToSell - bids[1].amountToSell;

        if (soldAmount != SAFEEngineMock(address(safeEngine)).sentCollateral(address(this))) return false;
        if (raisedAmount != LiquidationEngineMock(address(liquidationEngine)).removedCoinsFromAfuction()) return false;

        if (bids[1].forgoneCollateralReceiver != _forgoneCollateralReceiver) return false;
        if (bids[1].auctionIncomeRecipient != auctionIncomeRecipient) return false;
        if (bids[1].maxDiscount < bids[1].currentDiscount) return false;

        return true;
    }


    // adding a directed bidding function
    // we trust the fuzzer will find it's way to the active auction (it does), but here we're forcing valid bids to make we make the most of the runs.
    // (the buyCollateral function is also fuzzed)
    // setting it's visibility to internal will prevent it to be called by echidna
    function bid(uint val) public {
        buyCollateral(1, val %  bids[1].amountToSell);
    }
}

// @notice Will allow echidna accounts to create auctions and bid
contract FuzzAuctionsAndBids is IncreasingDiscountCollateralAuctionHouseMock {

    address auctionIncomeRecipient = address(0xfab);
    address _forgoneCollateralReceiver = address(0xacab);
    uint _amountToRaise = 50 * 10 ** 45;
    uint _amountToSell = 100 ether;

    constructor() public IncreasingDiscountCollateralAuctionHouseMock(
            address(new SAFEEngineMock()),
            address(new LiquidationEngineMock()),
            "ETH-A"
        ) {
            setUp();
        }

    function setUp() public
       {
            // creating feeds
            collateralFSM = OracleLike(address(new Feed(bytes32(uint256(3.14 ether)), true)));
            oracleRelayer = OracleRelayerLike(address(new OracleRelayerMock()));

            // authing accounts, authing them will also allow to modify parameters
            authorizedAccounts[address(0x10000)] = 1;
            authorizedAccounts[address(0x20000)] = 1;
            authorizedAccounts[address(0xabc00)] = 1;
        }

    // properties
    function echidna_collateralType() public returns (bool) {
        return collateralType == "ETH-A";
    }

    function echidna_lastReadRedemptionPrice() public returns (bool) {
        return lastReadRedemptionPrice == 0 || lastReadRedemptionPrice == 3.14 ether;
    }

    function echidna_bids() public returns (bool) {
        uint raisedAmountSum;
        uint soldAmountSum;

        for (uint i = 1; i <= auctionsStarted; i++) {
            // auction settled, auctionHouse deletes the bid
            raisedAmountSum += _amountToRaise - bids[i].amountToRaise;
            soldAmountSum += _amountToSell - bids[i].amountToSell;
        }

        if (raisedAmountSum < SAFEEngineMock(address(safeEngine)).receivedCoin(auctionIncomeRecipient)) return false; // rad
        if (soldAmountSum < SAFEEngineMock(address(safeEngine)).sentCollateral(address(this))) return false;
        if (raisedAmountSum < LiquidationEngineMock(address(liquidationEngine)).removedCoinsFromAfuction()) return false; // failing
        return true;
    }

    // adding a directed bidding function
    // we trust the fuzzer will find it's way to the active auction (it does), but here we're forcing valid bids to make we make the most of the runs.
    // (the buyCollateral function is also fuzzed)
    // setting it's visibility to internal will prevent it to be called by echidna
    function bid(uint campaign, uint val) internal {
        buyCollateral(campaign % auctionsStarted, val %  bids[campaign % auctionsStarted].amountToSell);
    }
}