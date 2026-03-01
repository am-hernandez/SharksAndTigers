// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/utils/ReentrancyGuardTransient.sol";
import {EscrowManager} from "./EscrowManager.sol";

contract SharksAndTigers is ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    uint256 public constant BOARD_SIZE = 9;
    uint256 public immutable i_gameId;
    uint256 public immutable i_stake;
    uint256 public immutable i_playClock;
    IERC20 public immutable i_usdcToken;
    uint256 public s_lastPlayTime;
    address public immutable i_playerOne;
    address public s_playerTwo;
    address public s_currentPlayer;
    address public s_winner;
    bool public s_isDraw;
    GameState public s_gameState;
    Mark public immutable i_playerOneMark;
    Mark public immutable i_playerTwoMark;
    Mark[BOARD_SIZE] public s_gameBoard;
    address public immutable i_escrowManager;

    event PlayerTwoJoined(
        uint256 indexed gameId,
        address indexed gameContract,
        address indexed playerTwo,
        Mark playerTwoMark,
        uint8 position,
        uint256 playClock,
        uint256 stake
    );

    event MoveMade(
        uint256 indexed gameId,
        address indexed gameContract,
        address indexed player,
        Mark playerMark,
        uint8 position,
        uint256 playClock,
        uint256 lastPlayTime,
        uint256 stake
    );

    event GameEnded(
        uint256 indexed gameId,
        address indexed gameContract,
        address playerOne,
        address playerTwo,
        Mark playerOneMark,
        Mark playerTwoMark,
        uint256 stake,
        uint256 playClock,
        uint256 lastPlayTime,
        bool isExpired,
        address indexed winner,
        bool isDraw
    );

    enum GameState {
        Open,
        Active,
        Ended
    }

    enum Mark {
        Empty,
        Shark,
        Tiger
    }

    struct Game {
        uint256 gameId;
        uint256 stake;
        uint256 playClock;
        uint256 lastPlayTime;
        address playerOne;
        address playerTwo;
        address currentPlayer;
        address winner;
        bool isDraw;
        GameState gameState;
        Mark playerOneMark;
        Mark playerTwoMark;
        Mark[BOARD_SIZE] gameBoard;
        address escrowManager;
    }

    constructor(
        address _playerOne,
        uint8 _position,
        Mark _mark,
        uint256 _playClock,
        uint256 _gameId,
        IERC20 _usdcToken,
        uint256 _stake,
        address _escrowManager
    ) {
        require(_playerOne != address(0), "Player one cannot be the zero address");
        require(address(_usdcToken) != address(0), "USDC token address cannot be zero");
        require(_escrowManager != address(0), "Escrow manager cannot be the zero address");
        require(_stake > 0, "Stake must be greater than zero");
        require(_playClock > 0, "Play clock must be greater than zero");
        require(_mark == Mark.Shark || _mark == Mark.Tiger, "Invalid mark choice");
        require(_position < BOARD_SIZE, "Position is out of range");
        require(_gameId > 0, "Game ID must be greater than zero");

        i_gameId = _gameId;
        i_playerOne = _playerOne;
        s_gameState = GameState.Open;
        i_stake = _stake;
        i_playClock = _playClock;
        i_usdcToken = _usdcToken;
        i_playerOneMark = Mark(_mark);
        i_playerTwoMark = (_mark == Mark.Shark) ? Mark.Tiger : Mark.Shark;

        // set the first move on the board
        s_gameBoard[_position] = i_playerOneMark;
        i_escrowManager = _escrowManager;
    }

    modifier validatePlayerMove(uint8 _position) {
        require(_position < BOARD_SIZE, "Position is out of range");
        require(s_gameBoard[_position] == Mark.Empty, "Position is already marked");
        _;
    }

    // External functions

    /**
     * @notice Allows player two to join the game with matching stake amount
     * @param _position Board position (0-8) for player two's first move
     */
    function joinGame(uint8 _position) external nonReentrant validatePlayerMove(_position) {
        require(s_gameState == GameState.Open, "Game is not open to joining");
        require(s_playerTwo == address(0), "Player two already joined");
        require(msg.sender != i_playerOne, "Player one cannot join as player two");

        s_gameState = GameState.Active;
        s_playerTwo = msg.sender;
        s_gameBoard[_position] = i_playerTwoMark;
        s_currentPlayer = i_playerOne;
        s_lastPlayTime = block.timestamp;

        EscrowManager escrowManager = EscrowManager(i_escrowManager);
        escrowManager.setPlayer2(msg.sender);
        escrowManager.depositPlayer2();

        emit PlayerTwoJoined(i_gameId, address(this), msg.sender, i_playerTwoMark, _position, i_playClock, i_stake);
    }

    function makeMove(uint8 _position) external nonReentrant validatePlayerMove(_position) {
        require(s_gameState == GameState.Active, "Game is not active");
        require(s_currentPlayer == msg.sender, "You are not the current player");
        require(block.timestamp - s_lastPlayTime <= i_playClock, "You ran out of time to make a move");

        Mark playMark;

        if (i_playerOne == s_currentPlayer) {
            playMark = i_playerOneMark;
            s_currentPlayer = s_playerTwo;
        } else {
            playMark = i_playerTwoMark;
            s_currentPlayer = i_playerOne;
        }

        s_gameBoard[_position] = playMark;
        s_lastPlayTime = block.timestamp;
        EscrowManager escrowManager = EscrowManager(i_escrowManager);

        if (_isWinningMove(_position)) {
            // game is won
            s_gameState = GameState.Ended;
            s_isDraw = false;
            s_winner = msg.sender;

            escrowManager.finalize(msg.sender, false, false);

            emit GameEnded(
                i_gameId,
                address(this),
                i_playerOne,
                s_playerTwo,
                i_playerOneMark,
                i_playerTwoMark,
                i_stake,
                i_playClock,
                s_lastPlayTime,
                false,
                msg.sender,
                false
            );
        } else if (_isBoardFull()) {
            // game is a draw
            s_gameState = GameState.Ended;
            s_isDraw = true;
            s_winner = address(0);

            escrowManager.finalize(address(0), true, false);

            emit GameEnded(
                i_gameId,
                address(this),
                i_playerOne,
                s_playerTwo,
                i_playerOneMark,
                i_playerTwoMark,
                i_stake,
                i_playClock,
                s_lastPlayTime,
                false,
                address(0),
                true
            );
        } else {
            emit MoveMade(
                i_gameId, address(this), msg.sender, playMark, _position, i_playClock, s_lastPlayTime, i_stake
            );
        }
    }

    function resolveTimeout() external nonReentrant {
        address playerOne = i_playerOne;
        address playerTwo = s_playerTwo;
        uint256 lastPlayTime = s_lastPlayTime;
        uint256 playClock = i_playClock;
        require(s_gameState == GameState.Active, "Game not active");
        require(block.timestamp - lastPlayTime > playClock, "Not expired");
        require(playerTwo != address(0), "Player2 not set");

        // winner is the opponent of currentPlayer
        address winner = (s_currentPlayer == playerOne) ? playerTwo : playerOne;

        s_gameState = GameState.Ended;
        s_isDraw = false;
        s_winner = winner;

        EscrowManager(i_escrowManager).finalize(winner, false, false);

        emit GameEnded(
            i_gameId,
            address(this),
            playerOne,
            playerTwo,
            i_playerOneMark,
            i_playerTwoMark,
            i_stake,
            playClock,
            lastPlayTime,
            true,
            winner,
            false
        );
    }

    function cancelOpenGame() external nonReentrant {
        address playerOne = i_playerOne;
        address playerTwo = s_playerTwo;
        require(s_gameState == GameState.Open, "Game is not open");
        require(msg.sender == playerOne, "Only player1 can cancel an open game");
        require(playerTwo == address(0), "Player2 has already joined the game");

        s_gameState = GameState.Ended;
        s_isDraw = false;
        s_winner = address(0);

        EscrowManager(i_escrowManager).finalize(address(0), false, true);

        emit GameEnded(
            i_gameId,
            address(this),
            playerOne,
            playerTwo,
            i_playerOneMark,
            i_playerTwoMark,
            i_stake,
            i_playClock,
            s_lastPlayTime,
            false,
            address(0),
            true
        );
    }

    // External functions that are view

    function getGameInfo() external view returns (Game memory) {
        Game memory gameInfo = Game({
            gameId: i_gameId,
            stake: i_stake,
            playClock: i_playClock,
            lastPlayTime: s_lastPlayTime,
            playerOne: i_playerOne,
            playerTwo: s_playerTwo,
            currentPlayer: s_currentPlayer,
            winner: s_winner,
            isDraw: s_isDraw,
            gameState: s_gameState,
            playerOneMark: i_playerOneMark,
            playerTwoMark: i_playerTwoMark,
            gameBoard: s_gameBoard,
            escrowManager: i_escrowManager
        });

        return gameInfo;
    }

    // Private functions

    function _isWinningMove(uint8 _position) private view returns (bool) {
        // validate if this move is the winning move
        Mark playerMark = s_gameBoard[_position];
        uint8 numOfColsAndRows = 3;

        /**
         *
         * Check rows **
         *
         */
        uint8 rowStartIndex = uint8(_position - (_position % numOfColsAndRows)); // 0,3,6

        if (
            s_gameBoard[rowStartIndex] == playerMark && s_gameBoard[rowStartIndex + 1] == playerMark
                && s_gameBoard[rowStartIndex + 2] == playerMark
        ) {
            return true;
        }

        /**
         *
         * Check columns **
         *
         */
        uint8 colStartIndex = uint8(_position % numOfColsAndRows); // 0,1,2

        if (
            s_gameBoard[colStartIndex] == playerMark && s_gameBoard[colStartIndex + numOfColsAndRows] == playerMark
                && s_gameBoard[colStartIndex + 2 * numOfColsAndRows] == playerMark
        ) {
            return true;
        }

        /**
         *
         * Check diagonals **
         *
         */
        if (_position % 2 == 0) {
            // Check main diagonal
            if (s_gameBoard[0] == playerMark && s_gameBoard[4] == playerMark && s_gameBoard[8] == playerMark) {
                return true;
            }

            // Check anti-diagonal
            if (s_gameBoard[2] == playerMark && s_gameBoard[4] == playerMark && s_gameBoard[6] == playerMark) {
                return true;
            }
        }

        return false;
    }

    function _isBoardFull() private view returns (bool) {
        // validate the board is full and game is a draw
        for (uint256 i = 0; i < BOARD_SIZE; i++) {
            if (s_gameBoard[i] == Mark.Empty) {
                return false; // Game board is not full
            }
        }
        return true; // Game board is full
    }
}
