// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SharksAndTigersFactory} from "src/SharksAndTigersFactory.sol";
import {SharksAndTigers} from "src/SharksAndTigers.sol";
import "@openzeppelin/mocks/token/ERC20Mock.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

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

    uint256 internal constant WAGER = 100e6; // 100 USDC (6 decimals)
    uint256 internal constant PLAY_CLOCK = 3600; // 1 hour

    function setUp() public {
        // Deploy mock USDC token
        usdc = new ERC20Mock();

        // Deploy factory with USDC token address
        factory = new SharksAndTigersFactory(address(usdc));

        walletOne = makeAddr("walletOne");
        walletTwo = makeAddr("walletTwo");
        walletThree = makeAddr("walletThree");

        // Mint USDC to wallets
        usdc.mint(walletOne, 1000e6);
        usdc.mint(walletTwo, 1000e6);
        usdc.mint(walletThree, 1000e6);

        // Create game: player one approves USDC to factory and creates game
        vm.startPrank(walletOne);
        usdc.approve(address(factory), WAGER);
        factory.createGame(0, 1, PLAY_CLOCK, WAGER); // Shark at pos 0
        vm.stopPrank();

        game = SharksAndTigers(factory.getGameAddress(factory.s_gameCount()));
    }

    function test_playerOneCannotJoinAsPlayerTwo() public {
        vm.startPrank(walletOne);
        usdc.approve(address(game), WAGER);
        vm.expectRevert(bytes("Player one cannot join as player two"));
        game.joinGame(1);
        vm.stopPrank();
    }

    function test_doubleJoinReverts() public {
        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
        game.joinGame(1);
        vm.stopPrank();

        vm.startPrank(walletThree);
        usdc.approve(address(game), WAGER);
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
        usdc.approve(address(game), WAGER);
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
        usdc.approve(address(game), WAGER);
        vm.expectRevert(bytes("Position is already marked"));
        game.joinGame(0);
        vm.stopPrank();
    }

    function test_maliciousJoinerCannotImmediatelyMove() public {
        MaliciousJoiner attacker = new MaliciousJoiner();

        // Fund attacker and approve
        usdc.mint(address(attacker), WAGER);
        vm.prank(address(attacker));
        usdc.approve(address(game), WAGER);

        // Have attacker attempt join then immediate move
        bool moveFailed = attacker.attemptJoinThenImmediateMove(game, 2, 3);
        assertTrue(moveFailed, "Attacker unexpectedly made a move");

        // Game should be active and it's playerOne's turn
        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Active));
        assertEq(game.s_currentPlayer(), game.i_playerOne());
    }

    function test_factoryInvalidIdReturnsZeroAddress() public view {
        // id 0 was never used
        assertEq(factory.getGameAddress(0), address(0));
        // id s_gameCount + 1 is also unused
        assertEq(factory.getGameAddress(factory.s_gameCount() + 1), address(0));
    }

    function test_joinGameRequiresWagerApproval() public {
        vm.startPrank(walletTwo);
        // Don't approve - should fail
        vm.expectRevert(
            bytes("Insufficient USDC allowance. Please approve the game contract to spend the wager amount.")
        );
        game.joinGame(1);
        vm.stopPrank();
    }

    function test_joinGameRequiresMatchingWager() public {
        vm.startPrank(walletTwo);
        // Approve less than wager
        usdc.approve(address(game), WAGER - 1);
        vm.expectRevert(
            bytes("Insufficient USDC allowance. Please approve the game contract to spend the wager amount.")
        );
        game.joinGame(1);
        vm.stopPrank();
    }

    function test_withdrawWager_revertsWhenGameIsOpenButNotCreator() public {
        // Game is open, but walletTwo did not create it
        vm.prank(walletTwo);
        vm.expectRevert(bytes("You are not a player in this game"));
        game.withdrawWager();
    }

    function test_withdrawWager_revertsWhenGameIsActiveAndPlayerTwo() public {
        // Join game as player two
        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
        game.joinGame(1);
        vm.stopPrank();

        // Game is now active, player two tries to withdraw
        vm.prank(walletTwo);
        vm.expectRevert(bytes("Cannot withdraw wager while game is active"));
        game.withdrawWager();
    }

    function test_withdrawWager_revertsWhenGameIsActiveAndNotAPlayer() public {
        // Join game as player two
        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
        game.joinGame(1);
        vm.stopPrank();

        // Game is now active, walletThree (not a player) tries to withdraw
        vm.prank(walletThree);
        vm.expectRevert(bytes("You are not a player in this game"));
        game.withdrawWager();
    }

    function test_withdrawWager_revertsWhenGameIsDrawButNotAPlayer() public {
        // Join game and play to a draw
        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
        game.joinGame(1);
        vm.stopPrank();

        // Play to a draw
        vm.prank(walletOne);
        game.makeMove(4);
        vm.prank(walletTwo);
        game.makeMove(8);
        vm.prank(walletOne);
        game.makeMove(5);
        vm.prank(walletTwo);
        game.makeMove(3);
        vm.prank(walletOne);
        game.makeMove(7);
        vm.prank(walletTwo);
        game.makeMove(2);
        vm.prank(walletOne);
        game.makeMove(6); // Draw

        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Ended));
        assertEq(game.s_isDraw(), true);

        // walletThree (not a player) tries to withdraw
        vm.prank(walletThree);
        vm.expectRevert(bytes("You are not a player in this game"));
        game.withdrawWager();
    }

    // Play clock vulnerability tests

    function test_makeMove_revertsWhenPlayClockExpired() public {
        // Join game
        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
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
        usdc.approve(address(game), WAGER);
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
        // Join game
        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
        game.joinGame(1);
        vm.stopPrank();

        // Fast forward past play clock
        vm.warp(block.timestamp + PLAY_CLOCK + 1);

        // Current player (player one) tries to claim - should revert
        vm.prank(walletOne);
        vm.expectRevert(bytes("Only the winner can claim the reward"));
        game.claimReward();
    }

    function test_claimReward_allowsNonCurrentPlayerToClaimAfterExpiration() public {
        // Join game
        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
        game.joinGame(1);
        vm.stopPrank();

        // Fast forward past play clock
        vm.warp(block.timestamp + PLAY_CLOCK + 1);

        // Non-current player is player two and should be able to claim the reward
        uint256 balanceBefore = usdc.balanceOf(walletTwo);
        vm.prank(walletTwo);
        game.claimReward();

        // Verify reward was claimed
        assertEq(usdc.balanceOf(walletTwo), balanceBefore + WAGER * 2);
        assertEq(game.s_isRewardClaimed(), true);
        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Ended));
        assertEq(game.s_winner(), walletTwo);
    }

    function test_claimReward_revertsWhenGameEndedNormallyButTimeAlsoExpired() public {
        // This tests that if game ends normally but time also expired,
        // non-winner cannot claim using expiration logic

        // Join game
        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
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

        // Now player two (non-winner) tries to claim using expiration logic
        // This should revert because game already ended normally
        vm.prank(walletTwo);
        vm.expectRevert(bytes("Only the winner can claim the reward"));
        game.claimReward();

        // Only the actual winner should be able to claim
        uint256 balanceBefore = usdc.balanceOf(walletOne);
        vm.prank(walletOne);
        game.claimReward();
        assertEq(usdc.balanceOf(walletOne), balanceBefore + WAGER * 2);
    }

    function test_claimReward_revertsWhenNonPlayerTriesToClaimAfterExpiration() public {
        // Join game
        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
        game.joinGame(1);
        vm.stopPrank();

        // Fast forward past play clock
        vm.warp(block.timestamp + PLAY_CLOCK + 1);

        // Non-player tries to claim - should revert (no balance to transfer)
        vm.prank(walletThree);
        // This will fail when trying to transfer balance, but let's see the exact error
        vm.expectRevert();
        game.claimReward();
    }

    function test_claimReward_revertsWhenRewardAlreadyClaimed() public {
        // Join game
        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
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
        game.claimReward();

        // Try to claim again - should revert
        vm.prank(walletOne);
        vm.expectRevert(bytes("Reward already claimed"));
        game.claimReward();
    }

    function test_makeMove_updatesLastPlayTimeCorrectly() public {
        // Join game
        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
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
        usdc.approve(address(factory), WAGER);
        factory.createGame(0, 1, largePlayClock, WAGER);
        vm.stopPrank();

        SharksAndTigers largeClockGame = SharksAndTigers(factory.getGameAddress(factory.s_gameCount()));

        // Join game
        vm.startPrank(walletTwo);
        usdc.approve(address(largeClockGame), WAGER);
        largeClockGame.joinGame(1);
        vm.stopPrank();

        // Even with very large clock, should work
        vm.prank(walletOne);
        largeClockGame.makeMove(3);

        assertEq(uint256(largeClockGame.s_gameBoard(3)), uint256(SharksAndTigers.Mark.Shark));
    }
}

