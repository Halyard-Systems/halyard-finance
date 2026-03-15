import { useCallback, useEffect, useState } from "react";
import {
  useWriteContract,
  useSwitchChain,
  useAccount,
  useReadContract,
  useWaitForTransactionReceipt,
  useWatchContractEvent,
} from "wagmi";
import { keccak256, encodePacked, maxUint256 } from "viem";
import { useQueryClient } from "@tanstack/react-query";

import { localWalletClient } from "./wagmi";

import ERC20_ABI from "../abis/ERC20.json";
import SPOKE_CONTROLLER_ABI from "../abis/SpokeController.json";
import LIQUIDITY_VAULT_ABI from "../abis/LiquidityVault.json";
import HUB_ROUTER_ABI from "../abis/HubRouter.json";
import LIQUIDATION_ENGINE_ABI from "../abis/LiquidationEngine.json";
import POSITION_BOOK_ABI from "../abis/PositionBook.json";

import { hubConfig, type SpokeConfig } from "./contracts";
import type { ChainAsset, MessagingFee, TransactionStatus } from "./types";
import { buildLzOptions, GAS_LIMITS } from "./layerzero";

// ─── Token Approval ────────────────────────────────────────────────────────

export function useTokenApproval(
  tokenAddress: `0x${string}` | undefined,
  spenderAddress: `0x${string}` | undefined,
  chainId: number | undefined
) {
  const { address: userAddress } = useAccount();

  const allowanceQuery = useReadContract({
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: userAddress && spenderAddress ? [userAddress, spenderAddress] : undefined,
    chainId,
    query: { enabled: !!tokenAddress && !!userAddress && !!spenderAddress },
  });

  const { writeContractAsync } = useWriteContract();

  const approve = useCallback(
    async (amount: bigint) => {
      if (!tokenAddress || !spenderAddress) throw new Error("Missing token or spender");
      return writeContractAsync({
        address: tokenAddress,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [spenderAddress, amount],
        chainId,
      });
    },
    [tokenAddress, spenderAddress, chainId, writeContractAsync]
  );

  const allowance = (allowanceQuery.data as bigint) ?? 0n;

  return {
    allowance,
    approve,
    refetchAllowance: allowanceQuery.refetch,
    isLoading: allowanceQuery.isLoading,
  };
}

// ─── Generate unique operation IDs ─────────────────────────────────────────

function generateOperationId(
  prefix: string,
  userAddress: `0x${string}`,
  nonce: number
): `0x${string}` {
  return keccak256(
    encodePacked(
      ["string", "address", "uint256", "uint256"],
      [prefix, userAddress, BigInt(nonce), BigInt(Date.now())]
    )
  );
}

// ─── Multi-step transaction hook ───────────────────────────────────────────

