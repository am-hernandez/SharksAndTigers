# **Sharks & Tigers**

**Sharks & Tigers** is an onchain Tic-Tac-Toe game built with Solidity.
Players create and join individual games deployed as separate smart contracts, with all game state and moves recorded onchain.

The game replaces traditional X and O marks with Shark and Tiger symbols, giving each match a simple identity while keeping the underlying rules unchanged.

---

## Overview

**Sharks & Tigers** is an adaptation of the classic Tic-Tac-Toe game for the EVM.

* Two players take turns marking a 3×3 board
* The first player to get three marks in a row, column or diagonal wins
* If all positions are filled without a winner, the game ends in a draw

Each game begins with Player One choosing a mark (Shark or Tiger) and committing to an opening move. The game is then available for another player to join.

---

## Key Features

* **Factory Pattern**: A single factory contract deploys and tracks game instances
* **Onchain Game State**: All moves and outcomes are enforced by smart contracts
* **One Game = One Contract**: Each match is its own immutable contract
* **Event-Based Updates**: Game lifecycle events are emitted for indexing and UI use
* **Fixed Rules per Game**: Rules are set at creation and cannot change mid-game

---

## Architecture

The system consists of two main contracts:

1. **SharksAndTigersFactory**
   Creates and tracks individual game contracts.

2. **SharksAndTigers**
   Manages the state and logic for a single game.

```
SharksAndTigersFactory
    ├── Creates → SharksAndTigers (Game 1)
    ├── Creates → SharksAndTigers (Game 2)
    └── Creates → SharksAndTigers (Game N)
```

---

## Contracts

### SharksAndTigersFactory

The factory contract is responsible for creating new games and keeping a registry of deployed game contracts.

#### State Variables

* `s_gameCount` (`uint256`): Total number of games created
* `s_games` (`mapping(uint256 => address)`): Maps game IDs to game addresses

#### Functions

##### `createGame(uint8 position, uint256 _playerOneMark) external`

Creates a new game instance with Player One’s initial move.

**Parameters**

* `position`: Board position (0–8)
* `_playerOneMark`: Mark choice (`1 = Shark`, `2 = Tiger`)

**Requirements**

* `position` must be within range
* `_playerOneMark` must be Shark or Tiger

**Effects**

* Deploys a new `SharksAndTigers` contract
* Increments the game counter
* Stores the game address
* Emits `GameCreated`

##### `getGameAddress(uint256 gameId) external view returns (address)`

Returns the address of a game contract by ID.

##### `getGameCount() external view returns (uint256)`

Returns the total number of games created.

---

### SharksAndTigers

A single game contract that contains all logic and state for one match.

#### State Variables

* `s_gameId` (`uint256 immutable`)
* `s_lastPlayTime` (`uint256`)
* `s_playerOne` (`address immutable`)
* `s_playerTwo` (`address`)
* `s_currentPlayer` (`address`)
* `s_winner` (`address`)
* `s_isDraw` (`bool`)
* `s_gameState` (`GameState`)
* `s_playerOneMark` (`Mark immutable`)
* `s_playerTwoMark` (`Mark immutable`)
* `s_gameBoard` (`Mark[9]`)

#### Enums

```solidity
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
```

---

## Game Flow

1. **Create Game**

   * Player One creates a game through the factory
   * Chooses a mark and an opening position
   * Game enters the `Open` state

2. **Join Game**

   * Player Two joins the game and makes their first move
   * Game transitions to `Active`

3. **Play**

   * Players alternate turns
   * Each move is validated and recorded onchain

4. **End Game**

   * A player wins by completing three in a row, column, diagonal, or
   * The game ends in a draw when the board is full
   * Game state transitions to `Ended`

---

## Board Layout

Board positions are indexed as follows:

```
0 | 1 | 2
--+---+--
3 | 4 | 5
--+---+--
6 | 7 | 8
```

---

## Development

### Requirements

* [Foundry](https://getfoundry.sh/)

### Install
Install foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Deploy

```bash
forge deploy
```

---

## Technical Details

* Solidity version: `^0.8.26`
* License: MIT
* Compatible with EVM-based networks

---

## Security Notes

* All inputs are validated
* State transitions are enforced through a finite state machine
* Game parameters are immutable once deployed
* No external calls after state changes
* Events emitted for all critical actions

---

## Future Work

* USDC-based wagers with escrow
* Time limits for moves
* Open game cancellation
* Game statistics and leaderboards
* Additional game versions via an upgraded factory
