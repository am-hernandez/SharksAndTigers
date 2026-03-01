<a id="readme-top"></a>
[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]



<br />
<div align="center">
  <h3 align="center">Sharks & Tigers</h3>

  <p align="center">
    An onchain Tic-Tac-Toe game built with Solidity
    <br />
    <br />
    <a href="https://github.com/am-hernandez/SharksAndTigers/issues/new?labels=bug&template=bug-report---.md">Report Bug</a>
    &middot;
    <a href="https://github.com/am-hernandez/SharksAndTigers/issues/new?labels=enhancement&template=feature-request---.md">Request Feature</a>
  </p>
</div>



<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li>
      <a href="#usage">Usage</a>
      <ul>
        <li><a href="#game-flow">Game Flow</a></li>
        <li><a href="#board-layout">Board Layout</a></li>
        <li><a href="#architecture">Architecture</a></li>
        <li><a href="#contracts">Contracts</a></li>
        <li><a href="#interaction-scripts">Interaction Scripts</a></li>
      </ul>
    </li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#security">Security</a></li>
    <li><a href="#design-tradeoffs--non-goals">Design Tradeoffs & Non-Goals</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>



## About The Project

**Sharks & Tigers** is an onchain Tic-Tac-Toe game built with Solidity. Each game is deployed as its own immutable smart contract, with all state transitions and outcomes enforced onchain.

The game replaces traditional X and O marks with Shark and Tiger symbols, giving each match a simple identity while keeping the underlying rules unchanged.

### Key Features

* **Factory Pattern**: A single factory contract deploys and tracks game instances
* **Onchain Game State**: All moves and outcomes are enforced by smart contracts
* **One Game = One Contract**: Each match is its own immutable contract
* **Event-Based Updates**: Game lifecycle events are emitted for indexing and UI use
* **Fixed Rules per Game**: Rules are set at creation and cannot change mid-game
* **USDC Staking**: Players stake USDC in a central **EscrowManager** until the game ends

<p align="right">(<a href="#readme-top">back to top</a>)</p>



### Built With

This section lists the major frameworks and libraries used in this project.

