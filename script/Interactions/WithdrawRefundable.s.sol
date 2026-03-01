// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {SharksAndTigersFactory} from "../../src/SharksAndTigersFactory.sol";
import {SharksAndTigers} from "../../src/SharksAndTigers.sol";
import {EscrowManager} from "../../src/EscrowManager.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {DeploymentHelper} from "./lib/DeploymentHelper.s.sol";

/**
 * @title WithdrawRefundable
 * @notice Interaction script to withdraw refundable stake (from draws or cancellations) from EscrowManager.
 * @dev Usage: make withdraw-refundable PLAYER=1 (or PLAYER=2). Prints success/failure, amount, and balance.
 */
contract WithdrawRefundable is DeploymentHelper {
    function run(uint8 player) external {
        if (player != 1 && player != 2) revert("PLAYER must be 1 or 2");

        (address factoryAddress, address gameAddress) = _getFactoryAndLatestGame();
        EscrowManager escrowManager = SharksAndTigersFactory(factoryAddress).i_escrowManager();
        IERC20 usdc = IERC20(escrowManager.i_usdcToken());

        address playerAddress;
        if (gameAddress != address(0)) {
            SharksAndTigers.Game memory g = SharksAndTigers(gameAddress).getGameInfo();
            playerAddress = player == 1 ? g.playerOne : g.playerTwo;
        } else {
            revert("No game found. Create a game first with: make create-game");
        }

        uint256 refundableAmount = escrowManager.refundable(playerAddress);
        if (refundableAmount == 0) {
            console.log("Failure: Nothing to withdraw.");
            console.log("Reason: This player has no refundable stake (refundable balance is 0).");
            console.log("Player address:", playerAddress);
            return;
        }

        uint256 balanceBefore = usdc.balanceOf(playerAddress);
        vm.startBroadcast();
        escrowManager.withdrawRefundableStake();
        vm.stopBroadcast();
        uint256 balanceAfter = usdc.balanceOf(playerAddress);

        console.log("Success: Refundable stake withdrawn.");
        console.log("Player address:", playerAddress);
        console.log("Amount withdrawn (raw):", refundableAmount);
        console.log("Amount withdrawn (USDC):", refundableAmount / 1e6);
        console.log("USDC balance before:", balanceBefore);
        console.log("USDC balance after:", balanceAfter);
    }
}
