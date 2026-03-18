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

import { spokeConfigs, getSpokeByEid, type SpokeConfig, type SpokeAsset } from "../lib/contracts";
import { ChainPicker } from "./ChainPicker";
import { AssetPicker } from "./AssetPicker";
import { useTransactionFlow } from "../lib/writeHooks";
import { useCanBorrow, useCanWithdraw, useERC20Balance, useAssetPrice, useQuoteDeposit, useQuoteHubCommand, useQuoteRepayReceipt } from "../lib/hooks";
import type { AccountData, ActionName, ChainAsset, CollateralPosition, DebtPosition, MessagingFee } from "../lib/types";
import { fromWei } from "../lib/utils";
import { buildLzOptions, GAS_LIMITS, applyFeeBuffer } from "../lib/layerzero";
import ERC20_ABI from "../abis/ERC20.json";

interface TransactionFormProps {
  actionName: ActionName;
  actionDescription: string;
  isOpen: boolean;
  onClose: () => void;
  collateralSlots: ChainAsset[];
  debtSlots: ChainAsset[];
  collateralPositions?: CollateralPosition[];
  debtPositions?: DebtPosition[];
  accountData?: AccountData;
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

export function TransactionForm({
  actionName,
  actionDescription,
  isOpen,
  onClose,
  collateralSlots,
  debtSlots,
  collateralPositions,
  debtPositions,
  accountData,
  onTransactionComplete,
}: TransactionFormProps) {
  const { address } = useAccount();
  const txFlow = useTransactionFlow();

  const [amount, setAmount] = useState("");
  const [localError, setLocalError] = useState<string | null>(null);

  // For Repay: compute which chains/assets have debt
  const debtEids = useMemo(() => {
    if (actionName !== "Repay" || !debtPositions) return new Set<number>();
    return new Set(debtPositions.filter((d) => d.debt > 0n).map((d) => d.eid));
  }, [actionName, debtPositions]);

  const debtAssetsByEid = useMemo(() => {
    if (actionName !== "Repay" || !debtPositions) return new Map<number, Set<string>>();
    const map = new Map<number, Set<string>>();
    for (const d of debtPositions) {
      if (d.debt <= 0n) continue;
      const set = map.get(d.eid) ?? new Set<string>();
      set.add(d.asset.toLowerCase());
      map.set(d.eid, set);
    }
    return map;
  }, [actionName, debtPositions]);

  // For Repay: filter spokes and assets to only those with debt
  const availableSpokes = useMemo(() => {
    if (actionName !== "Repay") return spokeConfigs;
    return spokeConfigs.filter((s) => debtEids.has(s.lzEid));
  }, [actionName, debtEids]);

  const filteredSpokeForAssets = useCallback(
    (spoke: SpokeConfig): SpokeConfig => {
      if (actionName !== "Repay") return spoke;
      const debtAssets = debtAssetsByEid.get(spoke.lzEid);
      if (!debtAssets) return { ...spoke, assets: [] };
      return {
        ...spoke,
        assets: spoke.assets.filter((a) =>
          debtAssets.has(a.canonicalAddress.toLowerCase())
        ),
      };
    },
    [actionName, debtAssetsByEid]
  );

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
      if (actionName === "Repay") {
        const filtered = filteredSpokeForAssets(spoke);
        const sameAsset = filtered.assets.find(
          (a) => a.symbol === selectedAsset?.symbol
        );
        setSelectedAsset(sameAsset || filtered.assets[0]);
      } else {
        const sameAsset = spoke.assets.find(
          (a) => a.symbol === selectedAsset?.symbol
        );
        setSelectedAsset(sameAsset || spoke.assets[0]);
      }
    },
    [selectedAsset, actionName, filteredSpokeForAssets]
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

  // For withdraw: find matching collateral position's available amount
  const withdrawableBalance = useMemo(() => {
    if (actionName !== "Withdraw" || !selectedSpoke || !selectedAsset || !collateralPositions) {
      return undefined;
    }
    const match = collateralPositions.find(
      (p) =>
        p.eid === selectedSpoke.lzEid &&
        p.asset.toLowerCase() === selectedAsset.canonicalAddress.toLowerCase()
    );
    return match?.available;
  }, [actionName, selectedSpoke, selectedAsset, collateralPositions]);