export function useTransactionFlow() {
  const [status, setStatus] = useState<TransactionStatus>("idle");
  const [error, setError] = useState<string | null>(null);
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const { address, chainId: currentChainId } = useAccount();
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();

  // Use local wallet client (bypasses MetaMask nonce issues) or fall back to wagmi hook
  const sendTx = useCallback(
    async (args: Parameters<typeof writeContractAsync>[0] & { value?: bigint }) => {
      if (localWalletClient) {
        return localWalletClient.writeContract(args as any);
      }
      return writeContractAsync(args as any);
    },
    [writeContractAsync]
  );

  const receipt = useWaitForTransactionReceipt({ hash: txHash });

  // Transition to confirmed/failed based on the on-chain receipt status
  useEffect(() => {
    if (status !== "pending" || !receipt.data) return;
    if (receipt.data.status === "reverted") {
      setStatus("failed");
      setError("Transaction reverted on-chain");
    } else if (receipt.data.status === "success") {
      setStatus("confirmed");
    }
  }, [status, receipt.data]);

  const reset = useCallback(() => {
    setStatus("idle");
    setError(null);
    setTxHash(undefined);
  }, []);

  // ─── Approve (standalone, user-triggered) ────────────────────────────

  const approve = useCallback(
    async (
      tokenAddress: `0x${string}`,
      spender: `0x${string}`,
      chainId: number
    ) => {
      if (!address) throw new Error("Wallet not connected");
      try {
        setError(null);

        if (currentChainId !== chainId) {
          setStatus("switching-chain");
          await switchChainAsync({ chainId });
        }

        setStatus("approving");
        const hash = await sendTx({
          address: tokenAddress,
          abi: ERC20_ABI,
          functionName: "approve",
          args: [spender, maxUint256],
          chainId,
        });

        setTxHash(hash);
        setStatus("pending");
        return hash;
      } catch (err: any) {
        setStatus("failed");
        setError(err?.shortMessage || err?.message || "Transaction failed");
        throw err;
      }
    },
    [address, currentChainId, switchChainAsync, sendTx]
  );

  // ─── Deposit (spoke chain) ─────────────────────────────────────────────

  const deposit = useCallback(
    async (
      spoke: SpokeConfig,
      canonicalAsset: `0x${string}`,
      amount: bigint,
      fee: MessagingFee
    ) => {
      if (!address) throw new Error("Wallet not connected");
      try {
        setError(null);

        if (currentChainId !== spoke.chainId) {
          setStatus("switching-chain");
          await switchChainAsync({ chainId: spoke.chainId });
        }

        const depositId = generateOperationId("deposit", address, Date.now());
        const options = buildLzOptions(GAS_LIMITS.deposit);

        setStatus("sending");
        const hash = await sendTx({
          address: spoke.spokeController,
          abi: SPOKE_CONTROLLER_ABI,
          functionName: "depositAndNotify",
          args: [depositId, canonicalAsset, amount, options, fee],
          value: fee.nativeFee,
          chainId: spoke.chainId,
        });

        setTxHash(hash);
        setStatus("pending");
        return hash;
      } catch (err: any) {
        setStatus("failed");
        setError(err?.shortMessage || err?.message || "Transaction failed");
        throw err;
      }
    },
    [address, currentChainId, switchChainAsync, sendTx]
  );

  // ─── Repay (spoke chain) ───────────────────────────────────────────────

  const repay = useCallback(
    async (
      spoke: SpokeConfig,
      spokeTokenAddress: `0x${string}`,
      amount: bigint,
      onBehalfOf: `0x${string}`,
      fee: MessagingFee
    ) => {
      if (!address) throw new Error("Wallet not connected");
      try {
        setError(null);

        if (currentChainId !== spoke.chainId) {
          setStatus("switching-chain");
          await switchChainAsync({ chainId: spoke.chainId });
        }

        const repayId = generateOperationId("repay", address, Date.now());

        setStatus("sending");
        const hash = await sendTx({
          address: spoke.liquidityVault,
          abi: LIQUIDITY_VAULT_ABI,
          functionName: "repay",
          args: [repayId, spokeTokenAddress, amount, onBehalfOf],
          value: fee.nativeFee,
          chainId: spoke.chainId,
        });

        setTxHash(hash);
        setStatus("pending");
        return hash;
      } catch (err: any) {
        setStatus("failed");
        setError(err?.shortMessage || err?.message || "Transaction failed");
        throw err;
      }
    },
    [address, currentChainId, switchChainAsync, sendTx]
  );

  // ─── Borrow (hub chain) ────────────────────────────────────────────────

  const borrow = useCallback(
    async (
      dstEid: number,
      asset: `0x${string}`,
      amount: bigint,
      collateralSlots: ChainAsset[],
      debtSlots: ChainAsset[],
      fee: MessagingFee
    ) => {
      if (!address) throw new Error("Wallet not connected");
      try {
        setError(null);

        if (currentChainId !== hubConfig.chainId) {
          setStatus("switching-chain");
          await switchChainAsync({ chainId: hubConfig.chainId });
        }

        const options = buildLzOptions(GAS_LIMITS.borrow);

        setStatus("sending");
        const hash = await sendTx({
          address: hubConfig.hubRouter,
          abi: HUB_ROUTER_ABI,
          functionName: "borrowAndNotify",
          args: [dstEid, asset, amount, collateralSlots, debtSlots, options, fee],
          value: fee.nativeFee,
          chainId: hubConfig.chainId,
        });

        setTxHash(hash);
        setStatus("pending");
        return hash;
      } catch (err: any) {
        setStatus("failed");
        setError(err?.shortMessage || err?.message || "Transaction failed");
        throw err;
      }
    },
    [address, currentChainId, switchChainAsync, sendTx]
  );

  // ─── Withdraw (hub chain) ──────────────────────────────────────────────

  const withdraw = useCallback(
    async (
      dstEid: number,
      asset: `0x${string}`,
      amount: bigint,
      collateralSlots: ChainAsset[],
      debtSlots: ChainAsset[],
      fee: MessagingFee
    ) => {
      if (!address) throw new Error("Wallet not connected");
      try {
        setError(null);

        if (currentChainId !== hubConfig.chainId) {
          setStatus("switching-chain");
          await switchChainAsync({ chainId: hubConfig.chainId });
        }

        const options = buildLzOptions(GAS_LIMITS.withdraw);

        setStatus("sending");
        const hash = await sendTx({
          address: hubConfig.hubRouter,
          abi: HUB_ROUTER_ABI,
          functionName: "withdrawAndNotify",
          args: [dstEid, asset, amount, collateralSlots, debtSlots, options, fee],
          value: fee.nativeFee,
          chainId: hubConfig.chainId,
        });

        setTxHash(hash);
        setStatus("pending");
        return hash;
      } catch (err: any) {
        setStatus("failed");
        setError(err?.shortMessage || err?.message || "Transaction failed");
        throw err;
      }
    },
    [address, currentChainId, switchChainAsync, sendTx]
  );

  // ─── Liquidate (hub chain) ─────────────────────────────────────────────

  const liquidate = useCallback(
    async (
      user: `0x${string}`,
      debtEid: number,
      debtAsset: `0x${string}`,
      debtRepayAmount: bigint,
      seizeEid: number,
      seizeAsset: `0x${string}`,
      collateralSlots: ChainAsset[],
      debtSlots: ChainAsset[],
      fee: MessagingFee
    ) => {
      if (!address) throw new Error("Wallet not connected");
      try {
        setError(null);

        if (currentChainId !== hubConfig.chainId) {
          setStatus("switching-chain");
          await switchChainAsync({ chainId: hubConfig.chainId });
        }

        const options = buildLzOptions(GAS_LIMITS.liquidation);

        setStatus("sending");
        const hash = await sendTx({
          address: hubConfig.liquidationEngine,
          abi: LIQUIDATION_ENGINE_ABI,
          functionName: "liquidate",
          args: [
            user,
            debtEid,
            debtAsset,
            debtRepayAmount,
            seizeEid,
            seizeAsset,
            collateralSlots,
            debtSlots,
            options,
            fee,
          ],
          value: fee.nativeFee,
          chainId: hubConfig.chainId,
        });

        setTxHash(hash);
        setStatus("pending");
        return hash;
      } catch (err: any) {
        setStatus("failed");
        setError(err?.shortMessage || err?.message || "Transaction failed");
        throw err;
      }
    },
    [address, currentChainId, switchChainAsync, sendTx]
  );

  return {
    status,
    error,
    txHash,
    receipt,
    reset,
    approve,
    deposit,
    repay,
    borrow,
    withdraw,
    liquidate,
  };
}

