// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/mocks/token/ERC20Mock.sol";

/**
 * @title UsdcHelper
 * @notice Helper library for USDC operations in interaction scripts
 * @dev Provides reusable functions for minting USDC on local chains
 */
library UsdcHelper {
    /**
     * @notice Mints USDC to the given address on local Anvil chain if balance is insufficient for wager amount
     * @param usdcTokenAddress The address of the USDC token contract
     * @param recipient The address to mint USDC to
     * @param requiredAmount The minimum amount of USDC needed
     * @param playerLabel Label for logging (e.g., "player one", "player two")
     */
    function ensureUsdcBalance(
        address usdcTokenAddress,
        address recipient,
        uint256 requiredAmount,
        string memory playerLabel
    ) internal {
        // Only mint on local Anvil chains
        if (block.chainid != 31337) {
            return;
        }

        IERC20 usdc = IERC20(usdcTokenAddress);
        uint256 currentBalance = usdc.balanceOf(recipient);

        if (currentBalance < requiredAmount) {
            ERC20Mock mockUsdc = ERC20Mock(usdcTokenAddress);
            uint256 amountToMint = requiredAmount * 2; // Mint enough for wager plus some extra
            mockUsdc.mint(recipient, amountToMint);
            console.log("Minted", amountToMint / 1e6, "USDC to", playerLabel);
            console.log("Recipient:", recipient);
        }
    }
}

