// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {SharksAndTigers} from "src/SharksAndTigers.sol";
import {SharksAndTigersFactory} from "src/SharksAndTigersFactory.sol";

contract SharksAndTigersFactoryTest is Test {
    SharksAndTigersFactory internal factory;
    address internal walletOne;
    address internal walletTwo;

    function setUp() public {
        factory = new SharksAndTigersFactory();
        walletOne = makeAddr("walletOne");
        walletTwo = makeAddr("walletTwo");
        vm.deal(walletOne, 100 ether);
        vm.deal(walletTwo, 100 ether);
    }

    function test_deploysSuccessfully() public {
        assertTrue(address(factory) != address(0));
    }

    function test_initialGameCountIsZero() public {
        uint256 count = factory.gameCount();
        assertEq(count, 0);
        assertEq(factory.getGameCount(), 0);
    }

    function test_createGame_revertsOnInvalidMark() public {
        vm.prank(walletOne);
        vm.expectRevert(bytes("Invalid mark for board"));

        // arg1 is position, arg2 is mark
        // 0 is Empty, and 1 is Shark, 2 is Tiger, so 0 is invalid
        factory.createGame(0, 0);
    }

    function test_createGame_revertsOnOutOfRangePosition() public {
        vm.prank(walletOne);
        vm.expectRevert(bytes("Position is out of range"));

        // arg1 is position, arg2 is mark
        // acceptable range is 0 - 8
        factory.createGame(9, 1);
    }

    function test_createGame_incrementsGameCountAndStoresMapping() public {
        vm.prank(walletOne);
        factory.createGame(0, 1);

        assertEq(factory.gameCount(), 1);

        address gameAddr = factory.getGameAddress(1);
        assertTrue(gameAddr != address(0));

        // Assert game is Open for joining
        SharksAndTigers game = SharksAndTigers(gameAddr);
        assertEq(uint256(game.gameState()), uint256(SharksAndTigers.GameState.Open));
    }

    function test_createGame_emitsEvent_andMappingSet() public {
        // Record logs then create game
        vm.recordLogs();
        vm.prank(walletOne);
        factory.createGame(0, 1);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 sig = keccak256("GameCreated(uint256,address,address,uint8,uint256)");

        bool found;
        for (uint256 i; i < entries.length; i++) {
            if (entries[i].emitter == address(factory) && entries[i].topics.length == 4 && entries[i].topics[0] == sig)
            {
                found = true;
                uint256 gameId = uint256(entries[i].topics[1]);
                address gameContract = address(uint160(uint256(entries[i].topics[2])));
                address playerOneAddr = address(uint160(uint256(entries[i].topics[3])));
                (uint8 playerOneMark, uint256 position) = abi.decode(entries[i].data, (uint8, uint256));

                assertEq(gameId, 1);
                assertEq(gameContract, factory.getGameAddress(gameId));
                assertEq(playerOneAddr, walletOne);
                assertEq(playerOneMark, uint8(SharksAndTigers.Mark.Shark));
                assertEq(position, 0);
                break;
            }
        }
        assertTrue(found, "GameCreated event not found");
    }
}
