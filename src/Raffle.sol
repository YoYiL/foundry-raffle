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

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
//import {VRFV2PlusClient} from "@chainlink/contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

import {VRFV2PlusClient} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
//import {VRFConsumerBaseV2Plus} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {console} from "forge-std/console.sol"; // For debugging purposes, can be removed in production

/**
 * @title Raffle
 * @author YoYi
 * @notice This contract is for creating a sample raffle.
 * @dev Implements Chainlink VRFv2.5
 */

contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors */
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__NotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );
    /* Type Declarations */

    enum RaffleState {
        OPEN, // Raffle is open for entries,  0
        CALCULATING // Winner is being calculated,  1
    }

    /*  State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3; // Number of confirmations before fulfilling the request

    uint32 private constant NUM_WORDS = 1; // Number of random words to request
    // @dev The duration of the lottery in seconds.
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_entranceFee;
    uint32 private immutable i_callbackGasLimit; // Gas limit for the callback
    uint256 private immutable i_subscriptionId; // Subscription ID for VRF
    address payable[] private s_players; // Array to store players' addresses
    uint256 private s_lastTimeStamp;
    address private s_recentWinner; // Address of the most recent winner
    RaffleState private s_raffleState; // State of the raffle

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gaslane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        // s_vrfCoordinator.requestRandomWords();
        i_keyHash = gaslane; // Set the key hash for VRF
        i_subscriptionId = subscriptionId; // Set the subscription ID for VRF
        i_callbackGasLimit = callbackGasLimit; // Set the callback gas limit}

        s_raffleState = RaffleState.OPEN; // Initialize the raffle state to OPEN
        s_lastTimeStamp = block.timestamp; // Initialize the last timestamp
    }

    function enterRaffle() external payable {
        // Logic for entering the raffle
        // require(
        //     msg.value >= i_entranceFee,
        //     revert SendMoreToEnterRaffle()
        // );
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__NotOpen();
        }
        s_players.push(payable(msg.sender)); // Add player to the array
        emit RaffleEntered(msg.sender); // Emit event when a player enters
    }

    /**
     * @dev This is the function that the Chainlink Keeper nodes call
     * they look for `upkeepNeeded` to return True.
     * the following should be true for this to return true:
     * 1. The time interval has passed between raffle runs.
     * 2. The lottery is open.
     * 3. The contract has ETH.
     * 4. Implicity, your subscription is funded with LINK.
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasPlayers = (s_players.length > 0);
        bool hasBalance = (address(this).balance > 0);
        // console.log("raffle i_interval:", i_interval);
        // console.log("raffle isOpen:", isOpen);
        // console.log("raffle timePassed:", timePassed);
        // console.log("raffle hasPlayers:", hasPlayers);
        // console.log("raffle hasBalance:", hasBalance);

        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
        // console.log("Final upkeepNeeded:", upkeepNeeded);
    }

    function performUpkeep(bytes calldata /* performdata */) external {
        // check to see if enough time has passed
        (bool upkeepNeeded, ) = checkUpkeep(""); // Call checkUpkeep to ensure conditions are met
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            ); // Revert if upkeep is not needed
        }
        s_raffleState = RaffleState.CALCULATING; // Set the raffle state to CALCULATING

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestRaffleWinner(requestId); // Emit event when a request is made
    }

    // CEI: Check-Effect-Interaction
    function fulfillRandomWords(
        uint256,
        /*requestId*/ uint256[] calldata randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length; // Get a random index
        address payable recentWinner = s_players[indexOfWinner]; // Get the winner's address

        s_recentWinner = recentWinner; // Set the recent winner

        s_raffleState = RaffleState.OPEN; // Set the raffle state back to OPEN
        s_players = new address payable[](0); // Reset the players array
        s_lastTimeStamp = block.timestamp; // Update the last timestamp
        emit WinnerPicked(s_recentWinner); // Emit event when a winner is picked

        (bool success, ) = recentWinner.call{value: address(this).balance}(""); // Transfer the balance to the winner
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**
     * Getter Function
     */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getPlayersLength() public view returns (uint256) {
        return s_players.length;
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }
}
