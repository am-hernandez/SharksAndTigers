// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {SharksAndTigersFactory} from "../../../src/SharksAndTigersFactory.sol";

/**
 * @title DeploymentHelper
 * @notice Shared helper for interaction scripts: read factory and latest game from broadcast deployment.
 */
contract DeploymentHelper is Script {
    /// @notice Returns factory address and latest game address (game may be address(0) if no games exist).
    function _getFactoryAndLatestGame() internal view returns (address factoryAddress, address gameAddress) {
        string memory chainId = vm.toString(block.chainid);
        string memory broadcastPath = string.concat("broadcast/Deploy.s.sol/", chainId);
        string memory runPath = string.concat(broadcastPath, "/run-latest.json");
        string memory dryRunPath = string.concat(broadcastPath, "/dry-run/run-latest.json");

        string memory json;
        try vm.readFile(runPath) returns (string memory fileContent) {
            json = fileContent;
        } catch {
            try vm.readFile(dryRunPath) returns (string memory fileContent) {
                json = fileContent;
            } catch {
                revert("Could not find deployment. Deploy the factory first with: make deploy");
            }
        }

        uint256 i = 0;
        while (true) {
            try vm.parseJsonString(json, string.concat(".transactions[", vm.toString(i), "].contractName")) returns (
                string memory contractName
            ) {
                if (keccak256(bytes(contractName)) == keccak256(bytes("SharksAndTigersFactory"))) {
                    factoryAddress =
                        vm.parseJsonAddress(json, string.concat(".transactions[", vm.toString(i), "].contractAddress"));
                    break;
                }
                i++;
            } catch {
                revert("SharksAndTigersFactory not found in deployment. Deploy first with: make deploy");
            }
        }

        SharksAndTigersFactory factory = SharksAndTigersFactory(factoryAddress);
        uint256 gameCount = factory.s_gameCount();
        gameAddress = gameCount == 0 ? address(0) : factory.s_games(gameCount);
    }

    /// @notice Returns the latest game address; reverts if no games exist.
    function _getLatestGameAddress() internal view returns (address) {
        (, address gameAddress) = _getFactoryAndLatestGame();
        if (gameAddress == address(0)) revert("No games found. Create a game first with: make create-game");
        return gameAddress;
    }
}
