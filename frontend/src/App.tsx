import { useMemo, useState } from "react";
import { useAccount } from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { DepositForm } from "./components/DepositForm";
import { WithdrawForm } from "./components/WithdrawForm";
import { MarketTable } from "./components/MarketTable";
import { Header } from "./components/Header";
import { Connect } from "./components/Connect";
import { BorrowForm } from "./components/BorrowForm";
import {
  useReadAssets,
  useReadDepositManagerBalances,
  useReadBorrowManagerBalances,
  useReadBorrowIndices,
  useReadRay,
  useReadSupportedTokens,
  useReadTotalBorrowScaled,
} from "./lib/hooks";
import type { Asset, Token } from "./lib/types";

// Import both token files
import MAINNET_TOKENS from "./tokens.json";
import SEPOLIA_TOKENS from "./tokens_sepolia.json";

const network = import.meta.env.VITE_NETWORK;

// Function to get tokens based on network
const getTokens = (): Token[] => {
  if (network === "sepolia") {
    return SEPOLIA_TOKENS;
  }
  // Default to mainnet tokens
  return MAINNET_TOKENS;
};
import { RepayForm } from "./components/RepayForm";
import { TestnetInstructions } from "./components/TestnetInstructions";

const buildMarketRows = (
  assets: Asset[],
  tokens: Token[],
  tokenIdMap: Map<string, `0x${string}`>,
  userDeposits: bigint[],
  userBorrows: bigint[],
  totalBorrowScaledValues: bigint[],
  borrowIndicesValues: bigint[],
  setSelectedToken: (token: Token) => void,
  setIsDepositModalOpen: (isOpen: boolean) => void,
  setIsWithdrawModalOpen: (isOpen: boolean) => void,
  setIsBorrowModalOpen: (isOpen: boolean) => void,
  setIsRepayModalOpen: (isOpen: boolean) => void
) => {
  if (!assets) return [];

  return assets.map((asset, index) => {
    const token = tokens.find((token) => token.symbol === asset.symbol);
    const tokenId = tokenIdMap.get(token!.symbol);
    const userDeposit = userDeposits[index];
    const userBorrow = userBorrows[index];
    const totalBorrowScaled = totalBorrowScaledValues[index] || 0n;
    const storedBorrowIndex = borrowIndicesValues[index] || 0n;

    const { depositApy, borrowApy } = calculateAPY(asset);

    // Calculate actual total deposits with accrued interest
    const actualTotalDeposits = calculateActualTotalDeposits(asset);

    // Calculate actual total borrows with accrued interest
    const actualTotalBorrows = calculateActualTotalBorrows(
      asset,
      totalBorrowScaled,
      storedBorrowIndex
    );

    return {
      token: token!,
      tokenId,
      deposits: actualTotalDeposits,
      borrows: actualTotalBorrows,
      depositApy,
      borrowApy,
      userDeposit,
      userBorrow,
      onDeposit: () => {
        setSelectedToken(token!);
        setIsDepositModalOpen(true);
      },
      onWithdraw: () => {
        setSelectedToken(token!);
        setIsWithdrawModalOpen(true);
      },
      onBorrow: () => {
        setSelectedToken(token!);
        setIsBorrowModalOpen(true);
      },
      onRepay: () => {
        setSelectedToken(token!);
        setIsRepayModalOpen(true);
      },
    };
  });
};

const RAY = 1000000000000000000000000000n; // 1e27

// Calculate supply rate using the contract's interest rate model
const calculateSupplyRate = (
  U: bigint,
  baseRate: bigint,
  slope1: bigint,
  slope2: bigint,
  kink: bigint,
  reserveFactor: bigint
): bigint => {
  let borrowRate: bigint;
  const ONE_E18 = 1000000000000000000n; // 1e18

  if (U <= kink) {
    borrowRate = baseRate + (slope1 * U) / kink;
  } else {
    borrowRate = baseRate + slope1 + (slope2 * (U - kink)) / (ONE_E18 - kink);
  }

  return (borrowRate * (RAY - reserveFactor)) / RAY;
};

