import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("SharksAndTigersFactoryModule", (m) => {  
  const sharksAndTigersFactory = m.contract("SharksAndTigersFactory");

  return { sharksAndTigersFactory };
});
