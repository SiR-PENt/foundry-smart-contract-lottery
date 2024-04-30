// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Test, console } from "forge-std/Test.sol";
import { Raffle } from '../../src/Raffle.sol';
import { DeployRaffle } from '../../script/DeployRaffle.s.sol';
import { HelperConfig } from '../../script/HelperConfig.s.sol';
import { Vm } from "forge-std/Vm.sol";
import { VRFCoordinatorV2Mock } from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";


contract RaffleTest is Test {

    // Events
    event EnteredRaffle(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee; 
    uint256 interval;
    address vrfCoordinator; 
    bytes32 gasLane;
    uint64 subscriptionId; 
    uint32 callbackGasLimit;
    address link;


    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    
    function setUp() external {
       DeployRaffle deployer = new DeployRaffle();
       (raffle, helperConfig) = deployer.run();
       (entranceFee, interval, vrfCoordinator, gasLane, subscriptionId, callbackGasLimit, link, ) = helperConfig.activeNetworkConfig();
       vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    // enterRaffle function tests

    function testRaffleRevertsWhenYouDontPayEnough() public {
      // Arrange
      vm.prank(PLAYER);
      vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
      raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    //this checks whether an event is emitted when a player enters the raffle
    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle)); // emit the event we are supposed to see during the next call.
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public { //error
       vm.prank(PLAYER);
       raffle.enterRaffle{value: entranceFee}();
       vm.warp(block.timestamp + interval + 1); // vm.warp checks current timestamp. Here we are adding it to the interval and 1 to ensure we are over the interval
       vm.roll(block.number + 1 ); // i think this is to increase the number of blocks subscribed to the contract
       raffle.performUpkeep(""); // now safely perform the upkeep, which means Raffle is now calculating
      
       vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
       vm.prank(PLAYER); 
       raffle.enterRaffle{value: entranceFee}();
    }

    // check upkeep

    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
       // Arrange
       vm.warp(block.timestamp + interval + 1);
       vm.roll(block.number + 1);

       (bool upkeepNeeded, ) = raffle.checkUpkeep("");
       // assert
       assert(!upkeepNeeded);   
    }

    function testCheckUpKeepReturnsFalseIfRaffleNotOpen() public { //error
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep(""); // this is will assign isOpen to false, there upkeep needed will also be false 
        
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded == false);
    }

    // write for testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(raffle.getLastTimeStamp() + 29);
        vm.roll(block.number + 1); 
        
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(raffle.getLastTimeStamp() + 31);
        vm.roll(block.number + 1); 
        
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded);
    }

    function testCheckPerformUpkeepCanRunOnlyIfCheckupkeepIsTrue() public { //error
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;

        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEnteredAndTimePassed {
        vm.recordLogs(); // get the values of all the events we emitted
        raffle.performUpkeep(""); //emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs(); // we'll get the requestId out of the ist of all the emitted events
        // all logs are recorded as bytes32 in foundry
        // now, since we know that there are two events to be emitted here: 
        // 1. in the vrfmock
        // 2. in the performupkeep function
        //  and we want to test for the second emitted event which is in index 1
        bytes32 requestId = entries[1].topics[1];  // this is how you get the requestid from an event 
        Raffle.RaffleState rState = raffle.getRaffleState();

        assert(uint256(rState) == 1);
        assert(uint256(requestId) > 0); //this will make sure that the requestId was actually generated
    }

    // fulfillRandomWords()

    modifier skipFork() { // this is to skip the fork if it's not on an anvil chain because fulfillRandomWords works totally differently from how it works on a real network
        if(block.chainid != 31337) { //anvil chainid
            return;
        }
        _;
    }
    // Fuzz tests
    // N.B: This test will be skipped when we are on a fork
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) 
    public raffleEnteredAndTimePassed skipFork {
        //  Arrange
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle)); // this is a fuzz test, because it is testing for multiple cases
        // now, the rzn why we have to mock the chainlink vrf is because on our local chain there's no chainlink vrf. So on a real testnet, this is not gonna work 
        // cos we are not the chainlink vrf and we cant call fulfillRandom words, only the chainlink node can
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() 
    public raffleEnteredAndTimePassed skipFork {
    //    Arrange
    uint256 additionalEntrants = 5;
    uint256 startingIndex = 1; // because one person has already entered the contract from the modifier, I think

    for(uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
        address player = address(uint160(i)); // this is to say an address should be generated for each of the numbers 
        hoax(player, STARTING_USER_BALANCE); // prank + deal = dont forget 
        raffle.enterRaffle{value: entranceFee}(); // each player enters the raffle here
    }

        uint256 prize = entranceFee * (additionalEntrants + 1); // to get the prize the winner won

        vm.recordLogs(); // get the values of all the events we emitted
        raffle.performUpkeep(""); //emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs(); // we'll get the requestId out of the ist of all the emitted events
        // all vm.logs are recorded as bytes32 in foundry
        // now, since we know that there are two events to be emitted here: 
        // 1. in the vrfmock
        // 2. in the performupkeep function
        //  and we want to test for the second emitted event which is in index 1
        bytes32 requestId = entries[1].topics[1]; // this will serve as the consumer
        // here we are going to pretend to be chainlink vrf to get a random number and pick a winner. I think this is because test runs on a local chain and there's no chainlink vrf on local
        // we'll call the fulfillRandomWords function from the mock,
        
        uint256 previousTimeStamp = raffle.getLastTimeStamp();
        
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId), 
            address(raffle) // this is the consumer
        );

        // Assert
        assert(uint256(raffle.getRaffleState()) == 0); // the raffle state resolves to open
        assert(raffle.getRecentWinner() != address(0)); // the winner's address is populated
        assert(raffle.getLengthOfPlayers() == 0);
        assert(previousTimeStamp < raffle.getLastTimeStamp());
        assert(raffle.getRecentWinner().balance == STARTING_USER_BALANCE + prize - entranceFee); // the winner had a balance before, then he won a prize which adds to it, but entranceFee has been paid from the starting user balance, so we have subtract it     
    } 

}
