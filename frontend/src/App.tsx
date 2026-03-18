import { useState } from "react";
import { useAccount } from "wagmi";
import { useQueryClient } from "@tanstack/react-query";

import { Header } from "./components/Header";
import { Connect } from "./components/Connect";
import { AccountSummary } from "./components/AccountSummary";
import { Portfolio } from "./components/Portfolio";
import { QuickActions } from "./components/QuickActions";
import { TransactionForm } from "./components/TransactionForm";
import { Liquidation } from "./components/Liquidation";
import { PendingTransactions } from "./components/PendingTransactions";

import {
  useUserSlots,
  useAccountData,
  useCollateralPositions,
  useDebtPositions,
} from "./lib/hooks";
import { useHubEventRefetch } from "./lib/writeHooks";
import type { ActionName } from "./lib/types";

type Tab = "dashboard" | "liquidation";

function App() {
  const queryClient = useQueryClient();
  const { address, isConnected } = useAccount();

  // Active tab
  const [activeTab, setActiveTab] = useState<Tab>("dashboard");

  // Transaction modals
  const [activeAction, setActiveAction] = useState<ActionName | null>(null);

  // Read user's position slots from hub chain
  const {
    collateralSlots,
    debtSlots,
    isLoading: slotsLoading,
  } = useUserSlots(address as `0x${string}` | undefined);

  // Account summary data from RiskEngine
  const { accountData, isLoading: accountLoading } = useAccountData(
    address as `0x${string}` | undefined,
    collateralSlots,
    debtSlots
  );

  // Detailed position data
  const { positions: collateralPositions, isLoading: collateralLoading } =
    useCollateralPositions(
      address as `0x${string}` | undefined,
      collateralSlots
    );

  const { positions: debtPositions, isLoading: debtLoading } = useDebtPositions(
    address as `0x${string}` | undefined,
    debtSlots
  );

  // Watch hub-chain events to refetch data when cross-chain messages land
  useHubEventRefetch();

  const handleTransactionComplete = () => {
    queryClient.invalidateQueries();
  };

  const openModal = (action: ActionName) => setActiveAction(action);
  const closeModal = () => setActiveAction(null);

  return (
    <div className="min-h-screen bg-background">
      <Header />

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {isConnected ? (
          <>
            {/* Tab Navigation */}
            <div className="flex gap-4 mb-6">
              <button
                onClick={() => setActiveTab("dashboard")}
                className={`px-4 py-2 rounded-md text-sm font-medium transition-colors ${
                  activeTab === "dashboard"
                    ? "bg-primary text-primary-foreground"
                    : "bg-muted text-muted-foreground hover:bg-muted/80"
                }`}
              >
                Dashboard
              </button>
              <button
                onClick={() => setActiveTab("liquidation")}
                className={`px-4 py-2 rounded-md text-sm font-medium transition-colors ${
                  activeTab === "liquidation"
                    ? "bg-primary text-primary-foreground"
                    : "bg-muted text-muted-foreground hover:bg-muted/80"
                }`}
              >
                Liquidation
              </button>
            </div>

            {activeTab === "dashboard" && (
              <>
                <AccountSummary
                  accountData={accountData}
                  isLoading={accountLoading || slotsLoading}
                />
                <Portfolio
                  collateralPositions={collateralPositions}
                  debtPositions={debtPositions}
                  isLoading={collateralLoading || debtLoading || slotsLoading}
                />
                <QuickActions
                  onDeposit={() => openModal("Deposit")}
                  onWithdraw={() => openModal("Withdraw")}
                  onBorrow={() => openModal("Borrow")}
                  onRepay={() => openModal("Repay")}
                />
              </>
            )}

            {activeTab === "liquidation" && <Liquidation />}

            {/* Transaction Modal */}
            {activeAction && (
              <TransactionForm
                isOpen={!!activeAction}
                onClose={closeModal}
                actionName={activeAction}
                actionDescription={getActionDescription(activeAction)}
                collateralSlots={collateralSlots}
                debtSlots={debtSlots}
                collateralPositions={collateralPositions}
                debtPositions={debtPositions}
                accountData={accountData}
                onTransactionComplete={handleTransactionComplete}
              />
            )}

            {/* Pending Transaction Notifications */}
            <PendingTransactions />
          </>
        ) : (
          <Connect />
        )}
      </main>
    </div>
  );
}

function getActionDescription(action: ActionName): string {
  switch (action) {
    case "Deposit":
      return "Deposit collateral on a spoke chain. Your deposit will be tracked on the hub chain.";
    case "Withdraw":
      return "Withdraw collateral from a spoke chain. Requires sufficient health factor.";
    case "Borrow":
      return "Borrow assets against your deposited collateral. Funds will be sent to the spoke chain.";
    case "Repay":
      return "Repay borrowed assets on a spoke chain to reduce your debt.";
  }
}

export default App;
