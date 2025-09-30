import { useMemo, useState } from 'react'
import { useAccount } from 'wagmi'
import { useQueryClient } from '@tanstack/react-query'
import { DepositForm } from './components/DepositForm'
import { WithdrawForm } from './components/WithdrawForm'
import { MarketTable } from './components/MarketTable'
import { Header } from './components/Header'
import { Connect } from './components/Connect'
import { BorrowForm } from './components/BorrowForm'
import {
  useReadAssets,
  useReadDepositManagerBalances,
  useReadBorrowManagerBalances,
  useReadBorrowIndices,
  useReadRay,
  useReadSupportedTokens,
} from './lib/hooks'
import type { Asset, Token } from './lib/types'

// Import both token files
import MAINNET_TOKENS from './tokens.json'
import SEPOLIA_TOKENS from './tokens_sepolia.json'

const network = import.meta.env.VITE_NETWORK

// Function to get tokens based on network
const getTokens = (): Token[] => {
  if (network === 'sepolia') {
    return SEPOLIA_TOKENS
  }
  // Default to mainnet tokens
  return MAINNET_TOKENS
}
import { RepayForm } from './components/RepayForm'
import { TestnetInstructions } from './components/TestnetInstructions'
import { AccountSummary } from './components/AccountSummary'
import { Portfolio } from './components/Portfolio'
import { QuickActions } from './components/QuickActions'

const buildMarketRows = (
  assets: Asset[],
  tokens: Token[],
  tokenIdMap: Map<string, `0x${string}`>,
  userDeposits: bigint[],
  userBorrows: bigint[],
  setSelectedToken: (token: Token) => void,
  setIsDepositModalOpen: (isOpen: boolean) => void,
  setIsWithdrawModalOpen: (isOpen: boolean) => void,
  setIsBorrowModalOpen: (isOpen: boolean) => void,
  setIsRepayModalOpen: (isOpen: boolean) => void
) => {
  if (!assets) return []

  return assets.map((asset, index) => {
    const token = tokens.find((token) => token.symbol === asset.symbol)
    const tokenId = tokenIdMap.get(token!.symbol)
    const userDeposit = userDeposits[index]
    const userBorrow = userBorrows[index]

    const { depositApy, borrowApy } = calculateAPY(asset)

    return {
      token: token!,
      tokenId,
      deposits: asset.totalDeposits,
      borrows: asset.totalBorrows,
      depositApy,
      borrowApy,
      userDeposit,
      userBorrow,
      onDeposit: () => {
        setSelectedToken(token!)
        setIsDepositModalOpen(true)
      },
      onWithdraw: () => {
        setSelectedToken(token!)
        setIsWithdrawModalOpen(true)
      },
      onBorrow: () => {
        setSelectedToken(token!)
        setIsBorrowModalOpen(true)
      },
      onRepay: () => {
        setSelectedToken(token!)
        setIsRepayModalOpen(true)
      },
    }
  })
}

// TODO: Replace with contract interest rate model
// Calculate APY from asset data
const calculateAPY = (
  asset: Asset | undefined
): { depositApy: number; borrowApy: number } => {
  if (!asset || asset.totalDeposits === 0n) {
    return { depositApy: 0, borrowApy: 0 }
  }

  // Calculate utilization rate
  const utilization =
    Number((asset.totalBorrows * 10000n) / asset.totalDeposits) / 10000

  // Simple APY calculation based on utilization
  // In a real implementation, you'd use the contract's interest rate model
  const baseRate = 0.025 // 2.5% base rate
  const utilizationMultiplier = 1 + utilization * 2 // Higher utilization = higher rates

  const depositApy = baseRate * utilizationMultiplier * 100
  const borrowApy = depositApy * 1.5 // Borrow rate is typically higher than deposit rate

  return { depositApy, borrowApy }
}

