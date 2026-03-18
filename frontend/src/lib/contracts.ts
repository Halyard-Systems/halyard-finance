import { getAddress } from "viem";

// Hub chain contract addresses (all on hub chain)
export interface HubConfig {
  chainId: number;
  hubRouter: `0x${string}`;
  riskEngine: `0x${string}`;
  positionBook: `0x${string}`;
  debtManager: `0x${string}`;
  liquidationEngine: `0x${string}`;
  pythOracleAdapter: `0x${string}`;
  hubController: `0x${string}`;
}

export interface SpokeAsset {
  symbol: string;
  name: string;
  decimals: number;
  canonicalAddress: `0x${string}`;
  spokeAddress: `0x${string}`;
  icon: string;
}

// Per-spoke-chain configuration
export interface SpokeConfig {
  chainId: number;
  name: string;
  logo: string;
  lzEid: number;
  spokeController: `0x${string}`;
  collateralVault: `0x${string}`;
  liquidityVault: `0x${string}`;
  assets: SpokeAsset[];
}

// Map well-known symbols to their public/ logo files
const ASSET_ICONS: Record<string, string> = {
  USDC: "/usd-coin-usdc-logo.svg",
  WETH: "/wrapped-ethereum-weth-logo.svg",
  WBTC: "/wrapped-bitcoin-wbtc-logo.svg",
  USDT: "/tether-usdt-logo.svg",
  ETH: "/ethereum-eth-logo.svg",
};

function defaultAssetIcon(symbol: string): string {
  return ASSET_ICONS[symbol] ?? "/ethereum-eth-logo.svg";
}

// Normalise env-format assets (may have `address` instead of canonical/spoke split)
function normaliseAssets(raw: unknown[]): SpokeAsset[] {
  return (raw as Record<string, unknown>[]).map((a) => ({
    symbol: (a.symbol as string) ?? "???",
    name: (a.name as string) ?? (a.symbol as string) ?? "",
    decimals: Number(a.decimals ?? 18),
    canonicalAddress: getAddress((a.canonicalAddress ?? a.address) as string) as `0x${string}`,
    spokeAddress: getAddress((a.spokeAddress ?? a.address) as string) as `0x${string}`,
    icon: (a.icon as string) ?? defaultAssetIcon(a.symbol as string),
  }));
}

export const hubConfig: HubConfig = {
  chainId: Number(import.meta.env.VITE_HUB_CHAIN_ID || 1),
  hubRouter: import.meta.env.VITE_HUB_ROUTER_ADDRESS as `0x${string}`,
  riskEngine: import.meta.env.VITE_RISK_ENGINE_ADDRESS as `0x${string}`,
  positionBook: import.meta.env.VITE_POSITION_BOOK_ADDRESS as `0x${string}`,
  debtManager: import.meta.env.VITE_DEBT_MANAGER_ADDRESS as `0x${string}`,
  liquidationEngine: import.meta.env
    .VITE_LIQUIDATION_ENGINE_ADDRESS as `0x${string}`,
  pythOracleAdapter: import.meta.env
    .VITE_PYTH_ORACLE_ADAPTER_ADDRESS as `0x${string}`,
  hubController: import.meta.env
    .VITE_HUB_CONTROLLER_ADDRESS as `0x${string}`,
};

