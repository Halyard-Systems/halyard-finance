import { http, createConfig, createStorage } from "wagmi";
import { mainnet, arbitrum, bsc, optimism, base, polygon, sepolia, hardhat } from "wagmi/chains";
import { injected, mock } from "wagmi/connectors";
import { createWalletClient, type WalletClient } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const nodeUrl = import.meta.env.VITE_NODE_URL;
const arbNodeUrl = import.meta.env.VITE_ARB_NODE_URL;
const bnbNodeUrl = import.meta.env.VITE_BNB_NODE_URL;
const opNodeUrl = import.meta.env.VITE_OP_NODE_URL;
const baseNodeUrl = import.meta.env.VITE_BASE_NODE_URL;
const polyNodeUrl = import.meta.env.VITE_POLY_NODE_URL;

const isLocalDev = import.meta.env.VITE_NETWORK === "localhost";

// For local dev, use Hardhat's default account directly (bypasses MetaMask nonce issues)
const localDevAccount = isLocalDev
  ? privateKeyToAccount("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80")
  : undefined;

const connectors = isLocalDev && localDevAccount
  ? [mock({ accounts: [localDevAccount.address] })]
  : [injected()];

export const config = createConfig({
  chains: [mainnet, sepolia, arbitrum, bsc, optimism, base, polygon, hardhat],
  connectors,
  ...(isLocalDev ? { storage: createStorage({ storage: localStorage }) } : {}),
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

// Viem wallet client for local dev — manages nonces directly via RPC, no MetaMask
export const localWalletClient: WalletClient | undefined =
  isLocalDev && localDevAccount
    ? createWalletClient({
        account: localDevAccount,
        chain: hardhat,
        transport: http(nodeUrl),
      })
    : undefined;