* [![Solidity][Solidity]][Solidity-url]
* [![Foundry][Foundry]][Foundry-url]
* [![OpenZeppelin][OpenZeppelin]][OpenZeppelin-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p>



## Getting Started

This section provides instructions on setting up the project locally. To get a local copy up and running, follow these steps.

### Prerequisites

* [Foundry](https://getfoundry.sh/) - Solidity development framework

### Installation

1. Install Foundry
   ```sh
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. Clone the repo
   ```sh
   git clone https://github.com/am-hernandez/SharksAndTigers.git
   cd SharksAndTigers
   ```

3. Install dependencies
   ```sh
   forge install
   ```

4. Build the project
   ```sh
   forge build
   ```

5. Run tests
   ```sh
   forge test
   ```

<p align="right">(<a href="#readme-top">back to top</a>)</p>



## Usage

### Game Flow

1. **Create Game**
   * Player One creates a game through the factory
   * Chooses a mark (Shark or Tiger) and an opening position
   * Approves USDC to the **EscrowManager**; the factory registers the game with escrow and deposits Player One’s stake there
   * Game enters the `Open` state

2. **Join Game**
   * Player Two joins the game and makes their first move
   * Approves and transfers matching USDC stake to **EscrowManager**
   * Game transitions to `Active`

3. **Play**
   * Players alternate turns
   * Each move is validated and recorded onchain
   * Play clock enforces liveness guarantees, preventing griefing where funds could otherwise be locked indefinitely

4. **End Game**
   * A player wins by completing three in a row, column, or diagonal
   * The game ends in a draw when the board is full
   * Game state transitions to `Ended`
   * EscrowManager credits the winner; the winner claims both escrowed stakes from EscrowManager

### Board Layout

Board positions are indexed as follows:

```
0 | 1 | 2
--+---+--
3 | 4 | 5
--+---+--
6 | 7 | 8
```

### Architecture

The system has three main contracts:

1. **SharksAndTigersFactory**
   Deploys a single **EscrowManager** and creates/tracks individual game contracts. Holds `FACTORY_ROLE` on the escrow.

2. **EscrowManager**
   Custodies all USDC stakes and tracks per-game escrow state. Registers games, receives deposits from both players, and records outcomes when games call `finalize`. Players claim winnings or withdraw refunds from here.

3. **SharksAndTigers**
   One contract per game. Manages board state and moves; has `GAME_ROLE` on the escrow and finalizes the escrow position when the game ends. Players claim reward or withdraw refundable stake from EscrowManager.

The EscrowManager is deployed once in the Factory constructor and is immutable. All games created by that factory register with this escrow instance.

A global EscrowManager is used instead of per-game escrow contracts to reduce token approval friction and allow players to withdraw accumulated winnings/refunds across multiple games in a single transaction.

### Contracts

#### SharksAndTigersFactory

The factory deploys one EscrowManager and creates new games, registering each game with the escrow and keeping a registry of game contracts.

**State Variables**

* `i_usdcToken` (`IERC20 immutable`): USDC token contract
* `i_escrowManager` (`EscrowManager immutable`): Central escrow that holds stakes and pays out winners/refunds
* `s_gameCount` (`uint256`): Total number of games created
* `s_games` (`mapping(uint256 => address)`): Maps game IDs to game addresses

**Functions**

##### `createGame(uint8 position, uint256 _playerOneMark, uint256 playClock, uint256 stake) external`

Creates a new game instance with Player One's initial move.

**Parameters**

* `position`: Board position (0–8)
* `_playerOneMark`: Mark choice (`1 = Shark`, `2 = Tiger`)
* `playClock`: Time limit in seconds for each move
* `stake`: USDC stake amount (must match for player two)

**Requirements**

* `position` must be within range
* `_playerOneMark` must be Shark or Tiger
* Player must have approved the EscrowManager to spend USDC
* Player must have sufficient USDC balance

**Effects**

* Deploys a new `SharksAndTigers` contract
* Registers the game with the EscrowManager and deposits Player One’s USDC stake there
* Increments the game counter and stores the game address
* Emits `GameCreated`

##### `s_games(uint256 gameId)` / `s_gameCount()`

Public state: use `s_games(gameId)` to get the game address and `s_gameCount` for the latest game ID.

#### SharksAndTigers

A single game contract that contains all logic and state for one match.

**State Variables**

* `BOARD_SIZE` (`uint256 constant`): The number of position spaces on the game board
* `i_gameId` (`uint256 immutable`): Unique game identifier
* `i_stake` (`uint256 immutable`): USDC stake amount per player
* `i_playClock` (`uint256 immutable`): Time limit per move in seconds
* `i_usdcToken` (`address immutable`): USDC token contract address
* `s_lastPlayTime` (`uint256`): Timestamp of the last move
* `i_playerOne` (`address immutable`): Address of player one
* `s_playerTwo` (`address`): Address of player two
* `s_currentPlayer` (`address`): Address of the player whose turn it is
* `s_winner` (`address`): Address of the winner (if any)
* `s_isDraw` (`bool`): Whether the game ended in a draw
* `s_gameState` (`GameState`): Current state of the game
* `i_playerOneMark` (`Mark immutable`): Mark assigned to player one
* `i_playerTwoMark` (`Mark immutable`): Mark assigned to player two
* `s_gameBoard` (`Mark[9]`): The game board
* `i_escrowManager` (`address immutable`): EscrowManager address; game calls it to finalize outcomes

**Enums**

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

**Functions**

##### `joinGame(uint8 position) external`

Allows player two to join the game and make their first move.

##### `makeMove(uint8 position) external`

Allows the current player to make a move. If the move completes three in a row, column, or diagonal, the game ends and EscrowManager is finalized for the winner; if the board is full, the game ends in a draw and escrow is finalized. Uses internal `_isWinningMove` and `_isBoardFull` for outcome detection.

##### `resolveTimeout() external`

Callable when the play clock has expired (current player did not move in time). Requires game in `Active` state and Player Two already joined. Awards the win to the opponent, updates game state to `Ended`, and calls EscrowManager `finalize(winner, false, false)`.

##### `cancelOpenGame() external`

Allows Player One to cancel before anyone joins. Requires game in `Open` state and Player Two not set. Marks game as `Ended` and calls EscrowManager `finalize(address(0), false, true)` so Player One’s stake becomes refundable.

##### `getGameInfo() external view returns (Game memory)`

Returns the full game state (gameId, stake, playClock, lastPlayTime, playerOne, playerTwo, currentPlayer, winner, isDraw, gameState, playerOneMark, playerTwoMark, gameBoard, escrowManager).

#### EscrowManager

Central contract that custodies all USDC stakes and tracks per-game escrow state. 

**Access Controls**
- `FACTORY_ROLE`: granted to the game factory 
- `GAME_ROLE`: granted to each registered game

**Key functions**

* **Factory**: `registerGame(game, gameId, player1, stake)` then `depositPlayer1(game)` after creating a game.
* **Game**: `setPlayer2(player2)`, `depositPlayer2()`, and `finalize(winner, isDraw, isCancelled)` when the game ends.
* **Players**: `claimReward()` (winners) and `withdrawRefundableStake()` (draw/cancel refunds).

State includes `escrows(gameAddress)`, `claimable[player]`, and `refundable[player]`.

### Interaction Scripts

Foundry scripts under `script/Interactions/` can be run via the Makefile against a local node (e.g. `make anvil` in another terminal) or a configured network.

| Command | Description |
|--------|-------------|
| `make deploy` | Deploy the factory (and its EscrowManager). |
| `make create-game` | Player One creates a game (default key). |
| `make join-game` | Player Two joins the latest game. |
| `make play-game PLAYER=1 POS=2` | Play one move; `PLAYER` 1 or 2, `POS` 0–8. |
| `make claim-reward PLAYER=1` | Winner claims winnings from EscrowManager. |
| `make withdraw-refundable PLAYER=1` | Withdraw refundable stake (draw/cancel). |
| `make get-game-state` | Print latest game state (read-only). |
| `make get-claimable PLAYER=1` | Print claimable balance for player (read-only). |
| `make get-refundable PLAYER=1` | Print refundable balance for player (read-only). |

Use `ARGS=base-sepolia` (or similar) with deploy/create-game/join-game/play-game/claim-reward/withdraw-refundable for a live testnet; ensure `.env` and keys are set.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Roadmap

- [x] Factory pattern for game deployment
- [x] Onchain game state management
- [x] USDC staking with escrow
- [x] Play clock with liveness guarantees
- [x] Event-based updates
- [x] Open game cancellation
- [ ] Game statistics and leaderboards
- [ ] Additional game versions via an upgraded factory
- [ ] Frontend UI integration

See the [open issues](https://github.com/am-hernandez/SharksAndTigers/issues) for a full list of proposed features (and known issues).

<p align="right">(<a href="#readme-top">back to top</a>)</p>



## Security

This project implements several security best practices:

* **Input Validation**: All inputs are validated before processing
* **State Machine**: State transitions are enforced through a finite state machine
* **Immutability**: Game parameters are immutable once deployed
* **CEI Pattern**: Checks-Effects-Interactions (CEI) pattern enforced before all external calls to EscrowManager
* **ReentrancyGuard**: OpenZeppelin's ReentrancyGuardTransient used for critical functions
* **Centralized escrow**: Centralized escrow accounting reduces per-game attack surface while isolating game logic
* **SafeERC20**: OpenZeppelin's SafeERC20 used for all token transfers
* **Event Logging**: Events emitted for all critical actions for transparency

<p align="right">(<a href="#readme-top">back to top</a>)</p>



## Design Tradeoffs & Non-Goals

### Design Tradeoffs

* **Each game is deployed as its own contract** to guarantee isolation and immutability at the cost of higher deployment overhead.
* **No admin or upgrade hooks are included** to avoid trust assumptions and governance complexity.
* **USDC is used instead of ETH** to reduce volatility and simplify escrow accounting.
* **Play clock enforces liveness** rather than relying on offchain arbitration or admin intervention.
* **Centralized escrow is used** to improve user expeerience in setting USDC approval for one contract instead of approving the factory and each game contract.

### Non-Goals

* No upgradeability or proxy patterns.
* No offchain arbitration or admin intervention.
* No shared game state across instances.
* No support for multiple token types per game.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".
Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

<p align="right">(<a href="#readme-top">back to top</a>)</p>



## License

Distributed under the MIT License. See `LICENSE` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



## Contact

AM - [@am-hernandez](https://farcaster.xyz/am-hernandez)

Project Link: [https://github.com/am-hernandez/SharksAndTigers](https://github.com/am-hernandez/SharksAndTigers)

<p align="right">(<a href="#readme-top">back to top</a>)</p>



## Acknowledgments

* [Foundry](https://getfoundry.sh/) - The Solidity development framework
* [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) - Secure smart contract libraries
* [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html) - Official Solidity style guide
* [Best README Template](https://github.com/othneildrew/Best-README-Template) - README template inspiration

<p align="right">(<a href="#readme-top">back to top</a>)</p>



[contributors-shield]: https://img.shields.io/github/contributors/am-hernandez/SharksAndTigers.svg?style=for-the-badge
[contributors-url]: https://github.com/am-hernandez/SharksAndTigers/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/am-hernandez/SharksAndTigers.svg?style=for-the-badge
[forks-url]: https://github.com/am-hernandez/SharksAndTigers/network/members
[stars-shield]: https://img.shields.io/github/stars/am-hernandez/SharksAndTigers.svg?style=for-the-badge
[stars-url]: https://github.com/am-hernandez/SharksAndTigers/stargazers
[issues-shield]: https://img.shields.io/github/issues/am-hernandez/SharksAndTigers.svg?style=for-the-badge
[issues-url]: https://github.com/am-hernandez/SharksAndTigers/issues
[license-shield]: https://img.shields.io/github/license/am-hernandez/SharksAndTigers.svg?style=for-the-badge
[license-url]: https://github.com/am-hernandez/SharksAndTigers/blob/main/LICENSE
[Solidity]: https://img.shields.io/badge/Solidity-363636?style=for-the-badge&logo=solidity&logoColor=white
[Solidity-url]: https://soliditylang.org/
[Foundry]: https://img.shields.io/badge/Foundry-000000?style=for-the-badge&logo=foundry&logoColor=white
[Foundry-url]: https://getfoundry.sh/
[OpenZeppelin]: https://img.shields.io/badge/OpenZeppelin-4E5EE4?style=for-the-badge&logo=openzeppelin&logoColor=white
[OpenZeppelin-url]: https://openzeppelin.com/
