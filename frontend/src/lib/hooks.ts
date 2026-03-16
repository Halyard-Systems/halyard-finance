import {
  useReadContract,
  useReadContracts,
  type UseReadContractReturnType,
} from "wagmi";
import type { Abi } from "viem";

import POSITION_BOOK_ABI from "../abis/PositionBook.json";
import DEBT_MANAGER_ABI from "../abis/DebtManager.json";
import RISK_ENGINE_ABI from "../abis/RiskEngine.json";
import ERC20_ABI from "../abis/ERC20.json";

import { hubConfig } from "./contracts";
import type {
  AccountData,
  ChainAsset,
  CollateralPosition,
  DebtPosition,
} from "./types";

// ─── ERC20 ──────────────────────────────────────────────────────────────────

export function useERC20Balance(
  tokenAddress: `0x${string}` | undefined,
  userAddress: `0x${string}` | undefined,
  chainId?: number,
  lzEid?: number
): UseReadContractReturnType {
  return useReadContract({
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: userAddress ? [userAddress] : undefined,
    chainId,
    scopeKey: `${lzEid ?? chainId ?? "default"}-${tokenAddress ?? "none"}`,
    query: {
      enabled: !!tokenAddress && !!userAddress,
    },
  });
}

export function useERC20Allowance(
  tokenAddress: `0x${string}` | undefined,
  ownerAddress: `0x${string}` | undefined,
  spenderAddress: `0x${string}` | undefined,
  chainId?: number
): UseReadContractReturnType {
  return useReadContract({
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: ownerAddress && spenderAddress ? [ownerAddress, spenderAddress] : undefined,
    chainId,
    query: { enabled: !!tokenAddress && !!ownerAddress && !!spenderAddress },
  });
}

// ─── User Slots (Phase 1.1) ────────────────────────────────────────────────

export function useUserSlots(userAddress: `0x${string}` | undefined) {
  const collateralQuery = useReadContract({
    address: hubConfig.positionBook,
    abi: POSITION_BOOK_ABI as Abi,
    functionName: "collateralAssetsOf",
    args: userAddress ? [userAddress] : undefined,
    chainId: hubConfig.chainId,
    query: { enabled: !!userAddress },
  });

  const debtQuery = useReadContract({
    address: hubConfig.debtManager,
    abi: DEBT_MANAGER_ABI as Abi,
    functionName: "debtAssetsOf",
    args: userAddress ? [userAddress] : undefined,
    chainId: hubConfig.chainId,
    query: { enabled: !!userAddress },
  });

  const collateralSlots = (collateralQuery.data as ChainAsset[] | undefined) ?? [];
  const debtSlots = (debtQuery.data as ChainAsset[] | undefined) ?? [];

  return {
    collateralSlots,
    debtSlots,
    isLoading: collateralQuery.isLoading || debtQuery.isLoading,
    isError: collateralQuery.isError || debtQuery.isError,
    refetch: () => {
      collateralQuery.refetch();
      debtQuery.refetch();
    },
  };
}

// ─── Account Data (Phase 1.2) ──────────────────────────────────────────────

export function useAccountData(
  userAddress: `0x${string}` | undefined,
  collateralSlots: ChainAsset[],
  debtSlots: ChainAsset[]
) {
  const query = useReadContract({
    address: hubConfig.riskEngine,
    abi: RISK_ENGINE_ABI as Abi,
    functionName: "accountData",
    args: userAddress ? [userAddress, collateralSlots, debtSlots] : undefined,
    chainId: hubConfig.chainId,
    query: {
      enabled: !!userAddress && (collateralSlots.length > 0 || debtSlots.length > 0),
    },
  });

  const result = query.data as
    | [bigint, bigint, bigint, bigint, bigint]
    | undefined;

  const accountData: AccountData | undefined = result
    ? {
        collateralValueE18: result[0],
        borrowPowerE18: result[1],
        liquidationValueE18: result[2],
        debtValueE18: result[3],
        healthFactorE18: result[4],
      }
    : undefined;

  return {
    accountData,
    isLoading: query.isLoading,
    isError: query.isError,
    refetch: query.refetch,
  };
}

