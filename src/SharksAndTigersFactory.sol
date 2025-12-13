// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SharksAndTigers} from "./SharksAndTigers.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SharksAndTigersFactory {
    using SafeERC20 for IERC20;

    address public immutable s_usdcToken;
    uint256 public s_gameCount = 0;
    mapping(uint256 => address) public s_games;

    event GameCreated(
        uint256 indexed gameId,
        address indexed gameContract,
        address indexed playerOne,
        SharksAndTigers.Mark _playerOneMark,
        uint256 position,
        uint256 playClock,
        uint256 wager
    );

    constructor(address _usdcToken) {
        require(_usdcToken != address(0), "USDC token address cannot be zero");
        s_usdcToken = _usdcToken;
    }

    /**
     * @notice Creates a new game with a USDC wager
     * @dev User must first approve this factory contract to spend USDC: usdc.approve(factoryAddress, wagerAmount)
     * @param position Board position (0-8) for player one's first move
     * @param _playerOneMark Mark choice (1 = Shark, 2 = Tiger)
     * @param playClock Time limit in seconds for each move
     * @param wager USDC wager amount (must match for player two)
     */
    function createGame(uint8 position, uint256 _playerOneMark, uint256 playClock, uint256 wager) external {
        require(_playerOneMark == 1 || _playerOneMark == 2, "Invalid mark for board");
        require(position < 9, "Position is out of range");
        require(wager > 0, "Game creation requires a wager");
        require(playClock > 0, "Must set a play clock value");

        SharksAndTigers.Mark playerOneMark = SharksAndTigers.Mark(_playerOneMark);

        // Check that user has approved sufficient USDC for the wager
        // User must call: IERC20(s_usdcToken).approve(address(this), wager) first
        IERC20 usdc = IERC20(s_usdcToken);
        uint256 allowance = usdc.allowance(msg.sender, address(this));
        require(
            allowance >= wager, "Insufficient USDC allowance. Please approve the factory to spend your wager amount."
        );

        // Transfer USDC from player one to this contract first
        usdc.safeTransferFrom(msg.sender, address(this), wager);

        s_gameCount++;

        // Deploy game contract
        SharksAndTigers game =
            new SharksAndTigers(msg.sender, position, playerOneMark, playClock, s_gameCount, s_usdcToken, wager);

        // Transfer USDC from factory to game contract
        usdc.safeTransfer(address(game), wager);

        // persist game address for lookups without relying on events
        s_games[s_gameCount] = address(game);

        emit GameCreated(s_gameCount, address(game), msg.sender, playerOneMark, position, playClock, wager);
    }

    function getGameAddress(uint256 gameId) external view returns (address) {
        return s_games[gameId];
    }

    function getGameCount() external view returns (uint256) {
        return s_gameCount;
    }

    /**
     * @notice Helper function to check if user has sufficient allowance for a wager
     * @param user The address to check allowance for
     * @param wagerAmount The wager amount to check
     * @return hasAllowance True if user has sufficient allowance
     * @return currentAllowance The current allowance amount
     */
    function checkAllowance(address user, uint256 wagerAmount)
        external
        view
        returns (bool hasAllowance, uint256 currentAllowance)
    {
        IERC20 usdc = IERC20(s_usdcToken);
        currentAllowance = usdc.allowance(user, address(this));
        hasAllowance = currentAllowance >= wagerAmount;
    }

    /**
     * @notice Returns the USDC token address for easy approval
     * @return The USDC token contract address
     */
    function getUsdcToken() external view returns (address) {
        return s_usdcToken;
    }
}
