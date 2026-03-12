import { useCallback, useState } from "react";
import {
  useWriteContract,
  useSwitchChain,
  useAccount,
  useReadContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { keccak256, encodePacked, type Abi } from "viem";

import ERC20_ABI from "../abis/ERC20.json";
import SPOKE_CONTROLLER_ABI from "../abis/SpokeController.json";
import LIQUIDITY_VAULT_ABI from "../abis/LiquidityVault.json";
import HUB_ROUTER_ABI from "../abis/HubRouter.json";
import LIQUIDATION_ENGINE_ABI from "../abis/LiquidationEngine.json";

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
    abi: ERC20_ABI as Abi,
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
        abi: ERC20_ABI as Abi,
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

  const receipt = useWaitForTransactionReceipt({ hash: txHash });

  const reset = useCallback(() => {
    setStatus("idle");
    setError(null);
    setTxHash(undefined);
  }, []);

  // ─── Deposit (spoke chain) ─────────────────────────────────────────────

  const deposit = useCallback(
    async (
      spoke: SpokeConfig,
      canonicalAsset: `0x${string}`,
      spokeTokenAddress: `0x${string}`,
      amount: bigint,
      fee: MessagingFee
    ) => {
      if (!address) throw new Error("Wallet not connected");
      try {
        setError(null);

        // Switch chain if needed
        if (currentChainId !== spoke.chainId) {
          setStatus("switching-chain");
          await switchChainAsync({ chainId: spoke.chainId });
        }

        // Approve CollateralVault to spend token
        setStatus("approving");
        await writeContractAsync({
          address: spokeTokenAddress,
          abi: ERC20_ABI as Abi,
          functionName: "approve",
          args: [spoke.collateralVault, amount],
          chainId: spoke.chainId,
        });

        // Generate deposit ID
        const depositId = generateOperationId("deposit", address, Date.now());

        // Build LZ options
        const options = buildLzOptions(GAS_LIMITS.deposit);

        // Send deposit tx
        setStatus("sending");
        const hash = await writeContractAsync({
          address: spoke.spokeController,
          abi: SPOKE_CONTROLLER_ABI as Abi,
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
    [address, currentChainId, switchChainAsync, writeContractAsync]
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

        // Approve LiquidityVault
        setStatus("approving");
        await writeContractAsync({
          address: spokeTokenAddress,
          abi: ERC20_ABI as Abi,
          functionName: "approve",
          args: [spoke.liquidityVault, amount],
          chainId: spoke.chainId,
        });

        const repayId = generateOperationId("repay", address, Date.now());

        setStatus("sending");
        const hash = await writeContractAsync({
          address: spoke.liquidityVault,
          abi: LIQUIDITY_VAULT_ABI as Abi,
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
    [address, currentChainId, switchChainAsync, writeContractAsync]
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
        const hash = await writeContractAsync({
          address: hubConfig.hubRouter,
          abi: HUB_ROUTER_ABI as Abi,
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
    [address, currentChainId, switchChainAsync, writeContractAsync]
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
        const hash = await writeContractAsync({
          address: hubConfig.hubRouter,
          abi: HUB_ROUTER_ABI as Abi,
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
    [address, currentChainId, switchChainAsync, writeContractAsync]
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
        const hash = await writeContractAsync({
          address: hubConfig.liquidationEngine,
          abi: LIQUIDATION_ENGINE_ABI as Abi,
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
    [address, currentChainId, switchChainAsync, writeContractAsync]
  );

  return {
    status,
    error,
    txHash,
    receipt,
    reset,
    deposit,
    repay,
    borrow,
    withdraw,
    liquidate,
  };
}