// ─── Hub event watcher — invalidates queries when cross-chain messages land ──

export function useHubEventRefetch() {
  const { address } = useAccount();
  const queryClient = useQueryClient();

  const invalidate = useCallback(() => {
    queryClient.invalidateQueries();
  }, [queryClient]);

  const matchesUser = useCallback(
    (logs: any[]) => {
      if (!address) return;
      for (const log of logs) {
        const user = log.args?.user as string | undefined;
        if (!user || user.toLowerCase() === address.toLowerCase()) {
          invalidate();
          return;
        }
      }
    },
    [address, invalidate]
  );

  // Deposit: PositionBook.CollateralCredited(address user, uint32 eid, address asset, uint256 amount)
  useWatchContractEvent({
    address: hubConfig.positionBook,
    abi: POSITION_BOOK_ABI,
    eventName: "CollateralCredited",
    onLogs: matchesUser,
    enabled: !!address,
  });

  // Repay: HubRouter.RepayFinalized(bytes32 repayId, address user, ...)
  useWatchContractEvent({
    address: hubConfig.hubRouter,
    abi: HUB_ROUTER_ABI,
    eventName: "RepayFinalized",
    onLogs: matchesUser,
    enabled: !!address,
  });

  // Borrow: HubRouter.BorrowFinalized(bytes32 borrowId, address user, bool success)
  useWatchContractEvent({
    address: hubConfig.hubRouter,
    abi: HUB_ROUTER_ABI,
    eventName: "BorrowFinalized",
    onLogs: matchesUser,
    enabled: !!address,
  });

  // Withdraw: HubRouter.WithdrawFinalized(bytes32 withdrawId, address user, bool success)
  useWatchContractEvent({
    address: hubConfig.hubRouter,
    abi: HUB_ROUTER_ABI,
    eventName: "WithdrawFinalized",
    onLogs: matchesUser,
    enabled: !!address,
  });

  // Liquidation: HubRouter.LiquidationFinalized(bytes32 liqId, bool success)
  useWatchContractEvent({
    address: hubConfig.hubRouter,
    abi: HUB_ROUTER_ABI,
    eventName: "LiquidationFinalized",
    onLogs() {
      // LiquidationFinalized doesn't have a user arg, so always invalidate
      invalidate();
    },
    enabled: !!address,
  });
}