  // For repay: find matching debt position amount
  const repayableBalance = useMemo(() => {
    if (actionName !== "Repay" || !selectedSpoke || !selectedAsset || !debtPositions) {
      return undefined;
    }
    const match = debtPositions.find(
      (d) =>
        d.eid === selectedSpoke.lzEid &&
        d.asset.toLowerCase() === selectedAsset.canonicalAddress.toLowerCase()
    );
    return match?.debt;
  }, [actionName, selectedSpoke, selectedAsset, debtPositions]);

  // For borrow: calculate max borrowable from borrow power and asset price
  const assetPrice = useAssetPrice(
    actionName === "Borrow" ? selectedAsset?.canonicalAddress : undefined
  );

  const borrowableBalance = useMemo(() => {
    if (actionName !== "Borrow" || !accountData || !selectedAsset || !assetPrice.priceE18) {
      return undefined;
    }
    const { borrowPowerE18, debtValueE18 } = accountData;
    // Remaining borrow power = borrowPower - existing debt (both in USD E18)
    const remainingPowerE18 = borrowPowerE18 > debtValueE18
      ? borrowPowerE18 - debtValueE18
      : 0n;
    if (remainingPowerE18 === 0n) return 0n;
    // Convert USD value to token amount: remainingPower / price, adjusted for decimals
    return remainingPowerE18 * 10n ** BigInt(selectedAsset.decimals) / assetPrice.priceE18;
  }, [actionName, accountData, selectedAsset, assetPrice.priceE18]);

  const displayBalance = actionName === "Withdraw"
    ? withdrawableBalance
    : actionName === "Borrow"
    ? borrowableBalance
    : actionName === "Repay"
    ? repayableBalance
    : walletBalance;

  const formattedBalance = useMemo(() => {
    if (!selectedAsset) return undefined;
    if (displayBalance === undefined) return undefined;
    return formatUnits(displayBalance, selectedAsset.decimals);
  }, [displayBalance, selectedAsset]);

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

  // LZ options and fee quoting
  const lzOptions = useMemo(() => {
    switch (actionName) {
      case "Deposit": return buildLzOptions(GAS_LIMITS.deposit);
      case "Borrow": return buildLzOptions(GAS_LIMITS.borrow);
      case "Withdraw": return buildLzOptions(GAS_LIMITS.withdraw);
      case "Repay": return undefined; // repay receipt uses empty options
    }
  }, [actionName]);

  const depositQuote = useQuoteDeposit(
    actionName === "Deposit" ? selectedSpoke?.spokeController : undefined,
    actionName === "Deposit" ? selectedSpoke?.chainId : undefined,
    actionName === "Deposit" ? lzOptions : undefined
  );

  const hubCommandQuote = useQuoteHubCommand(
    actionName === "Borrow" || actionName === "Withdraw" ? selectedSpoke?.lzEid : undefined,
    actionName === "Borrow" || actionName === "Withdraw" ? lzOptions : undefined
  );

  const repayQuote = useQuoteRepayReceipt(
    actionName === "Repay" ? selectedSpoke?.spokeController : undefined,
    actionName === "Repay" ? selectedSpoke?.chainId : undefined
  );

  const { quotedFee, feeLoading, feeError } = useMemo(() => {
    let raw: MessagingFee | undefined;
    let loading = false;
    let error = false;
    switch (actionName) {
      case "Deposit":
        raw = depositQuote.fee;
        loading = depositQuote.isLoading;
        error = depositQuote.isError;
        break;
      case "Borrow":
      case "Withdraw":
        raw = hubCommandQuote.fee;
        loading = hubCommandQuote.isLoading;
        error = hubCommandQuote.isError;
        break;
      case "Repay":
        raw = repayQuote.fee;
        loading = repayQuote.isLoading;
        error = repayQuote.isError;
        break;
    }
    return {
      quotedFee: raw ? applyFeeBuffer(raw) : undefined,
      feeLoading: loading,
      feeError: error,
    };
  }, [actionName, depositQuote, hubCommandQuote, repayQuote]);

  const estimatedFeeEth = quotedFee ? Number(quotedFee.nativeFee) / 1e18 : undefined;

