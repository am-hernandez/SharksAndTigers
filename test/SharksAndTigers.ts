import { expect } from "chai";
import { ethers } from "hardhat";
import { ContractRunner, Signer } from "ethers";
import { SharksAndTigers, SharksAndTigersFactory } from "../typechain-types";

describe("🦈 & 🐅", function () {
  let sharksAndTigersFactory: SharksAndTigersFactory;
  let owner: ContractRunner | null | undefined;
  let walletOne: Signer;
  let walletTwo: Signer;
  let walletThree: Signer;

  beforeEach("before each test", async function (){
    [owner, walletOne, walletTwo, walletThree] = await ethers.getSigners();

    const factory = await ethers.getContractFactory("SharksAndTigersFactory");
    sharksAndTigersFactory = (await factory.deploy()) as SharksAndTigersFactory;
  });

  describe("SharksAndTigersFactory", function () {
    describe("contract", function () {
      it("should deploy successfully", async function () {
        const factoryAddress = await sharksAndTigersFactory.getAddress();
        expect(factoryAddress).to.be.properAddress;
      });
  
      it("should initialize with a gameCount of 0", async function () {
        const gameCount = await sharksAndTigersFactory.gameCount();
        
        expect(gameCount).to.be.equal(0);
      });
    });

    describe("createGame", function () {
      it("should revert when passed an invalid mark", async function () {
        const revertErrorMessage = "Invalid mark for board";

        await expect(sharksAndTigersFactory.connect(walletOne).createGame(0, 0, 10, {
          value: ethers.parseEther("1.0")
        })).to.be.revertedWith(revertErrorMessage);
      });

      it("should revert if wager not provided", async function () {
        const revertErrorMessage = "Game creation requires a wager";

        await expect(sharksAndTigersFactory.connect(walletOne).createGame(0, 1, 10, {
          value: ethers.parseEther("0")
        })).to.be.revertedWith(revertErrorMessage);
      });

      it("should revert if the position is out of range", async function () {
        const revertErrorMessage = "Position is out of range";

        // acceptable range is 0 - 8
        await expect(sharksAndTigersFactory.connect(walletOne).createGame(9, 1, 10, {
          value: ethers.parseEther("1.0")
        })).to.be.revertedWith(revertErrorMessage);
      });

      it("should revert when play clock value not greater than 0", async function () {
        const revertErrorMessage = "Must set a play clock value";

        await expect(sharksAndTigersFactory.connect(walletOne).createGame(0, 1, 0, {
          value: ethers.parseEther("1.0")
        })).to.be.revertedWith(revertErrorMessage);
      });

      it("should create a SharksAndTigers game when proper arguments and wager passed", async function () {
        const newGame = await sharksAndTigersFactory.connect(walletOne).createGame(0, 1, 10, {
          value: ethers.parseEther("1.0"),
        });

        const rec = await newGame.wait();
        // @ts-ignore
        const log = rec?.logs[0].args["gameContract"];

        expect(log).to.be.properAddress;
      });

      it("should increase gameCount by 1", async function () {
        // checks gameCount before creating new game
        const gameCountBefore = await sharksAndTigersFactory.gameCount();

        const newGame = await sharksAndTigersFactory.connect(walletOne).createGame(0, 1, 10, {
          value: ethers.parseEther("1.0"),
        });

        // checks gameCount after creating new game
        const gameCountAfter = await sharksAndTigersFactory.gameCount();
      
        expect(Number(gameCountAfter - gameCountBefore)).to.be.equal(1);
      });

      it("should emit GameCreated event with player and game contract address, play clock, and game count", async function () {
        const walletOneAddr = await walletOne.getAddress();

        const gameCreationResponse = await sharksAndTigersFactory.connect(walletOne).createGame(0, 1, 10, {
          value: ethers.parseEther("1.0"),
        });

        const gameCreationReceipt = await gameCreationResponse.wait();
        // @ts-ignore
        const [playerOneAddress, gameContractAddress, playClock, gameIdNumber] = gameCreationReceipt?.logs[0].args;

        await expect(gameCreationReceipt).to.emit(sharksAndTigersFactory, "GameCreated").withArgs(playerOneAddress, gameContractAddress, playClock, gameIdNumber);
      });
    });
  });

  describe("SharksAndTigers", function () {
    let game1: SharksAndTigers;
    let game2: SharksAndTigers;

    beforeEach("before each test", async function (){
      /* Create GAME 1 */
      const game1Res = await sharksAndTigersFactory.connect(walletOne).createGame(0, 1, 10, {
        value: ethers.parseEther("1.0"),
      });
      const game1Rec = await game1Res.wait();

      // @ts-ignore
      const [, gameContract1,] = game1Rec?.logs[0].args;
      game1 = await ethers.getContractAt("SharksAndTigers", gameContract1);

      /* Create Game 2 */
      const game2Res = await sharksAndTigersFactory.connect(walletTwo).createGame(5, 2, 10, {
        value: ethers.parseEther("0.5"),
      });
      const game2Rec = await game2Res.wait();

      // @ts-ignore
      const [, gameContract2,] = game2Rec?.logs[0].args;
      game2 = await ethers.getContractAt("SharksAndTigers", gameContract2);
    });

    describe("contract", function(){
      it("should initialize with isDraw as bool false", async function(){
        const game1IsDraw = await game1.isDraw();
        
        expect(game1IsDraw).to.be.equal(false);
      })

      it("should initialize with isRewardClaimed as bool false", async function(){
        const IsRewardClaimedGame1 = await game1.isRewardClaimed();
        
        expect(IsRewardClaimedGame1).to.equal(false);

        const IsRewardClaimedGame2 = await game2.isRewardClaimed();
        
        expect(IsRewardClaimedGame2).to.equal(false);
      })
      
      it("should initialize with playerTwo as 0 address", async function(){
        const playerTwoGame1 = await game1.playerTwo();
        
        expect(playerTwoGame1).to.equal(ethers.ZeroAddress);

        const playerTwoGame2 = await game2.playerTwo();
        
        expect(playerTwoGame2).to.equal(ethers.ZeroAddress);
      })

      it("should initialize with currentPlayer as 0 address", async function(){
        const currentPlayerGame1 = await game1.currentPlayer();
        
        expect(currentPlayerGame1).to.equal(ethers.ZeroAddress);

        const currentPlayerGame2 = await game2.currentPlayer();
        
        expect(currentPlayerGame2).to.equal(ethers.ZeroAddress);
      })
      
      it("should initialize with winner as 0 address", async function(){
        const winnerGame1 = await game1.winner();
        
        expect(winnerGame1).to.equal(ethers.ZeroAddress);

        const winnerGame2 = await game2.winner();
        
        expect(winnerGame2).to.equal(ethers.ZeroAddress);
      })
      
      it("should set contract wager", async function(){
        // Before each test the two game contracts are deployed with the following wagers:
        // - game1: 1 ETH
        // - game2: 0.5 ETH

        const wagerGame1 = await game1.wager();
        const wagerGame2 = await game2.wager();
        
        expect(wagerGame1.toString()).to.equal("1000000000000000000");
        expect(wagerGame2.toString()).to.equal("500000000000000000");
      })

      it("should assign game creator as playerOne", async function(){
        // Before each test the two game contracts are deployed with the following players:
        // - game1: walletOne
        // - game2: walletTwo

        const playerOneGame1 = await game1.playerOne();
        const playerOneGame2 = await game2.playerOne();
        
        expect(playerOneGame1.toString()).to.equal(await walletOne.getAddress());
        expect(playerOneGame2.toString()).to.equal(await walletTwo.getAddress());
      })

      it("should set gameState to Open", async function(){
        /*
          GameState public gameState;

          enum GameState {
            Open,    // 0
            Active,  // 1
            Ended    // 2
          }
        */

        const gameStateGame1 = await game1.gameState();
        const gameStateGame2 = await game2.gameState();

        expect(gameStateGame1.toString()).to.equal("0");
        expect(gameStateGame2.toString()).to.equal("0");
      })

      it("should set playerOneMark to the given mark", async function(){
        /*
          Mark public playerOneMark;

          enum Mark {
            Empty,  // 0
            Shark,  // 1
            Tiger   // 2
          }
        */

        const playerOneMarkGame1 = await game1.playerOneMark();
        const playerOneMarkGame2 = await game2.playerOneMark();

        expect(playerOneMarkGame1.toString()).to.not.equal("0");
        expect(playerOneMarkGame2.toString()).to.not.equal("0");

        expect(playerOneMarkGame1.toString()).to.equal("1");
        expect(playerOneMarkGame2.toString()).to.equal("2");
      })
      
      it("should set playerTwoMark opposite to playerOneMark", async function(){
        /*
          Mark public playerTwoMark;

          enum Mark {
            Empty,  // 0
            Shark,  // 1
            Tiger   // 2
          }
        */

        const playerTwoMarkGame1 = await game1.playerTwoMark();
        const playerTwoMarkGame2 = await game2.playerTwoMark();

        expect(playerTwoMarkGame1.toString()).to.not.equal("0");
        expect(playerTwoMarkGame2.toString()).to.not.equal("0");

        expect(playerTwoMarkGame1.toString()).to.equal("2");
        expect(playerTwoMarkGame2.toString()).to.equal("1");
      })
      
      it("should apply playerOneMark to the given board position", async function(){
        /*
          Mark[9] public gameBoard;

          Starting state for games:
          - game1:
            - position: 0
            - playerOneMark: 1
          - game2:
            - position: 5
            - playerOneMark: 2

        */

        const markOnPositionGame1 = await game1.gameBoard(0);
        const markOnPositionGame2 = await game2.gameBoard(5);

        expect(markOnPositionGame1.toString()).to.not.equal("0");
        expect(markOnPositionGame2.toString()).to.not.equal("0");

        expect(markOnPositionGame1.toString()).to.equal("1");
        expect(markOnPositionGame2.toString()).to.equal("2");
      })
      
      it("should add playerOne's wager to contract balances mapping", async function(){
        /*
          mapping(address => uint256) balances;

          Starting state for games:
          - game1:
            - wager: 1.0 ETH
          - game2:
            - wager: 0.5 ETH
        */

        const walletOneAddr = await walletOne.getAddress();
        const walletTwoAddr = await walletTwo.getAddress();

        const playerOnesBalanceGame1 = await game1.balances(walletOneAddr);
        const playerOnesBalanceGame2 = await game2.balances(walletTwoAddr);

        expect(playerOnesBalanceGame1.toString()).to.equal("1000000000000000000");
        expect(playerOnesBalanceGame2.toString()).to.equal("500000000000000000");
      })

      it("should increase contract value by wager amount", async function(){
        /*
          mapping(address => uint256) balances;

          Expected contract values for games:
          - game1:
            - value: 1.0 ETH
          - game2:
            - value: 0.5 ETH
        */

        const contractBalanceGame1 = await ethers.provider.getBalance(game1);
        const contractBalanceGame2 = await ethers.provider.getBalance(game2);

        expect(contractBalanceGame1.toString()).to.equal("1000000000000000000");
        expect(contractBalanceGame2.toString()).to.equal("500000000000000000");
      })
    })

    describe("joinGame", function(){
      it("should revert if game is not Open", async function(){
        /*
          GameState public gameState;

          enum GameState {
            Open,
            Active,
            Ended
          }
        */

        const revertErrorMessage = "Game is not open to joining";
       
        // make walletTwo join game1 so that its gameState is no longer Open
        await game1.connect(walletTwo).joinGame(6, {
          value: ethers.parseEther("1.0")
        })
       
        // attempt to join game1 as walletThree
        await expect(game1.connect(walletThree).joinGame(7, {
          value: ethers.parseEther("1.0")
        })).to.be.revertedWith(revertErrorMessage);
      })

      it("should revert if playerTwo's wager doesn't match contract wager", async function(){
        const revertErrorMessage = "Incorrect wager amount";
       
        // game1 wager is 1.0 ETH
        await expect(game1.connect(walletThree).joinGame(7, {
          value: ethers.parseEther("2.0")
        })).to.be.revertedWith(revertErrorMessage);
      })

      it("should revert if move position is out of range", async function(){
        const revertErrorMessage = "Position is out of range";
       
        await expect(game1.connect(walletThree).joinGame(9, {
          value: ethers.parseEther("1.0")
        })).to.be.revertedWith(revertErrorMessage);
      })

      it("should revert if move position is already marked", async function(){
        const revertErrorMessage = "Position is already marked";
       
        await expect(game1.connect(walletThree).joinGame(0, {
          value: ethers.parseEther("1.0")
        })).to.be.revertedWith(revertErrorMessage);
      })

      it("should set gameState to Active", async function(){
        /*
          GameState public gameState;

          enum GameState {
            Open,    // 0
            Active,  // 1
            Ended    // 2
          }
        */

        await game1.connect(walletThree).joinGame(6, {
          value: ethers.parseEther("1.0")
        })

        const gameStateGame1 = await game1.gameState();

        expect(gameStateGame1.toString()).to.equal("1");
      })
      
      it("should set playerTwo", async function(){
        await game1.connect(walletThree).joinGame(6, {
          value: ethers.parseEther("1.0")
        })

        const walletThreeAddr = await walletThree.getAddress();

        const playerTwoGame1 = await game1.playerTwo();

        expect(playerTwoGame1).to.equal(walletThreeAddr);
      })
      
      it("should set playerTwoMark on gameBoard in given position", async function(){
        /*
          Mark[9] public gameBoard;

          Starting state for game1:
          - playerOneMark: 1
          - playerTwoMark: 2
        */

        await game1.connect(walletThree).joinGame(6, {
          value: ethers.parseEther("1.0")
        })

        const markOnPositionGame1 = await game1.gameBoard(6);

        expect(markOnPositionGame1.toString()).to.not.equal("0");

        expect(markOnPositionGame1.toString()).to.equal("2");
      })
      
      it("should set currentPlayer to playerOne", async function(){
        /*
          - game1 is started by walletOne
          - before playerTwo joins game the currentPlayer is 0 address
          - after playerTwo joins the currentPlayer is playerOne (walletOne)
        */

        await game1.connect(walletThree).joinGame(6, {
          value: ethers.parseEther("1.0")
        })

        const walletOneAddr = await walletOne.getAddress();

        const currentPlayerGame1 = await game1.currentPlayer();

        expect(currentPlayerGame1).to.not.equal(ethers.ZeroAddress);

        expect(currentPlayerGame1).to.equal(walletOneAddr);
      })
      
      it("should emit PlayerTwoJoined event", async function(){
        const game1Address = await game1.getAddress();
        const walletThreeAddr = await walletThree.getAddress();

        await expect(game1.connect(walletThree).joinGame(6, {
          value: ethers.parseEther("1.0"),
        })).to.emit(game1, "PlayerTwoJoined").withArgs(game1Address, walletThreeAddr, 6);
      })
      
      it("should add playerTwo's wager to balances mapping", async function(){
        await game1.connect(walletThree).joinGame(6, {
          value: ethers.parseEther("1.0"),
        });

        const walletThreeAddr = await walletThree.getAddress();
        const playerTwosBalanceGame1 = await game1.balances(walletThreeAddr);

        expect(playerTwosBalanceGame1.toString()).to.equal("1000000000000000000");
      })

      it("should increase contract value by wager amount", async function(){
        /*
          mapping(address => uint256) balances;

          Expected contract values for game1:
          - playerOne: 1.0 ETH
          - playerTwo: 1.0 ETH
          - total: 2.0 ETH
        */
       
        await game1.connect(walletThree).joinGame(6, {
          value: ethers.parseEther("1.0"),
        });

        const contractBalanceGame1 = await ethers.provider.getBalance(game1);

        expect(contractBalanceGame1.toString()).to.equal("2000000000000000000");
      })
    })

    describe("makeMove", function(){
      beforeEach("before each test", async function (){
        /* JOIN GAME 1 */
        game1.connect(walletThree).joinGame(2, {
          value: ethers.parseEther("1.0")
        })
      });

      it("should revert if move position is out of range", async function(){
        const revertErrorMessage = "Position is out of range";

        await expect(game1.connect(walletThree).makeMove(9)).to.be.revertedWith(revertErrorMessage);
      })

      it("should revert if move position is already marked", async function(){
        const revertErrorMessage = "Position is already marked";

        await expect(game1.connect(walletThree).makeMove(2)).to.be.revertedWith(revertErrorMessage);
      })

      it("should revert if gameState is not Active", async function(){
        const revertErrorMessage = "Game is not active";

        await expect(game2.connect(walletThree).makeMove(3)).to.be.revertedWith(revertErrorMessage);
      })

      it("should revert if sender is not the currentPlayer", async function(){
        const revertErrorMessage = "You are not the current player";

        await expect(game1.connect(walletThree).makeMove(3)).to.be.revertedWith(revertErrorMessage);
      })

      it("should revert if play clock is exceeded", async function(){
        // game 1 has a 10 second play clock
        const timeDelay = 10;
        
        const revertErrorMessage = "You ran out of time to make a move";

        const block = await ethers.provider.getBlock(await ethers.provider.getBlockNumber());

        await ethers.provider.send("evm_increaseTime", [timeDelay]);
        await ethers.provider.send("evm_mine");

        await expect(game1.connect(walletOne).makeMove(3)).to.be.revertedWith(revertErrorMessage);
      })

      it("should set player's Mark on gameBoard in given position", async function(){
        /*
          Mark[9] public gameBoard;

          Starting state for game1:
          - playerOneMark: 1
          - playerTwoMark: 2
        */

        await game1.connect(walletOne).makeMove(3);

        const markOnPositionGame1 = await game1.gameBoard(3);

        expect(markOnPositionGame1.toString()).to.not.equal("0");

        expect(markOnPositionGame1.toString()).to.equal("1");
      })
      
      it("should set currentPlayer to playerTwo", async function(){
        /*
          - game1 is started by walletOne (playerOne)
          - game1 is joined by walletThree (playerTwo)
          - game1 currentPlayer is changed to playerOne
        */

        // playerOne makes a move
        await game1.connect(walletOne).makeMove(3);

        // now currentPlayer should be playerTwo
        const walletThreeAddr = await walletThree.getAddress();
        const currentPlayerGame1 = await game1.currentPlayer();
        const playerTwoGame1 = await game1.playerTwo();

        expect(currentPlayerGame1).to.not.equal(ethers.ZeroAddress);
        expect(playerTwoGame1).to.not.equal(ethers.ZeroAddress);

        expect(walletThreeAddr).to.equal(currentPlayerGame1);
        expect(currentPlayerGame1).to.equal(playerTwoGame1);
      })
      
      it("should emit MoveMade event", async function(){
        const game1Address = await game1.getAddress();
        const walletOneAddr = await walletOne.getAddress();
        const movePosition = 6;

        await expect(game1.connect(walletOne).makeMove(movePosition)).to.emit(game1, "MoveMade").withArgs(game1Address, walletOneAddr, movePosition);
      })

      it("should set message sender as winner if winning move is made", async function(){
        /* playerOne will win the game as below:
          | 🦈 | -- | 🐅 |
          | 🦈 | -- | 🐅 |
          | 🦈 | -- | -- |
        */

        const walletOneAddr = await walletOne.getAddress();
       
        // play the game to win for playerOne
        await game1.connect(walletOne).makeMove(3);
        await game1.connect(walletThree).makeMove(5);
        await game1.connect(walletOne).makeMove(6);

        const winner = await game1.winner();

        expect(winner).to.equal(walletOneAddr);
      });

      it("should set GameState to Ended if game is won", async function(){
        /* playerOne will win the game as below:
          | 🦈 | -- | 🐅 |
          | 🦈 | -- | 🐅 |
          | 🦈 | -- | -- |
        */

        const walletOneAddr = await walletOne.getAddress();
       
        // play the game to win for playerOne
        await game1.connect(walletOne).makeMove(3);
        await game1.connect(walletThree).makeMove(5);
        await game1.connect(walletOne).makeMove(6);

        const winner = await game1.winner();
        expect(winner).to.equal(walletOneAddr);

        /*
          GameState public gameState;

          enum GameState {
            Open,    // 0
            Active,  // 1
            Ended    // 2
          }
        */

        const gameStateGame1 = await game1.gameState();
        expect(gameStateGame1.toString()).to.equal("2");
      });

      it("should set GameState to Ended if game is a draw", async function(){
        /* Will complete the board as below:
          | 🦈 | 🐅 | 🦈 |
          | 🐅 | 🐅 | 🦈 |
          | 🦈 | 🦈 | 🐅 |
        */

        // play the game to fill the board
        await game1.connect(walletOne).makeMove(4);
        await game1.connect(walletThree).makeMove(8);
        await game1.connect(walletOne).makeMove(5);
        await game1.connect(walletThree).makeMove(3);
        await game1.connect(walletOne).makeMove(7);
        await game1.connect(walletThree).makeMove(1);
        await game1.connect(walletOne).makeMove(6);

        /*
          GameState public gameState;

          enum GameState {
            Open,    // 0
            Active,  // 1
            Ended    // 2
          }
        */

        const gameStateGame1 = await game1.gameState();
        expect(gameStateGame1.toString()).to.equal("2");
      });

      it("should set isDraw to true if game is a draw", async function(){
        /* Will complete the board as below:
          | 🦈 | 🐅 | 🦈 |
          | 🐅 | 🐅 | 🦈 |
          | 🦈 | 🦈 | 🐅 |
        */

        // play the game to fill the board
        await game1.connect(walletOne).makeMove(4);
        await game1.connect(walletThree).makeMove(8);
        await game1.connect(walletOne).makeMove(5);
        await game1.connect(walletThree).makeMove(3);
        await game1.connect(walletOne).makeMove(7);
        await game1.connect(walletThree).makeMove(1);
        await game1.connect(walletOne).makeMove(6);

        const winner = await game1.winner();
        expect(winner).to.equal(ethers.ZeroAddress);
        const isDraw = await game1.isDraw();
        expect(isDraw).to.equal(true);
      });

      it("should emit GameEnded event when game ends in a draw", async function(){
        /* Will complete the board as below:
          | 🦈 | 🐅 | 🦈 |
          | 🐅 | 🐅 | 🦈 |
          | 🦈 | 🦈 | 🐅 |
        */

        // play the game to fill the board
        await game1.connect(walletOne).makeMove(4);
        await game1.connect(walletThree).makeMove(8);
        await game1.connect(walletOne).makeMove(5);
        await game1.connect(walletThree).makeMove(3);
        await game1.connect(walletOne).makeMove(7);
        await game1.connect(walletThree).makeMove(1);
        
        const game1Address = await game1.getAddress();
        const walletOneAddr = await walletOne.getAddress();
        const walletThreeAddr = await walletThree.getAddress();
        const wager = await game1.wager();

        await expect(game1.connect(walletOne).makeMove(6)).to.emit(game1, "GameEnded").withArgs(game1Address, walletOneAddr, walletThreeAddr, wager, ethers.ZeroAddress, true);
      })

      it("should emit GameEnded event when game is won", async function(){
        /* playerOne will win the game as below:
          | 🦈 | -- | 🐅 |
          | 🦈 | -- | 🐅 |
          | 🦈 | -- | -- |
        */

      
        // play the game to win for playerOne
        await game1.connect(walletOne).makeMove(3);
        await game1.connect(walletThree).makeMove(5);

        const game1Address = await game1.getAddress();
        const walletOneAddr = await walletOne.getAddress();
        const walletThreeAddr = await walletThree.getAddress();
        const wager = await game1.wager();
        const isDraw = await game1.isDraw();
        
        await expect(game1.connect(walletOne).makeMove(6)).to.emit(game1, "GameEnded").withArgs(game1Address, walletOneAddr, walletThreeAddr, wager, walletOneAddr, isDraw);
      })
    })

    describe("claimReward", function(){
      beforeEach("before each test", async function (){
        /* JOIN GAME 1 */
        await game1.connect(walletThree).joinGame(1, {
          value: ethers.parseEther("1.0")
        })
      });

      it("should revert if GameState is not Ended", async function(){
        const revertErrorMessage = "Game is not ended";

        // playerTwo
        await expect(game1.connect(walletThree).claimReward()).to.be.revertedWith(revertErrorMessage);
        // playerOne
        await expect(game1.connect(walletOne).claimReward()).to.be.revertedWith(revertErrorMessage);
      });

      it("should revert if game ended in a draw", async function(){
        const revertErrorMessage = "No winner, game ended in a draw";

        /* Will complete the board as below:
          | 🦈 | 🐅 | 🦈 |
          | 🐅 | 🐅 | 🦈 |
          | 🦈 | 🦈 | 🐅 |
        */

        // play the game to fill the board
        await game1.connect(walletOne).makeMove(2);
        await game1.connect(walletThree).makeMove(3);
        await game1.connect(walletOne).makeMove(5);
        await game1.connect(walletThree).makeMove(4);
        await game1.connect(walletOne).makeMove(7);
        await game1.connect(walletThree).makeMove(8);
        await game1.connect(walletOne).makeMove(6);


        const gameStateGame1 = await game1.gameState();
        const isDraw = await game1.isDraw();
        const winner = await game1.winner();

        expect(isDraw).to.equal(true);
        expect(winner).to.equal(ethers.ZeroAddress);

        // playerTwo
        await expect(game1.connect(walletThree).claimReward()).to.be.revertedWith(revertErrorMessage);
        // playerOne
        await expect(game1.connect(walletThree).claimReward()).to.be.revertedWith(revertErrorMessage);
      });

      it("should revert if not the winner", async function(){
        const revertErrorMessage = "Only the winner can claim the reward";

        /* playerOne will win the game as below:
          | 🦈 | 🐅 | -- |
          | 🦈 | 🐅 | -- |
          | 🦈 | -- | -- |
        */

        // play the game to win for playerOne
        await game1.connect(walletOne).makeMove(3);
        await game1.connect(walletThree).makeMove(4);
        await game1.connect(walletOne).makeMove(6);


        const walletOneAddr = await walletOne.getAddress();
        const winner = await game1.winner();

        expect(walletOneAddr).to.equal(winner);

        await expect(game1.connect(walletThree).claimReward()).to.be.revertedWith(revertErrorMessage);
      });

      it("should revert if reward already claimed", async function(){
        const revertErrorMessage = "Reward already claimed";

        /* playerOne will win the game as below:
          | 🦈 | 🐅 | -- |
          | 🦈 | 🐅 | -- |
          | 🦈 | -- | -- |
        */

        // play the game to win for playerOne
        await game1.connect(walletOne).makeMove(3);
        await game1.connect(walletThree).makeMove(4);
        await game1.connect(walletOne).makeMove(6);


        const walletOneAddr = await walletOne.getAddress();
        const winner = await game1.winner();

        expect(walletOneAddr).to.equal(winner);

        await game1.connect(walletOne).claimReward();

        await expect(game1.connect(walletOne).claimReward()).to.be.revertedWith(revertErrorMessage);
      });

      it("should payout 2x the wager to the winner", async function(){
        /* playerOne will win the game as below:
          | 🦈 | 🐅 | -- |
          | 🦈 | 🐅 | -- |
          | 🦈 | -- | -- |
        */

        const walletOneAddr = await walletOne.getAddress();
       
        // play the game to win for playerOne
        await game1.connect(walletOne).makeMove(3);
        await game1.connect(walletThree).makeMove(4);
        await game1.connect(walletOne).makeMove(6);

        const winner = await game1.winner();

        expect(walletOneAddr).to.equal(winner);

        const initialBalance = await walletOne.provider?.getBalance(walletOneAddr);
        const rewardClaimReceipt = await game1.connect(walletOne).claimReward();
        const endingBalance = await walletOne.provider?.getBalance(walletOneAddr);

        const txrec = await rewardClaimReceipt.wait();
        const gasUsed = txrec?.gasUsed;
        const gasPrice = txrec?.gasPrice;
        const wagerGame1 = await game1.wager();


        const gasCost = gasUsed * gasPrice;        
        const totalReward = wagerGame1 + wagerGame1;
        
        expect(endingBalance).to.equal(initialBalance - gasCost + totalReward);
      });

      it("should reset contract balances for both players to 0", async function(){
        /* playerOne will win the game as below:
          | 🦈 | 🐅 | -- |
          | 🦈 | 🐅 | -- |
          | 🦈 | -- | -- |
        */

      
        // play the game to win for playerOne
        await game1.connect(walletOne).makeMove(3);
        await game1.connect(walletThree).makeMove(4);
        await game1.connect(walletOne).makeMove(6);

        const winner = await game1.winner();

        const walletOneAddr = await walletOne.getAddress();
        const walletThreeAddr = await walletThree.getAddress();

        expect(walletOneAddr).to.equal(winner);

        await game1.connect(walletOne).claimReward();

        const playerOneContractBalance = await game1.balances(walletOneAddr);
        const playerThreeContractBalance = await game1.balances(walletThreeAddr);

        expect(playerOneContractBalance).to.equal(0);
        expect(playerThreeContractBalance).to.equal(0);
      });

      it("should set isRewardClaimed to true", async function(){
        /* playerOne will win the game as below:
          | 🦈 | 🐅 | -- |
          | 🦈 | 🐅 | -- |
          | 🦈 | -- | -- |
        */

      
        // play the game to win for playerOne
        await game1.connect(walletOne).makeMove(3);
        await game1.connect(walletThree).makeMove(4);
        await game1.connect(walletOne).makeMove(6);

        const winner = await game1.winner();

        const walletOneAddr = await walletOne.getAddress();
        const walletThreeAddr = await walletThree.getAddress();

        expect(walletOneAddr).to.equal(winner);

        await game1.connect(walletOne).claimReward();

        const isRewardClaimed = await game1.isRewardClaimed();

        expect(isRewardClaimed).to.equal(true);
      });
    })

    describe("withdrawWager", function(){
      beforeEach("before each test", async function (){
        /* JOIN GAME 1 */
        await game1.connect(walletThree).joinGame(1, {
          value: ethers.parseEther("1.0")
        })

        /* JOIN GAME 2 */
        await game2.connect(walletThree).joinGame(4, {
          value: ethers.parseEther("0.5")
        })
        /* Will complete the game2 board as below:
          | 🦈 | 🐅 | 🦈 |
          | 🐅 | 🦈 | 🐅 |
          | 🐅 | 🦈 | 🐅 |
        */

        // play the game to fill the board
        await game2.connect(walletTwo).makeMove(8);
        await game2.connect(walletThree).makeMove(2);
        await game2.connect(walletTwo).makeMove(1);
        await game2.connect(walletThree).makeMove(0);
        await game2.connect(walletTwo).makeMove(6);
        await game2.connect(walletThree).makeMove(7);
        await game2.connect(walletTwo).makeMove(3);
      });

      it("should revert if GameState is not ended", async function(){
        const revertErrorMessage = "Game is not ended";

        // playerTwo
        await expect(game1.connect(walletThree).withdrawWager()).to.be.revertedWith(revertErrorMessage);
        // playerOne
        await expect(game1.connect(walletOne).withdrawWager()).to.be.revertedWith(revertErrorMessage);
      });
      it("should revert if game has a winner", async function(){
        const revertErrorMessage = "Game is not a draw, winner must call claimReward";

        /* playerOne will win the game as below:
          | 🦈 | 🐅 | -- |
          | 🦈 | 🐅 | -- |
          | 🦈 | -- | -- |
        */

        // play the game to win for playerOne
        await game1.connect(walletOne).makeMove(3);
        await game1.connect(walletThree).makeMove(4);
        await game1.connect(walletOne).makeMove(6);


        const walletOneAddr = await walletOne.getAddress();
        const winner = await game1.winner();

        expect(walletOneAddr).to.equal(winner);

        await expect(game1.connect(walletOne).withdrawWager()).to.be.revertedWith(revertErrorMessage);
        await expect(game1.connect(walletThree).withdrawWager()).to.be.revertedWith(revertErrorMessage);
      });
      it("should revert if player does not have a balance to withdraw", async function(){
        const revertErrorMessage = "Nothing to withdraw";

        /* GAME 2 ended in a draw between walletTwo and walletThree */

        // attempt to withdraw twice for one player
        await game2.connect(walletThree).withdrawWager();
        await expect(game2.connect(walletThree).withdrawWager()).to.be.revertedWith(revertErrorMessage);

        // attempt to withdraw as a non-player
        await expect(game2.connect(walletOne).withdrawWager()).to.be.revertedWith(revertErrorMessage);
      });
    })
  })
});