function App() {
  const queryClient = useQueryClient()
  const { address, isConnected, chainId } = useAccount()

  // Check if connected to Sepolia
  const isSepolia = chainId === 11155111

  // Supported tokens
  const { data: tokenIds } = useReadSupportedTokens()

  // Map the token symbols to their IDs
  const tokenIdMap = useMemo(() => {
    const tokenMap = new Map<string, `0x${string}`>()
    if (!tokenIds || !Array.isArray(tokenIds)) return tokenMap

    const tokens = getTokens()
    tokens.forEach((token, index) => {
      const tokenId = tokenIds[index]
      if (tokenId) {
        tokenMap.set(token.symbol, tokenId as `0x${string}`)
      }
    })
    return tokenMap
  }, [tokenIds])

  // Asset data
  const { data: assets } = useReadAssets(tokenIds as `0x${string}`[])

  // Deposits
  const { data: depositManagerBalances } = useReadDepositManagerBalances(
    address! as `0x${string}`,
    tokenIds as `0x${string}`[]
  )

  // Borrows (scaled)
  const { data: borrowManagerBalances } = useReadBorrowManagerBalances(
    address! as `0x${string}`,
    tokenIds as `0x${string}`[]
  )

  // Borrow indices
  const { data: borrowIndices } = useReadBorrowIndices(
    tokenIds as `0x${string}`[]
  )

  // RAY constant
  const { data: ray } = useReadRay()

  // Calculate actual borrowed amounts
  const actualBorrows = useMemo(() => {
    if (
      !borrowManagerBalances ||
      !borrowIndices ||
      !ray ||
      !tokenIds ||
      !Array.isArray(tokenIds)
    ) {
      return new Array(0).fill(0n)
    }

    return borrowManagerBalances.map((balance, index) => {
      const scaledBorrow = BigInt((balance as any).result || 0)
      const borrowIndex = BigInt((borrowIndices[index] as any).result || 0)
      const rayValue = BigInt((ray as any) || 0)

      // If no borrows, return 0
      if (scaledBorrow === 0n) {
        return 0n
      }

      // If borrow index is 0, it means no borrows have happened yet
      // In this case, use RAY as the borrow index (matches contract initialization)
      const effectiveBorrowIndex = borrowIndex === 0n ? rayValue : borrowIndex

      // Calculate actual borrow: (scaledBorrow * effectiveBorrowIndex) / RAY
      return (scaledBorrow * effectiveBorrowIndex) / rayValue
    })
  }, [borrowManagerBalances, borrowIndices, ray, tokenIds])

  const [selectedToken, setSelectedToken] = useState<Token>(getTokens()[0])
  const [isDepositModalOpen, setIsDepositModalOpen] = useState(false)
  const [isWithdrawModalOpen, setIsWithdrawModalOpen] = useState(false)
  const [isBorrowModalOpen, setIsBorrowModalOpen] = useState(false)
  const [isRepayModalOpen, setIsRepayModalOpen] = useState(false)

  // Function to refresh all data after transaction completion
  const handleTransactionComplete = () => {
    queryClient.invalidateQueries()
  }

  const marketRows = buildMarketRows(
    assets ? assets!.map((asset) => asset.result as Asset) : [],
    getTokens(),
    tokenIdMap,
    depositManagerBalances
      ? depositManagerBalances!.map((balance) => balance.result as bigint)
      : [],
    actualBorrows,
    setSelectedToken,
    setIsDepositModalOpen,
    setIsWithdrawModalOpen,
    setIsBorrowModalOpen,
    setIsRepayModalOpen
  )

  // Get selected token data for modals
  const selectedTokenData = marketRows.find(
    (data) => data.token.symbol === selectedToken.symbol
  )

  return (
    <div className='min-h-screen bg-background'>
      {/* Header */}
      <Header />

      {/* Main Content */}
      <main className='max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8'>
        {isConnected && (
          <>
            <AccountSummary />
            <Portfolio />
            <QuickActions
              onDeposit={() => {
                setSelectedToken(getTokens()[0])
                setIsDepositModalOpen(true)
              }}
              onWithdraw={() => {
                setSelectedToken(getTokens()[0])
                setIsWithdrawModalOpen(true)
              }}
              onBorrow={() => {
                setSelectedToken(getTokens()[0])
                setIsBorrowModalOpen(true)
              }}
              onRepay={() => {
                setSelectedToken(getTokens()[0])
                setIsRepayModalOpen(true)
              }}
            />
          </>
        )}
        {!isConnected && <Connect />}

        {/* Modals */}
        {isDepositModalOpen && (
          <DepositForm
            isOpen={isDepositModalOpen}
            onClose={() => setIsDepositModalOpen(false)}
            onTransactionComplete={handleTransactionComplete}
          />
        )}

        {isWithdrawModalOpen && (
          <WithdrawForm
            isOpen={isWithdrawModalOpen}
            onClose={() => setIsWithdrawModalOpen(false)}
            onTransactionComplete={handleTransactionComplete}
          />
        )}

        {isBorrowModalOpen && (
          <BorrowForm
            isOpen={isBorrowModalOpen}
            tokenIds={tokenIds as `0x${string}`[]}
            borrows={actualBorrows}
            onClose={() => setIsBorrowModalOpen(false)}
            onTransactionComplete={handleTransactionComplete}
          />
        )}

        {isRepayModalOpen && (
          <RepayForm
            isOpen={isRepayModalOpen}
            borrows={actualBorrows}
            onClose={() => setIsRepayModalOpen(false)}
            onTransactionComplete={handleTransactionComplete}
          />
        )}

        {isSepolia && <TestnetInstructions />}
      </main>
    </div>
  )
}

export default App
