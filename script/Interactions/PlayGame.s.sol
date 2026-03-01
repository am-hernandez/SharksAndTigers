// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {SharksAndTigers} from "../../src/SharksAndTigers.sol";
import {DeploymentHelper} from "./lib/DeploymentHelper.s.sol";

/**
 * @title PlayGame
 * @notice Interaction script to play one move as a given player at a given position.
 * @dev Usage: make play-game PLAYER=1 POS=2 (player 1 or 2, position 0-8).
 *      Makefile selects the private key from PLAYER. Game must be Active and it must be that player's turn.
 */
contract PlayGame is DeploymentHelper {
    function run(uint8 player, uint8 position) external {
        if (player != 1 && player != 2) revert("PLAYER must be 1 or 2");
        if (position >= 9) revert("POS must be 0-8");

        address gameAddress = _getLatestGameAddress();
        SharksAndTigers game = SharksAndTigers(gameAddress);
        SharksAndTigers.Game memory info = game.getGameInfo();

        if (info.gameState != SharksAndTigers.GameState.Active) {
            revert("Game is not active. Run make create-game and make join-game first.");
        }

        address expectedCurrent = player == 1 ? info.playerOne : info.playerTwo;
        if (info.currentPlayer != expectedCurrent) {
            revert("Not this player's turn. Current player does not match PLAYER.");
        }
        if (info.gameBoard[position] != SharksAndTigers.Mark.Empty) {
            revert("Position is already marked.");
        }

        console.log("Playing at:", gameAddress);
        console.log("player", uint256(player));
        console.log("position", uint256(position));
        vm.startBroadcast();
        game.makeMove(position);
        vm.stopBroadcast();

        SharksAndTigers.Game memory after_ = game.getGameInfo();
        if (after_.gameState == SharksAndTigers.GameState.Ended) {
            console.log("Game ended. Winner:", after_.winner);
            console.log("Is draw:", after_.isDraw);
        } else {
            console.log("Move played. Game still active.");
        }
    }
}
