// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
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

        SharksAndTigersFactory factory = new SharksAndTigersFactory(usdcToken);

        vm.stopBroadcast();

        console.log("Deployer address:", msg.sender);
        console.log("SharksAndTigersFactory deployed at:", address(factory));
        console.log("USDC Token address:", usdcToken);
        console.log("Chain ID:", block.chainid);
    }
}

