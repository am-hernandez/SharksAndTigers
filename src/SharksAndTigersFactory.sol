// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SharksAndTigers} from "./SharksAndTigers.sol";

contract SharksAndTigersFactory {
    uint256 public s_gameCount = 0;
    mapping(uint256 => address) public s_games;

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

        s_gameCount++;

        SharksAndTigers game = new SharksAndTigers(msg.sender, position, playerOneMark, s_gameCount);

        // persist game address for lookups without relying on events
        s_games[s_gameCount] = address(game);

        emit GameCreated(s_gameCount, address(game), msg.sender, playerOneMark, position);
    }

    function getGameAddress(uint256 gameId) external view returns (address) {
        return s_games[gameId];
    }

    function getGameCount() external view returns (uint256) {
        return s_gameCount;
    }
}
