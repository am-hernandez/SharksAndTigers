// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract SharksAndTigers {
    uint256 public constant BOARD_SIZE = 9;
    uint256 public immutable s_gameId;
    uint256 public s_lastPlayTime;
    address public immutable s_playerOne;
    address public s_playerTwo;
    address public s_currentPlayer;
    address public s_winner;
    bool public s_isDraw;
    GameState public s_gameState;
    Mark public immutable s_playerOneMark;
    Mark public immutable s_playerTwoMark;
    Mark[BOARD_SIZE] public s_gameBoard;

    event PlayerTwoJoined(
        uint256 indexed gameId,
        address indexed gameContract,
        address indexed playerTwo,
        Mark playerTwoMark,
        uint8 position
    );
    event MoveMade(
        uint256 indexed gameId,
        address indexed gameContract,
        address indexed player,
        Mark playerMark,
        uint8 position,
        uint256 lastPlayTime
    );
    event GameEnded(
        uint256 indexed gameId,
        address indexed gameContract,
        address playerOne,
        address playerTwo,
        Mark playerOneMark,
        Mark playerTwoMark,
        uint256 lastPlayTime,
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
    }

    constructor(address _playerOne, uint8 _position, Mark _mark, uint256 _gameId) {
        require(_playerOne != address(0), "Player one cannot be the zero address");

        s_gameId = _gameId;
        s_playerOne = _playerOne;
        s_gameState = GameState.Open;
        s_playerOneMark = Mark(_mark);
        s_playerTwoMark = (_mark == Mark.Shark) ? Mark.Tiger : Mark.Shark;

        // set the first move on the board
        s_gameBoard[_position] = s_playerOneMark;
    }

    modifier validatePlayerMove(uint8 _position) {
        require(_position < BOARD_SIZE, "Position is out of range");
        require(s_gameBoard[_position] == Mark.Empty, "Position is already marked");
        _;
    }

    function joinGame(uint8 _position) external validatePlayerMove(_position) {
        require(s_gameState == GameState.Open, "Game is not open to joining");
        require(s_playerTwo == address(0), "Player two already joined");
        require(msg.sender != s_playerOne, "Player one cannot join as player two");

        s_gameState = GameState.Active;
        s_playerTwo = msg.sender;
        s_gameBoard[_position] = s_playerTwoMark;
        s_currentPlayer = s_playerOne;
        s_lastPlayTime = block.timestamp;

        emit PlayerTwoJoined(s_gameId, address(this), s_playerTwo, s_playerTwoMark, _position);
    }

    function makeMove(uint8 _position) external validatePlayerMove(_position) {
        require(s_gameState == GameState.Active, "Game is not active");
        require(s_currentPlayer == msg.sender, "You are not the current player");

        Mark playMark;

        if (s_playerOne == s_currentPlayer) {
            playMark = s_playerOneMark;
            s_currentPlayer = s_playerTwo;
        } else {
            playMark = s_playerTwoMark;
            s_currentPlayer = s_playerOne;
        }

        s_gameBoard[_position] = playMark;
        s_lastPlayTime = block.timestamp;

        if (isWinningMove(_position)) {
            // game is won
            s_gameState = GameState.Ended;
            s_winner = msg.sender;
            emit GameEnded(
                s_gameId,
                address(this),
                s_playerOne,
                s_playerTwo,
                s_playerOneMark,
                s_playerTwoMark,
                s_lastPlayTime,
                s_winner,
                s_isDraw
            );
        } else if (isBoardFull()) {
            // game is a draw
            s_gameState = GameState.Ended;
            s_isDraw = true;
            emit GameEnded(
                s_gameId,
                address(this),
                s_playerOne,
                s_playerTwo,
                s_playerOneMark,
                s_playerTwoMark,
                s_lastPlayTime,
                s_winner,
                s_isDraw
            );
        } else {
            emit MoveMade(s_gameId, address(this), msg.sender, playMark, _position, s_lastPlayTime);
        }
    }

    function isWinningMove(uint8 _position) private view returns (bool) {
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

    function isBoardFull() private view returns (bool) {
        // validate the board is full and game is a draw
        for (uint256 i; i < BOARD_SIZE; i++) {
            if (s_gameBoard[i] == Mark.Empty) {
                return false; // Game board is not full
            }
        }
        return true; // Game board is full
    }

    function getGameInfo() external view returns (Game memory) {
        Game memory gameInfo = Game({
            gameId: s_gameId,
            lastPlayTime: s_lastPlayTime,
            playerOne: s_playerOne,
            playerTwo: s_playerTwo,
            currentPlayer: s_currentPlayer,
            winner: s_winner,
            isDraw: s_isDraw,
            gameState: s_gameState,
            playerOneMark: s_playerOneMark,
            playerTwoMark: s_playerTwoMark,
            gameBoard: s_gameBoard
        });

        return gameInfo;
    }
}
