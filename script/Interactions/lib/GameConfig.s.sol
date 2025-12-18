// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title GameConfig
 * @notice Shared configuration constants for game interaction scripts
 * @dev Both CreateGame and JoinGame reference this to ensure consistency
 */
library GameConfig {
    // Stake amount in USDC (6 decimals)
    uint256 public constant STAKE = 5e6; // 5 USDC

    // Play clock in seconds
    uint256 public constant PLAY_CLOCK = 3600; // 1 hour

    // Player marks (1 = Shark, 2 = Tiger)
    uint256 public constant PLAYER_ONE_MARK = 1; // Shark
    uint256 public constant PLAYER_TWO_MARK = 2; // Tiger

    // Starting positions
    uint8 public constant PLAYER_ONE_STARTING_POSITION = 0;
    uint8 public constant PLAYER_TWO_STARTING_POSITION = 1;
}

