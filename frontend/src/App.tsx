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
  useReadSupportedTokens,
} from './lib/hooks'
import type { Asset, Token } from './lib/types'

import TOKENS from './tokens.json'

const buildMarketRows = (
  assets: Asset[],
  tokens: Token[],
  tokenIdMap: Map<string, `0x${string}`>,
  userDeposits: bigint[],
  setSelectedToken: (token: Token) => void,
  setIsDepositModalOpen: (isOpen: boolean) => void,
  setIsWithdrawModalOpen: (isOpen: boolean) => void,
  setIsBorrowModalOpen: (isOpen: boolean) => void
) => {
  if (!assets) return []

  return assets.map((asset, index) => {
    const token = tokens.find((token) => token.symbol === asset.symbol)
    const tokenId = tokenIdMap.get(token!.symbol)
    const userDeposit = userDeposits[index]

    const { depositApy, borrowApy } = calculateAPY(asset)

    return {
      token: token!,
      tokenId,
      deposits: asset.totalDeposits,
      borrows: asset.totalBorrows,
      depositApy,
      borrowApy,
      userDeposit,
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
  const { address, isConnected } = useAccount()

  // Supported tokens
  const { data: tokenIds } = useReadSupportedTokens()

  // Map the token symbols to their IDs
  const tokenIdMap = useMemo(() => {
    const tokenMap = new Map<string, `0x${string}`>()
    if (!tokenIds || !Array.isArray(tokenIds)) return tokenMap

    TOKENS.forEach((token, index) => {
      const tokenId = tokenIds[index]
      if (tokenId) {
        tokenMap.set(token.symbol, tokenId as `0x${string}`)
      }
    })
    return tokenMap
  }, [tokenIds, TOKENS])

  // Asset data
  const { data: assets } = useReadAssets(tokenIds as `0x${string}`[])

  // Deposits
  const { data: depositManagerBalances } = useReadDepositManagerBalances(
    address! as `0x${string}`,
    tokenIds as `0x${string}`[]
  )

  const [selectedToken, setSelectedToken] = useState<Token>(TOKENS[0])
  const [isDepositModalOpen, setIsDepositModalOpen] = useState(false)
  const [isWithdrawModalOpen, setIsWithdrawModalOpen] = useState(false)
  const [isBorrowModalOpen, setIsBorrowModalOpen] = useState(false)

  // Function to refresh all data after transaction completion
  const handleTransactionComplete = () => {
    queryClient.invalidateQueries()
  }

  const marketRows = buildMarketRows(
    assets ? assets!.map((asset) => asset.result as Asset) : [],
    TOKENS,
    tokenIdMap,
    depositManagerBalances
      ? depositManagerBalances!.map((balance) => balance.result as bigint)
      : [],
    setSelectedToken,
    setIsDepositModalOpen,
    setIsWithdrawModalOpen,
    setIsBorrowModalOpen
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
            {/* Deposit & Borrow Section */}
            <MarketTable rows={marketRows} />

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
              onTransactionComplete={handleTransactionComplete}
            />
          </>
        )}
        {!isConnected && <Connect />}
      </main>
    </div>
  )
}

export default App
