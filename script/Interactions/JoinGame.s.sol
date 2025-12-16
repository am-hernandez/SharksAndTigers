// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {SharksAndTigersFactory} from "../../src/SharksAndTigersFactory.sol";
import {SharksAndTigers} from "../../src/SharksAndTigers.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {GameConfig} from "./lib/GameConfig.s.sol";
import {UsdcHelper} from "./lib/UsdcHelper.s.sol";

contract JoinGame is Script {
    using SafeERC20 for IERC20;

    function joinGame(address gameAddress) internal {
        SharksAndTigers game = SharksAndTigers(gameAddress);

        // Get USDC token address from game contract
        address usdcTokenAddress = game.i_usdcToken();
        IERC20 usdc = IERC20(usdcTokenAddress);

        // Game parameters from shared config
        uint8 position = GameConfig.PLAYER_TWO_STARTING_POSITION;
        uint256 wager = GameConfig.WAGER;

        vm.startBroadcast();

        // On local chains (Anvil), mint USDC to player two if needed
        UsdcHelper.ensureUsdcBalance(usdcTokenAddress, msg.sender, wager, "player two");

        // Check balance and allowance
        uint256 balance = usdc.balanceOf(msg.sender);
        uint256 currentAllowance = usdc.allowance(msg.sender, gameAddress);
        console.log("Player two USDC balance:", balance);
        console.log("Current USDC allowance:", currentAllowance);
        console.log("Required wager amount:", wager);

        if (balance < wager) {
            if (block.chainid != 31337) {
                revert("Insufficient USDC balance. Player two needs at least the wager amount.");
            }
        }

        // Approve game contract to spend USDC if needed
        if (currentAllowance < wager) {
            console.log("Approving game contract to spend USDC...");
            // Reset to zero first to handle tokens that require zero before new approval
            if (currentAllowance > 0) {
                usdc.approve(gameAddress, 0);
            }
            usdc.approve(gameAddress, wager);
            console.log("Approval successful");
        }

        // Join the game
        console.log("Joining game as player two...");
        game.joinGame(position);

        vm.stopBroadcast();

        // Read game details (view calls don't need broadcast)
        address playerTwo = game.s_playerTwo();
        uint256 gameId = game.i_gameId();

        console.log("Successfully joined game!");
        console.log("Game ID:", gameId);
        console.log("Game contract address:", gameAddress);
        console.log("Player Two:", playerTwo);
        console.log("Player Two Mark:", GameConfig.PLAYER_TWO_MARK == 1 ? "Shark" : "Tiger");
        console.log("Starting Position:", position);
        console.log("Wager:", wager / 1e6, "USDC");
    }

    function run() external {
        // Read factory address from most recent deployment in broadcast folder
        string memory chainId = vm.toString(block.chainid);
        string memory broadcastPath = string.concat("broadcast/Deploy.s.sol/", chainId);

        // Try to find the most recent run file (either dry-run or actual broadcast)
        string memory runPath = string.concat(broadcastPath, "/run-latest.json");
        string memory dryRunPath = string.concat(broadcastPath, "/dry-run/run-latest.json");

        address factoryAddress;
        string memory json;
        bool found = false;

        // Try to read from broadcast folder first, then dry-run
        try vm.readFile(runPath) returns (string memory fileContent) {
            json = fileContent;
        } catch {
            try vm.readFile(dryRunPath) returns (string memory fileContent) {
                json = fileContent;
            } catch {
                revert("Could not find deployment. Deploy the factory first with: make deploy");
            }
        }

        // Search through transactions to find SharksAndTigersFactory
        uint256 i = 0;
        while (true) {
            try vm.parseJsonString(json, string.concat(".transactions[", vm.toString(i), "].contractName")) returns (
                string memory contractName
            ) {
                if (keccak256(bytes(contractName)) == keccak256(bytes("SharksAndTigersFactory"))) {
                    factoryAddress =
                        vm.parseJsonAddress(json, string.concat(".transactions[", vm.toString(i), "].contractAddress"));
                    found = true;
                    break;
                }
                i++;
            } catch {
                break; // No more transactions
            }
        }

        if (!found) {
            revert("SharksAndTigersFactory not found in deployment. Deploy the factory first with: make deploy");
        }

        SharksAndTigersFactory factory = SharksAndTigersFactory(factoryAddress);

        // Get the most recent game from the factory
        uint256 gameCount = factory.getGameCount();
        if (gameCount == 0) {
            revert("No games found. Create a game first with: make create-game");
        }

        address gameAddress = factory.getGameAddress(gameCount);
        console.log("Using factory address:", factoryAddress);
        console.log("Found game ID:", gameCount);
        console.log("Game address:", gameAddress);

        joinGame(gameAddress);
    }
}

