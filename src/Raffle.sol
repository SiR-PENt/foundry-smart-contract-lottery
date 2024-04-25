// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-modifier: MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
/**
 * @title A Sample Reffle draw Contract
 * @author Olasunkanmi
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chainline VRFv2
 */

contract Raffle is VRFConsumerBaseV2 {
    //  this is for the entrance fee
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState); // errors can take parameters too

    // Type Declarations
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    // State Variables
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;


    uint256 private immutable i_entranceFee; // since we wont be changing the entrance fee, let's have it as immutable
    // @dev Duration of the lottery in secs
    uint256 private immutable i_interval; // the interval for when a winner should be picked after the lottery
    address payable[] private s_players; // an array of players' payable address
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator; 
    bytes32 private immutable i_gasLane;
    uint64  private immutable i_subscriptionId;
    uint32  private immutable i_callbackGasLimit;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    // Events
    event EnteredRaffle(address indexed player); //Indexed parameters are called topics
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor (uint256 entranceFee, uint256 interval,
     address vrfCoordinator,// address of the vrfcoordinator contract
     bytes32 gasLane,
     uint64 subscriptionId, uint32 callbackGasLimit) VRFConsumerBaseV2(vrfCoordinator) { //this statement "VRFConsumerBaseV2(vrfCoordinator)" is because the VRFconsumer also has a constructor i think
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator); //why are we type-casting this to the VRFCoordinatorV2Interface? okay, i think its so we can use the types declared in the interface
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() public payable {
     // we want people to pay a fee to enter a raffle
    //  require(msg.value >= i_entranceFee, "Not enough ETH sent!");
      if(msg.value < i_entranceFee) {
        revert Raffle__NotEnoughEthSent();
      }
      
      if(s_raffleState != RaffleState.OPEN) {
        revert Raffle__RaffleNotOpen();
      }

      s_players.push(payable(msg.sender));
      emit EnteredRaffle(msg.sender);
    }
     
     // when is the winner supposed to be picked
    /**
     * @dev This is the function that the Chainlink Automation nodes call
     * to see if it's time to perform an upkeep.
     * The following should be true for this to return true:
     * 1. The time interval HAS PASSED between raffle runs
     * 2. The raffle is in the OPEN state
     * 3. The contract has ETH (aka, players)
     * 4. (Implicit) The subscription is funded with LINK 
     */
    function checkUpkeep (bytes memory /* checkData */) public view 
    returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) > i_interval; // check if the time interval has passed
        bool isOpen = RaffleState.OPEN == s_raffleState; // check if the raffle is OPEN
        // check for balance and players
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0"); // the second argument here is for the commented param up i think 
    }
 
    //1. Get a random number
    //2. Use the random number to pick a player
    //3. Be automatically called 
    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if(!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING;
        // COORDINATOR is the chainlink VRF coordinator address we are going to make a request to
        // on every address that chainlink VRF exists, there's an address that allows you to make requests to a chainlink node 
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, // gas lane
            i_subscriptionId, // id of the subscription that has been funded
            REQUEST_CONFIRMATIONS, // no of block confirmations
            i_callbackGasLimit, // to ensure we dont overspend
            NUM_WORDS //number of random number
        );
        emit RequestedRaffleWinner(requestId); // this is already emitted in the vrfcoordinatorv2mock contract. This is just for test purposes
    }

//  Remember the below design pattern
// CEI: Checks, Effects, Interactions

// HOW requestRandomWords AND fulfillRandomWords WORK.
// Click the requestRandomWords() function to send the request for random values to Chainlink VRF. 
// MetaMask opens and asks you to confirm the transaction. After you approve the transaction, Chainlink VRF processes your request. 
// Chainlink VRF fulfills the request and returns the random values to your contract in a callback to the fulfillRandomWords() function. 
// At this point, a new key requestId is added to the mapping s_requests.

    function fulfillRandomWords(
        uint256 /* requestId*/,
        uint256[] memory randomWords
    ) internal override { // i think we are overriding this function from the original contract: VRFConsumerBaseV2
       uint256 indexOfWinner = randomWords[0] % s_players.length; // get the index of the winner
       address payable winner = s_players[indexOfWinner]; // assign the address in the index as the winner
       s_recentWinner = winner;
       s_raffleState = RaffleState.OPEN;
       
       s_players = new address payable[](0); //reset the array to an empty array for a new session
       s_lastTimeStamp = block.timestamp; // reset the timestamp to an empty time for a new session
       (bool success, ) = winner.call{value: address(this).balance}(""); //transfer all the money in this address to the winner
       if(!success) {
        revert Raffle__TransferFailed();
       }
      // emit a log after a winner has been picked
      emit PickedWinner(winner);    
    }

    // getter functions
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getPlayerLength() external view returns (bool) {
        return s_players.length > 0;
    }

    function getInitialTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
