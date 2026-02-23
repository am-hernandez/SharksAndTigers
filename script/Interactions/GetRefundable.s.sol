// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {SharksAndTigersFactory} from "../../src/SharksAndTigersFactory.sol";
import {SharksAndTigers} from "../../src/SharksAndTigers.sol";
import {EscrowManager} from "../../src/EscrowManager.sol";
import {DeploymentHelper} from "./lib/DeploymentHelper.s.sol";

/**
 * @title GetRefundable
 * @notice Read-only script to print a player's refundable stake balance from EscrowManager.
 * @dev Usage: make get-refundable PLAYER=1 (or PLAYER=2).
 */
contract GetRefundable is DeploymentHelper {
    function run(uint8 player) external view {
        if (player != 1 && player != 2) revert("PLAYER must be 1 or 2");

        (address factoryAddress, address gameAddress) = _getFactoryAndLatestGame();
        if (gameAddress == address(0)) revert("No games found. Create a game first with: make create-game");

        EscrowManager escrowManager = SharksAndTigersFactory(factoryAddress).i_escrowManager();
        SharksAndTigers.Game memory g = SharksAndTigers(gameAddress).getGameInfo();
        address playerAddress = player == 1 ? g.playerOne : g.playerTwo;

        uint256 amount = escrowManager.refundable(playerAddress);

        console.log("Player", uint256(player));
        console.log("Player address:", playerAddress);
        console.log("Refundable (raw):", amount);
        console.log("Refundable (USDC):", amount / 1e6);
    }
}
