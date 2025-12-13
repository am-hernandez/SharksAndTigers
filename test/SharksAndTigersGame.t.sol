// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {SharksAndTigersFactory} from "src/SharksAndTigersFactory.sol";
import {SharksAndTigers} from "src/SharksAndTigers.sol";
import "@openzeppelin/mocks/token/ERC20Mock.sol";

contract SharksAndTigersGameTest is Test {
    SharksAndTigersFactory internal factory;
    ERC20Mock internal usdc;
    address internal walletOne;
    address internal walletTwo;
    address internal walletThree;

    SharksAndTigers internal game1;
    SharksAndTigers internal game2;

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

        // game1: walletOne creates with mark Shark (1) at pos 0
        vm.startPrank(walletOne);
        usdc.approve(address(factory), WAGER);
        factory.createGame(0, 1, PLAY_CLOCK, WAGER);
        vm.stopPrank();
        game1 = SharksAndTigers(factory.getGameAddress(1));

        // game2: walletTwo creates with mark Tiger (2) at pos 5
        vm.startPrank(walletTwo);
        usdc.approve(address(factory), WAGER);
        factory.createGame(5, 2, PLAY_CLOCK, WAGER);
        vm.stopPrank();
        game2 = SharksAndTigers(factory.getGameAddress(2));
    }

    function test_initialContractState() public view {
        assertEq(game1.s_isDraw(), false);
        assertEq(game1.s_playerTwo(), address(0));

        // currentPlayer is 0 address because playerTwo has not joined yet
        assertEq(game1.s_currentPlayer(), address(0));
        assertEq(game1.s_winner(), address(0));
        assertEq(uint256(game1.s_gameState()), uint256(SharksAndTigers.GameState.Open));

        // playerOneMark is Shark because playerOne created game1 with mark Shark
        assertEq(uint256(game1.i_playerOneMark()), uint256(SharksAndTigers.Mark.Shark));

        // playerTwoMark is Tiger because playerOne created game1 with mark Shark
        assertEq(uint256(game1.i_playerTwoMark()), uint256(SharksAndTigers.Mark.Tiger));

        // gameBoard[0] is Shark because playerOne created game1 with mark Shark at pos 0
        assertEq(uint256(game1.s_gameBoard(0)), uint256(SharksAndTigers.Mark.Shark));

        // playerOneMark is Tiger because playerOne created game2 with mark Tiger
        assertEq(uint256(game2.i_playerOneMark()), uint256(SharksAndTigers.Mark.Tiger));

        // playerTwoMark is Shark because playerOne created game2 with mark Tiger
        assertEq(uint256(game2.i_playerTwoMark()), uint256(SharksAndTigers.Mark.Shark));

        // gameBoard[5] is Tiger because playerOne created game2 with mark Tiger at pos 5
        assertEq(uint256(game2.s_gameBoard(5)), uint256(SharksAndTigers.Mark.Tiger));
    }

    function test_joinGame_revertsWhenNotOpen() public {
        // walletThree joins, making game1 Active
        vm.startPrank(walletThree);
        usdc.approve(address(game1), WAGER);
        game1.joinGame(6);
        vm.stopPrank();

        // another join should revert because game1 is no longer open to joining
        vm.startPrank(walletTwo);
        usdc.approve(address(game1), WAGER);
        vm.expectRevert(bytes("Game is not open to joining"));
        game1.joinGame(7);
        vm.stopPrank();
    }

    function test_joinGame_revertsOnOutOfRange() public {
        // acceptable range is 0 - 8
        vm.startPrank(walletThree);
        usdc.approve(address(game1), WAGER);
        vm.expectRevert(bytes("Position is out of range"));
        game1.joinGame(9);
        vm.stopPrank();
    }

    function test_joinGame_revertsOnAlreadyMarked() public {
        // Position 0 is already marked because game1 was created with mark Shark at pos 0
        vm.startPrank(walletThree);
        usdc.approve(address(game1), WAGER);
        vm.expectRevert(bytes("Position is already marked"));
        game1.joinGame(0);
        vm.stopPrank();
    }

    function test_joinGame_setsStateAndEmitsEvent() public {
        // walletThree joins, making game1 Active
        vm.startPrank(walletThree);
        usdc.approve(address(game1), WAGER);
        vm.expectEmit(true, true, true, false, address(game1));
        emit SharksAndTigers.PlayerTwoJoined(
            1, address(game1), walletThree, SharksAndTigers.Mark.Tiger, 6, PLAY_CLOCK, WAGER
        );
        game1.joinGame(6);
        vm.stopPrank();

        assertEq(uint256(game1.s_gameState()), uint256(SharksAndTigers.GameState.Active));

        // playerTwo is walletThree because walletThree joined game1
        assertEq(game1.s_playerTwo(), walletThree);
        assertEq(uint256(game1.s_gameBoard(6)), uint256(SharksAndTigers.Mark.Tiger));

        // currentPlayer is game1.playerOne() because walletThree joined and made a move on game1
        assertEq(game1.s_currentPlayer(), game1.i_playerOne());
    }

    function _joinGame1Helper(address player, uint8 pos) internal {
        vm.startPrank(player);
        usdc.approve(address(game1), WAGER);
        game1.joinGame(pos);
        vm.stopPrank();
    }

    function test_makeMove_validations() public {
        _joinGame1Helper(walletThree, 2);

        // out of range
        vm.prank(walletThree);
        vm.expectRevert(bytes("Position is out of range"));
        game1.makeMove(9);

        // already marked
        vm.prank(walletThree);
        vm.expectRevert(bytes("Position is already marked"));
        game1.makeMove(2);

        // wrong state
        vm.prank(walletThree);
        vm.expectRevert(bytes("Game is not active"));
        game2.makeMove(3);

        // not current player
        vm.prank(walletThree);
        vm.expectRevert(bytes("You are not the current player"));
        game1.makeMove(3);
    }

    function test_makeMove_marksBoard_andSwitchesTurn_andEmits() public {
        _joinGame1Helper(walletThree, 2);

        address p1 = game1.i_playerOne();
        vm.prank(p1);
        vm.expectEmit(true, true, true, false, address(game1));
        emit SharksAndTigers.MoveMade(
            1, address(game1), p1, SharksAndTigers.Mark.Shark, 3, PLAY_CLOCK, block.timestamp, WAGER
        );
        game1.makeMove(3);
        assertEq(uint256(game1.s_gameBoard(3)), uint256(SharksAndTigers.Mark.Shark));
        assertEq(game1.s_currentPlayer(), game1.s_playerTwo());
    }

    /**
     *
     * Should recognize all 8 winning scenarios **
     *
     */
    function test_winScenario_leftColumn_setsWinner_andEndsGame_andEmits() public {
        /* Scenario #1
          | 🦈 | -- | 🐅 |
          | 🦈 | -- | 🐅 |
          | 🦈 | -- | -- |
        */
        _joinGame1Helper(walletTwo, 2);

        vm.prank(walletOne);
        game1.makeMove(3);
        vm.prank(walletTwo);
        game1.makeMove(5);

        address pOne = game1.i_playerOne();
        address pTwo = game1.s_playerTwo();
        vm.prank(walletOne);
        vm.expectEmit(true, true, false, false, address(game1));
        emit SharksAndTigers.GameEnded(
            1,
            address(game1),
            pOne,
            pTwo,
            SharksAndTigers.Mark.Shark,
            SharksAndTigers.Mark.Tiger,
            WAGER,
            PLAY_CLOCK,
            block.timestamp,
            false,
            walletOne,
            false
        );
        game1.makeMove(6);

        assertEq(game1.s_winner(), walletOne);
        assertEq(uint256(game1.s_gameState()), uint256(SharksAndTigers.GameState.Ended));
    }

    function test_winScenario_centerColumn_setsWinner_andEndsGame_andEmits() public {
        /* Scenario #2
          | -- | 🦈 | 🐅 |
          | -- | 🦈 | 🐅 |
          | -- | 🦈 | -- |
        */

        // Create a fresh game: start at pos 1 with Shark
        vm.startPrank(walletOne);
        usdc.approve(address(factory), WAGER);
        factory.createGame(1, 1, PLAY_CLOCK, WAGER);
        vm.stopPrank();
        SharksAndTigers game = SharksAndTigers(factory.getGameAddress(factory.s_gameCount()));

        // playerTwo joins at a safe position
        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
        game.joinGame(2);
        vm.stopPrank();

        // Sequence to complete column 1: positions 1,4,7 for playerOne
        vm.prank(walletOne);
        game.makeMove(4);
        vm.prank(walletTwo);
        game.makeMove(5);

        address pOne = game.i_playerOne();
        address pTwo = game.s_playerTwo();
        uint256 gid = game.i_gameId();
        vm.prank(walletOne);
        vm.expectEmit(true, true, false, false, address(game));
        emit SharksAndTigers.GameEnded(
            gid,
            address(game),
            pOne,
            pTwo,
            SharksAndTigers.Mark.Shark,
            SharksAndTigers.Mark.Tiger,
            WAGER,
            PLAY_CLOCK,
            block.timestamp,
            false,
            walletOne,
            false
        );
        game.makeMove(7);

        assertEq(game.s_winner(), walletOne);
        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Ended));
    }

    function test_winScenario_rightColumn_setsWinner_andEndsGame_andEmits() public {
        /* Scenario #3
          | 🐅 | -- | 🦈 |
          | 🐅 | -- | 🦈 |
          | -- | -- | 🦈 |
         */
        // Create a fresh game: start at pos 2 with Shark
        vm.startPrank(walletOne);
        usdc.approve(address(factory), WAGER);
        factory.createGame(2, 1, PLAY_CLOCK, WAGER);
        vm.stopPrank();
        SharksAndTigers game = SharksAndTigers(factory.getGameAddress(factory.s_gameCount()));

        // playerTwo joins
        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
        game.joinGame(0);
        vm.stopPrank();

        // Complete column 2: positions 2,5,8 for playerOne
        vm.prank(walletOne);
        game.makeMove(5);
        vm.prank(walletTwo);
        game.makeMove(3);

        address pOne = game.i_playerOne();
        address pTwo = game.s_playerTwo();
        uint256 gid = game.i_gameId();
        vm.prank(walletOne);
        vm.expectEmit(true, true, false, false, address(game));
        emit SharksAndTigers.GameEnded(
            gid,
            address(game),
            pOne,
            pTwo,
            SharksAndTigers.Mark.Shark,
            SharksAndTigers.Mark.Tiger,
            WAGER,
            PLAY_CLOCK,
            block.timestamp,
            false,
            walletOne,
            false
        );
        game.makeMove(8);

        assertEq(game.s_winner(), walletOne);
        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Ended));
    }

    function test_winScenario_topRow_setsWinner_andEndsGame_andEmits() public {
        /* Scenario #4
          | 🦈 | 🦈 | 🦈 |
          | -- | -- | -- |
          | 🐅 | 🐅 | -- |
        */

        // Create a fresh game: start at pos 0 with Shark
        vm.startPrank(walletOne);
        usdc.approve(address(factory), WAGER);
        factory.createGame(0, 1, PLAY_CLOCK, WAGER);
        vm.stopPrank();
        SharksAndTigers game = SharksAndTigers(factory.getGameAddress(factory.s_gameCount()));

        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
        game.joinGame(6);
        vm.stopPrank();

        vm.prank(walletOne);
        game.makeMove(1);
        vm.prank(walletTwo);
        game.makeMove(7);

        address pOne = game.i_playerOne();
        address pTwo = game.s_playerTwo();
        uint256 gid = game.i_gameId();
        vm.prank(walletOne);
        vm.expectEmit(true, true, false, false, address(game));
        emit SharksAndTigers.GameEnded(
            gid,
            address(game),
            pOne,
            pTwo,
            SharksAndTigers.Mark.Shark,
            SharksAndTigers.Mark.Tiger,
            WAGER,
            PLAY_CLOCK,
            block.timestamp,
            false,
            walletOne,
            false
        );
        game.makeMove(2);

        assertEq(game.s_winner(), walletOne);
        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Ended));
    }

    function test_winScenario_centerRow_setsWinner_andEndsGame_andEmits() public {
        /* Scenario #5
          | -- | -- | -- |
          | 🦈 | 🦈 | 🦈 |
          | 🐅 | 🐅 | -- |
        */

        // Create a fresh game: start at pos 3 with Shark
        vm.startPrank(walletOne);
        usdc.approve(address(factory), WAGER);
        factory.createGame(3, 1, PLAY_CLOCK, WAGER);
        vm.stopPrank();
        SharksAndTigers game = SharksAndTigers(factory.getGameAddress(factory.s_gameCount()));

        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
        game.joinGame(6);
        vm.stopPrank();

        vm.prank(walletOne);
        game.makeMove(4);
        vm.prank(walletTwo);
        game.makeMove(7);

        address pOne = game.i_playerOne();
        address pTwo = game.s_playerTwo();
        uint256 gid = game.i_gameId();
        vm.prank(walletOne);
        vm.expectEmit(true, true, false, false, address(game));
        emit SharksAndTigers.GameEnded(
            gid,
            address(game),
            pOne,
            pTwo,
            SharksAndTigers.Mark.Shark,
            SharksAndTigers.Mark.Tiger,
            WAGER,
            PLAY_CLOCK,
            block.timestamp,
            false,
            walletOne,
            false
        );
        game.makeMove(5);

        assertEq(game.s_winner(), walletOne);
        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Ended));
    }

    function test_winScenario_bottomRow_setsWinner_andEndsGame_andEmits() public {
        /* Scenario #6
          | 🐅 | 🐅 | -- |
          | -- | -- | -- |
          | 🦈 | 🦈 | 🦈 |
        */

        // Create a fresh game: start at pos 6 with Shark
        vm.startPrank(walletOne);
        usdc.approve(address(factory), WAGER);
        factory.createGame(6, 1, PLAY_CLOCK, WAGER);
        vm.stopPrank();
        SharksAndTigers game = SharksAndTigers(factory.getGameAddress(factory.s_gameCount()));

        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
        game.joinGame(0);
        vm.stopPrank();

        vm.prank(walletOne);
        game.makeMove(7);
        vm.prank(walletTwo);
        game.makeMove(1);

        address pOne = game.i_playerOne();
        address pTwo = game.s_playerTwo();
        uint256 gid = game.i_gameId();
        vm.prank(walletOne);
        vm.expectEmit(true, true, false, false, address(game));
        emit SharksAndTigers.GameEnded(
            gid,
            address(game),
            pOne,
            pTwo,
            SharksAndTigers.Mark.Shark,
            SharksAndTigers.Mark.Tiger,
            WAGER,
            PLAY_CLOCK,
            block.timestamp,
            false,
            walletOne,
            false
        );
        game.makeMove(8);

        assertEq(game.s_winner(), walletOne);
        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Ended));
    }

    function test_winScenario_mainDiagonal_setsWinner_andEndsGame_andEmits() public {
        /* Scenario #7
          | 🦈 | 🐅 | 🐅 |
          | -- | 🦈 | -- |
          | -- | -- | 🦈 |
        */

        // Main diagonal: 0,4,8 for playerOne
        vm.startPrank(walletOne);
        usdc.approve(address(factory), WAGER);
        factory.createGame(0, 1, PLAY_CLOCK, WAGER);
        vm.stopPrank();
        SharksAndTigers game = SharksAndTigers(factory.getGameAddress(factory.s_gameCount()));

        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
        game.joinGame(1);
        vm.stopPrank();

        vm.prank(walletOne);
        game.makeMove(4);
        vm.prank(walletTwo);
        game.makeMove(2);

        address pOne = game.i_playerOne();
        address pTwo = game.s_playerTwo();
        uint256 gid = game.i_gameId();
        vm.prank(walletOne);
        vm.expectEmit(true, true, false, false, address(game));
        emit SharksAndTigers.GameEnded(
            gid,
            address(game),
            pOne,
            pTwo,
            SharksAndTigers.Mark.Shark,
            SharksAndTigers.Mark.Tiger,
            WAGER,
            PLAY_CLOCK,
            block.timestamp,
            false,
            walletOne,
            false
        );
        game.makeMove(8);

        assertEq(game.s_winner(), walletOne);
        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Ended));
    }

    function test_winScenario_antiDiagonal_setsWinner_andEndsGame_andEmits() public {
        /* Scenario #8
          | 🐅 | 🐅 | 🦈 |
          | -- | 🦈 | -- |
          | 🦈 | -- | -- |
        */

        // Anti-diagonal: 2,4,6 for playerOne
        vm.startPrank(walletOne);
        usdc.approve(address(factory), WAGER);
        factory.createGame(2, 1, PLAY_CLOCK, WAGER);
        vm.stopPrank();
        SharksAndTigers game = SharksAndTigers(factory.getGameAddress(factory.s_gameCount()));

        vm.startPrank(walletTwo);
        usdc.approve(address(game), WAGER);
        game.joinGame(1);
        vm.stopPrank();

        vm.prank(walletOne);
        game.makeMove(4);
        vm.prank(walletTwo);
        game.makeMove(0);

        address pOne = game.i_playerOne();
        address pTwo = game.s_playerTwo();
        uint256 gid = game.i_gameId();
        vm.prank(walletOne);
        vm.expectEmit(true, true, false, false, address(game));
        emit SharksAndTigers.GameEnded(
            gid,
            address(game),
            pOne,
            pTwo,
            SharksAndTigers.Mark.Shark,
            SharksAndTigers.Mark.Tiger,
            WAGER,
            PLAY_CLOCK,
            block.timestamp,
            false,
            walletOne,
            false
        );
        game.makeMove(6);

        assertEq(game.s_winner(), walletOne);
        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Ended));
    }

    function test_draw_setsEnded_andEmits() public {
        /* Will complete the board as below:
          | 🦈 | 🐅 | 🐅 |
          | 🐅 | 🦈 | 🦈 |
          | 🦈 | 🦈 | 🐅 |
        */

        _joinGame1Helper(walletThree, 1);

        vm.prank(walletOne);
        game1.makeMove(4);
        vm.prank(walletThree);
        game1.makeMove(8);
        vm.prank(walletOne);
        game1.makeMove(5);
        vm.prank(walletThree);
        game1.makeMove(3);
        vm.prank(walletOne);
        game1.makeMove(7);
        vm.prank(walletThree);
        game1.makeMove(2);

        address plOne = game1.i_playerOne();
        address plTwo = game1.s_playerTwo();
        vm.prank(walletOne);
        vm.expectEmit(true, true, false, false, address(game1));
        emit SharksAndTigers.GameEnded(
            1,
            address(game1),
            plOne,
            plTwo,
            SharksAndTigers.Mark.Shark,
            SharksAndTigers.Mark.Tiger,
            WAGER,
            PLAY_CLOCK,
            block.timestamp,
            false,
            address(0),
            true
        );
        game1.makeMove(6);

        assertEq(uint256(game1.s_gameState()), uint256(SharksAndTigers.GameState.Ended));
        assertEq(game1.s_isDraw(), true);
        assertEq(game1.s_winner(), address(0));
    }

    function test_getGameInfo_returnsAccurateData() public {
        // join then make one move to set lastPlayTime
        vm.startPrank(walletThree);
        usdc.approve(address(game1), WAGER);
        game1.joinGame(1);
        vm.stopPrank();
        vm.prank(walletOne);
        game1.makeMove(2);

        SharksAndTigers.Game memory info = game1.getGameInfo();
        assertEq(info.gameId, 1);
        assertEq(info.lastPlayTime, game1.s_lastPlayTime());
        assertEq(info.playerOne, game1.i_playerOne());
        assertEq(info.playerTwo, game1.s_playerTwo());
        assertEq(info.currentPlayer, game1.s_currentPlayer());
        assertEq(info.winner, game1.s_winner());
        assertEq(info.isDraw, false);
        assertEq(uint256(info.gameState), uint256(SharksAndTigers.GameState.Active));
        assertEq(uint256(info.playerOneMark), uint256(game1.i_playerOneMark()));
        assertEq(uint256(info.playerTwoMark), uint256(game1.i_playerTwoMark()));
        for (uint256 i; i < 9; i++) {
            assertEq(uint256(info.gameBoard[i]), uint256(game1.s_gameBoard(i)));
        }
    }
}
