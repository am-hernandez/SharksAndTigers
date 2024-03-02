// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// 🦈 & 🐅
contract SharksAndTigersFactory {
  uint public gameCount = 0;

  event GameCreated(address playerOne, address gameContract, uint indexed id);

  function createGame(uint firstMovePos, uint _playerOneMark) public payable{
    require(_playerOneMark == 1 || _playerOneMark == 2, "Invalid mark for board");
    require(msg.value > 0, "Game creation requires a wager");
    require(firstMovePos >= 0 && firstMovePos < 9, "Position is out of range");

    SharksAndTigers.Mark playerOneMark = SharksAndTigers.Mark(_playerOneMark);

    SharksAndTigers game = (new SharksAndTigers){value: msg.value}(msg.sender, firstMovePos, playerOneMark);

    gameCount++;

    emit GameCreated(msg.sender, address(game), gameCount);
  }
}


/* Sharks and Tigers - Game
  
  This game requires the following:
  - player one
  - player two
  - wager
  - availability state (enum)
    - Open
    - Active
    - Ended
  - board state (mark on each space of the board)
  - Mark enum (T, S, empty)
*/
contract SharksAndTigers {
  uint256 public wager;
  address public playerOne;
  address public playerTwo;
  address public currentPlayer;
  address public winner;
  bool public isDraw;
  bool public isRewardClaimed;
  GameState public gameState;
  Mark public playerOneMark;
  Mark public playerTwoMark;
  Mark[9] public gameBoard;
  mapping(address => uint256) public balances;

  event PlayerTwoJoined(address gameContract, address playerTwo, uint position);
  event MoveMade(address gameContract, address player, uint position);

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

  constructor(address _playerOne, uint position, Mark mark) payable {
    playerOne = _playerOne;
    gameState = GameState.Open;
    wager = msg.value;
    isRewardClaimed = false;
    balances[_playerOne] = msg.value;
    playerOneMark = Mark(mark);
    playerTwoMark = (mark == Mark.Shark) ? Mark.Tiger : Mark.Shark;
    
    // set the first move on the board
    gameBoard[position] = playerOneMark;
  }

  modifier validatePlayerMove(uint position) {
    require(position >= 0 && position < 9, "Position is out of range");
    require(gameBoard[position] == Mark.Empty, "Position is already marked");
    _;
  }

  function joinGame(uint position) external payable validatePlayerMove(position) {
    require(gameState == GameState.Open, "Game is not open to joining");
    require(msg.value == wager, "Incorrect wager amount");

    gameState = GameState.Active;
    playerTwo = msg.sender;
    balances[msg.sender] = msg.value;
    gameBoard[position] = playerTwoMark;
    currentPlayer = playerOne;

    emit PlayerTwoJoined(address(this) ,playerTwo, position);    
  }

  function makeMove(uint position) public validatePlayerMove(position){
    require(gameState == GameState.Active, "Game is not active");
    require(currentPlayer == msg.sender, "You are not the current player");

    Mark playMark;

    if(playerOne == currentPlayer){
      playMark = playerOneMark;
      currentPlayer = playerTwo;
    } else {
      playMark = playerTwoMark;
      currentPlayer = playerOne;
    }

    gameBoard[position] = playMark;    

    if(isWinningMove(position)){
      // game is won
      gameState = GameState.Ended;
      winner = msg.sender;
    } else if(isBoardFull()){
      // game is a draw
      gameState = GameState.Ended;
      isDraw = true;
    } else {
      emit MoveMade(address(this), msg.sender, position);
    }
  }

  function isWinningMove(uint position)private view returns(bool){
    // validate if this move is the winning move
    Mark playerMark = gameBoard[position];
    uint row = position / 3; // determines the row of the move
    uint col = position % 3; // determines the column of the move

    // Check row
    if(gameBoard[row * 3] == playerMark &&
      gameBoard[row * 3 + 1] == playerMark &&
      gameBoard[row * 3 + 2] == playerMark){
        return true;
    }

    // Check column
    if(gameBoard[col * 3] == playerMark &&
      gameBoard[col * 3 + 3] == playerMark &&
      gameBoard[col * 3 + 6] == playerMark){
        return true;
    }

    // Check diagonals
    if(position % 2 == 0){
        // Check first diagonal
        if(gameBoard[0] == playerMark &&
          gameBoard[4] == playerMark &&
          gameBoard[8] == playerMark){
            return true;
        }

        // Check second diagonal
        if(gameBoard[2] == playerMark &&
          gameBoard[4] == playerMark &&
          gameBoard[6] == playerMark){
            return true;
        }
    }
    return false;
  }

  function isBoardFull() private view returns(bool){
    // validate the board is full and game is a draw
    for(uint i; i < 9; i++){
      if(gameBoard[i] == Mark.Empty){
        return false; // Game board is not full
      }
    }
    return true; // Game board is full
  }

  function claimReward() public {
    require(gameState == GameState.Ended, "Game is not ended");
    require(isDraw == false, "No winner, game ended in a draw");
    require(winner == msg.sender, "Only the winner can claim the reward");
    require(isRewardClaimed == false, "Reward already claimed");


    balances[playerOne] = 0;
    balances[playerTwo] = 0;
    isRewardClaimed = true;
    (bool sent, ) = payable(winner).call{value: wager*2}("");
    require(sent, "transfer failed");
  }

  function withdrawWager() public {
    require(gameState == GameState.Ended, "Game is not ended");
    require(winner == address(0), "Game is not a draw, winner must call claimReward");

    uint256 playerBalance = balances[msg.sender];
    require(playerBalance > 0, "Nothing to withdraw");

    balances[msg.sender] = 0;
    (bool sent, ) = payable(msg.sender).call{value: playerBalance}("");
    require(sent, "transfer failed");
  }
  
}