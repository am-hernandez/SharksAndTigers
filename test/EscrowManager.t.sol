// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/mocks/token/ERC20Mock.sol";
import {IAccessControl} from "@openzeppelin/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {EscrowManager} from "src/EscrowManager.sol";
import {SharksAndTigersFactory} from "src/SharksAndTigersFactory.sol";
import {SharksAndTigers} from "src/SharksAndTigers.sol";

contract EscrowManagerTest is Test {
    EscrowManager internal escrowManager;
    ERC20Mock internal usdc;
    SharksAndTigersFactory internal gameFactory;

    address internal player1;
    address internal player2;
    address internal player3;

    uint256 internal constant STAKE = 100e6; // 100 USDC (treating 18-decimal ERC20Mock as 6-decimal USDC)
    uint256 internal constant PLAY_CLOCK = 3600; // 1 hour
    uint256 internal constant PLAYER_INITIAL_BALANCE = 1000e6; // 1000 USDC (6 decimals)

    function setUp() public {
        // Deploy mock USDC token (ERC20Mock has 18 decimals, but we treat values as USDC units)
        usdc = new ERC20Mock();

        // Deploy game factory with USDC token address
        gameFactory = new SharksAndTigersFactory(address(usdc));

        // Get escrow manager deployed by factory
        escrowManager = EscrowManager(address(gameFactory.s_escrowManager()));

        // Create players
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");
        player3 = makeAddr("player3");

        // Mint mock USDC to players
        usdc.mint(player1, PLAYER_INITIAL_BALANCE);
        usdc.mint(player2, PLAYER_INITIAL_BALANCE);
        usdc.mint(player3, PLAYER_INITIAL_BALANCE);

        // Approve escrow manager to spend USDC for all players
        vm.prank(player1);
        usdc.approve(address(escrowManager), type(uint256).max);
        vm.prank(player2);
        usdc.approve(address(escrowManager), type(uint256).max);
        vm.prank(player3);
        usdc.approve(address(escrowManager), type(uint256).max);
    }

    /// @notice Helper function to create a game using the factory
    /// @param player Address of player one
    /// @param position Board position (0-8) for player one's first move
    /// @param mark Mark choice (1 = Shark, 2 = Tiger)
    /// @param clock Time limit in seconds for each move
    /// @param stake Stake amount
    /// @return gameId The created game ID
    /// @return gameAddress The address of the deployed game contract
    function _createGame(address player, uint8 position, uint256 mark, uint256 clock, uint256 stake)
        internal
        returns (uint256 gameId, address gameAddress)
    {
        vm.prank(player);
        gameFactory.createGame(position, mark, clock, stake);

        gameId = gameFactory.getGameCount();
        gameAddress = gameFactory.getGameAddress(gameId);

        return (gameId, gameAddress);
    }

    /// @notice Helper function to create a game with default parameters
    /// @param player Address of player one
    /// @param stake Stake amount
    /// @return gameId The created game ID
    /// @return gameAddress The address of the deployed game contract
    function _createGame(address player, uint256 stake) internal returns (uint256 gameId, address gameAddress) {
        return _createGame(player, 0, 1, PLAY_CLOCK, stake);
    }

    // ============ Factory createGame Tests ============

    function test_createGame_succeeds() public {
        (uint256 gameId, address gameAddress) = _createGame(player1, 0, 1, PLAY_CLOCK, STAKE);

        assertEq(gameId, 1);
        assertTrue(gameAddress != address(0));
        assertEq(gameFactory.getGameCount(), 1);
        assertEq(gameFactory.getGameAddress(1), gameAddress);

        // Verify game is registered and player1 deposited - unpack all fields
        (
            uint256 escrowGameId,
            address escrowPlayer1,
            address escrowPlayer2,
            uint256 stakeAmountPerPlayer,
            uint256 totalStaked,
            bool stakeDepositedForPlayer1,
            bool stakeDepositedForPlayer2,
            bool finalized
        ) = escrowManager.escrows(gameAddress);

        // Assert all fields
        assertEq(escrowGameId, gameId, "Game ID mismatch");
        assertEq(escrowPlayer1, player1, "Player1 address mismatch");
        assertEq(escrowPlayer2, address(0), "Player2 should not be set yet");
        assertEq(stakeAmountPerPlayer, STAKE, "Stake amount per player mismatch");
        assertEq(totalStaked, STAKE, "Total staked should equal player1 stake");
        assertTrue(stakeDepositedForPlayer1, "Player1 should have deposited");
        assertFalse(stakeDepositedForPlayer2, "Player2 should not have deposited yet");
        assertFalse(finalized, "Game should not be finalized yet");

        // Verify USDC balances
        assertEq(usdc.balanceOf(address(escrowManager)), STAKE, "Escrow manager balance mismatch");
        assertEq(usdc.balanceOf(player1), PLAYER_INITIAL_BALANCE - STAKE, "Player1 balance mismatch");
    }

    function test_createGame_emitsEvent() public {
        vm.recordLogs();
        uint8 position = 0;
        uint256 mark = 1; // Shark
        (uint256 gameId, address gameAddress) = _createGame(player1, position, mark, PLAY_CLOCK, STAKE);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Find the GameCreated event from factory
        // Event signature: GameCreated(uint256,address,address,uint8,uint256,uint256,uint256,address)
        bytes32 gameCreatedSig = keccak256("GameCreated(uint256,address,address,uint8,uint256,uint256,uint256,address)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == gameCreatedSig) {
                found = true;

                // Verify all indexed topics
                assertEq(uint256(logs[i].topics[1]), gameId, "Game ID in event mismatch");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), gameAddress, "Game address in event mismatch");
                assertEq(address(uint160(uint256(logs[i].topics[3]))), player1, "Player1 address in event mismatch");

                // Decode and verify all data fields: (uint8 mark, uint256 position, uint256 playClock, uint256 stake, address escrowManager)
                (
                    uint8 eventMark,
                    uint256 eventPosition,
                    uint256 eventPlayClock,
                    uint256 eventStake,
                    address eventEscrowManager
                ) = abi.decode(logs[i].data, (uint8, uint256, uint256, uint256, address));

                assertEq(eventMark, mark, "Mark in event mismatch");
                assertEq(eventPosition, position, "Position in event mismatch");
                assertEq(eventPlayClock, PLAY_CLOCK, "Play clock in event mismatch");
                assertEq(eventStake, STAKE, "Stake in event mismatch");
                assertEq(eventEscrowManager, address(escrowManager), "Escrow manager address in event mismatch");

                break;
            }
        }
        assertTrue(found, "GameCreated event not found");
    }

    function test_createGame_incrementsGameCount() public {
        (uint256 gameId1,) = _createGame(player1, 0, 1, PLAY_CLOCK, STAKE);
        assertEq(gameId1, 1);
        assertEq(gameFactory.getGameCount(), 1);

        (uint256 gameId2,) = _createGame(player2, 5, 2, PLAY_CLOCK, STAKE);
        assertEq(gameId2, 2);
        assertEq(gameFactory.getGameCount(), 2);
    }

    function test_createGame_revertsWhenInsufficientAllowance() public {
        // Player hasn't approved escrow manager
        vm.startPrank(player1);
        usdc.approve(address(escrowManager), 0);
        // EscrowManager checks allowance and will revert with ERC20InsufficientAllowance or custom error
        vm.expectRevert();
        gameFactory.createGame(0, 1, PLAY_CLOCK, STAKE);
        vm.stopPrank();
    }

    // ============ Registration Tests ============

    function test_registerGame_succeeds() public {
        // createGame() internally calls registerGame() and depositPlayer1() via factory
        (uint256 gameId, address gameAddress) = _createGame(player1, 0, 1, PLAY_CLOCK, STAKE);

        // Verify game was registered and player1 deposited by factory - unpack all fields
        (
            uint256 escrowGameId,
            address escrowPlayer1,
            address escrowPlayer2,
            uint256 stakeAmountPerPlayer,
            uint256 totalStaked,
            bool stakeDepositedForPlayer1,
            bool stakeDepositedForPlayer2,
            bool finalized
        ) = escrowManager.escrows(gameAddress);

        // Assert all fields
        assertEq(escrowGameId, gameId, "Game ID mismatch");
        assertEq(escrowPlayer1, player1, "Player1 address mismatch");
        assertEq(escrowPlayer2, address(0), "Player2 should not be set yet");
        assertEq(stakeAmountPerPlayer, STAKE, "Stake amount per player mismatch");
        assertEq(totalStaked, STAKE, "Total staked should equal player1 stake");
        assertTrue(stakeDepositedForPlayer1, "Player1 should have deposited");
        assertFalse(stakeDepositedForPlayer2, "Player2 should not have deposited yet");
        assertFalse(finalized, "Game should not be finalized yet");

        // Verify USDC balances
        assertEq(usdc.balanceOf(address(escrowManager)), STAKE, "Escrow manager balance mismatch");
        assertEq(usdc.balanceOf(player1), PLAYER_INITIAL_BALANCE - STAKE, "Player1 balance mismatch");
    }

    function test_registerGame_emitsEvent() public {
        vm.recordLogs();
        (uint256 gameId, address gameAddress) = _createGame(player1, 0, 1, PLAY_CLOCK, STAKE);

        // Check for GameRegistered event emitted during createGame()
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 gameRegisteredSig = keccak256("GameRegistered(uint256,address,address,uint256)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == gameRegisteredSig) {
                found = true;
                assertEq(uint256(logs[i].topics[1]), gameId);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), gameAddress);
                assertEq(address(uint160(uint256(logs[i].topics[3]))), player1);
                uint256 stake = abi.decode(logs[i].data, (uint256));
                assertEq(stake, STAKE);
                break;
            }
        }
        assertTrue(found, "GameRegistered event not found");
    }

    function test_registerGame_revertsWhenNotFactory() public {
        // prank as a legit game
        (, address gameAddress) = _createGame(player1, 0, 1, PLAY_CLOCK, STAKE);
        bytes32 factoryRole = escrowManager.FACTORY_ROLE();
        vm.prank(gameAddress);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, gameAddress, factoryRole)
        );
        escrowManager.registerGame(address(0), 1, player1, STAKE);
    }

    function test_registerGame_revertsWhenGameAddressZero() public {
        // Factory calls registerGame internally, but we can test validation by simulating factory call
        vm.prank(address(gameFactory));
        vm.expectRevert(EscrowManager.InvalidGameAddress.selector);
        escrowManager.registerGame(address(0), 1, player1, STAKE);
    }

    function test_registerGame_revertsWhenGameIdZero() public {
        // Use an unregistered game address to test validation
        address unregisteredGame = makeAddr("unregisteredGame");
        vm.prank(address(gameFactory));
        vm.expectRevert(EscrowManager.InvalidGameId.selector);
        escrowManager.registerGame(unregisteredGame, 0, player1, STAKE);
    }

    function test_registerGame_revertsWhenPlayer1Zero() public {
        // Use an unregistered game address to test validation
        address unregisteredGame = makeAddr("unregisteredGame");
        vm.prank(address(gameFactory));
        vm.expectRevert(EscrowManager.InvalidPlayer.selector);
        escrowManager.registerGame(unregisteredGame, 999, address(0), STAKE);
    }

    function test_registerGame_revertsWhenStakeZero() public {
        // Use an unregistered game address to test validation
        address unregisteredGame = makeAddr("unregisteredGame");
        vm.prank(address(gameFactory));
        vm.expectRevert(EscrowManager.InvalidStake.selector);
        escrowManager.registerGame(unregisteredGame, 999, player1, 0);
    }

    function test_registerGame_revertsWhenAlreadyRegistered() public {
        // Create a game (which registers it)
        (, address gameAddress) = _createGame(player1, 0, 1, PLAY_CLOCK, STAKE);
        // Try to register the same game again (should fail)
        vm.prank(address(gameFactory));
        vm.expectRevert(EscrowManager.AlreadyRegistered.selector);
        escrowManager.registerGame(gameAddress, 999, player1, STAKE);
    }

    // ============ Deposit Player1 Tests ============

    function test_depositPlayer1_succeeds() public {
        // Use createGame which calls both registerGame and depositPlayer1
        (uint256 gameId, address gameAddress) = _createGame(player1, STAKE);

        (,,,, uint256 totalStaked, bool p1Deposited,,) = escrowManager.escrows(gameAddress);
        assertEq(gameId, 1);
        assertEq(totalStaked, STAKE);
        assertTrue(p1Deposited);
        assertEq(usdc.balanceOf(address(escrowManager)), STAKE);
        assertEq(usdc.balanceOf(player1), PLAYER_INITIAL_BALANCE - STAKE);
    }

    function test_depositPlayer1_emitsEvent() public {
        // createGame() already deposits player1, so we check the event was emitted during creation
        vm.recordLogs();
        (, address gameAddress) = _createGame(player1, 0, 1, PLAY_CLOCK, STAKE);

        // Check for StakeDeposited event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 stakeDepositedSig = keccak256("StakeDeposited(address,address,uint256)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == stakeDepositedSig) {
                found = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), gameAddress);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), player1);
                uint256 amount = abi.decode(logs[i].data, (uint256));
                assertEq(amount, STAKE);
                break;
            }
        }
        assertTrue(found, "StakeDeposited event not found");
    }

    function test_depositPlayer1_revertsWhenNotFactory() public {
        // Create a game to get a valid game address
        (, address gameAddress) = _createGame(player1, 0, 1, PLAY_CLOCK, STAKE);
        // Try to deposit as non-factory (should fail)
        vm.expectRevert();
        escrowManager.depositPlayer1(gameAddress);
    }

    function test_depositPlayer1_revertsWhenNotRegistered() public {
        // Use an unregistered game address
        address unregisteredGame = makeAddr("unregisteredGame");
        vm.prank(address(gameFactory));
        vm.expectRevert(EscrowManager.GameNotRegistered.selector);
        escrowManager.depositPlayer1(unregisteredGame);
    }

    function test_depositPlayer1_revertsWhenAlreadyDeposited() public {
        // Create a game (which already deposits player1)
        (, address gameAddress) = _createGame(player1, 0, 1, PLAY_CLOCK, STAKE);
        // Try to deposit again (should fail)
        vm.prank(address(gameFactory));
        vm.expectRevert(EscrowManager.AlreadyDeposited.selector);
        escrowManager.depositPlayer1(gameAddress);
    }

    // ============ Set Player2 Tests ============

    function test_setPlayer2_succeeds() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.prank(gameAddress);
        escrowManager.setPlayer2(player2);

        (,, address p2,,,,,) = escrowManager.escrows(gameAddress);
        assertEq(p2, player2);
    }

    function test_setPlayer2_emitsEvent() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.expectEmit(true, true, false, false);
        emit EscrowManager.Player2Set(gameAddress, player2);

        vm.prank(gameAddress);
        escrowManager.setPlayer2(player2);
    }

    function test_setPlayer2_revertsWhenNotRegistered() public {
        // Use an unregistered game address (no GAME_ROLE)
        address unregisteredGame = makeAddr("unregisteredGame");
        bytes32 gameRole = escrowManager.GAME_ROLE();
        vm.prank(unregisteredGame);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, unregisteredGame, gameRole)
        );
        escrowManager.setPlayer2(player2);
    }

    function test_setPlayer2_revertsWhenPlayer1NotDeposited() public {
        // Deploy a mock game contract to get a valid game address
        address mockGameAddress = makeAddr("mockGame");

        // Register the game via factory (this grants GAME_ROLE and sets up escrow with stakeDepositedForPlayer1: false)
        vm.startPrank(address(gameFactory));
        escrowManager.registerGame(mockGameAddress, 999, player1, STAKE);
        vm.stopPrank();

        // Verify the game is registered but player1 hasn't deposited
        (,,,,, bool stakeDepositedForPlayer1,,) = escrowManager.escrows(mockGameAddress);
        assertFalse(stakeDepositedForPlayer1, "Player1 should not have deposited");

        // Try to setPlayer2 as the game - should revert because player1 hasn't deposited
        vm.prank(mockGameAddress);
        vm.expectRevert(EscrowManager.PlayerOneNotDeposited.selector);
        escrowManager.setPlayer2(player2);
    }

    function test_setPlayer2_revertsWhenPlayer2Zero() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.prank(gameAddress);
        vm.expectRevert(EscrowManager.InvalidPlayer.selector);
        escrowManager.setPlayer2(address(0));
    }

    function test_setPlayer2_revertsWhenPlayer2SameAsPlayer1() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.prank(gameAddress);
        vm.expectRevert(EscrowManager.InvalidPlayer.selector);
        escrowManager.setPlayer2(player1);
    }

    function test_setPlayer2_revertsWhenAlreadySet() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        vm.expectRevert(EscrowManager.PlayerTwoAlreadySet.selector);
        escrowManager.setPlayer2(player3);
        vm.stopPrank();
    }

    // ============ Deposit Player2 Tests ============

    function test_depositPlayer2_succeeds() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        vm.stopPrank();

        (,,,, uint256 totalStaked,, bool p2Deposited,) = escrowManager.escrows(gameAddress);
        assertEq(totalStaked, 2 * STAKE);
        assertTrue(p2Deposited);
        assertEq(usdc.balanceOf(address(escrowManager)), 2 * STAKE);
        assertEq(usdc.balanceOf(player2), PLAYER_INITIAL_BALANCE - STAKE);
    }

    function test_depositPlayer2_emitsEvent() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        vm.expectEmit(true, true, true, true);
        emit EscrowManager.StakeDeposited(gameAddress, player2, STAKE);
        escrowManager.depositPlayer2();
        vm.stopPrank();
    }

    function test_depositPlayer2_revertsWhenNotGame() public {
        vm.expectRevert();
        escrowManager.depositPlayer2();
    }

    function test_depositPlayer2_revertsWhenNotRegistered() public {
        // Use an unregistered game address (no GAME_ROLE)
        address unregisteredGame = makeAddr("unregisteredGame");
        vm.prank(unregisteredGame);
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        escrowManager.depositPlayer2();
    }

    function test_depositPlayer2_revertsWhenPlayer2NotSet() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.prank(gameAddress);
        vm.expectRevert(EscrowManager.PlayerTwoNotSet.selector);
        escrowManager.depositPlayer2();
    }

    function test_depositPlayer2_revertsWhenPlayer1NotDeposited() public {
        // register game
        address mockGameAddress = makeAddr("mockGame");
        vm.startPrank(address(gameFactory));
        escrowManager.registerGame(mockGameAddress, 999, player1, STAKE);
        vm.stopPrank();

        // cannot set player 2 if player 1 has not deposited their stake yet
        vm.prank(mockGameAddress);
        vm.expectRevert(EscrowManager.PlayerOneNotDeposited.selector);
        escrowManager.setPlayer2(player2);

        // cannot deposit player 2 if player 2 has not been set
        // Since setPlayer2 failed, player2 is still not set, so depositPlayer2 should revert with PlayerTwoNotSet
        vm.prank(mockGameAddress);
        vm.expectRevert(EscrowManager.PlayerTwoNotSet.selector);
        escrowManager.depositPlayer2();
    }

    function test_depositPlayer2_revertsWhenAlreadyDeposited() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        vm.expectRevert(EscrowManager.AlreadyDeposited.selector);
        escrowManager.depositPlayer2();
        vm.stopPrank();
    }

    // ============ Finalize Tests ============

    function test_finalize_cancelBeforeJoin_succeeds() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.prank(gameAddress);
        escrowManager.finalize(address(0), false, true);

        (,,,,,,, bool finalized) = escrowManager.escrows(gameAddress);
        assertTrue(finalized);
        assertEq(escrowManager.refundable(player1), STAKE);
    }

    function test_finalize_cancelBeforeJoin_emitsEvent() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.expectEmit(true, true, false, false);
        emit EscrowManager.Finalized(gameAddress, address(0), false, true);

        vm.prank(gameAddress);
        escrowManager.finalize(address(0), false, true);
    }

    function test_finalize_draw_succeeds() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        escrowManager.finalize(address(0), true, false);
        vm.stopPrank();

        (,,,,,,, bool finalized) = escrowManager.escrows(gameAddress);
        assertTrue(finalized);
        assertEq(escrowManager.refundable(player1), STAKE);
        assertEq(escrowManager.refundable(player2), STAKE);
    }

    function test_finalize_draw_emitsEvent() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        vm.expectEmit(true, true, false, false);
        emit EscrowManager.Finalized(gameAddress, address(0), true, false);
        escrowManager.finalize(address(0), true, false);
        vm.stopPrank();
    }

    function test_finalize_win_succeeds() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        escrowManager.finalize(player1, false, false);
        vm.stopPrank();

        (,,,,,,, bool finalized) = escrowManager.escrows(gameAddress);
        assertTrue(finalized);
        assertEq(escrowManager.claimable(player1), 2 * STAKE);
    }

    function test_finalize_win_emitsEvent() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        vm.expectEmit(true, true, false, false);
        emit EscrowManager.Finalized(gameAddress, player1, false, false);
        escrowManager.finalize(player1, false, false);
        vm.stopPrank();
    }

    function test_finalize_revertsWhenNotRegistered() public {
        // Use an unregistered game address (no GAME_ROLE)
        address unregisteredGame = makeAddr("unregisteredGame");
        bytes32 gameRole = escrowManager.GAME_ROLE();
        vm.prank(unregisteredGame);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, unregisteredGame, gameRole)
        );
        escrowManager.finalize(address(0), false, false);
    }

    function test_finalize_revertsWhenAlreadyFinalized() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.finalize(address(0), false, true);
        vm.expectRevert(EscrowManager.AlreadyFinalized.selector);
        escrowManager.finalize(address(0), false, true);
        vm.stopPrank();
    }

    function test_finalize_revertsWhenDrawAndCancelled() public {
        (uint256 gameId, address gameAddress) = _createGame(player1, STAKE);

        vm.prank(gameAddress);
        vm.expectRevert(abi.encodeWithSelector(EscrowManager.InvalidEndState.selector, gameId, true, true, address(0)));
        escrowManager.finalize(address(0), true, true);
    }

    function test_finalize_revertsWhenCancelledAndWinnerSet() public {
        (uint256 gameId, address gameAddress) = _createGame(player1, STAKE);

        vm.prank(gameAddress);
        vm.expectRevert(abi.encodeWithSelector(EscrowManager.InvalidEndState.selector, gameId, false, true, player1));
        escrowManager.finalize(player1, false, true);
    }

    function test_finalize_revertsWhenDrawAndWinnerSet() public {
        (uint256 gameId, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        vm.expectRevert(abi.encodeWithSelector(EscrowManager.InvalidEndState.selector, gameId, true, false, player1));
        escrowManager.finalize(player1, true, false);
        vm.stopPrank();
    }

    function test_finalize_revertsWhenNotDrawNotCancelButNoWinner() public {
        // Test that finalize reverts when trying to finalize as a win (not draw, not cancel)
        // but no winner address is provided
        (uint256 gameId, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        vm.expectRevert(
            abi.encodeWithSelector(EscrowManager.InvalidEndState.selector, gameId, false, false, address(0))
        );
        escrowManager.finalize(address(0), false, false);
        vm.stopPrank();
    }

    function test_finalize_revertsWhenWinnerNotAPlayerInGame() public {
        (uint256 gameId, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        vm.expectRevert(abi.encodeWithSelector(EscrowManager.InvalidEndState.selector, gameId, false, false, player3));
        escrowManager.finalize(player3, false, false);
        vm.stopPrank();
    }

    function test_finalize_revertsWhenCancelButPlayer2Set() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        vm.expectRevert(EscrowManager.PlayerTwoAlreadySet.selector);
        escrowManager.finalize(address(0), false, true);
        vm.stopPrank();
    }

    // ============ Withdraw Refundable Stake Tests ============

    function test_withdrawRefundableStake_succeeds() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.prank(gameAddress);
        escrowManager.finalize(address(0), false, true);

        uint256 balanceBefore = usdc.balanceOf(player1);
        vm.prank(player1);
        escrowManager.withdrawRefundableStake();

        assertEq(escrowManager.refundable(player1), 0);
        assertEq(usdc.balanceOf(player1), balanceBefore + STAKE);
    }

    function test_withdrawRefundableStake_emitsEvent() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.prank(gameAddress);
        escrowManager.finalize(address(0), false, true);

        vm.expectEmit(true, false, false, false);
        emit EscrowManager.RefundableStakeWithdrawn(player1, STAKE);

        vm.prank(player1);
        escrowManager.withdrawRefundableStake();
    }

    function test_withdrawRefundableStake_revertsWhenNothingToWithdraw() public {
        vm.prank(player1);
        vm.expectRevert(EscrowManager.NothingToWithdraw.selector);
        escrowManager.withdrawRefundableStake();
    }

    function test_withdrawRefundableStake_cannotWithdrawTwice() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.prank(gameAddress);
        escrowManager.finalize(address(0), false, true);

        vm.startPrank(player1);
        escrowManager.withdrawRefundableStake();
        vm.expectRevert(EscrowManager.NothingToWithdraw.selector);
        escrowManager.withdrawRefundableStake();
        vm.stopPrank();
    }

    // ============ Claim Reward Tests ============

    function test_claimReward_succeeds() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        escrowManager.finalize(player1, false, false);
        vm.stopPrank();

        uint256 balanceBefore = usdc.balanceOf(player1);
        vm.prank(player1);
        escrowManager.claimReward();

        assertEq(escrowManager.claimable(player1), 0);
        assertEq(usdc.balanceOf(player1), balanceBefore + 2 * STAKE);
    }

    function test_claimReward_emitsEvent() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        escrowManager.finalize(player1, false, false);
        vm.stopPrank();

        vm.expectEmit(true, false, false, false);
        emit EscrowManager.RewardClaimed(player1, 2 * STAKE);

        vm.prank(player1);
        escrowManager.claimReward();
    }

    function test_claimReward_revertsWhenNothingToClaim() public {
        vm.prank(player1);
        vm.expectRevert(EscrowManager.NothingToClaim.selector);
        escrowManager.claimReward();
    }

    function test_claimReward_cannotClaimTwice() public {
        (, address gameAddress) = _createGame(player1, STAKE);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        escrowManager.finalize(player1, false, false);
        vm.stopPrank();

        vm.startPrank(player1);
        escrowManager.claimReward();
        vm.expectRevert(EscrowManager.NothingToClaim.selector);
        escrowManager.claimReward();
        vm.stopPrank();
    }

    // ============ Wrong Caller Tests ============

    function test_nonFactory_cannotRegister() public {
        // Create a game to get a valid game address
        (, address gameAddress) = _createGame(player1, 0, 1, PLAY_CLOCK, STAKE);

        // Try to register as non-factory (should fail)
        bytes32 factoryRole = escrowManager.FACTORY_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), factoryRole)
        );
        escrowManager.registerGame(gameAddress, 999, player1, STAKE);
    }

    function test_nonFactory_cannotDepositPlayer1() public {
        // Create a game (which already registers and deposits via factory)
        (, address gameAddress) = _createGame(player1, 0, 1, PLAY_CLOCK, STAKE);

        // Try to deposit as non-factory (should fail)
        bytes32 factoryRole = escrowManager.FACTORY_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), factoryRole)
        );
        escrowManager.depositPlayer1(gameAddress);
    }

    function test_nonGame_cannotSetPlayer2() public {
        // Use an unregistered game address (no GAME_ROLE)
        address unregisteredGame = makeAddr("unregisteredGame");
        bytes32 gameRole = escrowManager.GAME_ROLE();
        vm.prank(unregisteredGame);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, unregisteredGame, gameRole)
        );
        escrowManager.setPlayer2(player2);
    }

    function test_nonGame_cannotDepositPlayer2() public {
        // Create a game
        (, address gameAddress) = _createGame(player1, 0, 1, PLAY_CLOCK, STAKE);
        bytes32 gameRole = escrowManager.GAME_ROLE();

        // Set player2 as the game
        vm.prank(gameAddress);
        escrowManager.setPlayer2(player2);
        // Try to depositPlayer2 as non-game (should fail)
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), gameRole)
        );
        escrowManager.depositPlayer2();
    }

    function test_nonGame_cannotFinalize() public {
        // Create a game
        (, address gameAddress) = _createGame(player1, 0, 1, PLAY_CLOCK, STAKE);
        bytes32 gameRole = escrowManager.GAME_ROLE();
        // Try to finalize as non-game (should fail)
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), gameRole)
        );
        escrowManager.finalize(address(0), false, true);
    }

    function test_oneGame_cannotMutateAnotherGameEscrow() public {
        // Create both games using factory
        (, address game1Address) = _createGame(player1, STAKE);
        (, address game2Address) = _createGame(player2, STAKE);

        // Each game can only access its own escrow (via msg.sender)
        // game1 sets player2 for its own escrow
        vm.prank(game1Address);
        escrowManager.setPlayer2(player3);

        // Verify game1's escrow has player3 as player2
        (,, address p2Game1,,,,,) = escrowManager.escrows(game1Address);
        assertEq(p2Game1, player3);

        // Verify game2's escrow still has no player2
        (,, address p2Game2,,,,,) = escrowManager.escrows(game2Address);
        assertEq(p2Game2, address(0));

        // game2 sets its own player2
        vm.prank(game2Address);
        escrowManager.setPlayer2(player1);

        // Verify each game's escrow is independent
        (,, p2Game1,,,,,) = escrowManager.escrows(game1Address);
        (,, p2Game2,,,,,) = escrowManager.escrows(game2Address);
        assertEq(p2Game1, player3); // game1's player2
        assertEq(p2Game2, player1); // game2's player2
    }
}
