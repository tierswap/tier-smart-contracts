import { HardhatUserConfig } from "hardhat/config";
import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-toolbox";
import "solidity-coverage";
import dotenv from "dotenv";
dotenv.config();

dotenv.config();
const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 9999,
      },
    },
  },
  networks: {
    atestnet: {
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      accounts: process.env.TESTNET_PRIVATE_KEY
        ? [process.env.TESTNET_PRIVATE_KEY]
        : [],
    },
    btestnet: {
      url: "https://api-testnet.bscscan.com/api",
      accounts: process.env.TESTNET_PRIVATE_KEY
        ? [process.env.TESTNET_PRIVATE_KEY]
        : [],
    },
  },
  etherscan: {
    apiKey: {
      avalancheFujiTestnet: "YGUG682F3PQM5ESJFIQECZR6BTXG1XFPQG",
      bscTestnet: "J15TBU6MXRSA6GU4Y1IBYSH7BKB2JM2A48",
    },
  },
};

export default config;
