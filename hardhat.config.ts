import { HardhatUserConfig } from "hardhat/config";
import { task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

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
};

export default config;