// Calculate the current liquidity index (same as contract's _getCurrentLiquidityIndex)
const getCurrentLiquidityIndex = (asset: Asset): bigint => {
  const now = BigInt(Math.floor(Date.now() / 1000));
  const delta = now - asset.lastUpdateTimestamp;

  if (delta === 0n) {
    return asset.liquidityIndex;
  }

  if (asset.totalDeposits === 0n) {
    return asset.liquidityIndex;
  }

  const ONE_E18 = 1000000000000000000n; // 1e18
  const SECONDS_PER_YEAR = 31536000n; // 365 days

  // Calculate utilization: U = totalBorrows * 1e18 / (totalDeposits + totalBorrows)
  const U =
    (asset.totalBorrows * ONE_E18) / (asset.totalDeposits + asset.totalBorrows);

  const supplyRate = calculateSupplyRate(
    U,
    asset.baseRate,
    asset.slope1,
    asset.slope2,
    asset.kink,
    asset.reserveFactor
  );

  const accrued = (supplyRate * delta) / SECONDS_PER_YEAR;

  return (asset.liquidityIndex * (RAY + accrued)) / RAY;
};

// Calculate the actual total deposits with accrued interest
const calculateActualTotalDeposits = (asset: Asset): bigint => {
  const currentLiquidityIndex = getCurrentLiquidityIndex(asset);
  return (asset.totalScaledSupply * currentLiquidityIndex) / RAY;
};

// Calculate borrow rate using the contract's interest rate model (without reserve factor)
const calculateBorrowRate = (
  U: bigint,
  baseRate: bigint,
  slope1: bigint,
  slope2: bigint,
  kink: bigint
): bigint => {
  let borrowRate: bigint;
  const ONE_E18 = 1000000000000000000n; // 1e18

  if (U <= kink) {
    borrowRate = baseRate + (slope1 * U) / kink;
  } else {
    borrowRate = baseRate + slope1 + (slope2 * (U - kink)) / (ONE_E18 - kink);
  }

  return borrowRate;
};

// Calculate the current borrow index (same as contract's _updateBorrowIndex)
const getCurrentBorrowIndex = (
  asset: Asset,
  storedBorrowIndex: bigint
): bigint => {
  const now = BigInt(Math.floor(Date.now() / 1000));
  const delta = now - asset.lastUpdateTimestamp;

  if (delta === 0n) {
    return storedBorrowIndex;
  }

  const ONE_E18 = 1000000000000000000n; // 1e18
  const SECONDS_PER_YEAR = 31536000n; // 365 days

  // Handle case where totalDeposits is 0 to avoid division by zero
  let U: bigint;
  if (asset.totalDeposits === 0n) {
    U = 0n;
  } else {
    U = (asset.totalBorrows * ONE_E18) / asset.totalDeposits;
  }

  const borrowRate = calculateBorrowRate(
    U,
    asset.baseRate,
    asset.slope1,
    asset.slope2,
    asset.kink
  );

  const accrued = (borrowRate * delta) / SECONDS_PER_YEAR;

  return (storedBorrowIndex * (RAY + accrued)) / RAY;
};

// Calculate the actual total borrows with accrued interest
const calculateActualTotalBorrows = (
  asset: Asset,
  totalBorrowScaled: bigint,
  storedBorrowIndex: bigint
): bigint => {
  // If no stored borrow index, use RAY as default (matches contract initialization)
  const effectiveBorrowIndex =
    storedBorrowIndex === 0n ? RAY : storedBorrowIndex;
  const currentBorrowIndex = getCurrentBorrowIndex(asset, effectiveBorrowIndex);
  return (totalBorrowScaled * currentBorrowIndex) / RAY;
};

