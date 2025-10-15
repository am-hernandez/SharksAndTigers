// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract SharksAndTigers {
    uint256 public gameId;
    uint256 public lastPlayTime;
    address public playerOne;
    address public playerTwo;
    address public currentPlayer;
    address public winner;
    bool public isDraw;
    GameState public gameState;
    Mark public playerOneMark;
    Mark public playerTwoMark;
    Mark[9] public gameBoard;

    event PlayerTwoJoined(
        uint256 indexed gameId,
        address indexed gameContract,
        address indexed playerTwo,
        Mark playerTwoMark,
        uint256 position
    );
    event MoveMade(
        uint256 indexed gameId,
        address indexed gameContract,
        address indexed player,
        Mark playerMark,
        uint256 position,
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
        Mark[9] gameBoard;
    }

    constructor(address _playerOne, uint256 position, Mark mark, uint256 _gameId) {
        gameId = _gameId;
        playerOne = _playerOne;
        gameState = GameState.Open;
        playerOneMark = Mark(mark);
        playerTwoMark = (mark == Mark.Shark) ? Mark.Tiger : Mark.Shark;

        // set the first move on the board
        gameBoard[position] = playerOneMark;
    }

    modifier validatePlayerMove(uint256 position) {
        require(position < 9, "Position is out of range");
        require(gameBoard[position] == Mark.Empty, "Position is already marked");
        _;
    }

    function joinGame(uint256 position) external validatePlayerMove(position) {
        require(gameState == GameState.Open, "Game is not open to joining");
        require(playerTwo == address(0), "Player two already joined");
        require(msg.sender != playerOne, "Player one cannot join as player two");

        gameState = GameState.Active;
        playerTwo = msg.sender;
        gameBoard[position] = playerTwoMark;
        currentPlayer = playerOne;
        lastPlayTime = block.timestamp;

        emit PlayerTwoJoined(gameId, address(this), playerTwo, playerTwoMark, position);
    }

    function makeMove(uint256 position) external validatePlayerMove(position) {
        require(gameState == GameState.Active, "Game is not active");
        require(currentPlayer == msg.sender, "You are not the current player");

        Mark playMark;

        if (playerOne == currentPlayer) {
            playMark = playerOneMark;
            currentPlayer = playerTwo;
        } else {
            playMark = playerTwoMark;
            currentPlayer = playerOne;
        }

        gameBoard[position] = playMark;
        lastPlayTime = block.timestamp;

        if (isWinningMove(position)) {
            // game is won
            gameState = GameState.Ended;
            winner = msg.sender;
            emit GameEnded(
                gameId, address(this), playerOne, playerTwo, playerOneMark, playerTwoMark, lastPlayTime, winner, isDraw
            );
        } else if (isBoardFull()) {
            // game is a draw
            gameState = GameState.Ended;
            isDraw = true;
            emit GameEnded(
                gameId, address(this), playerOne, playerTwo, playerOneMark, playerTwoMark, lastPlayTime, winner, isDraw
            );
        } else {
            emit MoveMade(gameId, address(this), msg.sender, playMark, position, lastPlayTime);
        }
    }

    function isWinningMove(uint256 position) private view returns (bool) {
        // validate if this move is the winning move
        Mark playerMark = gameBoard[position];
        uint256 row = (position / 3) * 3; // determines the row of the move

        /**
         *
         * Check rows **
         *
         */
        if (gameBoard[row] == playerMark && gameBoard[row + 1] == playerMark && gameBoard[row + 2] == playerMark) {
            return true;
        }

        /**
         *
         * Check columns **
         *
         */

        // left column
        if (gameBoard[0] == playerMark && gameBoard[3] == playerMark && gameBoard[6] == playerMark) {
            return true;
        }

        // center column
        if (gameBoard[1] == playerMark && gameBoard[4] == playerMark && gameBoard[7] == playerMark) {
            return true;
        }

        // right column
        if (gameBoard[2] == playerMark && gameBoard[5] == playerMark && gameBoard[8] == playerMark) {
            return true;
        }

        /**
         *
         * Check diagonals **
         *
         */
        if (position % 2 == 0) {
            // Check first diagonal
            if (gameBoard[0] == playerMark && gameBoard[4] == playerMark && gameBoard[8] == playerMark) {
                return true;
            }

            // Check second diagonal
            if (gameBoard[2] == playerMark && gameBoard[4] == playerMark && gameBoard[6] == playerMark) {
                return true;
            }
        }

        return false;
    }

    function isBoardFull() private view returns (bool) {
        // validate the board is full and game is a draw
        for (uint256 i; i < 9; i++) {
            if (gameBoard[i] == Mark.Empty) {
                return false; // Game board is not full
            }
        }
        return true; // Game board is full
    }

    function getGameInfo() external view returns (Game memory) {
        Game memory gameInfo = Game({
            gameId: gameId,
            lastPlayTime: lastPlayTime,
            playerOne: playerOne,
            playerTwo: playerTwo,
            currentPlayer: currentPlayer,
            winner: winner,
            isDraw: isDraw,
            gameState: gameState,
            playerOneMark: playerOneMark,
            playerTwoMark: playerTwoMark,
            gameBoard: gameBoard
        });

        return gameInfo;
    }
}
