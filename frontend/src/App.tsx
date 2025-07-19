import { useEffect, useState } from 'react'
import { useAccount } from 'wagmi'
import { DepositForm } from './components/DepositForm'
import { WithdrawForm } from './components/WithdrawForm'
import { MarketTable, type MarketRow } from './components/MarketTable'
import { Header } from './components/Header'
import { Connect } from './components/Connect'

import TOKENS from './tokens.json'

import {
  useReadDepositManagerAllowance,
  useReadDepositManagerBalance,
  useReadERC20Balance,
} from './lib/queries'

function App() {
  const [selectedToken, setSelectedToken] = useState(TOKENS[0])
  const [depositedBalance, setDepositedBalance] = useState(0)
  const [isDepositModalOpen, setIsDepositModalOpen] = useState(false)
  const [isWithdrawModalOpen, setIsWithdrawModalOpen] = useState(false)

  const { address, isConnected } = useAccount()

  // Read USDC balance for connected account using useReadContract
  const {
    data: usdcBalanceRaw,
    status: usdcStatus,
    error: usdcError,
    refetch: refetchUsdcBalance,
  } = useReadERC20Balance(selectedToken)
  const usdcBalance = usdcBalanceRaw ? Number(usdcBalanceRaw) / 1e6 : 0

  // Read USDC allowance for DepositManager contract
  const {
    data: allowanceRaw,
    status: allowanceStatus,
    error: allowanceError,
    refetch: refetchAllowance,
  } = useReadDepositManagerAllowance(
    address ?? '0x0000000000000000000000000000000000000000',
    selectedToken
  )
  const allowance = allowanceRaw ? Number(allowanceRaw) / 1e6 : 0

  // Read deposited balance from DepositManager contract
  const { data: depositedBalanceRaw, refetch: refetchDepositedBalance } =
    useReadDepositManagerBalance(
      address ?? '0x0000000000000000000000000000000000000000'
    )

  // Update deposited balance when data changes
  useEffect(() => {
    if (depositedBalanceRaw) {
      setDepositedBalance(Number(depositedBalanceRaw) / 1e6)
    }
  }, [depositedBalanceRaw])

  // Function to refresh all data after transaction completion
  const handleTransactionComplete = async () => {
    await Promise.all([
      refetchUsdcBalance(),
      refetchAllowance(),
      refetchDepositedBalance(),
    ])
  }

  // Prepare market data for the table
  const marketRows: MarketRow[] = [
    {
      token: selectedToken,
      deposits: depositedBalance,
      borrows: 0,
      depositApy: 2.5,
      borrowApy: 4.2,
      userDeposits: depositedBalance,
      onDeposit: () => setIsDepositModalOpen(true),
      onWithdraw: () => setIsWithdrawModalOpen(true),
    },
  ]

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
          usdcBalance={usdcBalance}
          allowance={allowance}
          onTransactionComplete={handleTransactionComplete}
        />

        {/* Withdraw Modal */}
        <WithdrawForm
          isOpen={isWithdrawModalOpen}
          onClose={() => setIsWithdrawModalOpen(false)}
          selectedToken={selectedToken}
          depositedBalance={depositedBalance}
          onTransactionComplete={handleTransactionComplete}
        />
      </main>
    </div>
  )
}

export default App
