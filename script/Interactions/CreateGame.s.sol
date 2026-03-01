// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {SharksAndTigersFactory} from "../../src/SharksAndTigersFactory.sol";
import {SharksAndTigers} from "../../src/SharksAndTigers.sol";
import {EscrowManager} from "../../src/EscrowManager.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {GameConfig} from "./lib/GameConfig.s.sol";
import {UsdcHelper} from "./lib/UsdcHelper.s.sol";

contract CreateGame is Script {
    using SafeERC20 for IERC20;

    function createGame(address mostRecentlyDeployedFactoryAddress) internal {
        // Cast address to factory contract
        SharksAndTigersFactory factory = SharksAndTigersFactory(mostRecentlyDeployedFactoryAddress);

        // Get EscrowManager and USDC token addresses from factory
        EscrowManager escrowManager = factory.i_escrowManager();
        address usdcTokenAddress = address(escrowManager.i_usdcToken());
        IERC20 usdc = IERC20(usdcTokenAddress);

        // Game parameters from shared config
        uint8 position = GameConfig.PLAYER_ONE_STARTING_POSITION;
        SharksAndTigers.Mark playerOneMark =
            GameConfig.PLAYER_ONE_MARK == 1 ? SharksAndTigers.Mark.Shark : SharksAndTigers.Mark.Tiger;
        uint256 playClock = GameConfig.PLAY_CLOCK;
        uint256 stake = GameConfig.STAKE;

        vm.startBroadcast();

        // On local chains (Anvil), mint USDC to player one if needed
        UsdcHelper.ensureUsdcBalance(usdcTokenAddress, msg.sender, stake, "player one");

        // Check balance and allowance
        uint256 balance = usdc.balanceOf(msg.sender);
        address escrowManagerAddress = address(escrowManager);
        uint256 currentAllowance = usdc.allowance(msg.sender, escrowManagerAddress);
        console.log("Player one USDC balance:", balance);
        console.log("Current USDC allowance to EscrowManager:", currentAllowance);
        console.log("Required stake amount:", stake);

        if (balance < stake) {
            if (block.chainid != 31337) {
                revert("Insufficient USDC balance. Player one needs at least the stake amount.");
            }
        }

        // Approve EscrowManager to spend USDC if needed
        if (currentAllowance < stake) {
            console.log("Approving EscrowManager to spend USDC...");
            // Reset to zero first to handle tokens that require zero before new approval
            if (currentAllowance > 0) {
                usdc.approve(escrowManagerAddress, 0);
            }
            usdc.approve(escrowManagerAddress, stake);
            console.log("Approval successful");
        }

        // Create the game
        console.log("Creating game with 5 USDC stake...");
        factory.createGame(position, playerOneMark, playClock, stake);

        vm.stopBroadcast();

        // Read game details (view calls don't need broadcast)
        uint256 gameCount = factory.s_gameCount();
        address gameAddress = factory.s_games(gameCount);
        SharksAndTigers gameContract = SharksAndTigers(gameAddress);
        address creator = gameContract.i_playerOne();

        console.log("Game created successfully!");
        console.log("Game ID:", gameCount);
        console.log("Game contract address:", gameAddress);
        console.log("Player One (creator):", creator);
        console.log("Player One Mark:", GameConfig.PLAYER_ONE_MARK == 1 ? "Shark" : "Tiger");
        console.log("Initial Position:", position);
        console.log("Play Clock:", playClock, "seconds");
        console.log("Stake:", stake / 1e6, "USDC");
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
        bool isDryRun = false;
        try vm.readFile(runPath) returns (string memory fileContent) {
            json = fileContent;
            console.log("Reading from broadcast deployment:", runPath);
        } catch {
            try vm.readFile(dryRunPath) returns (string memory fileContent) {
                json = fileContent;
                isDryRun = true;
                console.log("Reading from dry-run deployment:", dryRunPath);
            } catch {
                revert("Could not find deployment. Deploy the factory first with: make deploy");
            }
        }

        // Search through transactions to find SharksAndTigersFactory
        // Transactions are indexed starting from 0
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

        console.log("Using factory address from deployment:", factoryAddress);
        createGame(factoryAddress);
    }
}

