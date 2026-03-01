// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/mocks/token/ERC20Mock.sol";
import {SharksAndTigersFactory} from "../src/SharksAndTigersFactory.sol";

contract Deploy is Script {
    function run() external {
        address usdcToken;

        vm.startBroadcast();

        // On local chains (Anvil), deploy a mock USDC token
        // On testnets/mainnets, use USDC_TOKEN from environment
        if (block.chainid == 31337) {
            // Local Anvil chain - deploy mock USDC
            ERC20Mock mockUsdc = new ERC20Mock();
            usdcToken = address(mockUsdc);
        } else {
            // Testnet/Mainnet - use real USDC from environment
            usdcToken = vm.envAddress("USDC_TOKEN");
            console.log("Using USDC token from environment:", usdcToken);
        }

        SharksAndTigersFactory factory = new SharksAndTigersFactory(IERC20(usdcToken));

        vm.stopBroadcast();

        console.log("========== Deployment Summary ==========");
        console.log("Deployer address:", msg.sender);
        console.log("Chain ID:", block.chainid);
        console.log("");
        console.log("Contracts deployed:");
        console.log("  SharksAndTigersFactory:", address(factory));
        console.log("  EscrowManager:", address(factory.i_escrowManager()));
        console.log("");
        console.log("Configuration:");
        console.log("  USDC Token address:", usdcToken);
        console.log("========================================");
    }
}

