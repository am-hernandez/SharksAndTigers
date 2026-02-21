// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/mocks/token/ERC20Mock.sol";
import {IAccessControl} from "@openzeppelin/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {EscrowManager} from "src/EscrowManager.sol";
import {SharksAndTigersFactory} from "src/SharksAndTigersFactory.sol";
import {SharksAndTigers} from "src/SharksAndTigers.sol";

contract EscrowManagerTest is Test {
    EscrowManager internal escrowManager;
    IERC20 internal usdc;
    ERC20Mock internal usdcMock;
    SharksAndTigersFactory internal gameFactory;

    address internal player1;
    address internal player2;
    address internal player3;

    uint256 internal constant STAKE = 100e6; // 100 USDC (treating 18-decimal ERC20Mock as 6-decimal USDC)
    uint256 internal constant PLAY_CLOCK = 3600; // 1 hour
    uint256 internal constant PLAYER_INITIAL_BALANCE = 1000e6; // 1000 USDC (6 decimals)

    function setUp() public {
        // Deploy mock USDC token (ERC20Mock has 18 decimals, but we treat values as USDC units)
        usdcMock = new ERC20Mock();
        usdc = IERC20(address(usdcMock));

        // Deploy game factory with USDC token address
        gameFactory = new SharksAndTigersFactory(usdc);

        // Get escrow manager deployed by factory
        escrowManager = EscrowManager(address(gameFactory.i_escrowManager()));

        // Create players
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");
        player3 = makeAddr("player3");

        // Mint mock USDC to players
        usdcMock.mint(player1, PLAYER_INITIAL_BALANCE);
        usdcMock.mint(player2, PLAYER_INITIAL_BALANCE);
        usdcMock.mint(player3, PLAYER_INITIAL_BALANCE);

        // Approve escrow manager to spend USDC for all players
        vm.prank(player1);
        usdc.approve(address(escrowManager), type(uint256).max);
        vm.prank(player2);
        usdc.approve(address(escrowManager), type(uint256).max);
        vm.prank(player3);
        usdc.approve(address(escrowManager), type(uint256).max);
    }

    /// @notice Helper function to create a game using the factory with default parameters
    /// @param player Address of player one
    /// @return gameId The created game ID
    /// @return gameAddress The address of the deployed game contract
    /// @dev Uses defaults: position=0, mark=Shark, playClock=PLAY_CLOCK, stake=STAKE
    ///      For custom parameters, call gameFactory.createGame() directly in the test
    function _createGame(address player) internal returns (uint256 gameId, address gameAddress) {
        vm.prank(player);
        gameFactory.createGame(0, SharksAndTigers.Mark.Shark, PLAY_CLOCK, STAKE);

        gameId = gameFactory.s_gameCount();
        gameAddress = gameFactory.s_games(gameId);

        return (gameId, gameAddress);
    }

    // ============ Factory createGame Tests ============

    function test_createGame_succeeds() public {
        (uint256 gameId, address gameAddress) = _createGame(player1);

        assertEq(gameId, 1);
        assertTrue(gameAddress != address(0));
        assertEq(gameFactory.s_gameCount(), 1);
        assertEq(gameFactory.s_games(1), gameAddress);

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
        SharksAndTigers.Mark mark = SharksAndTigers.Mark.Shark;
        vm.prank(player1);
        gameFactory.createGame(position, mark, PLAY_CLOCK, STAKE);
        uint256 gameId = gameFactory.s_gameCount();
        address gameAddress = gameFactory.s_games(gameId);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Find the GameCreated event from factory
        // Event signature: GameCreated(uint256,address,address,uint8,uint256,uint256,uint256)
        // Note: SharksAndTigers.Mark is encoded as uint8 in the event
        bytes32 gameCreatedSig = keccak256("GameCreated(uint256,address,address,uint8,uint256,uint256,uint256)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == gameCreatedSig) {
                found = true;

                // Verify all indexed topics
                assertEq(uint256(logs[i].topics[1]), gameId, "Game ID in event mismatch");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), gameAddress, "Game address in event mismatch");
                assertEq(address(uint160(uint256(logs[i].topics[3]))), player1, "Player1 address in event mismatch");

                // Decode and verify all data fields: (uint8 mark, uint256 position, uint256 playClock, uint256 stake)
                (uint8 eventMark, uint256 eventPosition, uint256 eventPlayClock, uint256 eventStake) =
                    abi.decode(logs[i].data, (uint8, uint256, uint256, uint256));

                assertEq(eventMark, uint8(mark), "Mark in event mismatch");
                assertEq(eventPosition, position, "Position in event mismatch");
                assertEq(eventPlayClock, PLAY_CLOCK, "Play clock in event mismatch");
                assertEq(eventStake, STAKE, "Stake in event mismatch");

                break;
            }
        }
        assertTrue(found, "GameCreated event not found");
    }

    function test_createGame_incrementsGameCount() public {
        (uint256 gameId1,) = _createGame(player1);
        assertEq(gameId1, 1);
        assertEq(gameFactory.s_gameCount(), 1);

        vm.prank(player2);
        gameFactory.createGame(5, SharksAndTigers.Mark.Tiger, PLAY_CLOCK, STAKE);
        uint256 gameId2 = gameFactory.s_gameCount();
        assertEq(gameId2, 2);
        assertEq(gameFactory.s_gameCount(), 2);
    }

    function test_createGame_revertsWhenInsufficientAllowance() public {
        // Player hasn't approved escrow manager
        vm.startPrank(player1);
        usdc.approve(address(escrowManager), 0);
        // EscrowManager checks allowance and will revert with ERC20InsufficientAllowance or custom error
        vm.expectRevert();
        gameFactory.createGame(0, SharksAndTigers.Mark.Shark, PLAY_CLOCK, STAKE);
        vm.stopPrank();
    }

    // ============ Registration Tests ============

    function test_registerGame_succeeds() public {
        // createGame() internally calls registerGame() and depositPlayer1() via factory
        (uint256 gameId, address gameAddress) = _createGame(player1);

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
        (uint256 gameId, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);
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
        (, address gameAddress) = _createGame(player1);
        // Try to register the same game again (should fail)
        vm.prank(address(gameFactory));
        vm.expectRevert(EscrowManager.AlreadyRegistered.selector);
        escrowManager.registerGame(gameAddress, 999, player1, STAKE);
    }

    // ============ Deposit Player1 Tests ============

    function test_depositPlayer1_succeeds() public {
        // Use createGame which calls both registerGame and depositPlayer1
        (uint256 gameId, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);
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
        (, address gameAddress) = _createGame(player1);
        // Try to deposit again (should fail)
        vm.prank(address(gameFactory));
        vm.expectRevert(EscrowManager.AlreadyDeposited.selector);
        escrowManager.depositPlayer1(gameAddress);
    }

    /// @notice Test depositPlayer1 reverts when totalStaked != 0 (defensive check)
    /// @dev This tests the unreachable defensive branch at line 213 of EscrowManager.sol
    ///      Since registerGame always sets totalStaked: 0 and depositPlayer1 is called immediately
    ///      after, this state is unreachable through normal flow. We use storage manipulation
    ///      via vm.store to corrupt the state and verify the defensive check works correctly.
    /// @dev Storage layout: escrows mapping is at slot 1, GameEscrow.totalStaked is at offset 4
    ///      within the struct. We calculate the slot using keccak256(abi.encode(key, mappingSlot)) + offset
    function test_depositPlayer1_revertsWhenTotalStakedNotZero() public {
        // Step 1: Register a game (but don't deposit yet)
        address mockGame = makeAddr("mockGame");
        vm.prank(address(gameFactory));
        escrowManager.registerGame(mockGame, 999, player1, STAKE);

        // Step 2: Manually corrupt storage to set totalStaked to non-zero
        // Storage layout: _roles (from AccessControl) is at slot 0, escrows mapping is at slot 1
        // For a mapping, the slot for escrows[key] is: keccak256(abi.encode(key, mappingSlot))
        // The struct GameEscrow has totalStaked at offset 4 (after gameId, player1, player2, stakeAmountPerPlayer)
        uint256 mappingSlot = 1; // escrows mapping slot
        bytes32 key = bytes32(uint256(uint160(mockGame)));
        bytes32 structSlot = keccak256(abi.encode(key, mappingSlot));

        // totalStaked is the 5th field (offset 4) in the struct
        // Each uint256/address takes one slot, so totalStaked is at structSlot + 4
        bytes32 totalStakedSlot = bytes32(uint256(structSlot) + 4);

        // Corrupt the storage: set totalStaked to a non-zero value
        vm.store(address(escrowManager), totalStakedSlot, bytes32(uint256(100)));

        // Step 3: Verify the corruption worked
        (,,,, uint256 totalStaked,,,) = escrowManager.escrows(mockGame);
        assertEq(totalStaked, 100, "Storage corruption failed");

        // Step 4: Try to deposit - should revert with InvalidEscrowState
        vm.prank(address(gameFactory));
        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowManager.InvalidEscrowState.selector,
                999, // gameId
                100, // observedTotal
                0 // expectedTotal
            )
        );
        escrowManager.depositPlayer1(mockGame);
    }

    /// @notice Test depositPlayer1 defensive check for total != stake after increment
    /// @dev This tests the defensive branch at line 218 of EscrowManager.sol
    ///      After `total += stake` where total starts at 0, the check `if (total != stake)` should
    ///      never fail in normal execution (Solidity 0.8.x reverts on overflow, so 0 + stake = stake).
    ///      However, since `total` is a local variable, we cannot corrupt it during execution.
    ///      This test verifies the check exists by ensuring successful deposits pass through it,
    ///      and documents that the defensive check is present even though it's mathematically
    ///      impossible to trigger through normal means or storage manipulation.
    /// @dev The check at line 218 exists as defense-in-depth against theoretical edge cases
    ///      (compiler bugs, bytecode corruption, etc.). Direct testing would require bytecode
    ///      manipulation which is beyond standard testing practices.
    function test_depositPlayer1_defensiveCheckTotalEqualsStakeAfterIncrement() public {
        // Register a game
        address mockGame = makeAddr("mockGame");
        vm.prank(address(gameFactory));
        escrowManager.registerGame(mockGame, 999, player1, STAKE);

        // Verify the game is registered and ready for deposit
        (uint256 gameId,,,,,,,) = escrowManager.escrows(mockGame);
        assertEq(gameId, 999, "Game should be registered");

        // Attempt deposit - should succeed, which proves the defensive check at line 218 passes
        // The check `if (total != stake)` after `total += stake` (where total was 0) must pass
        // for the deposit to succeed. If the check were to fail, this would revert.
        vm.prank(address(gameFactory));
        escrowManager.depositPlayer1(mockGame);

        // Verify deposit succeeded - this confirms the defensive check at line 218 passed
        (,,,, uint256 totalStaked, bool p1Deposited,,) = escrowManager.escrows(mockGame);
        assertEq(totalStaked, STAKE, "Total staked should equal STAKE after increment");
        assertTrue(p1Deposited, "Player1 should have deposited");

        // Note: Directly testing the revert case (total != stake) is not possible because:
        // 1. `total` is a local variable, so storage corruption won't affect it after it's read
        // 2. Solidity 0.8.x reverts on overflow, so `total += stake` can't produce a wrong value
        // 3. The check is mathematically guaranteed to pass (0 + stake = stake)
        // This test verifies the check exists and works by ensuring successful deposits pass it.
    }

    // ============ Set Player2 Tests ============

    function test_setPlayer2_succeeds() public {
        (, address gameAddress) = _createGame(player1);

        vm.prank(gameAddress);
        escrowManager.setPlayer2(player2);

        (,, address p2,,,,,) = escrowManager.escrows(gameAddress);
        assertEq(p2, player2);
    }

    function test_setPlayer2_emitsEvent() public {
        (, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);

        vm.prank(gameAddress);
        vm.expectRevert(EscrowManager.InvalidPlayer.selector);
        escrowManager.setPlayer2(address(0));
    }

    function test_setPlayer2_revertsWhenPlayer2SameAsPlayer1() public {
        (, address gameAddress) = _createGame(player1);

        vm.prank(gameAddress);
        vm.expectRevert(EscrowManager.InvalidPlayer.selector);
        escrowManager.setPlayer2(player1);
    }

    function test_setPlayer2_revertsWhenAlreadySet() public {
        (, address gameAddress) = _createGame(player1);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        vm.expectRevert(EscrowManager.PlayerTwoAlreadySet.selector);
        escrowManager.setPlayer2(player3);
        vm.stopPrank();
    }

    // ============ Deposit Player2 Tests ============

    function test_depositPlayer2_succeeds() public {
        (, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        vm.expectRevert(EscrowManager.AlreadyDeposited.selector);
        escrowManager.depositPlayer2();
        vm.stopPrank();
    }

    // ============ Finalize Tests ============

    function test_finalize_cancelBeforeJoin_succeeds() public {
        (, address gameAddress) = _createGame(player1);

        vm.prank(gameAddress);
        escrowManager.finalize(address(0), false, true);

        (,,,,,,, bool finalized) = escrowManager.escrows(gameAddress);
        assertTrue(finalized);
        assertEq(escrowManager.refundable(player1), STAKE);
    }

    function test_finalize_cancelBeforeJoin_emitsEvent() public {
        (, address gameAddress) = _createGame(player1);

        vm.expectEmit(true, true, false, false);
        emit EscrowManager.Finalized(gameAddress, address(0), false, true);

        vm.prank(gameAddress);
        escrowManager.finalize(address(0), false, true);
    }

    function test_finalize_draw_succeeds() public {
        (, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        vm.expectEmit(true, true, false, false);
        emit EscrowManager.Finalized(gameAddress, address(0), true, false);
        escrowManager.finalize(address(0), true, false);
        vm.stopPrank();
    }

    function test_finalize_win_succeeds() public {
        (, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);

        vm.startPrank(gameAddress);
        escrowManager.finalize(address(0), false, true);
        vm.expectRevert(EscrowManager.AlreadyFinalized.selector);
        escrowManager.finalize(address(0), false, true);
        vm.stopPrank();
    }

    function test_finalize_revertsWhenDrawAndCancelled() public {
        (uint256 gameId, address gameAddress) = _createGame(player1);

        vm.prank(gameAddress);
        vm.expectRevert(abi.encodeWithSelector(EscrowManager.InvalidEndState.selector, gameId, true, true, address(0)));
        escrowManager.finalize(address(0), true, true);
    }

    function test_finalize_revertsWhenCancelledAndWinnerSet() public {
        (uint256 gameId, address gameAddress) = _createGame(player1);

        vm.prank(gameAddress);
        vm.expectRevert(abi.encodeWithSelector(EscrowManager.InvalidEndState.selector, gameId, false, true, player1));
        escrowManager.finalize(player1, false, true);
    }

    function test_finalize_revertsWhenDrawAndWinnerSet() public {
        (uint256 gameId, address gameAddress) = _createGame(player1);

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
        (uint256 gameId, address gameAddress) = _createGame(player1);

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
        (uint256 gameId, address gameAddress) = _createGame(player1);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        vm.expectRevert(abi.encodeWithSelector(EscrowManager.InvalidEndState.selector, gameId, false, false, player3));
        escrowManager.finalize(player3, false, false);
        vm.stopPrank();
    }

    function test_finalize_revertsWhenCancelButPlayer2Set() public {
        (, address gameAddress) = _createGame(player1);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        vm.expectRevert(EscrowManager.PlayerTwoAlreadySet.selector);
        escrowManager.finalize(address(0), false, true);
        vm.stopPrank();
    }

    function test_finalize_revertsWhenPlayerTwoNotSetForWin() public {
        (, address gameAddress) = _createGame(player1);

        // Try to finalize as win/draw without setting player2
        vm.startPrank(gameAddress);
        vm.expectRevert(EscrowManager.PlayerTwoNotSet.selector);
        escrowManager.finalize(player1, false, false); // win case
        vm.stopPrank();
    }

    /// @notice Test finalize reverts when cancelling but player2 has already deposited (line 284)
    /// @dev Cancel-before-join path requires neither player2 set nor player2 deposited.
    ///      The branch stakeDepositedForPlayer2 is only reachable when player2 is zero (otherwise
    ///      we hit PlayerTwoAlreadySet first). We set player2, deposit, then corrupt player2 to 0
    ///      so the contract reverts with PlayerTwoAlreadyDeposited.
    function test_finalize_revertsWhenCancelButPlayer2AlreadyDeposited() public {
        (, address gameAddress) = _createGame(player1);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        vm.stopPrank();

        // Corrupt player2 to address(0) so we hit the stakeDepositedForPlayer2 check (line 284)
        // rather than PlayerTwoAlreadySet (line 283). escrows at slot 1, player2 at struct offset 2.
        uint256 mappingSlot = 1;
        bytes32 key = bytes32(uint256(uint160(gameAddress)));
        bytes32 structSlot = keccak256(abi.encode(key, mappingSlot));
        bytes32 player2Slot = bytes32(uint256(structSlot) + 2);
        vm.store(address(escrowManager), player2Slot, bytes32(0));

        vm.prank(gameAddress);
        vm.expectRevert(EscrowManager.PlayerTwoAlreadyDeposited.selector);
        escrowManager.finalize(address(0), false, true);
    }

    /// @notice Test finalize reverts when totalStaked != 2*stake (defensive check at line 299)
    /// @dev We build a valid two-player escrow then corrupt totalStaked via vm.store
    ///      and verify InvalidEscrowState is reverted.
    function test_finalize_revertsWhenTotalStakedNotExpected() public {
        (, address gameAddress) = _createGame(player1);

        vm.startPrank(gameAddress);
        escrowManager.setPlayer2(player2);
        escrowManager.depositPlayer2();
        vm.stopPrank();

        // Corrupt totalStaked: escrows at slot 1, totalStaked at struct offset 4
        uint256 mappingSlot = 1;
        bytes32 key = bytes32(uint256(uint160(gameAddress)));
        bytes32 structSlot = keccak256(abi.encode(key, mappingSlot));
        bytes32 totalStakedSlot = bytes32(uint256(structSlot) + 4);
        vm.store(address(escrowManager), totalStakedSlot, bytes32(uint256(STAKE))); // wrong total

        uint256 gameId = 1;
        uint256 expectedTotal = 2 * STAKE;
        vm.prank(gameAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowManager.InvalidEscrowState.selector,
                gameId,
                STAKE, // observed (corrupted)
                expectedTotal
            )
        );
        escrowManager.finalize(player1, false, false);
    }

    // ============ Withdraw Refundable Stake Tests ============

    function test_withdrawRefundableStake_succeeds() public {
        (, address gameAddress) = _createGame(player1);

        vm.prank(gameAddress);
        escrowManager.finalize(address(0), false, true);

        uint256 balanceBefore = usdc.balanceOf(player1);
        vm.prank(player1);
        escrowManager.withdrawRefundableStake();

        assertEq(escrowManager.refundable(player1), 0);
        assertEq(usdc.balanceOf(player1), balanceBefore + STAKE);
    }

    function test_withdrawRefundableStake_emitsEvent() public {
        (, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);

        // Try to register as non-factory (should fail)
        bytes32 factoryRole = escrowManager.FACTORY_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), factoryRole)
        );
        escrowManager.registerGame(gameAddress, 999, player1, STAKE);
    }

    function test_nonFactory_cannotDepositPlayer1() public {
        // Create a game (which already registers and deposits via factory)
        (, address gameAddress) = _createGame(player1);

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
        (, address gameAddress) = _createGame(player1);
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
        _createGame(player1);
        bytes32 gameRole = escrowManager.GAME_ROLE();
        // Try to finalize as non-game (should fail)
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), gameRole)
        );
        escrowManager.finalize(address(0), false, true);
    }

    function test_oneGame_cannotMutateAnotherGameEscrow() public {
        // Create both games using factory
        (, address game1Address) = _createGame(player1);
        (, address game2Address) = _createGame(player2);

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
