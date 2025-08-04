import { useMemo, useState } from 'react'
import { useDispatch } from 'react-redux'
import { useAccount, usePublicClient } from 'wagmi'
import { useQueryClient } from '@tanstack/react-query'
import { DepositForm } from './components/DepositForm'
import { WithdrawForm } from './components/WithdrawForm'
import { MarketTable } from './components/MarketTable'
import { Header } from './components/Header'
import { Connect } from './components/Connect'
import { BorrowForm } from './components/BorrowForm'
import {
  useReadAsset,
  useReadAssets,
  useReadDepositManagerAllowance,
  useReadDepositManagerAllowances,
  useReadDepositManagerBalances,
  useReadERC20Balance,
  useReadERC20Balances,
  useReadSupportedTokens,
  useTokenData,
} from './lib/hooks'
import type { Asset, Token } from './lib/types'
//import { getTokens } from './store/interactions'

import TOKENS from './tokens.json'

const buildMarketRows = (
  assets: Asset[],
  tokens: Token[],
  tokenIdMap: Map<string, `0x${string}`>,
  userDeposits: bigint[],
  walletBalances: bigint[],
  allowances: bigint[],
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
    const walletBalance = walletBalances[index]
    const allowance = allowances[index]

    const { depositApy, borrowApy } = calculateAPY(asset)

    return {
      token: token!,
      tokenId,
      deposits: asset.totalDeposits,
      borrows: asset.totalBorrows,
      depositApy,
      borrowApy,
      userDeposit,
      walletBalance,
      allowance,
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
  const dispatch = useDispatch()
  const publicClient = usePublicClient()
  const queryClient = useQueryClient()
  const { address, isConnected } = useAccount()

  // Supported tokens
  const { data: tokenIds } = useReadSupportedTokens()
  console.log(tokenIds)

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
  console.log(assets, 'assets')

  // Wallet Balances
  const { data: erc20Balances } = useReadERC20Balances(
    tokenIds as `0x${string}`[],
    address! as `0x${string}`
  )
  console.log(erc20Balances)

  // Deposits
  const { data: depositManagerBalances } = useReadDepositManagerBalances(
    address! as `0x${string}`,
    tokenIds as `0x${string}`[]
  )

  // Allowances
  const { data: allowances } = useReadDepositManagerAllowances(
    address! as `0x${string}`,
    tokenIds as `0x${string}`[]
  )

  const [selectedToken, setSelectedToken] = useState<Token>(TOKENS[0])
  const [isDepositModalOpen, setIsDepositModalOpen] = useState(false)
  const [isWithdrawModalOpen, setIsWithdrawModalOpen] = useState(false)
  const [isBorrowModalOpen, setIsBorrowModalOpen] = useState(false)

  // getTokens(publicClient!, address!, dispatch).then((tokens) => {
  //   console.log('tokens', tokens)
  // })

  // Get all token data using the custom hook
  const tokenData = useTokenData(TOKENS, address!)
  console.log(tokenData, 'tokenData')

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
    erc20Balances
      ? erc20Balances!.map((balance) => balance.result as bigint)
      : [],
    allowances ? allowances!.map((balance) => balance.result as bigint) : [],
    setSelectedToken,
    setIsDepositModalOpen,
    setIsWithdrawModalOpen,
    setIsBorrowModalOpen
  )
  // const marketRows = assets?.map((asset) => ({
  //   token: asset.result,
  // }))

  console.log(marketRows, 'marketRows')

  // Create market rows with real data for each token
  const marketRowss = tokenData.map((data) => ({
    token: data.token,
    deposits: data.deposits,
    borrows: data.borrows,
    depositApy: data.depositApy,
    borrowApy: data.borrowApy,
    userDeposits: data.userDeposits,
    onDeposit: () => {
      setSelectedToken(data.token)
      setIsDepositModalOpen(true)
    },
    onWithdraw: () => {
      setSelectedToken(data.token)
      setIsWithdrawModalOpen(true)
    },
    onBorrow: () => {
      setSelectedToken(data.token)
      setIsBorrowModalOpen(true)
    },
  }))

  // Get selected token data for modals
  const selectedTokenData = tokenData.find(
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
              walletBalance={selectedTokenData?.walletBalance ?? 0}
              allowance={selectedTokenData?.allowance ?? 0}
              onTransactionComplete={handleTransactionComplete}
            />

            {/* Withdraw Modal */}
            <WithdrawForm
              key={`withdraw-${selectedToken.symbol}-${isWithdrawModalOpen}`}
              isOpen={isWithdrawModalOpen}
              onClose={() => setIsWithdrawModalOpen(false)}
              selectedToken={selectedToken}
              tokenId={selectedTokenData?.tokenId}
              depositedBalance={selectedTokenData?.userDeposits ?? 0}
              onTransactionComplete={handleTransactionComplete}
            />

            {/* Borrow Modal */}
            <BorrowForm
              key={`borrow-${selectedToken.symbol}-${isBorrowModalOpen}`}
              isOpen={isBorrowModalOpen}
              onClose={() => setIsBorrowModalOpen(false)}
              selectedToken={selectedToken}
              tokenId={selectedTokenData?.tokenId}
              //maxBorrowable={selectedTokenData?.userDeposits ?? 0} // For now, use userDeposits as max borrowable
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
