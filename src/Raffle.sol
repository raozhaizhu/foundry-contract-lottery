// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {console} from "forge-std/console.sol";

/**
 * @title A sample Raffle contract
 * @author Rzz
 * @notice This contract is for creating a sample raffle
 * @dev Implements ChainLInk VRFv2.5
 */

contract Raffle is VRFConsumerBaseV2Plus {
    /** Errors */
    error Raffle_SendMoreTOEnterRaffle();
    error Raffle_TransferFailed();
    error Raffle_RaffleNotOpen();
    error Raffle_UpkeepNotNeeded(
        uint256 balance,
        uint256 playersLength,
        uint256 raffleState
    );

    /** Type Variations */
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
    }

    /** State Variables */
    uint16 private constant REQUEST_CONFIRMATION = 3;
    uint16 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLImit;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /** Events */
    event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffledWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLImit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    /** Contracts */
    function enterRaffle() external payable {
        // Checks
        if (msg.value < i_entranceFee) revert Raffle_SendMoreTOEnterRaffle();
        if (s_raffleState != RaffleState.OPEN) revert Raffle_RaffleNotOpen();

        // Effects
        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender);
    }

    /**
     * @dev This is the function that the Chainlink nodes will call to sealed
     * if the latest is ready to have a winner
     * The following should be true in order to upkeepNeeded to be true:
     * 1.The time interval has passed between raffle runs
     * 2. The lottery is open
     * 3. The contract has ETH
     * 4. Implicitly,your subscription has LINK.
     * @param -ignored
     * @return upkeepNeeded
     * @return -ignored
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /** performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded)
            revert Raffle_UpkeepNotNeeded(
                address(this).balance,
                uint256(s_players.length),
                uint256(s_raffleState)
            );

        s_raffleState = RaffleState.CALCULATING;

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATION,
                callbackGasLimit: i_callbackGasLImit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffledWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] calldata randomWords
    ) internal override {
        // Checks
        // require(sth)

        // Effect (With Internal Contract State)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];

        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(s_recentWinner);

        // Interactions (External Contract Interactions)
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) revert Raffle_TransferFailed();
    }

    /** Getter Functions */
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

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}

// forge install smartcontractkit/chainlink-brownie-contracts@1.1.1
