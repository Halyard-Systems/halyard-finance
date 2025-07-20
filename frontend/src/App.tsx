import { useState } from 'react'
import { useAccount } from 'wagmi'
import { DepositForm } from './components/DepositForm'
import { WithdrawForm } from './components/WithdrawForm'
import { MarketTable } from './components/MarketTable'
import { Header } from './components/Header'
import { Connect } from './components/Connect'

import TOKENS from './tokens.json'

import { useTokenData } from './lib/queries'
import type { Token } from './lib/types'

function App() {
  const [selectedToken, setSelectedToken] = useState<Token>(TOKENS[0])
  const [isDepositModalOpen, setIsDepositModalOpen] = useState(false)
  const [isWithdrawModalOpen, setIsWithdrawModalOpen] = useState(false)

  const { address, isConnected } = useAccount()

  // Get all token data using the custom hook
  const tokenData = useTokenData(
    TOKENS,
    address ?? '0x0000000000000000000000000000000000000000'
  )

  console.log(tokenData)

  // Function to refresh all data after transaction completion
  const handleTransactionComplete = async () => {
    // The useTokenData hook will automatically refetch when dependencies change
    // For now, we'll rely on the automatic refetching
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
          isOpen={isWithdrawModalOpen}
          onClose={() => setIsWithdrawModalOpen(false)}
          selectedToken={selectedToken}
          tokenId={selectedTokenData?.tokenId}
          depositedBalance={selectedTokenData?.userDeposits ?? 0}
          onTransactionComplete={handleTransactionComplete}
        />
      </main>
    </div>
  )
}

export default App
