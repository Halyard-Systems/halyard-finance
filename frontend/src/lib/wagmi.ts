import { http, createConfig } from "wagmi";
import { mainnet, arbitrum, bsc, optimism, base, polygon, sepolia, hardhat } from "wagmi/chains";
import { injected } from "wagmi/connectors";

const nodeUrl = import.meta.env.VITE_NODE_URL;
const arbNodeUrl = import.meta.env.VITE_ARB_NODE_URL;
const bnbNodeUrl = import.meta.env.VITE_BNB_NODE_URL;
const opNodeUrl = import.meta.env.VITE_OP_NODE_URL;
const baseNodeUrl = import.meta.env.VITE_BASE_NODE_URL;
const polyNodeUrl = import.meta.env.VITE_POLY_NODE_URL;

export const config = createConfig({
  chains: [mainnet, sepolia, arbitrum, bsc, optimism, base, polygon, hardhat],
  connectors: [injected()],
  transports: {
    [mainnet.id]: http(nodeUrl),
    [sepolia.id]: http(nodeUrl),
    [arbitrum.id]: http(arbNodeUrl || undefined),
    [bsc.id]: http(bnbNodeUrl || undefined),
    [optimism.id]: http(opNodeUrl || undefined),
    [base.id]: http(baseNodeUrl || undefined),
    [polygon.id]: http(polyNodeUrl || undefined),
    [hardhat.id]: http(nodeUrl),
  },
});
