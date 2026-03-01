// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {SharksAndTigersFactory} from "../../src/SharksAndTigersFactory.sol";
import {SharksAndTigers} from "../../src/SharksAndTigers.sol";
import {EscrowManager} from "../../src/EscrowManager.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {DeploymentHelper} from "./lib/DeploymentHelper.s.sol";

/**
 * @title ClaimReward
 * @notice Interaction script for a winner to claim their reward from EscrowManager.
 * @dev Usage: make claim-reward PLAYER=1 (or PLAYER=2). Prints success/failure, amount, and balance.
 */
contract ClaimReward is DeploymentHelper {
    function run(uint8 player) external {
        if (player != 1 && player != 2) revert("PLAYER must be 1 or 2");

        (address factoryAddress, address gameAddress) = _getFactoryAndLatestGame();
        EscrowManager escrowManager = SharksAndTigersFactory(factoryAddress).i_escrowManager();
        IERC20 usdc = IERC20(escrowManager.i_usdcToken());

        address playerAddress;
        uint256 lastPlayTime;
        uint256 playClock;
        if (gameAddress != address(0)) {
            SharksAndTigers.Game memory g = SharksAndTigers(gameAddress).getGameInfo();
            playerAddress = player == 1 ? g.playerOne : g.playerTwo;
            lastPlayTime = g.lastPlayTime;
            playClock = g.playClock;
        } else {
            revert("No game found. Create and play a game first.");
        }

        uint256 claimableAmount = escrowManager.claimable(playerAddress);
        if (claimableAmount == 0) {
            console.log("Failure: Nothing to claim.");
            console.log("Reason: This player has no claimable winnings (claimable balance is 0).");
            console.log("Player address:", playerAddress);
            return;
        }

        uint256 balanceBefore = usdc.balanceOf(playerAddress);
        vm.startBroadcast();
        escrowManager.claimReward();
        vm.stopBroadcast();
        uint256 balanceAfter = usdc.balanceOf(playerAddress);

        console.log("Success: Reward claimed.");
        console.log("Player address (winner):", playerAddress);
        console.log("Amount claimed (winnings):", claimableAmount);
        console.log("Amount claimed (USDC):", claimableAmount / 1e6);
        console.log("USDC balance before claim:", balanceBefore);
        console.log("USDC balance after claim:", balanceAfter);
    }
}
