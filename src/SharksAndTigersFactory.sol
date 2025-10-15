// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SharksAndTigers} from "./SharksAndTigers.sol";

contract SharksAndTigersFactory {
    uint256 public gameCount = 0;
    mapping(uint256 => address) public games;

    event GameCreated(
        uint256 indexed gameId,
        address indexed gameContract,
        address indexed playerOne,
        SharksAndTigers.Mark _playerOneMark,
        uint256 position
    );

    function createGame(uint256 position, uint256 _playerOneMark) external {
        require(_playerOneMark == 1 || _playerOneMark == 2, "Invalid mark for board");
        require(position < 9, "Position is out of range");

        SharksAndTigers.Mark playerOneMark = SharksAndTigers.Mark(_playerOneMark);

        gameCount++;

        SharksAndTigers game = new SharksAndTigers(msg.sender, position, playerOneMark, gameCount);

        // persist game address for lookups without relying on events
        games[gameCount] = address(game);

        emit GameCreated(gameCount, address(game), msg.sender, playerOneMark, position);
    }

    function getGameAddress(uint256 gameId) external view returns (address) {
        return games[gameId];
    }

    function getGameCount() external view returns (uint256) {
        return gameCount;
    }
}
