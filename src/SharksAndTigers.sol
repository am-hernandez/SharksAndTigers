// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/utils/ReentrancyGuardTransient.sol";

contract SharksAndTigers is ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    uint256 public constant BOARD_SIZE = 9;
    uint256 public immutable i_gameId;
    uint256 public immutable i_wager;
    uint256 public immutable i_playClock;
    address public immutable i_usdcToken;
    uint256 public s_lastPlayTime;
    address public immutable i_playerOne;
    address public s_playerTwo;
    address public s_currentPlayer;
    address public s_winner;
    bool public s_isDraw;
    bool public s_isRewardClaimed;
    GameState public s_gameState;
    Mark public immutable i_playerOneMark;
    Mark public immutable i_playerTwoMark;
    Mark[BOARD_SIZE] public s_gameBoard;
    mapping(address => uint256) public s_balances;

    event PlayerTwoJoined(
        uint256 indexed gameId,
        address indexed gameContract,
        address indexed playerTwo,
        Mark playerTwoMark,
        uint8 position,
        uint256 playClock,
        uint256 wager
    );

    event MoveMade(
        uint256 indexed gameId,
        address indexed gameContract,
        address indexed player,
        Mark playerMark,
        uint8 position,
        uint256 playClock,
        uint256 lastPlayTime,
        uint256 wager
    );

    event GameEnded(
        uint256 indexed gameId,
        address indexed gameContract,
        address playerOne,
        address playerTwo,
        Mark playerOneMark,
        Mark playerTwoMark,
        uint256 wager,
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
        uint256 wager;
        uint256 playClock;
        uint256 lastPlayTime;
        address playerOne;
        address playerTwo;
        address currentPlayer;
        address winner;
        bool isDraw;
        bool isRewardClaimed;
        GameState gameState;
        Mark playerOneMark;
        Mark playerTwoMark;
        Mark[BOARD_SIZE] gameBoard;
    }

    constructor(
        address _playerOne,
        uint8 _position,
        Mark _mark,
        uint256 _playClock,
        uint256 _gameId,
        address _usdcToken,
        uint256 _wager
    ) {
        require(_playerOne != address(0), "Player one cannot be the zero address");
        require(_usdcToken != address(0), "USDC token address cannot be zero");
        require(_wager > 0, "Wager must be greater than zero");
        require(_playClock > 0, "Play clock must be greater than zero");

        i_gameId = _gameId;
        i_playerOne = _playerOne;
        s_gameState = GameState.Open;
        i_wager = _wager;
        i_playClock = _playClock;
        i_usdcToken = _usdcToken;
        s_isRewardClaimed = false;
        s_balances[_playerOne] = _wager;
        i_playerOneMark = Mark(_mark);
        i_playerTwoMark = (_mark == Mark.Shark) ? Mark.Tiger : Mark.Shark;

        // set the first move on the board
        s_gameBoard[_position] = i_playerOneMark;
    }

    modifier validatePlayerMove(uint8 _position) {
        require(_position < BOARD_SIZE, "Position is out of range");
        require(s_gameBoard[_position] == Mark.Empty, "Position is already marked");
        _;
    }

    // External functions

    /**
     * @notice Allows player two to join the game with matching wager
     * @dev User must first approve this game contract to spend USDC: usdc.approve(gameAddress, wagerAmount)
     * @param _position Board position (0-8) for player two's first move
     */
    function joinGame(uint8 _position) external validatePlayerMove(_position) nonReentrant {
        require(s_gameState == GameState.Open, "Game is not open to joining");
        require(s_playerTwo == address(0), "Player two already joined");
        require(msg.sender != i_playerOne, "Player one cannot join as player two");

        // Check that user has approved sufficient USDC for the wager
        // User must call: IERC20(i_usdcToken).approve(address(this), i_wager) first
        IERC20 usdc = IERC20(i_usdcToken);
        uint256 allowance = usdc.allowance(msg.sender, address(this));
        require(
            allowance >= i_wager,
            "Insufficient USDC allowance. Please approve the game contract to spend the wager amount."
        );

        // Transfer USDC from player two
        usdc.safeTransferFrom(msg.sender, address(this), i_wager);

        s_gameState = GameState.Active;
        s_playerTwo = msg.sender;
        s_balances[msg.sender] = i_wager;
        s_gameBoard[_position] = i_playerTwoMark;
        s_currentPlayer = i_playerOne;
        s_lastPlayTime = block.timestamp;

        emit PlayerTwoJoined(i_gameId, address(this), s_playerTwo, i_playerTwoMark, _position, i_playClock, i_wager);
    }

    function makeMove(uint8 _position) external validatePlayerMove(_position) {
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

        if (_isWinningMove(_position)) {
            // game is won
            s_gameState = GameState.Ended;
            s_winner = msg.sender;
            emit GameEnded(
                i_gameId,
                address(this),
                i_playerOne,
                s_playerTwo,
                i_playerOneMark,
                i_playerTwoMark,
                i_wager,
                i_playClock,
                s_lastPlayTime,
                false,
                s_winner,
                s_isDraw
            );
        } else if (_isBoardFull()) {
            // game is a draw
            s_gameState = GameState.Ended;
            s_isDraw = true;
            emit GameEnded(
                i_gameId,
                address(this),
                i_playerOne,
                s_playerTwo,
                i_playerOneMark,
                i_playerTwoMark,
                i_wager,
                i_playClock,
                s_lastPlayTime,
                false,
                s_winner,
                s_isDraw
            );
        } else {
            emit MoveMade(
                i_gameId, address(this), msg.sender, playMark, _position, i_playClock, s_lastPlayTime, i_wager
            );
        }
    }

    function claimReward() external nonReentrant {
        bool isExpired;

        if (block.timestamp - s_lastPlayTime > i_playClock) {
            // game is expired, winner is opposite of current player
            if (s_currentPlayer == i_playerOne) {
                s_winner = s_playerTwo;
            } else {
                s_winner = i_playerOne;
            }
            isExpired = true;
        } else {
            require(s_gameState == GameState.Ended, "Game is not ended");
            require(s_isDraw == false, "No winner, game ended in a draw");
            require(s_winner == msg.sender, "Only the winner can claim the reward");
            require(s_isRewardClaimed == false, "Reward already claimed");
        }
        require(s_winner == msg.sender, "Only the winner can claim the reward");

        s_balances[i_playerOne] = 0;
        s_balances[s_playerTwo] = 0;
        s_isRewardClaimed = true;

        IERC20 usdc = IERC20(i_usdcToken);
        usdc.safeTransfer(msg.sender, i_wager * 2);

        if (isExpired) {
            // if game is expired
            // update game state after winner claims
            s_gameState = GameState.Ended;
            emit GameEnded(
                i_gameId,
                address(this),
                i_playerOne,
                s_playerTwo,
                i_playerOneMark,
                i_playerTwoMark,
                i_wager,
                i_playClock,
                s_lastPlayTime,
                isExpired,
                s_winner,
                s_isDraw
            );
        }
    }

    function withdrawWager() external nonReentrant {
        require(msg.sender == i_playerOne || msg.sender == s_playerTwo, "You are not a player in this game");
        require(s_gameState != GameState.Active, "Cannot withdraw wager while game is active");
        require(s_winner == address(0), "Game is not a draw, winner must call claimReward");

        uint256 playerBalance = s_balances[msg.sender];
        require(playerBalance > 0, "Nothing to withdraw");

        s_balances[msg.sender] = 0;

        if (s_gameState == GameState.Open) {
            require(msg.sender == i_playerOne, "Only player one can end an open game");

            s_gameState = GameState.Ended;
        }

        IERC20 usdc = IERC20(i_usdcToken);
        usdc.safeTransfer(msg.sender, playerBalance);

        emit GameEnded(
            i_gameId,
            address(this),
            i_playerOne,
            s_playerTwo,
            i_playerOneMark,
            i_playerTwoMark,
            i_wager,
            i_playClock,
            s_lastPlayTime,
            false,
            s_winner,
            s_isDraw
        );
    }

    // External functions that are view

    function getGameInfo() external view returns (Game memory) {
        Game memory gameInfo = Game({
            gameId: i_gameId,
            wager: i_wager,
            playClock: i_playClock,
            lastPlayTime: s_lastPlayTime,
            playerOne: i_playerOne,
            playerTwo: s_playerTwo,
            currentPlayer: s_currentPlayer,
            winner: s_winner,
            isDraw: s_isDraw,
            isRewardClaimed: s_isRewardClaimed,
            gameState: s_gameState,
            playerOneMark: i_playerOneMark,
            playerTwoMark: i_playerTwoMark,
            gameBoard: s_gameBoard
        });

        return gameInfo;
    }

    /**
     * @notice Helper function to check if user has sufficient allowance for the wager
     * @param user The address to check allowance for
     * @return hasAllowance True if user has sufficient allowance
     * @return currentAllowance The current allowance amount
     * @return requiredWager The wager amount required
     */
    function checkAllowance(address user)
        external
        view
        returns (bool hasAllowance, uint256 currentAllowance, uint256 requiredWager)
    {
        IERC20 usdc = IERC20(i_usdcToken);
        currentAllowance = usdc.allowance(user, address(this));
        requiredWager = i_wager;
        hasAllowance = currentAllowance >= i_wager;
    }

    /**
     * @notice Returns the USDC token address for easy approval
     * @return The USDC token contract address
     */
    function getUsdcToken() external view returns (address) {
        return i_usdcToken;
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
        for (uint256 i; i < BOARD_SIZE; i++) {
            if (s_gameBoard[i] == Mark.Empty) {
                return false; // Game board is not full
            }
        }
        return true; // Game board is full
    }
}
