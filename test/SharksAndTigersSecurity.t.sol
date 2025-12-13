// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
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
}
