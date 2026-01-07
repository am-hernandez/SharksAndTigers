// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/interfaces/draft-IERC6093.sol";
import {ERC20Mock} from "@openzeppelin/mocks/token/ERC20Mock.sol";
import {SharksAndTigers} from "src/SharksAndTigers.sol";
import {SharksAndTigersFactory} from "src/SharksAndTigersFactory.sol";
import {EscrowManager} from "src/EscrowManager.sol";

contract MaliciousJoiner {
    function attemptJoinThenImmediateMove(SharksAndTigers game, uint8 joinPos, uint8 movePos)
        external
        returns (bool moveFailed)
    {
        game.joinGame(joinPos);
        // Will not be current player; expect revert
        try game.makeMove(movePos) {
            return false; // unexpected success
        } catch {
            return true; // expected failure
        }
    }
}

contract SharksAndTigersSecurityTest is Test {
    SharksAndTigersFactory internal factory;
    SharksAndTigers internal game;
    ERC20Mock internal usdc;
    address internal walletOne;
    address internal walletTwo;
    address internal walletThree;

    uint256 internal constant STAKE = 100e6; // 100 USDC (6 decimals)
    uint256 internal constant PLAY_CLOCK = 3600; // 1 hour

    function setUp() public {
        // Deploy mock USDC token
        usdc = new ERC20Mock();

        // Deploy factory with USDC token address
        factory = new SharksAndTigersFactory(IERC20(address(usdc)));

        walletOne = makeAddr("walletOne");
        walletTwo = makeAddr("walletTwo");
        walletThree = makeAddr("walletThree");

        // Mint USDC to wallets
        usdc.mint(walletOne, 1000e6);
        usdc.mint(walletTwo, 1000e6);
        usdc.mint(walletThree, 1000e6);

        // Create game: player one approves USDC to EscrowManager and creates game
        vm.startPrank(walletOne);
        EscrowManager escrowManager = factory.i_escrowManager();
        usdc.approve(address(escrowManager), STAKE);
        factory.createGame(0, SharksAndTigers.Mark.Shark, PLAY_CLOCK, STAKE); // Shark at pos 0
        vm.stopPrank();

        game = SharksAndTigers(factory.s_games(factory.s_gameCount()));
    }

    function test_playerOneCannotJoinAsPlayerTwo() public {
        vm.startPrank(walletOne);
        EscrowManager gameEscrowManager = EscrowManager(game.i_escrowManager());
        usdc.approve(address(gameEscrowManager), STAKE);
        vm.expectRevert(bytes("Player one cannot join as player two"));
        game.joinGame(1);
        vm.stopPrank();
    }

    function test_doubleJoinReverts() public {
        EscrowManager gameEscrowManager = EscrowManager(game.i_escrowManager());

        vm.startPrank(walletTwo);
        usdc.approve(address(gameEscrowManager), STAKE);
        game.joinGame(1);
        vm.stopPrank();

        vm.startPrank(walletThree);
        usdc.approve(address(gameEscrowManager), STAKE);
        vm.expectRevert(bytes("Game is not open to joining"));
        game.joinGame(2);
        vm.stopPrank();
    }

    function test_moveBeforeActiveReverts() public {
        vm.prank(walletTwo);
        vm.expectRevert(bytes("Game is not active"));
        game.makeMove(1);
    }

    function test_moveAfterEndedReverts() public {
        // Join and finish a quick win for playerOne: left column 0,3,6
        vm.startPrank(walletTwo);
        EscrowManager gameEscrowManager = EscrowManager(game.i_escrowManager());
        usdc.approve(address(gameEscrowManager), STAKE);
        game.joinGame(2);
        vm.stopPrank();

        vm.prank(walletOne);
        game.makeMove(3);
        vm.prank(walletTwo);
        game.makeMove(5);
        vm.prank(walletOne);
        game.makeMove(6); // ends game

        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Ended));

        vm.prank(walletTwo);
        vm.expectRevert(bytes("Game is not active"));
        game.makeMove(7);
    }

    function test_joinOnAlreadyMarkedPositionReverts() public {
        // Position 0 is already marked by playerOne's initial move in constructor
        vm.startPrank(walletTwo);
        EscrowManager gameEscrowManager = EscrowManager(game.i_escrowManager());
        usdc.approve(address(gameEscrowManager), STAKE);
        vm.expectRevert(bytes("Position is already marked"));
        game.joinGame(0);
        vm.stopPrank();
    }

    function test_maliciousJoinerCannotImmediatelyMove() public {
        MaliciousJoiner attacker = new MaliciousJoiner();
        EscrowManager gameEscrowManager = EscrowManager(game.i_escrowManager());

        // Fund attacker
        usdc.mint(address(attacker), STAKE);

        // Approve EscrowManager to spend attacker's USDC
        vm.startPrank(address(attacker));
        usdc.approve(address(gameEscrowManager), STAKE);
        vm.stopPrank();

        // Have attacker attempt join then immediate move
        bool moveFailed = attacker.attemptJoinThenImmediateMove(game, 2, 3);
        assertTrue(moveFailed, "Attacker unexpectedly made a move");

        // Game should be active and it's playerOne's turn
        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Active));
        assertEq(game.s_currentPlayer(), game.i_playerOne());
    }

    function test_factoryInvalidIdReturnsZeroAddress() public view {
        // id 0 was never used
        assertEq(factory.s_games(0), address(0));
        // id s_gameCount + 1 is also unused
        assertEq(factory.s_games(factory.s_gameCount() + 1), address(0));
    }

    function test_joinGameRequiresStakeApproval() public {
        EscrowManager gameEscrowManager = EscrowManager(game.i_escrowManager());

        vm.startPrank(walletTwo);
        // Don't approve - should fail with ERC20InsufficientAllowance when EscrowManager tries to transfer
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(gameEscrowManager), // spender
                0, // current allowance
                STAKE // needed
            )
        );

        game.joinGame(1);
        vm.stopPrank();
    }

    function test_joinGameRequiresMatchingStake() public {
        EscrowManager gameEscrowManager = EscrowManager(game.i_escrowManager());

        vm.startPrank(walletTwo);
        // Approve less than stake
        usdc.approve(address(gameEscrowManager), STAKE - 1);
        vm.expectRevert();
        game.joinGame(1);
        vm.stopPrank();
    }

    // Note: withdrawStake function no longer exists on SharksAndTigers contract
    // Withdrawals are now handled by EscrowManager: withdrawRefundableStake() and claimReward()
    // These tests are removed as they test functionality that has been moved to EscrowManager

    // Play clock vulnerability tests

    function test_makeMove_revertsWhenPlayClockExpired() public {
        // Join game
        vm.startPrank(walletTwo);
        EscrowManager gameEscrowManager = EscrowManager(game.i_escrowManager());
        usdc.approve(address(gameEscrowManager), STAKE);
        game.joinGame(1);
        vm.stopPrank();

        // Fast forward past play clock
        vm.warp(block.timestamp + PLAY_CLOCK + 1);

        // Player one tries to make move after clock expired
        vm.prank(walletOne);
        vm.expectRevert(bytes("You ran out of time to make a move"));
        game.makeMove(3);
    }

    function test_makeMove_allowsMoveExactlyAtPlayClock() public {
        // Join game
        vm.startPrank(walletTwo);
        EscrowManager gameEscrowManager = EscrowManager(game.i_escrowManager());
        usdc.approve(address(gameEscrowManager), STAKE);
        game.joinGame(1);
        vm.stopPrank();

        // Fast forward to exactly play clock (should still be valid)
        vm.warp(block.timestamp + PLAY_CLOCK);

        // Player one should be able to make move
        vm.prank(walletOne);
        game.makeMove(3);

        // Verify move was made
        assertEq(uint256(game.s_gameBoard(3)), uint256(SharksAndTigers.Mark.Shark));
    }

    function test_claimReward_revertsWhenCurrentPlayerTriesToClaimAfterExpiration() public {
        EscrowManager gameEscrowManager = EscrowManager(game.i_escrowManager());

        // Join game
        vm.startPrank(walletTwo);
        usdc.approve(address(gameEscrowManager), STAKE);
        game.joinGame(1);
        vm.stopPrank();

        // Fast forward past play clock
        vm.warp(block.timestamp + PLAY_CLOCK + 1);

        // Resolve timeout - this will finalize the game and set winner to playerTwo
        game.resolveTimeout();

        // Current player (player one) tries to claim - should revert (no claimable balance)
        vm.prank(walletOne);
        vm.expectRevert(EscrowManager.NothingToClaim.selector);
        gameEscrowManager.claimReward();
    }

    function test_claimReward_allowsNonCurrentPlayerToClaimAfterExpiration() public {
        EscrowManager gameEscrowManager = EscrowManager(game.i_escrowManager());

        // Join game
        vm.startPrank(walletTwo);
        usdc.approve(address(gameEscrowManager), STAKE);
        game.joinGame(1);
        vm.stopPrank();

        // Fast forward past play clock
        vm.warp(block.timestamp + PLAY_CLOCK + 1);

        // Resolve timeout - this will finalize the game and set winner to playerTwo
        game.resolveTimeout();

        // Non-current player is player two and should be able to claim the reward
        uint256 balanceBefore = usdc.balanceOf(walletTwo);
        vm.prank(walletTwo);
        gameEscrowManager.claimReward();

        // Verify reward was claimed
        assertEq(usdc.balanceOf(walletTwo), balanceBefore + STAKE * 2);
        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Ended));
        assertEq(game.s_winner(), walletTwo);
    }

    function test_claimReward_revertsWhenGameEndedNormallyButTimeAlsoExpired() public {
        EscrowManager gameEscrowManager = EscrowManager(game.i_escrowManager());

        // This tests that if game ends normally but time also expired,
        // non-winner cannot claim using expiration logic

        // Join game
        vm.startPrank(walletTwo);
        usdc.approve(address(gameEscrowManager), STAKE);
        game.joinGame(1);
        vm.stopPrank();

        // Play game to completion (player one wins)
        vm.prank(walletOne);
        game.makeMove(3);
        vm.prank(walletTwo);
        game.makeMove(5);
        vm.prank(walletOne);
        game.makeMove(6); // Player one wins

        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Ended));
        assertEq(game.s_winner(), walletOne);

        // Fast forward past play clock from last move
        vm.warp(block.timestamp + PLAY_CLOCK + 1);

        // Now player two (non-winner) tries to claim
        // This should revert because only winner has claimable balance
        vm.prank(walletTwo);
        vm.expectRevert(EscrowManager.NothingToClaim.selector);
        gameEscrowManager.claimReward();

        // Only the actual winner should be able to claim
        uint256 balanceBefore = usdc.balanceOf(walletOne);
        vm.prank(walletOne);
        gameEscrowManager.claimReward();
        assertEq(usdc.balanceOf(walletOne), balanceBefore + STAKE * 2);
    }

    function test_claimReward_revertsWhenNonPlayerTriesToClaimAfterExpiration() public {
        EscrowManager gameEscrowManager = EscrowManager(game.i_escrowManager());

        // Join game
        vm.startPrank(walletTwo);
        usdc.approve(address(gameEscrowManager), STAKE);
        game.joinGame(1);
        vm.stopPrank();

        // Fast forward past play clock
        vm.warp(block.timestamp + PLAY_CLOCK + 1);

        // Resolve timeout
        game.resolveTimeout();

        // Non-player tries to claim - should revert (no claimable balance)
        vm.prank(walletThree);
        vm.expectRevert(EscrowManager.NothingToClaim.selector);
        gameEscrowManager.claimReward();
    }

    function test_claimReward_revertsWhenRewardAlreadyClaimed() public {
        EscrowManager gameEscrowManager = EscrowManager(game.i_escrowManager());

        // Join game
        vm.startPrank(walletTwo);
        usdc.approve(address(gameEscrowManager), STAKE);
        game.joinGame(1);
        vm.stopPrank();

        // Play game to completion
        vm.prank(walletOne);
        game.makeMove(3);
        vm.prank(walletTwo);
        game.makeMove(5);
        vm.prank(walletOne);
        game.makeMove(6); // Player one wins

        // Winner claims reward
        vm.prank(walletOne);
        gameEscrowManager.claimReward();

        // Try to claim again - should revert
        vm.prank(walletOne);
        vm.expectRevert(EscrowManager.NothingToClaim.selector);
        gameEscrowManager.claimReward();
    }

    function test_makeMove_updatesLastPlayTimeCorrectly() public {
        // Join game
        vm.startPrank(walletTwo);
        EscrowManager gameEscrowManager = EscrowManager(game.i_escrowManager());
        usdc.approve(address(gameEscrowManager), STAKE);
        game.joinGame(1);
        vm.stopPrank();

        uint256 lastPlayTimeBefore = game.s_lastPlayTime();

        // Make a move
        vm.warp(block.timestamp + 100); // Advance time
        vm.prank(walletOne);
        game.makeMove(3);

        uint256 lastPlayTimeAfter = game.s_lastPlayTime();

        // Verify lastPlayTime was updated
        assertEq(lastPlayTimeAfter, block.timestamp);
        assertGt(lastPlayTimeAfter, lastPlayTimeBefore);
    }

    function test_playClock_edgeCase_veryLargePlayClock() public {
        // Test with very large play clock value
        uint256 largePlayClock = type(uint256).max / 2;

        vm.startPrank(walletOne);
        EscrowManager escrowManager = factory.i_escrowManager();
        usdc.approve(address(escrowManager), STAKE);
        factory.createGame(0, SharksAndTigers.Mark.Shark, largePlayClock, STAKE);
        vm.stopPrank();

        SharksAndTigers largeClockGame = SharksAndTigers(factory.s_games(factory.s_gameCount()));

        // Join game
        vm.startPrank(walletTwo);
        EscrowManager largeClockEscrowManager = EscrowManager(largeClockGame.i_escrowManager());
        usdc.approve(address(largeClockEscrowManager), STAKE);
        largeClockGame.joinGame(1);
        vm.stopPrank();

        // Even with very large clock, should work
        vm.prank(walletOne);
        largeClockGame.makeMove(3);

        assertEq(uint256(largeClockGame.s_gameBoard(3)), uint256(SharksAndTigers.Mark.Shark));
    }
}