// ─── Position Detail Hooks (Phase 1.3) ─────────────────────────────────────

export function useCollateralPositions(
  userAddress: `0x${string}` | undefined,
  slots: ChainAsset[]
) {
  const eids = slots.map((s) => s.eid);
  const assets = slots.map((s) => s.asset);

  const query = useReadContract({
    address: hubConfig.positionBook,
    abi: POSITION_BOOK_ABI as Abi,
    functionName: "batchCollateralOf",
    args: userAddress ? [userAddress, eids, assets] : undefined,
    chainId: hubConfig.chainId,
    query: { enabled: !!userAddress && slots.length > 0 },
  });

  const result = query.data as
    | [bigint[], bigint[], bigint[]]
    | undefined;

  const positions: CollateralPosition[] = result
    ? slots.map((slot, i) => ({
        eid: slot.eid,
        asset: slot.asset,
        balance: result[0][i],
        reserved: result[1][i],
        available: result[2][i],
      }))
    : [];

  return {
    positions,
    isLoading: query.isLoading,
    isError: query.isError,
    refetch: query.refetch,
  };
}

export function useDebtPositions(
  userAddress: `0x${string}` | undefined,
  slots: ChainAsset[]
) {
  const contracts = slots.map((slot) => ({
    address: hubConfig.debtManager as `0x${string}`,
    abi: DEBT_MANAGER_ABI as Abi,
    functionName: "debtOf" as const,
    args: [userAddress!, slot.eid, slot.asset],
    chainId: hubConfig.chainId,
  }));

  const query = useReadContracts({
    contracts,
    query: { enabled: !!userAddress && slots.length > 0 },
  });

  const positions: DebtPosition[] = query.data
    ? slots.map((slot, i) => ({
        eid: slot.eid,
        asset: slot.asset,
        debt: (query.data![i].result as bigint) ?? 0n,
      }))
    : [];

  return {
    positions,
    isLoading: query.isLoading,
    isError: query.isError,
    refetch: query.refetch,
  };
}

// ─── Risk Preview Hooks ────────────────────────────────────────────────────

export function useCanBorrow(
  userAddress: `0x${string}` | undefined,
  dstEid: number | undefined,
  asset: `0x${string}` | undefined,
  amount: bigint | undefined,
  collateralSlots: ChainAsset[],
  debtSlots: ChainAsset[]
) {
  const query = useReadContract({
    address: hubConfig.riskEngine,
    abi: RISK_ENGINE_ABI as Abi,
    functionName: "canBorrow",
    args:
      userAddress && dstEid && asset && amount
        ? [userAddress, dstEid, asset, amount, collateralSlots, debtSlots]
        : undefined,
    chainId: hubConfig.chainId,
    query: {
      enabled: !!userAddress && !!dstEid && !!asset && !!amount && amount > 0n,
    },
  });

  const result = query.data as [boolean, bigint] | undefined;

  return {
    ok: result?.[0] ?? false,
    nextHealthFactorE18: result?.[1] ?? 0n,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

export function useCanWithdraw(
  userAddress: `0x${string}` | undefined,
  eid: number | undefined,
  asset: `0x${string}` | undefined,
  amount: bigint | undefined,
  collateralSlots: ChainAsset[],
  debtSlots: ChainAsset[]
) {
  const query = useReadContract({
    address: hubConfig.riskEngine,
    abi: RISK_ENGINE_ABI as Abi,
    functionName: "canWithdraw",
    args:
      userAddress && eid && asset && amount
        ? [userAddress, eid, asset, amount, collateralSlots, debtSlots]
        : undefined,
    chainId: hubConfig.chainId,
    query: {
      enabled: !!userAddress && !!eid && !!asset && !!amount && amount > 0n,
    },
  });

  const result = query.data as [boolean, bigint] | undefined;

  return {
    ok: result?.[0] ?? false,
    nextHealthFactorE18: result?.[1] ?? 0n,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}
