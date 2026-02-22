// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {SharksAndTigers} from "../../src/SharksAndTigers.sol";
import {DeploymentHelper} from "./lib/DeploymentHelper.s.sol";

/**
 * @title GetGameState
 * @notice Read-only script to print the latest game's state.
 * @dev Uses getGameInfo(). Run: make get-game-state
 */
contract GetGameState is DeploymentHelper {
    function run() external view {
        address gameAddress = _getLatestGameAddress();
        SharksAndTigers.Game memory gameInfo = SharksAndTigers(gameAddress).getGameInfo();

        _logGameState(gameAddress, gameInfo);
    }

    function _padDots(string memory label, uint256 totalWidth) internal pure returns (string memory) {
        uint256 len = bytes(label).length;
        if (len >= totalWidth) return label;
        bytes memory dots = new bytes(totalWidth - len);
        for (uint256 i = 0; i < totalWidth - len; i++) {
            dots[i] = ".";
        }
        return string.concat(label, " ", string(dots), " ");
    }

    function _spaces(uint256 n) internal pure returns (string memory) {
        bytes memory b = new bytes(n);
        for (uint256 i = 0; i < n; i++) {
            b[i] = " ";
        }
        return string(b);
    }

    function _logGameState(address gameAddress, SharksAndTigers.Game memory g) internal pure {
        uint256 labelWidth = 18;
        string memory leader = _padDots("gameAddress", labelWidth);
        console.log(string.concat(leader, vm.toString(gameAddress)));
        console.log(string.concat(_padDots("gameId", labelWidth), vm.toString(g.gameId)));
        console.log(string.concat(_padDots("stake", labelWidth), vm.toString(g.stake)));
        console.log(string.concat(_padDots("playClock", labelWidth), vm.toString(g.playClock)));
        console.log(string.concat(_padDots("lastPlayTime", labelWidth), vm.toString(g.lastPlayTime)));
        console.log(string.concat(_padDots("playerOne", labelWidth), vm.toString(g.playerOne)));
        console.log(string.concat(_padDots("playerTwo", labelWidth), vm.toString(g.playerTwo)));
        console.log(string.concat(_padDots("currentPlayer", labelWidth), vm.toString(g.currentPlayer)));
        console.log(string.concat(_padDots("winner", labelWidth), vm.toString(g.winner)));
        console.log(string.concat(_padDots("isDraw", labelWidth), g.isDraw ? "true" : "false"));
        console.log(string.concat(_padDots("gameState", labelWidth), _gameStateLabel(g.gameState)));
        console.log(string.concat(_padDots("playerOneMark", labelWidth), _markLabel(g.playerOneMark)));
        console.log(string.concat(_padDots("playerTwoMark", labelWidth), _markLabel(g.playerTwoMark)));
        console.log(string.concat(_padDots("escrowManager", labelWidth), vm.toString(g.escrowManager)));

        string memory row0 = string.concat(
            "| ", _cell(g.gameBoard[0]), " | ", _cell(g.gameBoard[1]), " | ", _cell(g.gameBoard[2]), " |"
        );
        string memory row1 = string.concat(
            "| ", _cell(g.gameBoard[3]), " | ", _cell(g.gameBoard[4]), " | ", _cell(g.gameBoard[5]), " |"
        );
        string memory row2 = string.concat(
            "| ", _cell(g.gameBoard[6]), " | ", _cell(g.gameBoard[7]), " | ", _cell(g.gameBoard[8]), " |"
        );
        uint256 indent = labelWidth + 2;
        console.log(string.concat(_padDots("board", labelWidth), row0));
        console.log(string.concat(_spaces(indent), row1));
        console.log(string.concat(_spaces(indent), row2));
    }

    function _gameStateLabel(SharksAndTigers.GameState s) internal pure returns (string memory) {
        if (s == SharksAndTigers.GameState.Open) return "Open";
        if (s == SharksAndTigers.GameState.Active) return "Active";
        return "Ended";
    }

    function _markLabel(SharksAndTigers.Mark m) internal pure returns (string memory) {
        if (m == SharksAndTigers.Mark.Empty) return "Empty";
        if (m == SharksAndTigers.Mark.Shark) return unicode"🦈";
        return unicode"🐅";
    }

    function _cell(SharksAndTigers.Mark m) internal pure returns (string memory) {
        if (m == SharksAndTigers.Mark.Empty) return "--";
        if (m == SharksAndTigers.Mark.Shark) return unicode"🦈";
        return unicode"🐅";
    }
}
