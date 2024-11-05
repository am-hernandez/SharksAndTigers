import { HardhatUserConfig } from "hardhat/config";
import { task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ignition-ethers";

task("balance", "Prints an account's balance")
  .addParam("account", "The account's address")
  .setAction(async (taskArgs) => {
    // @ts-ignore
    const balance = await ethers.provider.getBalance(taskArgs.account);
    // @ts-ignore
    console.log(ethers.formatEther(balance), "ETH");
  });

const config: HardhatUserConfig = {
  solidity: "0.8.19",
  networks: {
    local: {
      url: "http://127.0.0.1:8545/", // <-- here add the '/' in the end
    },
    sepolia: {
      url: "https://eth-sepolia.alchemyapi.io/v2/YOUR_ALCHEMY_API_KEY", // Replace with sepolia RPC URL
      accounts: [`0x${YOUR_PRIVATE_KEY}`], // Replace with wallet private key
    },
  },
};

export default config;
