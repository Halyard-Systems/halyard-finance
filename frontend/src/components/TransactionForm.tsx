import { useState, useEffect, useCallback, useMemo } from "react";
import { useAccount, useReadContract } from "wagmi";
import { parseUnits, formatUnits, type Abi } from "viem";
import { Button } from "./ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogDescription,
} from "./ui/dialog";

import { spokeConfigs, type SpokeConfig, type SpokeAsset } from "../lib/contracts";
import { ChainPicker } from "./ChainPicker";
import { AssetPicker } from "./AssetPicker";
import { useTransactionFlow } from "../lib/writeHooks";
import { useCanBorrow, useCanWithdraw, useERC20Balance } from "../lib/hooks";
import type { ActionName, ChainAsset, MessagingFee } from "../lib/types";
import ERC20_ABI from "../abis/ERC20.json";

interface TransactionFormProps {
  actionName: ActionName;
  actionDescription: string;
  isOpen: boolean;
  onClose: () => void;
  collateralSlots: ChainAsset[];
  debtSlots: ChainAsset[];
  onTransactionComplete?: () => void;
}

const STATUS_LABELS: Record<string, string> = {
  idle: "",
  "switching-chain": "Switching chain...",
  approving: "Approving token...",
  quoting: "Quoting fee...",
  sending: "Sending transaction...",
  pending: "Waiting for confirmation...",
  confirmed: "Transaction confirmed!",
  failed: "Transaction failed",
};

// Estimated LZ fee (conservative default — users should have enough ETH)
const DEFAULT_LZ_FEE: MessagingFee = {
  nativeFee: parseUnits("0.01", 18),
  lzTokenFee: 0n,
};

