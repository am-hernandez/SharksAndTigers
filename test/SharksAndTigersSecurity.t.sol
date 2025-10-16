// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {SharksAndTigersFactory} from "src/SharksAndTigersFactory.sol";
import {SharksAndTigers} from "src/SharksAndTigers.sol";

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
    address internal walletOne;
    address internal walletTwo;
    address internal walletThree;

    function setUp() public {
        factory = new SharksAndTigersFactory();
        walletOne = makeAddr("walletOne");
        walletTwo = makeAddr("walletTwo");
        walletThree = makeAddr("walletThree");

        vm.deal(walletOne, 100 ether);
        vm.deal(walletTwo, 100 ether);
        vm.deal(walletThree, 100 ether);

        vm.prank(walletOne);
        factory.createGame(0, 1); // Shark at pos 0
        game = SharksAndTigers(payable(factory.getGameAddress(factory.getGameCount())));
    }

    function test_playerOneCannotJoinAsPlayerTwo() public {
        vm.prank(walletOne);
        vm.expectRevert(bytes("Player one cannot join as player two"));
        game.joinGame(1);
    }

    function test_doubleJoinReverts() public {
        vm.prank(walletTwo);
        game.joinGame(1);

        vm.prank(walletThree);
        vm.expectRevert(bytes("Game is not open to joining"));
        game.joinGame(2);
    }

    function test_moveBeforeActiveReverts() public {
        vm.prank(walletTwo);
        vm.expectRevert(bytes("Game is not active"));
        game.makeMove(1);
    }

    function test_moveAfterEndedReverts() public {
        // Join and finish a quick win for playerOne: left column 0,3,6
        vm.prank(walletTwo);
        game.joinGame(2);
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
        vm.prank(walletTwo);
        vm.expectRevert(bytes("Position is already marked"));
        game.joinGame(0);
    }

    function test_maliciousJoinerCannotImmediatelyMove() public {
        MaliciousJoiner attacker = new MaliciousJoiner();
        // Have attacker attempt join then immediate move
        bool moveFailed = attacker.attemptJoinThenImmediateMove(game, 2, 3);
        assertTrue(moveFailed, "Attacker unexpectedly made a move");

        // Game should be active and it's playerOne's turn
        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Active));
        assertEq(game.s_currentPlayer(), game.s_playerOne());
    }

    function test_factoryInvalidIdReturnsZeroAddress() public view {
        // id 0 was never used
        assertEq(factory.getGameAddress(0), address(0));
        // id s_gameCount + 1 is also unused
        assertEq(factory.getGameAddress(factory.getGameCount() + 1), address(0));
    }
}
