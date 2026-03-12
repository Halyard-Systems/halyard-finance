import { useSelector, useDispatch } from "react-redux";
import { useEffect } from "react";
import { useWatchContractEvent } from "wagmi";
import type { Abi } from "viem";

import HUB_ROUTER_ABI from "../abis/HubRouter.json";
import { hubConfig } from "../lib/contracts";
import type { RootState } from "../store/store";
import {
  updateTransactionStatus,
  removeTransaction,
} from "../store/reducers/pendingTransactions";

export function PendingTransactions() {
  const dispatch = useDispatch();
  const transactions = useSelector(
    (state: RootState) => state.pendingTransactions.transactions
  );

  const pendingTxs = transactions.filter((t) => t.status === "pending");

  // Watch for BorrowFinalized events
  useWatchContractEvent({
    address: hubConfig.hubRouter,
    abi: HUB_ROUTER_ABI as Abi,
    eventName: "BorrowFinalized",
    onLogs(logs) {
      for (const log of logs) {
        const args = (log as any).args;
        if (args?.borrowId) {
          // Find matching pending transaction
          const tx = pendingTxs.find((t) => t.id === args.borrowId);
          if (tx) {
            dispatch(
              updateTransactionStatus({
                txHash: tx.txHash,
                status: args.success ? "confirmed" : "failed",
              })
            );
          }
        }
      }
    },
    enabled: pendingTxs.some((t) => t.type === "borrow"),
  });

  // Watch for WithdrawFinalized events
  useWatchContractEvent({
    address: hubConfig.hubRouter,
    abi: HUB_ROUTER_ABI as Abi,
    eventName: "WithdrawFinalized",
    onLogs(logs) {
      for (const log of logs) {
        const args = (log as any).args;
        if (args?.withdrawId) {
          const tx = pendingTxs.find((t) => t.id === args.withdrawId);
          if (tx) {
            dispatch(
              updateTransactionStatus({
                txHash: tx.txHash,
                status: args.success ? "confirmed" : "failed",
              })
            );
          }
        }
      }
    },
    enabled: pendingTxs.some((t) => t.type === "withdraw"),
  });

  // Auto-dismiss confirmed transactions after 10 seconds
  useEffect(() => {
    const confirmed = transactions.filter((t) => t.status !== "pending");
    for (const tx of confirmed) {
      const timer = setTimeout(() => {
        dispatch(removeTransaction(tx.id));
      }, 10_000);
      return () => clearTimeout(timer);
    }
  }, [transactions, dispatch]);

  if (pendingTxs.length === 0) return null;

  return (
    <div className="fixed bottom-4 right-4 space-y-2 z-50">
      {pendingTxs.map((tx) => (
        <div
          key={tx.id}
          className="bg-card border border-border rounded-lg shadow-lg p-4 max-w-sm animate-in slide-in-from-right"
        >
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 bg-yellow-400 rounded-full animate-pulse" />
            <div className="text-sm font-medium">
              {tx.type.charAt(0).toUpperCase() + tx.type.slice(1)} pending
            </div>
          </div>
          <div className="text-xs text-muted-foreground mt-1">
            Waiting for cross-chain confirmation...
          </div>
          <div className="text-xs text-muted-foreground font-mono mt-1">
            {tx.txHash.slice(0, 10)}...{tx.txHash.slice(-6)}
          </div>
        </div>
      ))}
    </div>
  );
}
