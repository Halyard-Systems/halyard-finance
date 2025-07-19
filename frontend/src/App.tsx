import { useEffect, useState } from 'react'
import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { injected } from 'wagmi/connectors'
import { Button } from './components/ui/button'
import { DepositForm } from './components/DepositForm'
import { WithdrawForm } from './components/WithdrawForm'
import { MarketTable, type MarketRow } from './components/MarketTable'
import halyardLogo from './assets/halyard-finance-navbar-logo-cyan-gold.png'

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
  const { connect } = useConnect()
  const { disconnect } = useDisconnect()

  // Read USDC balance for connected account using useReadContract
  const {
    data: usdcBalanceRaw,
    status: usdcStatus,
    error: usdcError,
  } = useReadERC20Balance(selectedToken)
  const usdcBalance = usdcBalanceRaw ? Number(usdcBalanceRaw) / 1e6 : 0

  // Read USDC allowance for DepositManager contract
  const {
    data: allowanceRaw,
    status: allowanceStatus,
    error: allowanceError,
  } = useReadDepositManagerAllowance(
    address ?? '0x0000000000000000000000000000000000000000',
    selectedToken
  )
  const allowance = allowanceRaw ? Number(allowanceRaw) / 1e6 : 0

  // Read deposited balance from DepositManager contract
  const { data: depositedBalanceRaw } = useReadDepositManagerBalance(
    address ?? '0x0000000000000000000000000000000000000000'
  )

  // Update deposited balance when data changes
  useEffect(() => {
    if (depositedBalanceRaw) {
      setDepositedBalance(Number(depositedBalanceRaw) / 1e6)
    }
  }, [depositedBalanceRaw])

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
      <header className='bg-card shadow-sm border-b border-border sticky top-0 z-50'>
        <div className='max-w-7xl mx-auto px-4 sm:px-6 lg:px-8'>
          <div className='flex justify-between items-center h-16'>
            {/* Logo/Title */}
            <img
              src={halyardLogo}
              alt='Halyard Finance Logo'
              className='h-10 w-auto'
            />
            {/* Wallet Connection */}
            <div className='flex items-center space-x-4'>
              {!isConnected ? (
                <Button onClick={() => connect({ connector: injected() })}>
                  Connect Wallet
                </Button>
              ) : (
                <div className='flex items-center space-x-3'>
                  <div className='text-sm text-muted-foreground'>
                    <span className='font-medium'>Connected:</span>
                    <span className='ml-1 font-mono text-xs'>
                      {address?.slice(0, 6)}...{address?.slice(-4)}
                    </span>
                  </div>
                  <Button variant='secondary' onClick={() => disconnect()}>
                    Disconnect
                  </Button>
                </div>
              )}
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className='max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8'>
        {isConnected && (
          <>
            {/* Deposit & Borrow Section */}
            <MarketTable rows={marketRows} />
          </>
        )}
        {!isConnected && (
          <div className='bg-card rounded-lg shadow-sm border border-border p-6 text-center'>
            <h2 className='text-xl font-semibold text-card-foreground mb-4'>
              Welcome to Halyard Finance
            </h2>
            <p className='text-muted-foreground mb-6'>
              Connect your wallet to start depositing and managing your funds.
            </p>
            <Button
              onClick={() => connect({ connector: injected() })}
              size='lg'
            >
              Connect Wallet
            </Button>
          </div>
        )}

        {/* Deposit Modal */}
        <DepositForm
          isOpen={isDepositModalOpen}
          onClose={() => setIsDepositModalOpen(false)}
          selectedToken={selectedToken}
          usdcBalance={usdcBalance}
          allowance={allowance}
        />

        {/* Withdraw Modal */}
        <WithdrawForm
          isOpen={isWithdrawModalOpen}
          onClose={() => setIsWithdrawModalOpen(false)}
          selectedToken={selectedToken}
          depositedBalance={depositedBalance}
        />
      </main>
    </div>
  )
}

export default App
