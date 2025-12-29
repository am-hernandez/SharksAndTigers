// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/access/AccessControl.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/utils/ReentrancyGuardTransient.sol";

/// @notice Escrow manager for Sharks & Tigers stakes (USDC).
/// @dev Funds are held here; games only "declare outcomes" via finalize.
contract EscrowManager is AccessControl, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    /// @notice Role granted to the factory contract for registering games
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");
    /// @notice Role granted to individual game contracts for escrow operations
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");

    /// @notice Thrown when factory address is invalid
    error NotFactory();
    /// @notice Thrown when attempting to operate on an unregistered game
    error GameNotRegistered();
    /// @notice Thrown when attempting to register a game that is already registered
    error AlreadyRegistered();
    /// @notice Thrown when game address is invalid
    error InvalidGame();
    /// @notice Thrown when USDC token address is invalid
    error InvalidToken();
    /// @notice Thrown when stake amount is invalid (zero or otherwise)
    error InvalidStake();
    /// @notice Thrown when player address is invalid
    error InvalidPlayer();
    /// @notice Thrown when attempting to deposit stake that was already deposited
    error AlreadyDeposited();
    /// @notice Thrown when player1 is not set in escrow
    error PlayerOneNotSet();
    /// @notice Thrown when player2 is not set in escrow
    error PlayerTwoNotSet();
    /// @notice Thrown when attempting to set player2 when already set
    error PlayerTwoAlreadySet();
    /// @notice Thrown when player2 has already deposited stake
    error PlayerTwoAlreadyDeposited();
    /// @notice Thrown when player1 has not deposited stake
    error PlayerOneNotDeposited();
    /// @notice Thrown when player2 has not deposited stake
    error PlayerTwoNotDeposited();
    /// @notice Thrown when attempting to finalize an already finalized escrow
    error AlreadyFinalized();
    /// @notice Thrown when finalization parameters are inconsistent
    /// @param gameId The game ID with invalid end state
    /// @param isDraw Whether the game ended in a draw
    /// @param isCancelled Whether the game was cancelled
    /// @param winner The winner address
    error InvalidEndState(uint256 gameId, bool isDraw, bool isCancelled, address winner);
    /// @notice Thrown when escrow state does not match expected values
    /// @param gameId The game ID with invalid escrow state
    /// @param observedTotal The observed total staked amount
    /// @param expectedTotal The expected total staked amount
    error InvalidEscrowState(uint256 gameId, uint256 observedTotal, uint256 expectedTotal);
    /// @notice Thrown when attempting to withdraw with no refundable balance
    error NothingToWithdraw();
    /// @notice Thrown when attempting to claim with no claimable balance
    error NothingToClaim();

    /// @notice Escrow metadata for a game
    /// @param gameId Unique identifier for the game
    /// @param player1 Address of player one
    /// @param player2 Address of player two (zero address if not yet joined)
    /// @param stakeAmountPerPlayer Stake amount required from each player
    /// @param totalStaked Total amount currently staked in escrow
    /// @param stakeDepositedForPlayer1 Whether player1 has deposited their stake
    /// @param stakeDepositedForPlayer2 Whether player2 has deposited their stake
    /// @param finalized Whether the escrow has been finalized
    struct GameEscrow {
        uint256 gameId;
        address player1;
        address player2;
        uint256 stakeAmountPerPlayer;
        uint256 totalStaked;
        bool stakeDepositedForPlayer1;
        bool stakeDepositedForPlayer2;
        bool finalized;
    }

    /// @notice The USDC token used for all stakes
    IERC20 public immutable i_usdcToken;

    /// @notice game => escrow metadata
    mapping(address => GameEscrow) public escrows;

    /// @notice Mapping of player addresses to their refundable stake amounts (from draws or cancellations)
    mapping(address => uint256) public refundable;

    /// @notice Mapping of player addresses to their claimable reward amounts (from wins)
    mapping(address => uint256) public claimable;

    /// @notice Emitted when a new game escrow is registered
    /// @param game Address of the game contract
    /// @param player1 Address of player one
    /// @param stake Stake amount per player
    event GameRegistered(address indexed game, address indexed player1, uint256 stake);
    /// @notice Emitted when player2 is set for a game escrow
    /// @param game Address of the game contract
    /// @param player2 Address of player two
    event Player2Set(address indexed game, address indexed player2);
    /// @notice Emitted when a player deposits their stake into escrow
    /// @param game Address of the game contract
    /// @param player Address of the player depositing
    /// @param amount Amount deposited
    event StakeDeposited(address indexed game, address indexed player, uint256 amount);
    /// @notice Emitted when a game escrow is finalized
    /// @param game Address of the game contract
    /// @param winner Address of the winner (zero address for draws/cancellations)
    /// @param isDraw Whether the game ended in a draw
    /// @param isCancelled Whether the game was cancelled
    event Finalized(address indexed game, address indexed winner, bool isDraw, bool isCancelled);
    /// @notice Emitted when a player withdraws their refundable stake
    /// @param player Address of the player withdrawing
    /// @param amount Amount withdrawn
    event RefundableStakeWithdrawn(address indexed player, uint256 amount);
    /// @notice Emitted when a player claims their reward
    /// @param player Address of the player claiming
    /// @param amount Amount claimed
    event RewardClaimed(address indexed player, uint256 amount);

    /// @notice Constructs the EscrowManager contract
    /// @dev Grants DEFAULT_ADMIN_ROLE to deployer and FACTORY_ROLE to the factory address
    /// @param factory Address of the SharksAndTigersFactory contract
    /// @param usdcToken Address of the USDC token contract
    constructor(address factory, address usdcToken) {
        if (factory == address(0)) revert NotFactory();
        if (usdcToken == address(0)) revert InvalidToken();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FACTORY_ROLE, factory);
        i_usdcToken = IERC20(usdcToken);
    }

    /// @notice Register a new game escrow and grant GAME_ROLE (called by Factory after deploying the game)
    /// @dev Player1 is known at creation; player2 is set by game contract when player2 joins.
    /// @dev Factory must call this immediately after deploying a game to authorize it for escrow operations.
    /// @param game Address of the deployed game contract
    /// @param gameId Unique identifier for the game
    /// @param player1 Address of player one
    /// @param stake Stake amount required from each player (in USDC units)
    function registerGame(address game, uint256 gameId, address player1, uint256 stake)
        external
        onlyRole(FACTORY_ROLE)
    {
        if (game == address(0)) revert InvalidGame();
        if (player1 == address(0)) revert InvalidPlayer();
        if (stake == 0) revert InvalidStake();
        if (escrows[game].gameId != 0) revert AlreadyRegistered();

        // Register escrow
        escrows[game] = GameEscrow({
            gameId: gameId,
            player1: player1,
            player2: address(0),
            stakeAmountPerPlayer: stake,
            totalStaked: stake,
            stakeDepositedForPlayer1: false,
            stakeDepositedForPlayer2: false,
            finalized: false
        });

        // Grant GAME_ROLE to the specific game contract
        _grantRole(GAME_ROLE, game);

        emit GameRegistered(game, player1, stake);
    }

    /// @notice Set player2 for a game escrow (called by Game on join)
    /// @dev Only the game contract itself can set player2 when a player joins.
    /// @dev The game address is derived from msg.sender to ensure only the specific game contract can set its player2.
    /// @param game Address of the game contract (must match msg.sender)
    /// @param player2 Address of player two joining the game
    function setPlayer2(address game, address player2) external onlyRole(GAME_ROLE) {
        address gameAddress = msg.sender;
        GameEscrow storage gameEscrow = escrows[gameAddress];
        if (gameEscrow.gameId == 0) revert GameNotRegistered();
        if (gameEscrow.player1 == address(0)) revert PlayerOneNotSet();
        if (player2 == address(0) || player2 == gameEscrow.player1) revert InvalidPlayer();
        if (gameEscrow.player2 != address(0)) revert PlayerTwoAlreadySet();

        gameEscrow.player2 = player2;
        emit Player2Set(game, player2);
    }

    /// @notice Deposit stake from player1 into escrow for this game
    /// @dev Called by the factory contract when player1 creates the game.
    /// @dev Transfers USDC from player1 to this escrow contract. Requires player1 to have approved this contract.
    /// @param gameAddress Address of the game contract for which the deposit is made
    function depositPlayer1(address gameAddress) external onlyRole(FACTORY_ROLE) {
        GameEscrow storage gameEscrow = escrows[gameAddress];

        uint256 gameId = gameEscrow.gameId;
        address player1 = gameEscrow.player1;
        uint256 stake = gameEscrow.stakeAmountPerPlayer;
        uint256 total = gameEscrow.totalStaked;

        if (gameId == 0) revert GameNotRegistered();
        if (gameEscrow.finalized) revert AlreadyFinalized();
        if (stake == 0) revert InvalidStake();
        if (player1 == address(0)) revert PlayerOneNotSet();
        if (gameEscrow.stakeDepositedForPlayer1) revert AlreadyDeposited();
        if (total != 0) revert InvalidEscrowState(gameId, total, 0);

        gameEscrow.stakeDepositedForPlayer1 = true;
        total += stake;

        if (total != stake) revert InvalidEscrowState(gameId, total, stake);
        gameEscrow.totalStaked = total;

        i_usdcToken.safeTransferFrom(player1, address(this), stake);

        emit StakeDeposited(gameAddress, player1, stake);
    }

    /// @notice Deposit stake from player2 into escrow for this game
    /// @dev Called by the game contract when player2 joins the game.
    /// @dev Transfers USDC from player2 to this escrow contract. Requires player2 to have approved this contract.
    /// @dev The game address is derived from msg.sender to ensure only the specific game contract can deposit for its player2.
    function depositPlayer2() external onlyRole(GAME_ROLE) {
        address gameAddress = msg.sender;
        GameEscrow storage gameEscrow = escrows[gameAddress];

        uint256 gameId = gameEscrow.gameId;
        address player2 = gameEscrow.player2;
        uint256 stake = gameEscrow.stakeAmountPerPlayer;
        uint256 total = gameEscrow.totalStaked;

        if (gameId == 0) revert GameNotRegistered();
        if (gameEscrow.finalized) revert AlreadyFinalized();
        if (player2 == address(0)) revert PlayerTwoNotSet();
        if (stake == 0) revert InvalidStake();
        if (!gameEscrow.stakeDepositedForPlayer1) revert PlayerOneNotDeposited();
        if (gameEscrow.stakeDepositedForPlayer2) revert AlreadyDeposited();
        if (total != stake) revert InvalidEscrowState(gameId, total, stake);

        gameEscrow.stakeDepositedForPlayer2 = true;
        total += stake;

        uint256 expectedTotalStaked = 2 * stake;
        if (total != expectedTotalStaked) revert InvalidEscrowState(gameId, total, expectedTotalStaked);
        gameEscrow.totalStaked = total;

        i_usdcToken.safeTransferFrom(player2, address(this), stake);

        emit StakeDeposited(gameAddress, player2, stake);
    }

    /// @notice Finalize the escrow for a game (called by the game contract when game ends)
    /// @dev Winner gets 2*stake credited to claimable. Draw credits stake to refundable for both players.
    /// @dev Cancellation (before player2 joins) credits stake to refundable for player1 only.
    /// @dev The game address is derived from msg.sender to ensure only the specific game contract can finalize its escrow.
    /// @param winner Address of the winner (zero address for draws/cancellations)
    /// @param isDraw Whether the game ended in a draw
    /// @param isCancelled Whether the game was cancelled before player2 joined
    function finalize(address winner, bool isDraw, bool isCancelled) external onlyRole(GAME_ROLE) {
        address gameAddress = msg.sender;
        GameEscrow storage gameEscrow = escrows[gameAddress];
        uint256 gameId = gameEscrow.gameId;

        if (gameId == 0) revert GameNotRegistered();
        if (gameEscrow.finalized) revert AlreadyFinalized();

        // end-state sanity
        if (isDraw && isCancelled) revert InvalidEndState(gameId, isDraw, isCancelled, winner);
        if (isCancelled && winner != address(0)) revert InvalidEndState(gameId, isDraw, isCancelled, winner);
        if (isDraw && winner != address(0)) revert InvalidEndState(gameId, isDraw, isCancelled, winner);

        if (gameEscrow.player1 == address(0)) revert PlayerOneNotSet();
        if (!gameEscrow.stakeDepositedForPlayer1) revert PlayerOneNotDeposited();

        // Cancel-before-join case
        if (isCancelled) {
            if (gameEscrow.player2 != address(0)) revert PlayerTwoAlreadySet();
            if (gameEscrow.stakeDepositedForPlayer2) revert PlayerTwoAlreadyDeposited();

            gameEscrow.finalized = true;
            refundable[gameEscrow.player1] += gameEscrow.stakeAmountPerPlayer;

            emit Finalized(gameAddress, address(0), false, true);
            return;
        }

        // From here on: must be a started game (player2 joined + deposited)
        if (gameEscrow.player2 == address(0)) revert PlayerTwoNotSet();
        if (!gameEscrow.stakeDepositedForPlayer2) revert PlayerTwoNotDeposited();

        uint256 expectedTotal = 2 * gameEscrow.stakeAmountPerPlayer;
        if (gameEscrow.totalStaked != expectedTotal) {
            revert InvalidEscrowState(gameId, gameEscrow.totalStaked, expectedTotal);
        }

        gameEscrow.finalized = true;

        if (isDraw) {
            refundable[gameEscrow.player1] += gameEscrow.stakeAmountPerPlayer;
            refundable[gameEscrow.player2] += gameEscrow.stakeAmountPerPlayer;

            emit Finalized(gameAddress, address(0), true, false);
            return;
        }

        // Win case
        if (winner == address(0)) revert InvalidEndState(gameId, isDraw, isCancelled, winner);
        if (winner != gameEscrow.player1 && winner != gameEscrow.player2) {
            revert InvalidEndState(gameId, isDraw, isCancelled, winner);
        }

        claimable[winner] += expectedTotal;

        emit Finalized(gameAddress, winner, false, false);
    }

    /// @notice Withdraw refunded stake (from draws or cancellations)
    /// @dev Transfers USDC from escrow to the caller. Only callable by players with a refundable balance.
    /// @dev Uses nonReentrant modifier to prevent reentrancy attacks.
    function withdrawRefundableStake() external nonReentrant {
        uint256 refundableAmount = refundable[msg.sender];
        if (refundableAmount == 0) revert NothingToWithdraw();

        refundable[msg.sender] = 0;

        i_usdcToken.safeTransfer(msg.sender, refundableAmount);
        emit RefundableStakeWithdrawn(msg.sender, refundableAmount);
    }

    /// @notice Claim winnings (2x stake for winners)
    /// @dev Transfers USDC from escrow to the caller. Only callable by players with a claimable balance.
    /// @dev Winners receive the full pot (2x stake). Uses nonReentrant modifier to prevent reentrancy attacks.
    function claimReward() external nonReentrant {
        uint256 claimableAmount = claimable[msg.sender];
        if (claimableAmount == 0) revert NothingToClaim();

        claimable[msg.sender] = 0;

        i_usdcToken.safeTransfer(msg.sender, claimableAmount);
        emit RewardClaimed(msg.sender, claimableAmount);
    }
}
