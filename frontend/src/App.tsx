import { useState } from 'react'
import { useAccount } from 'wagmi'
import { useQueryClient } from '@tanstack/react-query'
import { DepositForm } from './components/DepositForm'
import { WithdrawForm } from './components/WithdrawForm'
import { MarketTable } from './components/MarketTable'
import { Header } from './components/Header'
import { Connect } from './components/Connect'
import { BorrowForm } from './components/BorrowForm'

import TOKENS from './tokens.json'

import { useTokenData } from './lib/queries'
import type { Token } from './lib/types'

function App() {
  const [selectedToken, setSelectedToken] = useState<Token>(TOKENS[0])
  const [isDepositModalOpen, setIsDepositModalOpen] = useState(false)
  const [isWithdrawModalOpen, setIsWithdrawModalOpen] = useState(false)
  const [isBorrowModalOpen, setIsBorrowModalOpen] = useState(false)

  const { address, isConnected } = useAccount()
  const queryClient = useQueryClient()

  // Get all token data using the custom hook
  const tokenData = useTokenData(
    TOKENS,
    address ?? '0x0000000000000000000000000000000000000000'
  )

  // Function to refresh all data after transaction completion
  const handleTransactionComplete = () => {
    queryClient.invalidateQueries()
  }

  // Create market rows with real data for each token
  const marketRows = tokenData.map((data) => ({
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
          </>
        )}
        {!isConnected && <Connect />}

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
      </main>
    </div>
  )
}

export default App