  // Clear state when modal opens; for Repay auto-select first debt position
  useEffect(() => {
    if (isOpen) {
      setAmount("");
      setLocalError(null);
      txFlow.reset();

      if (actionName === "Repay" && availableSpokes.length > 0) {
        const firstSpoke = availableSpokes[0];
        setSelectedSpoke(firstSpoke);
        const filtered = filteredSpokeForAssets(firstSpoke);
        if (filtered.assets.length > 0) {
          setSelectedAsset(filtered.assets[0]);
        }
      }
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

    if (!quotedFee) {
      setLocalError("Unable to quote cross-chain fee. Please try again.");
      return;
    }

    setLocalError(null);
    txFlow.reset();

    try {
      const fee = quotedFee;

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
          {/* Debt Summary for Repay */}
          {actionName === "Repay" && debtPositions && debtPositions.some((d) => d.debt > 0n) && (
            <div className="space-y-2">
              <label className="block text-sm font-medium text-card-foreground">
                Outstanding Debts
              </label>
              <div className="border border-input rounded-md divide-y divide-input">
                {debtPositions
                  .filter((d) => d.debt > 0n)
                  .map((d) => {
                    const spoke = getSpokeByEid(d.eid);
                    const asset = spoke?.assets.find(
                      (a) => a.canonicalAddress.toLowerCase() === d.asset.toLowerCase()
                    );
                    const isSelected =
                      selectedSpoke?.lzEid === d.eid &&
                      selectedAsset?.canonicalAddress.toLowerCase() === d.asset.toLowerCase();
                    return (
                      <button
                        key={`${d.eid}-${d.asset}`}
                        type="button"
                        className={`w-full px-3 py-2 flex items-center justify-between text-sm transition-colors ${
                          isSelected
                            ? "bg-primary/10 text-primary"
                            : "hover:bg-muted text-foreground"
                        }`}
                        onClick={() => {
                          if (spoke) {
                            setSelectedSpoke(spoke);
                            if (asset) setSelectedAsset(asset);
                          }
                        }}
                        disabled={isProcessing}
                      >
                        <div className="flex items-center gap-2">
                          {spoke && (
                            <img src={spoke.logo} alt={spoke.name} className="w-4 h-4" />
                          )}
                          <span>{spoke?.name ?? `Chain ${d.eid}`}</span>
                          {asset && (
                            <>
                              <span className="text-muted-foreground">/</span>
                              <img src={asset.icon} alt={asset.symbol} className="w-3 h-3" />
                              <span>{asset.symbol}</span>
                            </>
                          )}
                        </div>
                        <span className="font-medium text-red-600">
                          {fromWei(d.debt, asset?.decimals ?? 18).toLocaleString(undefined, {
                            maximumFractionDigits: 6,
                          })}{" "}
                          {asset?.symbol ?? ""}
                        </span>
                      </button>
                    );
                  })}
              </div>
            </div>
          )}

          {/* No debt notice for Repay */}
          {actionName === "Repay" && (!debtPositions || !debtPositions.some((d) => d.debt > 0n)) && (
            <div className="text-sm text-muted-foreground bg-muted p-3 rounded-md text-center">
              No outstanding debts to repay.
            </div>
          )}

          {/* Chain Selection */}
          {(actionName !== "Repay" ? spokeConfigs.length > 0 : availableSpokes.length > 0) && (
            <ChainPicker
              spokes={actionName === "Repay" ? availableSpokes : spokeConfigs}
              selectedSpoke={selectedSpoke}
              onChainSelect={handleSpokeChange}
            />
          )}

          {/* Asset Selection */}
          {selectedSpoke && selectedAsset && (
            <AssetPicker
              selectedSpoke={actionName === "Repay" ? filteredSpokeForAssets(selectedSpoke) : selectedSpoke}
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
                  {actionName === "Repay" ? "Owed:" : "Available:"}{" "}
                  {(balanceLoading || assetPrice.isLoading) && actionName !== "Withdraw" ? (
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
          <div className="text-xs text-muted-foreground">
            {feeLoading ? (
              <span className="animate-pulse">Quoting cross-chain fee...</span>
            ) : feeError ? (
              <span className="text-red-500">Unable to quote fee</span>
            ) : estimatedFeeEth !== undefined ? (
              <>Estimated cross-chain fee: ~{estimatedFeeEth.toFixed(4)} ETH</>
            ) : null}
          </div>

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
              disabled={isProcessing || !parsedAmount || txFlow.status === "confirmed" || feeLoading || !quotedFee}
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
