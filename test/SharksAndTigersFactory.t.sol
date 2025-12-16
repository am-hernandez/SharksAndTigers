// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC20Mock} from "@openzeppelin/mocks/token/ERC20Mock.sol";
import {SharksAndTigers} from "src/SharksAndTigers.sol";
import {SharksAndTigersFactory} from "src/SharksAndTigersFactory.sol";

contract SharksAndTigersFactoryTest is Test {
    SharksAndTigersFactory internal factory;
    ERC20Mock internal usdc;
    address internal walletOne;
    address internal walletTwo;

    uint256 internal constant WAGER = 100e6; // 100 USDC (6 decimals)
    uint256 internal constant PLAY_CLOCK = 3600; // 1 hour

    function setUp() public {
        // Deploy mock USDC token
        usdc = new ERC20Mock();

        // Deploy factory with USDC token address
        factory = new SharksAndTigersFactory(address(usdc));

        walletOne = makeAddr("walletOne");
        walletTwo = makeAddr("walletTwo");

        // Mint USDC to wallets
        usdc.mint(walletOne, 1000e6);
        usdc.mint(walletTwo, 1000e6);
    }

    function test_deploysSuccessfully() public view {
        assertTrue(address(factory) != address(0));
    }

    function test_initialGameCountIsZero() public view {
        uint256 count = factory.s_gameCount();
        assertEq(count, 0);
        assertEq(factory.getGameCount(), 0);
    }

    function test_createGame_revertsOnInvalidMark() public {
        vm.startPrank(walletOne);
        usdc.approve(address(factory), WAGER);
        vm.expectRevert(bytes("Invalid mark for board"));

        // arg1 is position, arg2 is mark, arg3 is playClock, arg4 is wager
        // 0 is Empty, and 1 is Shark, 2 is Tiger, so 0 is invalid
        factory.createGame(0, 0, PLAY_CLOCK, WAGER);
        vm.stopPrank();
    }

    function test_createGame_revertsOnOutOfRangePosition() public {
        vm.startPrank(walletOne);
        usdc.approve(address(factory), WAGER);
        vm.expectRevert(bytes("Position is out of range"));

        // arg1 is position, arg2 is mark, arg3 is playClock, arg4 is wager
        // acceptable range is 0 - 8
        factory.createGame(9, 1, PLAY_CLOCK, WAGER);
        vm.stopPrank();
    }

    function test_createGame_incrementsGameCountAndStoresMapping() public {
        vm.startPrank(walletOne);
        usdc.approve(address(factory), WAGER);
        factory.createGame(0, 1, PLAY_CLOCK, WAGER);
        vm.stopPrank();

        assertEq(factory.s_gameCount(), 1);

        address gameAddr = factory.getGameAddress(1);
        assertTrue(gameAddr != address(0));

        // Assert game is Open for joining
        SharksAndTigers game = SharksAndTigers(gameAddr);
        assertEq(uint256(game.s_gameState()), uint256(SharksAndTigers.GameState.Open));
    }

    function test_createGame_emitsEvent_andMappingSet() public {
        // Record logs then create game
        vm.recordLogs();
        vm.startPrank(walletOne);
        usdc.approve(address(factory), WAGER);
        factory.createGame(0, 1, PLAY_CLOCK, WAGER);
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 sig = keccak256("GameCreated(uint256,address,address,uint8,uint256,uint256,uint256)");

        bool found;
        for (uint256 i; i < entries.length; i++) {
            if (entries[i].emitter == address(factory) && entries[i].topics.length == 4 && entries[i].topics[0] == sig)
            {
                found = true;
                uint256 gameId = uint256(entries[i].topics[1]);
                address gameContract = address(uint160(uint256(entries[i].topics[2])));
                address playerOneAddr = address(uint160(uint256(entries[i].topics[3])));
                (uint8 playerOneMark, uint256 position, uint256 playClock, uint256 wager) =
                    abi.decode(entries[i].data, (uint8, uint256, uint256, uint256));

                assertEq(gameId, 1);
                assertEq(gameContract, factory.getGameAddress(gameId));
                assertEq(playerOneAddr, walletOne);
                assertEq(playerOneMark, uint8(SharksAndTigers.Mark.Shark));
                assertEq(position, 0);
                assertEq(playClock, PLAY_CLOCK);
                assertEq(wager, WAGER);
                break;
            }
        }
        assertTrue(found, "GameCreated event not found");
    }
}
