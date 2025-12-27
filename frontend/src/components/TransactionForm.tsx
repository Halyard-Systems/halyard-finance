import { useState, useEffect, useCallback } from "react";
import { Button } from "./ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogDescription,
} from "./ui/dialog";

//const USE_MOCK_PYTH = import.meta.env.VITE_USE_MOCK_PYTH === "true";

import { portfolioData, type MockChainData } from "@/sample-data";
import { ChainPicker } from "./ChainPicker";
import { AssetPicker } from "./AssetPicker";

type ActionName = "Borrow" | "Repay" | "Withdraw" | "Deposit";

interface TransactionFormProps {
  actionDescription: string;
  actionName: ActionName;
  isOpen: boolean;
  onClose: () => void;
  tokenIds?: `0x${string}`[];
  maxTransactable: number;
  handleTransaction: () => void;
  onTransactionComplete?: () => void;
  onTransactionError?: (error: string) => void;
}

export function TransactionForm({
  actionDescription,
  actionName,
  isOpen,
  onClose,
  maxTransactable,
  handleTransaction,
}: TransactionFormProps) {
  const [amount, setAmount] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [selectedChain, setSelectedChain] = useState(portfolioData[0]);
  const [selectedAsset, setSelectedAsset] = useState(selectedChain.assets[0]);

  const toggleChain = useCallback(
    (selectedChain: MockChainData) => {
      setSelectedChain(selectedChain);
      setSelectedAsset(
        selectedChain.assets.find(
          (asset) => asset.ticker === selectedAsset.ticker
        ) || selectedChain.assets[0]
      );
    },
    [selectedAsset]
  );
  // TODO: Handle transaction completion
  // useEffect(() => {
  //   if (isConfirmed) {
  //     // Clear the input and errors after successful borrow
  //     setAmount('')
  //     setError(null)
  //     onClose()
  //     // Trigger data refresh
  //     onTransactionComplete?.()
  //   }
  // }, [isConfirmed, onTransactionComplete, onClose])

  // // Handle transaction errors
  // useEffect(() => {
  //   if (isTransactionError && transactionError) {
  //     const formattedError = formatTransactionError(transactionError.message)
  //     setCustomError(formattedError)
  //     onTransactionError?.(formattedError)
  //   }
  // }, [isTransactionError, transactionError, onTransactionError])

  // Clear errors when modal opens/closes
  useEffect(() => {
    if (isOpen) setError(null);
  }, [isOpen]);

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-md max-h-[90vh] overflow-y-auto overflow-x-hidden">
        <DialogHeader>
          <DialogTitle>
            {actionName} {selectedAsset.ticker}
          </DialogTitle>
          <DialogDescription>{actionDescription}</DialogDescription>
        </DialogHeader>

        <div className="space-y-4 min-w-0">
          <ChainPicker
            portfolioData={portfolioData}
            selectedChain={selectedChain}
            onChainSelect={toggleChain}
          />

          {/* Asset Selection */}
          <AssetPicker
            selectedChain={selectedChain}
            selectedAsset={selectedAsset}
            onAssetSelect={setSelectedAsset}
          />

          {/* Amount Input */}
          <div className="min-w-0">
            <label className="block text-sm font-medium text-card-foreground mb-2">
              Amount ({selectedAsset.ticker})
            </label>
            <input
              type="number"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder={`0.00 ${selectedAsset.ticker}`}
              className="w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground"
              /* TODO: disable input on isTransacting || isConfirming || isUpdatingMockPyth */
              disabled={false}
              max={maxTransactable}
            />
          </div>

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
        </div>

        <DialogFooter className="flex space-x-2">
          <Button variant="outline" onClick={onClose} className="flex-1">
            Cancel
          </Button>
          <Button
            onClick={handleTransaction}
            disabled={false}
            className="flex-1"
          >
            {`${actionName} ${selectedAsset.ticker}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