// Parse spoke configs from env
function parseSpokeConfigs(): SpokeConfig[] {
  const spokesJson = import.meta.env.VITE_SPOKE_CONFIGS;
  if (spokesJson) {
    try {
      return JSON.parse(spokesJson) as SpokeConfig[];
    } catch {
      console.error("Failed to parse VITE_SPOKE_CONFIGS");
    }
  }

  // Fallback: build from individual env vars
  const configs: SpokeConfig[] = [];

  // Ethereum spoke
  if (import.meta.env.VITE_SPOKE_CONTROLLER_ETH_ADDRESS) {
    configs.push({
      chainId: Number(import.meta.env.VITE_SPOKE_ETH_CHAIN_ID || 1),
      name: "Ethereum",
      logo: "/ethereum-eth-logo.svg",
      lzEid: Number(import.meta.env.VITE_SPOKE_ETH_LZ_EID || 30101),
      spokeController: import.meta.env
        .VITE_SPOKE_CONTROLLER_ETH_ADDRESS as `0x${string}`,
      collateralVault: import.meta.env
        .VITE_COLLATERAL_VAULT_ETH_ADDRESS as `0x${string}`,
      liquidityVault: import.meta.env
        .VITE_LIQUIDITY_VAULT_ETH_ADDRESS as `0x${string}`,
      assets: normaliseAssets(
        JSON.parse(import.meta.env.VITE_SPOKE_ETH_ASSETS || "[]")
      ),
    });
  }

  // Arbitrum spoke
  if (import.meta.env.VITE_SPOKE_CONTROLLER_ARB_ADDRESS) {
    configs.push({
      chainId: Number(import.meta.env.VITE_SPOKE_ARB_CHAIN_ID || 42161),
      name: "Arbitrum",
      logo: "/arbitrum-arb-logo.svg",
      lzEid: Number(import.meta.env.VITE_SPOKE_ARB_LZ_EID || 30110),
      spokeController: import.meta.env
        .VITE_SPOKE_CONTROLLER_ARB_ADDRESS as `0x${string}`,
      collateralVault: import.meta.env
        .VITE_COLLATERAL_VAULT_ARB_ADDRESS as `0x${string}`,
      liquidityVault: import.meta.env
        .VITE_LIQUIDITY_VAULT_ARB_ADDRESS as `0x${string}`,
      assets: normaliseAssets(
        JSON.parse(import.meta.env.VITE_SPOKE_ARB_ASSETS || "[]")
      ),
    });
  }

  // BNB Chain spoke
  if (import.meta.env.VITE_SPOKE_CONTROLLER_BNB_ADDRESS) {
    configs.push({
      chainId: Number(import.meta.env.VITE_SPOKE_BNB_CHAIN_ID || 56),
      name: "BNB Chain",
      logo: "/binance-coin-bnb-logo.svg",
      lzEid: Number(import.meta.env.VITE_SPOKE_BNB_LZ_EID || 30102),
      spokeController: import.meta.env
        .VITE_SPOKE_CONTROLLER_BNB_ADDRESS as `0x${string}`,
      collateralVault: import.meta.env
        .VITE_COLLATERAL_VAULT_BNB_ADDRESS as `0x${string}`,
      liquidityVault: import.meta.env
        .VITE_LIQUIDITY_VAULT_BNB_ADDRESS as `0x${string}`,
      assets: normaliseAssets(
        JSON.parse(import.meta.env.VITE_SPOKE_BNB_ASSETS || "[]")
      ),
    });
  }

  // Optimism spoke
  if (import.meta.env.VITE_SPOKE_CONTROLLER_OP_ADDRESS) {
    configs.push({
      chainId: Number(import.meta.env.VITE_SPOKE_OP_CHAIN_ID || 10),
      name: "Optimism",
      logo: "/optimism-op-logo.svg",
      lzEid: Number(import.meta.env.VITE_SPOKE_OP_LZ_EID || 30111),
      spokeController: import.meta.env
        .VITE_SPOKE_CONTROLLER_OP_ADDRESS as `0x${string}`,
      collateralVault: import.meta.env
        .VITE_COLLATERAL_VAULT_OP_ADDRESS as `0x${string}`,
      liquidityVault: import.meta.env
        .VITE_LIQUIDITY_VAULT_OP_ADDRESS as `0x${string}`,
      assets: normaliseAssets(
        JSON.parse(import.meta.env.VITE_SPOKE_OP_ASSETS || "[]")
      ),
    });
  }

  // Base spoke
  if (import.meta.env.VITE_SPOKE_CONTROLLER_BASE_ADDRESS) {
    configs.push({
      chainId: Number(import.meta.env.VITE_SPOKE_BASE_CHAIN_ID || 8453),
      name: "Base",
      logo: "/base-logo.svg",
      lzEid: Number(import.meta.env.VITE_SPOKE_BASE_LZ_EID || 30184),
      spokeController: import.meta.env
        .VITE_SPOKE_CONTROLLER_BASE_ADDRESS as `0x${string}`,
      collateralVault: import.meta.env
        .VITE_COLLATERAL_VAULT_BASE_ADDRESS as `0x${string}`,
      liquidityVault: import.meta.env
        .VITE_LIQUIDITY_VAULT_BASE_ADDRESS as `0x${string}`,
      assets: normaliseAssets(
        JSON.parse(import.meta.env.VITE_SPOKE_BASE_ASSETS || "[]")
      ),
    });
  }

  // Polygon spoke
  if (import.meta.env.VITE_SPOKE_CONTROLLER_POLY_ADDRESS) {
    configs.push({
      chainId: Number(import.meta.env.VITE_SPOKE_POLY_CHAIN_ID || 137),
      name: "Polygon",
      logo: "/polygon-matic-logo.svg",
      lzEid: Number(import.meta.env.VITE_SPOKE_POLY_LZ_EID || 30109),
      spokeController: import.meta.env
        .VITE_SPOKE_CONTROLLER_POLY_ADDRESS as `0x${string}`,
      collateralVault: import.meta.env
        .VITE_COLLATERAL_VAULT_POLY_ADDRESS as `0x${string}`,
      liquidityVault: import.meta.env
        .VITE_LIQUIDITY_VAULT_POLY_ADDRESS as `0x${string}`,
      assets: normaliseAssets(
        JSON.parse(import.meta.env.VITE_SPOKE_POLY_ASSETS || "[]")
      ),
    });
  }

  return configs;
}

export const spokeConfigs: SpokeConfig[] = parseSpokeConfigs();

// Utility: find spoke config by chain ID
export function getSpokeByChainId(
  chainId: number
): SpokeConfig | undefined {
  return spokeConfigs.find((s) => s.chainId === chainId);
}

// Utility: find spoke config by LZ endpoint ID
export function getSpokeByEid(eid: number): SpokeConfig | undefined {
  return spokeConfigs.find((s) => s.lzEid === eid);
}

// Utility: map eid to chain name
export function eidToChainName(eid: number): string {
  const spoke = getSpokeByEid(eid);
  return spoke?.name ?? `Chain ${eid}`;
}

// Utility: get all assets across all spokes
export function getAllAssets(): (SpokeAsset & { chainId: number; lzEid: number; chainName: string })[] {
  return spokeConfigs.flatMap((spoke) =>
    spoke.assets.map((asset) => ({
      ...asset,
      chainId: spoke.chainId,
      lzEid: spoke.lzEid,
      chainName: spoke.name,
    }))
  );
}

// Check if a chainId is the hub chain
export function isHubChain(chainId: number): boolean {
  return chainId === hubConfig.chainId;
}
