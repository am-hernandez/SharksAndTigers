// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SharksAndTigers} from "./SharksAndTigers.sol";
import {EscrowManager} from "./EscrowManager.sol";

contract SharksAndTigersFactory {
    IERC20 public immutable i_usdcToken;
    uint256 public s_gameCount;
    mapping(uint256 => address) public s_games;
    EscrowManager public immutable i_escrowManager;

    error InvalidMark();
    error InvalidPosition();
    error InvalidStake();
    error InvalidPlayClock();
    error InvalidToken();

    event GameCreated(
        uint256 indexed gameId,
        address indexed gameContract,
        address indexed playerOne,
        SharksAndTigers.Mark playerOneMark,
        uint256 position,
        uint256 playClock,
        uint256 stake
    );

    constructor(IERC20 _usdcToken) {
        if (address(_usdcToken) == address(0)) revert InvalidToken();

        i_usdcToken = _usdcToken;
        i_escrowManager = new EscrowManager(address(this), address(_usdcToken));
    }

    /// @notice Creates a new game with a USDC stake
    /// @dev Player must approve USDC to EscrowManager before calling createGame:
    ///      i_usdcToken.approve(address(i_escrowManager), _stake)
    /// @param _position Board position (0-8) for player one's first move
    /// @param _playerOneMark Mark choice (Shark or Tiger)
    /// @param _playClock Time limit in seconds for each move
    /// @param _stake Amount of USDC to stake on the game(player two must match this amount)
    function createGame(uint8 _position, SharksAndTigers.Mark _playerOneMark, uint256 _playClock, uint256 _stake)
        external
    {
        if (_playerOneMark != SharksAndTigers.Mark.Shark && _playerOneMark != SharksAndTigers.Mark.Tiger) {
            revert InvalidMark();
        }
        if (_position >= 9) revert InvalidPosition();
        if (_stake == 0) revert InvalidStake();
        if (_playClock == 0) revert InvalidPlayClock();

        EscrowManager escrowManager = i_escrowManager;

        s_gameCount++;
        uint256 gameId = s_gameCount;

        // Deploy game contract
        SharksAndTigers game = new SharksAndTigers(
            msg.sender, _position, _playerOneMark, _playClock, gameId, i_usdcToken, _stake, address(escrowManager)
        );

        // register game with escrow manager
        escrowManager.registerGame(address(game), gameId, msg.sender, _stake);
        // deposit player one stake into escrow
        escrowManager.depositPlayer1(address(game));

        // persist game address for lookups without relying on events
        s_games[gameId] = address(game);

        emit GameCreated(gameId, address(game), msg.sender, _playerOneMark, _position, _playClock, _stake);
    }
}
