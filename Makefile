-include .env

.PHONY: build test clean deploy remove install update snapshot format anvil create-game join-game

# Anvil private keys
DEFAULT_ANVIL_PRIVATE_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
PLAYER_ONE_PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
PLAYER_TWO_PRIVATE_KEY=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a

build:; forge build

test:; forge test -vvv

clean:; forge clean

# Remove modules
remove:; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib

#  Install OpenZeppelin and Forge Std
install:; forge install OpenZeppelin/openzeppelin-contracts --no-commit && forge install foundry-rs/forge-std --no-commit

# Update dependencies
update:; forge update

snapshot:; forge snapshot

format:; forge fmt

# Start Anvil
anvil:; anvil -m "test test test test test test test test test test test junk" --steps-tracing --block-time 1

# Base network args without private key
BASE_NETWORK_ARGS := --rpc-url http://localhost:8545 --broadcast
DEPLOY_PK := $(DEFAULT_ANVIL_PRIVATE_KEY)

ifeq ($(ARGS),base-sepolia)
	BASE_NETWORK_ARGS := --rpc-url $(BASE_SEPOLIA_RPC_URL) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
	DEPLOY_PK := $(DEPLOYER_PRIVATE_KEY)
endif

ifeq ($(ARGS),base-mainnet)
	BASE_NETWORK_ARGS := --rpc-url $(BASE_MAINNET_RPC_URL) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
	DEPLOY_PK := $(DEPLOYER_PRIVATE_KEY)
endif

# Deploy (usage: make deploy ARGS=base-sepolia or make deploy ARGS=base-mainnet)
# Uses DEPLOYER_PRIVATE_KEY from .env for testnets/mainnets, DEFAULT_ANVIL_PRIVATE_KEY for anvil
deploy:; @forge script script/Deploy.s.sol:Deploy $(BASE_NETWORK_ARGS) --private-key $(DEPLOY_PK)

# Create game (usage: make create-game ARGS=base-sepolia or make create-game ARGS=base-mainnet)
# Uses player one's private key (can be overridden in .env for testnets/mainnets)
create-game:; @forge script script/Interactions/CreateGame.s.sol:CreateGame $(BASE_NETWORK_ARGS) --private-key $(PLAYER_ONE_PRIVATE_KEY)

# Join game as player two (usage: make join-game ARGS=base-sepolia or make join-game ARGS=base-mainnet)
# Uses player two's private key (can be overridden in .env for testnets/mainnets)
join-game:; @forge script script/Interactions/JoinGame.s.sol:JoinGame $(BASE_NETWORK_ARGS) --private-key $(PLAYER_TWO_PRIVATE_KEY)

