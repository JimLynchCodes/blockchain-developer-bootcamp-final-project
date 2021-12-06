// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.8;

/** Remix Imports */

// import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/master/contracts/access/Ownable.sol";
// import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/master/contracts/security/Pausable.sol";
// import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/master/contracts/token/ERC20/ERC20.sol";
// import "https://raw.githubusercontent.com/smartcontractkit/chainlink/v0.10.14/contracts/src/v0.8/VRFConsumerBase.sol";

/** NPM Imports */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

// Created by Jim!

/**
 *   A game where there are some face down cards (boardWidth * boardHeight)
 *
 *   Users pay 1 matic token to guess a card which is then revealed to all players.
 *
 *   There is 1 of each face card hidden in the pile.
 *
 *   The first user to find each face card gets paid according to this schedule:
 *
 *   ace   ->  acePayoutMultiplier
 *   king  ->  kingPayoutMultiplier
 *   queen ->  queenPayoutMultiplier
 *   jack ->   wins the progressive jackpot
 *
 *   A percentage of each user's bet (jackpotRakePercentage) is added to the pot for every wrong guess.
 *
 **/

contract CCGG_all is VRFConsumerBase, Ownable, Pausable {
    // address used for the server worker account
    address private worker = msg.sender;

    // contraints for how much user can bet
    uint256 public constant MIN_BET = 1 ether;
    uint256 public constant MAX_BET = 10 ether;

    uint256 constant CARDS_PER_LEVEL = 25;

    // cards per row
    uint256 public boardWidth = 10;

    // number of rows of cards
    uint256 public boardHeight = 10;

    // percentage of each user bet that gets added to the progressive jackpot
    uint256 jackpotRakePercentage = 25;

    // shrinks facecard payouts as level decreases
    uint256[] aceMultiplierLvls = [25, 15, 12, 3];
    uint256[] kingMultiplierLvls = [15, 10, 6, 2];
    uint256[] queenMultiplierLvls = [10, 5, 3, 1];

    mapping(address => string) nicknames;

    bool gameIsBeingCreated = true;

    enum FaceCard { Ace, King, Queen, Jack }

    struct GameState {
        bool gameIsBeingCreated;
        bool aceHasBeenFound;
        bool kingHasBeenFound;
        bool queenHasBeenFound;
        bool jackHasBeenFound;
        uint256 aceNum;
        uint256 kingNum;
        uint256 queenNum;
        uint256 jackNum;
        uint8 cardsChosen;
        uint256 currentLevel;
        uint256 jackpotSize;
        uint256[] revealedCards;
        string[] revealedCardValues;
    }

    bool public aceHasBeenFound;
    bool public kingHasBeenFound;
    bool public queenHasBeenFound;
    bool public jackHasBeenFound;

    uint256 aceNum;
    uint256 kingNum;
    uint256 queenNum;
    uint256 jackNum;

    uint8 public cardsChosen;
    uint256 public currentLevel;

    uint256 public jackpotSize;

    uint256[] revealedCards;
    string[] revealedCardValues;

    mapping(uint256 => string) internal currentBoard;

    mapping(uint256 => bool) alreadyChosenCards;

    event AceFound(address guesser, uint256 numGuessed, uint256 payoutAmount);
    event KingFound(address guesser, uint256 numGuessed, uint256 payoutAmount);
    event QueenFound(address guesser, uint256 numGuessed, uint256 payoutAmount);
    event JackFound(address guesser, uint256 numGuessed, uint256 payoutAmount);

    event FaceCardFound(
        address guesser,
        uint256 numGuessed,
        uint256 payoutAmount,
        FaceCard faceCardType
    );

    event JackpotSizeIncrease(
        address contributor,
        uint256 amountContributed,
        uint256 newJackpotSize,
        uint256 amountAddedToJackpot
    );

    event CardRevealed(uint256 cardNumber, string cardValue, address guessedBy);

    event GameOver();

    event NewGameCreated();

    event BoardIsReady();

    event GuessSubmitted(
        uint256 guessNumber,
        address guessedBy,
        uint256 betSize
    );

    event GameOverTimeout();

    bytes32 public keyHash;
    uint256 public fee;
    uint256 public randomResult;

    uint256 INITIAL_JACKPOT_SIZE = 1 ether;

    address mainnetLinkAddress = 0xb0897686c545045aFc77CF20eC7A532E3120E0F1;
    address testnetLinkAddress = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;

    address mainnetVrfCoordinator = 0x3d2341ADb2D31f1c5530cDC622016af293177AE0;
    address testnetVrfCoordinator = 0x8C7382F9D8f56b33781fE506E897a4F1e2d17255;

    bytes32 mainnetOracleKeyHash =
        0xf86195cf7690c55907b2b611ebb7343a6f649bff128701cc542f0569e2c549da;

    bytes32 testnetOracleKeyHash =
        0x6e75b569a01ef56d18cab6a8e71e6600d6ce853834d4a5748b720d06f878b3a4;

    uint256 MUMBAI_TESTNET_CHAINID = 80001;

    address __linkTokenAddress =
        getChainId() == MUMBAI_TESTNET_CHAINID
            ? testnetLinkAddress
            : mainnetLinkAddress;

    address __vrfCoordinatorAddress =
        getChainId() == MUMBAI_TESTNET_CHAINID
            ? testnetVrfCoordinator
            : mainnetVrfCoordinator;

    bytes32 __oracleKeyhash =
        getChainId() == MUMBAI_TESTNET_CHAINID
            ? testnetOracleKeyHash
            : mainnetOracleKeyHash;

    constructor()
        public
        VRFConsumerBase(__vrfCoordinatorAddress, __linkTokenAddress)
    {
        keyHash = __oracleKeyhash;

        fee = 0.0001 * 10**18; // 0.0001 Link

        // Set empty squares
        for (uint256 i = 1; i <= boardWidth * boardHeight; i++) {
            currentBoard[i] = "empty";
        }

        jackpotSize = INITIAL_JACKPOT_SIZE;
    }

    /**
     *        Randomness functions using Chainlink VRF
     **/
    function getRandomNumber()
        public
        returns (bytes32 requestId)
    {
        return requestRandomness(keyHash, fee);
    }

    /**
     * hardcoded Randomness
     **/
    // function requestRandomness(bytes32 _1, uint256 _2)
    //     internal
    //     returns (bytes32)
    // {
    //     aceNum = 1;
    //     currentBoard[aceNum] = "ace";

    //     kingNum = 2;
    //     currentBoard[kingNum] = "king";

    //     queenNum = 3;
    //     currentBoard[queenNum] = "queen";

    //     jackNum = 4;
    //     currentBoard[jackNum] = "jack";

    //     return __oracleKeyhash;
    // }

    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        uint256 newRandomNum = (randomness % (boardWidth * boardHeight)) + 1;

        // if that index is already a face card index, choose another random num.
        if (
            newRandomNum == aceNum ||
            newRandomNum == kingNum ||
            newRandomNum == queenNum ||
            newRandomNum == jackNum
        ) {
            requestRandomness(keyHash, fee);

            return;
        }

        // Now use random num as index of the next facecard whose value has not yet been set.

        if (aceNum == 0) {
            aceNum = newRandomNum;
            currentBoard[aceNum] = "ace";
        } else if (kingNum == 0) {
            kingNum = newRandomNum;
            currentBoard[kingNum] = "king";
        } else if (queenNum == 0) {
            queenNum = newRandomNum;
            currentBoard[queenNum] = "queen";
        } else if (jackNum == 0) {
            jackNum = newRandomNum;
            currentBoard[jackNum] = "jack";
            gameIsBeingCreated = false;
            emit BoardIsReady();
        }
    }

    /**
     *        function for front-end to get the current game state
     **/
    function getCurrentGameState() external view returns (GameState memory) {
        return
            GameState(
                gameIsBeingCreated,
                aceHasBeenFound,
                kingHasBeenFound,
                queenHasBeenFound,
                jackHasBeenFound,
                aceHasBeenFound ? aceNum : 0,
                kingHasBeenFound ? kingNum : 0,
                queenHasBeenFound ? queenNum : 0,
                jackHasBeenFound ? jackNum : 0,
                cardsChosen,
                currentLevel,
                jackpotSize,
                revealedCards,
                revealedCardValues
            );
    }

    function createNewBoard() public onlyWorker {
        getRandomNumber();
        getRandomNumber();
        getRandomNumber();
        getRandomNumber();

        emit NewGameCreated();
    }

    function destroyFinishedGameData() internal {
        
        gameIsBeingCreated = true;

        emit GameOver();

        for (uint256 i = 0; i < cardsChosen; i++) {
            delete alreadyChosenCards[revealedCards[i]];
        }

        currentBoard[aceNum] = "empty";
        currentBoard[kingNum] = "empty";
        currentBoard[queenNum] = "empty";
        currentBoard[jackNum] = "empty";

        aceHasBeenFound = false;
        kingHasBeenFound = false;
        queenHasBeenFound = false;
        jackHasBeenFound = false;

        aceNum = 0;
        kingNum = 0;
        queenNum = 0;
        jackNum = 0;

        cardsChosen = 0;
        currentLevel = 0;

        delete revealedCards;
        delete revealedCardValues;
    }

    /**
     *        function players call to make a bet
     **/
    function submitGuess(uint256 numGuessed) public payable whenNotPaused {
        require(
            msg.value >= MIN_BET,
            "please send more MATIC tokens with your guess!"
        );
        require(
            msg.value <= MAX_BET,
            "please send fewer MATIC tokens with your guess!"
        );

        emit GuessSubmitted(numGuessed, msg.sender, msg.value);
    }

    /**
     *        function called by relay server
     **/
    function processGuess(
        uint256 numGuessed,
        address guessedBy,
        uint256 betSize
    ) public payable onlyWorker whenNotPaused {

        // if new guess, increment cards chosen, possibly increment level
        if (alreadyChosenCards[numGuessed] != true) {
            alreadyChosenCards[numGuessed] = true;
            cardsChosen++;

            revealedCards.push(numGuessed);

            if (
                cardsChosen == (CARDS_PER_LEVEL - 1) ||
                cardsChosen == (CARDS_PER_LEVEL * 2 - 1) ||
                cardsChosen == (CARDS_PER_LEVEL * 3 - 1)
            ) {
                currentLevel++;
            }
        }

        string memory valueOfCardGuessed = currentBoard[numGuessed];

        if (
            !aceHasBeenFound &&
            keccak256(bytes(valueOfCardGuessed)) == keccak256("ace")
        ) {
            aceHasBeenFound = true;

            revealedCardValues.push("ace");

            uint256 payoutAmount = betSize *
                (1 + (aceMultiplierLvls[currentLevel])); // adds 1 to give the user's bet back

            payable(guessedBy).transfer(payoutAmount);

            emit AceFound(guessedBy, numGuessed, payoutAmount);

            emit CardRevealed(numGuessed, "ace", guessedBy);
        } else if (
            !kingHasBeenFound &&
            keccak256(bytes(valueOfCardGuessed)) == keccak256("king")
        ) {
            kingHasBeenFound = true;

            revealedCardValues.push("king");

            uint256 payoutAmount = betSize *
                (1 + (kingMultiplierLvls[currentLevel])); // adds 1 to give the user's bet back

            payable(guessedBy).transfer(payoutAmount);

            emit KingFound(guessedBy, numGuessed, payoutAmount);

            emit CardRevealed(numGuessed, "king", guessedBy);
        } else if (
            !queenHasBeenFound &&
            keccak256(bytes(valueOfCardGuessed)) == keccak256("queen")
        ) {
            queenHasBeenFound = true;

            revealedCardValues.push("queen");

            uint256 payoutAmount = betSize *
                (1 + (queenMultiplierLvls[currentLevel])); // adds 1 to give the user's bet back

            payable(guessedBy).transfer(payoutAmount);

            emit QueenFound(guessedBy, numGuessed, payoutAmount);
            emit CardRevealed(numGuessed, "queen", guessedBy);
        } else if (
            !jackHasBeenFound &&
            keccak256(bytes(valueOfCardGuessed)) == keccak256("jack")
        ) {
            jackHasBeenFound = true;

            revealedCardValues.push("jack");

            payable(guessedBy).transfer(jackpotSize);

            emit JackFound(guessedBy, numGuessed, jackpotSize);
            emit CardRevealed(numGuessed, "jack", guessedBy);

            jackpotSize = INITIAL_JACKPOT_SIZE;
        } else if (keccak256(bytes(valueOfCardGuessed)) == keccak256("nft")) {
            // transfer an nft to the user :)
        } else {
            uint256 amountAddedToJackpot = (betSize * jackpotRakePercentage) /
                100;

            jackpotSize += amountAddedToJackpot;

            emit JackpotSizeIncrease(
                guessedBy,
                numGuessed,
                jackpotSize,
                amountAddedToJackpot
            );

            emit CardRevealed(numGuessed, "empty", guessedBy);
        }

        if (
            jackHasBeenFound == true &&
            queenHasBeenFound == true &&
            kingHasBeenFound == true &&
            aceHasBeenFound == true
        ) {
            destroyFinishedGameData();
            createNewBoard();
        }
    }

    function setNickname(string memory newNickname) external whenNotPaused {
        nicknames[msg.sender] = newNickname;
    }

    function getNickname(address account)
        external
        view
        returns (string memory)
    {
        return nicknames[account];
    }

    function getMyNickname() external view returns (string memory) {
        return nicknames[msg.sender];
    }

    modifier onlyOnMumbaiTestnet() {
        require(
            getChainId() == MUMBAI_TESTNET_CHAINID,
            "This function is only available on testnet..."
        );
        _;
    }

    function getFaceCardNumbers()
        public
        view
        onlyOwner
        onlyOnMumbaiTestnet
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (aceNum, kingNum, queenNum, jackNum);
    }

    function getRevealedCards() public view returns (uint256[] memory) {
        return revealedCards;
    }

    function getRevealedCardValues() public view returns (string[] memory) {
        return revealedCardValues;
    }

    function getChainId() internal view returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }

    /**
     *        Admin functions
     **/

    function fundContract() public payable onlyOwner returns (string memory) {
        return "funded!";
    }

    function contractBalance() public view onlyOwner returns (uint256) {
        return address(this).balance;
    }

    function withdraw() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(success);
    }

    function withdrawSome(uint256 amountToWithdraw) public payable onlyOwner {
        require(
            amountToWithdraw <= address(this).balance,
            "Cannot withdraw more than the current balance!"
        );

        (bool success, ) = payable(msg.sender).call{value: amountToWithdraw}(
            ""
        );
        require(success);
    }

    function withdrawLink() public onlyOwner {
        ERC20(__linkTokenAddress).transfer(owner(), linkBalance());
    }

    function linkBalance() public view onlyOwner returns (uint256) {
        return ERC20(__linkTokenAddress).balanceOf(address(this));
    }

    function setWorker(address newWorker) external onlyOwner {
        worker = newWorker;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyWorker() {
        require(worker == msg.sender, "caller is not the worker!");
        _;
    }
}