export function TransactionForm({
  actionName,
  actionDescription,
  isOpen,
  onClose,
  collateralSlots,
  debtSlots,
  onTransactionComplete,
}: TransactionFormProps) {
  const { address } = useAccount();
  const txFlow = useTransactionFlow();

  const [amount, setAmount] = useState("");
  const [localError, setLocalError] = useState<string | null>(null);

  // Chain & asset selection
  const [selectedSpoke, setSelectedSpoke] = useState<SpokeConfig>(
    spokeConfigs[0]
  );
  const [selectedAsset, setSelectedAsset] = useState<SpokeAsset>(
    spokeConfigs[0]?.assets[0]
  );

  const handleSpokeChange = useCallback(
    (spoke: SpokeConfig) => {
      setSelectedSpoke(spoke);
      // Try to find the same asset on the new chain, else first asset
      const sameAsset = spoke.assets.find(
        (a) => a.symbol === selectedAsset?.symbol
      );
      setSelectedAsset(sameAsset || spoke.assets[0]);
    },
    [selectedAsset]
  );

  // Parse amount to bigint
  const parsedAmount = useMemo(() => {
    if (!amount || !selectedAsset) return undefined;
    try {
      return parseUnits(amount, selectedAsset.decimals);
    } catch {
      return undefined;
    }
  }, [amount, selectedAsset]);

  // Risk preview for borrow/withdraw
  const canBorrowResult = useCanBorrow(
    address,
    actionName === "Borrow" ? selectedSpoke?.lzEid : undefined,
    actionName === "Borrow" ? selectedAsset?.canonicalAddress : undefined,
    actionName === "Borrow" ? parsedAmount : undefined,
    collateralSlots,
    debtSlots
  );

  const canWithdrawResult = useCanWithdraw(
    address,
    actionName === "Withdraw" ? selectedSpoke?.lzEid : undefined,
    actionName === "Withdraw" ? selectedAsset?.canonicalAddress : undefined,
    actionName === "Withdraw" ? parsedAmount : undefined,
    collateralSlots,
    debtSlots
  );

  // Wallet balance for selected asset
  const balanceResult = useERC20Balance(
    selectedAsset?.spokeAddress,
    address,
    selectedSpoke?.chainId,
    selectedSpoke?.lzEid
  );

  const walletBalance = balanceResult.data as bigint | undefined;
  const balanceLoading = balanceResult.isLoading;

  // Determine the spender that needs approval (deposit → collateralVault, repay → liquidityVault)
  const needsApproval = actionName === "Deposit" || actionName === "Repay";
  const spenderAddress = useMemo(() => {
    if (!selectedSpoke || !needsApproval) return undefined;
    return actionName === "Deposit"
      ? selectedSpoke.collateralVault
      : selectedSpoke.liquidityVault;
  }, [selectedSpoke, actionName, needsApproval]);

  // Read current allowance
  const allowanceResult = useReadContract({
    address: selectedAsset?.spokeAddress,
    abi: ERC20_ABI as Abi,
    functionName: "allowance",
    args: address && spenderAddress ? [address, spenderAddress] : undefined,
    chainId: selectedSpoke?.chainId,
    query: { enabled: !!selectedAsset && !!address && !!spenderAddress },
  });
  const currentAllowance = (allowanceResult.data as bigint) ?? 0n;
  const needsApprovalStep =
    needsApproval && parsedAmount !== undefined && parsedAmount > 0n && currentAllowance < parsedAmount;

  const formattedBalance = useMemo(() => {
    if (!selectedAsset) return undefined;
    if (walletBalance === undefined) return undefined;
    return formatUnits(walletBalance, selectedAsset.decimals);
  }, [walletBalance, selectedAsset]);

  // Projected health factor display
  const projectedHF = useMemo(() => {
    if (actionName === "Borrow" && parsedAmount && parsedAmount > 0n) {
      return canBorrowResult.nextHealthFactorE18;
    }
    if (actionName === "Withdraw" && parsedAmount && parsedAmount > 0n) {
      return canWithdrawResult.nextHealthFactorE18;
    }
    return undefined;
  }, [actionName, parsedAmount, canBorrowResult, canWithdrawResult]);

  const riskOk = useMemo(() => {
    if (actionName === "Borrow") return canBorrowResult.ok;
    if (actionName === "Withdraw") return canWithdrawResult.ok;
    return true;
  }, [actionName, canBorrowResult.ok, canWithdrawResult.ok]);

  // Estimated LZ fee display
  const estimatedFeeEth = Number(DEFAULT_LZ_FEE.nativeFee) / 1e18;

  // Clear state when modal opens
  useEffect(() => {
    if (isOpen) {
      setAmount("");
      setLocalError(null);
      txFlow.reset();
    }
  }, [isOpen]);

  // Refetch allowance after approval confirms
  useEffect(() => {
    if (txFlow.status === "confirmed") {
      allowanceResult.refetch();
    }
  }, [txFlow.status]);

  // Auto-close on confirmed (only for the main tx, not approval)
  useEffect(() => {
    if (txFlow.status === "confirmed" && !needsApprovalStep) {
      onTransactionComplete?.();
      setTimeout(onClose, 1500);
    }
  }, [txFlow.status, needsApprovalStep, onTransactionComplete, onClose]);

  const handleApprove = async () => {
    if (!selectedSpoke || !selectedAsset || !spenderAddress) return;
    setLocalError(null);
    try {
      await txFlow.approve(
        selectedAsset.spokeAddress,
        spenderAddress,
        selectedSpoke.chainId
      );
    } catch {
      // Error captured in txFlow
    }
  };

  const handleSubmit = async () => {
    if (!address || !selectedSpoke || !selectedAsset || !parsedAmount) {
      setLocalError("Please enter a valid amount");
      return;
    }

    if (parsedAmount <= 0n) {
      setLocalError("Amount must be greater than 0");
      return;
    }

    // Validate risk for borrow/withdraw
    if ((actionName === "Borrow" || actionName === "Withdraw") && !riskOk) {
      setLocalError("Insufficient collateral for this operation");
      return;
    }

    setLocalError(null);
    txFlow.reset();

    try {
      const fee = DEFAULT_LZ_FEE;

      switch (actionName) {
        case "Deposit":
          await txFlow.deposit(
            selectedSpoke,
            selectedAsset.canonicalAddress,
            parsedAmount,
            fee
          );
          break;

        case "Repay":
          await txFlow.repay(
            selectedSpoke,
            selectedAsset.spokeAddress,
            parsedAmount,
            address,
            fee
          );
          break;

        case "Borrow":
          await txFlow.borrow(
            selectedSpoke.lzEid,
            selectedAsset.canonicalAddress,
            parsedAmount,
            collateralSlots,
            debtSlots,
            fee
          );
          break;

        case "Withdraw":
          await txFlow.withdraw(
            selectedSpoke.lzEid,
            selectedAsset.canonicalAddress,
            parsedAmount,
            collateralSlots,
            debtSlots,
            fee
          );
          break;
      }
    } catch {
      // Error is already captured in txFlow
    }
  };

  const isProcessing = ["switching-chain", "approving", "quoting", "sending", "pending"].includes(
    txFlow.status
  );

  const error = localError || txFlow.error;

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-md max-h-[90vh] overflow-y-auto overflow-x-hidden">
        <DialogHeader>
          <DialogTitle>
            {actionName} {selectedAsset?.symbol}
          </DialogTitle>
          <DialogDescription>{actionDescription}</DialogDescription>
        </DialogHeader>

        <div className="space-y-4 min-w-0">
          {/* Chain Selection */}
          {spokeConfigs.length > 0 && (
            <ChainPicker
              spokes={spokeConfigs}
              selectedSpoke={selectedSpoke}
              onChainSelect={handleSpokeChange}
            />
          )}

          {/* Asset Selection */}
          {selectedSpoke && selectedAsset && (
            <AssetPicker
              selectedSpoke={selectedSpoke}
              selectedAsset={selectedAsset}
              onAssetSelect={setSelectedAsset}
            />
          )}

          {/* Amount Input */}
          <div className="min-w-0">
            <div className="flex items-center justify-between mb-2">
              <label className="block text-sm font-medium text-card-foreground">
                Amount ({selectedAsset?.symbol})
              </label>
              {address && (
                <span className="text-xs text-muted-foreground">
                  Available:{" "}
                  {balanceLoading ? (
                    <span className="animate-pulse">...</span>
                  ) : formattedBalance !== undefined ? (
                    <button
                      type="button"
                      className="text-primary hover:underline"
                      onClick={() => setAmount(formattedBalance)}
                      disabled={isProcessing}
                    >
                      {Number(formattedBalance).toLocaleString(undefined, {
                        maximumFractionDigits: 6,
                      })}{" "}
                      {selectedAsset?.symbol}
                    </button>
                  ) : (
                    <span>0 {selectedAsset?.symbol}</span>
                  )}
                </span>
              )}
            </div>
            <input
              type="number"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder={`0.00 ${selectedAsset?.symbol}`}
              className="w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground"
              disabled={isProcessing}
            />
          </div>

          {/* LZ Fee Estimate */}
          {(actionName === "Deposit" || actionName === "Borrow" || actionName === "Withdraw") && (
            <div className="text-xs text-muted-foreground">
              Estimated cross-chain fee: ~{estimatedFeeEth.toFixed(4)} ETH
            </div>
          )}

          {/* Projected Health Factor */}
          {projectedHF !== undefined && projectedHF > 0n && parsedAmount && parsedAmount > 0n && (
            <div className="text-sm">
              <span className="text-muted-foreground">Projected Health Factor: </span>
              <span
                className={
                  Number(projectedHF) / 1e18 > 1.5
                    ? "text-green-600 font-medium"
                    : Number(projectedHF) / 1e18 >= 1.0
                    ? "text-yellow-500 font-medium"
                    : "text-red-600 font-medium"
                }
              >
                {(Number(projectedHF) / 1e18).toFixed(2)}
              </span>
              {!riskOk && (
                <span className="text-red-600 ml-2 text-xs">
                  (insufficient collateral)
                </span>
              )}
            </div>
          )}

          {/* Chain switching notice */}
          {txFlow.status === "switching-chain" && (
            <div className="text-sm text-blue-600 bg-blue-50 dark:bg-blue-900/20 p-3 rounded-md">
              Please confirm the chain switch in your wallet...
            </div>
          )}

          {/* Status Display */}
          {txFlow.status !== "idle" && txFlow.status !== "failed" && (
            <div className="text-sm text-muted-foreground">
              {STATUS_LABELS[txFlow.status]}
            </div>
          )}

          {/* Error Display */}
          {error && (
            <div className="text-sm text-red-500 bg-red-50 dark:bg-red-900/20 p-3 rounded-md min-w-0 overflow-x-hidden">
              <div className="flex items-start space-x-2">
                <div className="flex-shrink-0 mt-0.5">
                  <svg
                    className="w-4 h-4"
                    fill="currentColor"
                    viewBox="0 0 20 20"
                  >
                    <path
                      fillRule="evenodd"
                      d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z"
                      clipRule="evenodd"
                    />
                  </svg>
                </div>
                <div className="flex-1 break-words break-all whitespace-pre-wrap leading-relaxed">
                  {error}
                </div>
              </div>
            </div>
          )}

          {/* Success Display */}
          {txFlow.status === "confirmed" && (
            <div className="text-sm text-green-600 bg-green-50 dark:bg-green-900/20 p-3 rounded-md">
              Transaction confirmed!
              {txFlow.txHash && (
                <span className="block text-xs mt-1 font-mono">
                  {txFlow.txHash.slice(0, 10)}...{txFlow.txHash.slice(-8)}
                </span>
              )}
            </div>
          )}
        </div>

        <DialogFooter className="flex space-x-2">
          <Button variant="outline" onClick={onClose} className="flex-1" disabled={isProcessing}>
            Cancel
          </Button>
          {needsApprovalStep ? (
            <Button
              onClick={handleApprove}
              disabled={isProcessing || !parsedAmount}
              className="flex-1"
            >
              {isProcessing
                ? STATUS_LABELS[txFlow.status]
                : `Approve ${selectedAsset?.symbol}`}
            </Button>
          ) : (
            <Button
              onClick={handleSubmit}
              disabled={isProcessing || !parsedAmount || txFlow.status === "confirmed"}
              className="flex-1"
            >
              {isProcessing
                ? STATUS_LABELS[txFlow.status]
                : `${actionName} ${selectedAsset?.symbol}`}
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