// TODO: Replace with contract interest rate model
// Calculate APY from asset data
const calculateAPY = (
  asset: Asset | undefined
): { depositApy: number; borrowApy: number } => {
  if (!asset || asset.totalDeposits === 0n) {
    return { depositApy: 0, borrowApy: 0 };
  }

  // Calculate utilization rate
  const utilization =
    Number((asset.totalBorrows * 10000n) / asset.totalDeposits) / 10000;

  // Simple APY calculation based on utilization
  // In a real implementation, you'd use the contract's interest rate model
  const baseRate = 0.025; // 2.5% base rate
  const utilizationMultiplier = 1 + utilization * 2; // Higher utilization = higher rates

  const depositApy = baseRate * utilizationMultiplier * 100;
  const borrowApy = depositApy * 1.5; // Borrow rate is typically higher than deposit rate

  return { depositApy, borrowApy };
};

function App() {
  const queryClient = useQueryClient();
  const { address, isConnected, chainId } = useAccount();

  // Check if connected to Sepolia
  const isSepolia = chainId === 11155111;

  // Supported tokens
  const { data: tokenIds } = useReadSupportedTokens();

  // Map the token symbols to their IDs
  const tokenIdMap = useMemo(() => {
    const tokenMap = new Map<string, `0x${string}`>();
    if (!tokenIds || !Array.isArray(tokenIds)) return tokenMap;

    const tokens = getTokens();
    tokens.forEach((token, index) => {
      const tokenId = tokenIds[index];
      if (tokenId) {
        tokenMap.set(token.symbol, tokenId as `0x${string}`);
      }
    });
    return tokenMap;
  }, [tokenIds]);

  // Asset data
  const { data: assets } = useReadAssets(tokenIds as `0x${string}`[]);

  // Deposits
  const { data: depositManagerBalances } = useReadDepositManagerBalances(
    address! as `0x${string}`,
    tokenIds as `0x${string}`[]
  );

  // Borrows (scaled)
  const { data: borrowManagerBalances } = useReadBorrowManagerBalances(
    address! as `0x${string}`,
    tokenIds as `0x${string}`[]
  );

  // Borrow indices
  const { data: borrowIndices } = useReadBorrowIndices(
    tokenIds as `0x${string}`[]
  );

  // Total scaled borrows
  const { data: totalBorrowScaled } = useReadTotalBorrowScaled(
    tokenIds as `0x${string}`[]
  );

  // RAY constant
  const { data: ray } = useReadRay();

  // Calculate actual borrowed amounts
  const actualBorrows = useMemo(() => {
    if (
      !borrowManagerBalances ||
      !borrowIndices ||
      !ray ||
      !tokenIds ||
      !Array.isArray(tokenIds)
    ) {
      return new Array(0).fill(0n);
    }

    return borrowManagerBalances.map((balance, index) => {
      const scaledBorrow = BigInt((balance as any).result || 0);
      const borrowIndex = BigInt((borrowIndices[index] as any).result || 0);
      const rayValue = BigInt((ray as any) || 0);

      // If no borrows, return 0
      if (scaledBorrow === 0n) {
        return 0n;
      }

      // If borrow index is 0, it means no borrows have happened yet
      // In this case, use RAY as the borrow index (matches contract initialization)
      const effectiveBorrowIndex = borrowIndex === 0n ? rayValue : borrowIndex;

      // Calculate actual borrow: (scaledBorrow * effectiveBorrowIndex) / RAY
      return (scaledBorrow * effectiveBorrowIndex) / rayValue;
    });
  }, [borrowManagerBalances, borrowIndices, ray, tokenIds]);

  const [selectedToken, setSelectedToken] = useState<Token>(getTokens()[0]);
  const [isDepositModalOpen, setIsDepositModalOpen] = useState(false);
  const [isWithdrawModalOpen, setIsWithdrawModalOpen] = useState(false);
  const [isBorrowModalOpen, setIsBorrowModalOpen] = useState(false);
  const [isRepayModalOpen, setIsRepayModalOpen] = useState(false);

  // Function to refresh all data after transaction completion
  const handleTransactionComplete = () => {
    queryClient.invalidateQueries();
  };

  const marketRows = buildMarketRows(
    assets ? assets!.map((asset) => asset.result as Asset) : [],
    getTokens(),
    tokenIdMap,
    depositManagerBalances
      ? depositManagerBalances!.map((balance) => balance.result as bigint)
      : [],
    actualBorrows,
    totalBorrowScaled
      ? totalBorrowScaled!.map((item) => BigInt((item as any).result || 0))
      : [],
    borrowIndices
      ? borrowIndices!.map((item) => BigInt((item as any).result || 0))
      : [],
    setSelectedToken,
    setIsDepositModalOpen,
    setIsWithdrawModalOpen,
    setIsBorrowModalOpen,
    setIsRepayModalOpen
  );

  // Get selected token data for modals
  const selectedTokenData = marketRows.find(
    (data) => data.token.symbol === selectedToken.symbol
  );

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <Header />

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {isConnected && (
          <>
            {/* Network Warning */}
            {network === "sepolia" && !isSepolia && (
              <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 mb-6">
                <div className="flex items-center">
                  <div className="flex-shrink-0">
                    <svg
                      className="h-5 w-5 text-yellow-400"
                      viewBox="0 0 20 20"
                      fill="currentColor"
                    >
                      <path
                        fillRule="evenodd"
                        d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
                        clipRule="evenodd"
                      />
                    </svg>
                  </div>
                  <div className="ml-3">
                    <h3 className="text-sm font-medium text-yellow-800">
                      Wrong Network
                    </h3>
                    <div className="mt-2 text-sm text-yellow-700">
                      <p>
                        You are connected to the wrong network. Please switch
                        your wallet to Sepolia testnet to use.
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* Deposit & Borrow Section */}
            <MarketTable rows={marketRows} />

            {network === "sepolia" && (
              <div className="mt-8">
                <TestnetInstructions />
              </div>
            )}

            {/* Deposit Modal */}
            <DepositForm
              key={`deposit-${selectedToken.symbol}-${isDepositModalOpen}`}
              isOpen={isDepositModalOpen}
              onClose={() => setIsDepositModalOpen(false)}
              selectedToken={selectedToken}
              tokenId={selectedTokenData?.tokenId}
              onTransactionComplete={handleTransactionComplete}
            />

            {/* Withdraw Modal */}
            <WithdrawForm
              key={`withdraw-${selectedToken.symbol}-${isWithdrawModalOpen}`}
              isOpen={isWithdrawModalOpen}
              onClose={() => setIsWithdrawModalOpen(false)}
              selectedToken={selectedToken}
              tokenId={selectedTokenData?.tokenId}
              onTransactionComplete={handleTransactionComplete}
            />

            {/* Borrow Modal */}
            <BorrowForm
              key={`borrow-${selectedToken.symbol}-${isBorrowModalOpen}`}
              isOpen={isBorrowModalOpen}
              onClose={() => setIsBorrowModalOpen(false)}
              selectedToken={selectedToken}
              tokenId={selectedTokenData?.tokenId}
              tokenIds={tokenIds as `0x${string}`[]}
              borrows={actualBorrows}
              onTransactionComplete={handleTransactionComplete}
            />

            {/* Repay Modal */}
            <RepayForm
              key={`repay-${selectedToken.symbol}-${isRepayModalOpen}`}
              isOpen={isRepayModalOpen}
              onClose={() => setIsRepayModalOpen(false)}
              selectedToken={selectedToken}
              tokenId={selectedTokenData?.tokenId as `0x${string}`}
              borrows={actualBorrows}
              onTransactionComplete={handleTransactionComplete}
            />
          </>
        )}
        {!isConnected && <Connect />}
      </main>
    </div>
  );
}

export default App;
