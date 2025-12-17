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
      </ul>
    </li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#security">Security</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>



## About The Project

**Sharks & Tigers** is an onchain Tic-Tac-Toe game built with Solidity. Players create and join individual games deployed as separate smart contracts, with all game state and moves recorded onchain.

The game replaces traditional X and O marks with Shark and Tiger symbols, giving each match a simple identity while keeping the underlying rules unchanged.

### Key Features

* **Factory Pattern**: A single factory contract deploys and tracks game instances
* **Onchain Game State**: All moves and outcomes are enforced by smart contracts
* **One Game = One Contract**: Each match is its own immutable contract
* **Event-Based Updates**: Game lifecycle events are emitted for indexing and UI use
* **Fixed Rules per Game**: Rules are set at creation and cannot change mid-game
* **USDC Wagering**: Players wager USDC tokens with escrow until game completion

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
   git clone https://github.com/github_username/repo_name.git
   cd repo_name
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
   * Approves and transfers USDC wager to the factory
   * Game enters the `Open` state

2. **Join Game**
   * Player Two joins the game and makes their first move
   * Approves and transfers matching USDC wager
   * Game transitions to `Active`

3. **Play**
   * Players alternate turns
   * Each move is validated and recorded onchain
   * Play clock enforces time limits for moves

4. **End Game**
   * A player wins by completing three in a row, column, or diagonal
   * The game ends in a draw when the board is full
   * Game state transitions to `Ended`
   * Winner claims the reward (both wagers)

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

### Contracts

#### SharksAndTigersFactory

The factory contract is responsible for creating new games and keeping a registry of deployed game contracts.

**State Variables**

* `i_usdcToken` (`address immutable`): USDC token contract address
* `s_gameCount` (`uint256`): Total number of games created
* `s_games` (`mapping(uint256 => address)`): Maps game IDs to game addresses

**Functions**

##### `createGame(uint8 position, uint256 _playerOneMark, uint256 playClock, uint256 wager) external`

Creates a new game instance with Player One's initial move.

**Parameters**

* `position`: Board position (0–8)
* `_playerOneMark`: Mark choice (`1 = Shark`, `2 = Tiger`)
* `playClock`: Time limit in seconds for each move
* `wager`: USDC wager amount (must match for player two)

**Requirements**

* `position` must be within range
* `_playerOneMark` must be Shark or Tiger
* Player must have approved the factory to spend USDC
* Player must have sufficient USDC balance

**Effects**

* Deploys a new `SharksAndTigers` contract
* Transfers USDC wager from player to game contract
* Increments the game counter
* Stores the game address
* Emits `GameCreated`

##### `getGameAddress(uint256 gameId) external view returns (address)`

Returns the address of a game contract by ID.

##### `getGameCount() external view returns (uint256)`

Returns the total number of games created.

##### `checkAllowance(address owner, uint256 amount) external view returns (bool)`

Checks if the owner has approved the factory to spend the specified amount of USDC.

##### `getUsdcToken() external view returns (address)`

Returns the USDC token contract address.

#### SharksAndTigers

A single game contract that contains all logic and state for one match.

**State Variables**

* `i_gameId` (`uint256 immutable`): Unique game identifier
* `i_wager` (`uint256 immutable`): USDC wager amount
* `i_playClock` (`uint256 immutable`): Time limit per move in seconds
* `i_usdcToken` (`address immutable`): USDC token contract address
* `s_lastPlayTime` (`uint256`): Timestamp of the last move
* `i_playerOne` (`address immutable`): Address of player one
* `s_playerTwo` (`address`): Address of player two
* `s_currentPlayer` (`address`): Address of the player whose turn it is
* `s_winner` (`address`): Address of the winner (if any)
* `s_isDraw` (`bool`): Whether the game ended in a draw
* `s_isRewardClaimed` (`bool`): Whether the reward has been claimed
* `s_gameState` (`GameState`): Current state of the game
* `i_playerOneMark` (`Mark immutable`): Mark assigned to player one
* `i_playerTwoMark` (`Mark immutable`): Mark assigned to player two
* `s_gameBoard` (`Mark[9]`): The game board

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

Allows the current player to make a move.

##### `claimReward() external`

Allows the winner to claim the reward (both wagers) after the game ends.

##### `withdrawWager() external`

Allows players to withdraw their wager if the game expires due to play clock timeout.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



## Roadmap

- [x] Factory pattern for game deployment
- [x] Onchain game state management
- [x] USDC wagering with escrow
- [x] Play clock with time limits
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
* **CEI Pattern**: Checks-Effects-Interactions pattern followed to prevent reentrancy
* **ReentrancyGuard**: OpenZeppelin's ReentrancyGuardTransient used for critical functions
* **SafeERC20**: OpenZeppelin's SafeERC20 used for all token transfers
* **Event Logging**: Events emitted for all critical actions for transparency

### Security Notes

* All inputs are validated
* State transitions are enforced through a finite state machine
* Game parameters are immutable once deployed
* No external calls after state changes
* Events emitted for all critical actions

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
[license-shield]: https://img.shields.io/github/license/github_username/repo_name.svg?style=for-the-badge
[license-url]: https://github.com/am-hernandez/SharksAndTigers/blob/main/LICENSE
[Solidity]: https://img.shields.io/badge/Solidity-363636?style=for-the-badge&logo=solidity&logoColor=white
[Solidity-url]: https://soliditylang.org/
[Foundry]: https://img.shields.io/badge/Foundry-000000?style=for-the-badge&logo=foundry&logoColor=white
[Foundry-url]: https://getfoundry.sh/
[OpenZeppelin]: https://img.shields.io/badge/OpenZeppelin-4E5EE4?style=for-the-badge&logo=openzeppelin&logoColor=white
[OpenZeppelin-url]: https://openzeppelin.com/
