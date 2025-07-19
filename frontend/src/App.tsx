import { useEffect, useState } from 'react'
import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { injected } from 'wagmi/connectors'
import { Button } from './components/ui/button'
import { DepositForm } from './components/DepositForm'
import { WithdrawForm } from './components/WithdrawForm'
import halyardLogo from './assets/halyard-finance-navbar-logo-cyan-gold.png'

import TOKENS from './tokens.json'

import {
  useReadDepositManagerAllowance,
  useReadDepositManagerBalance,
  useReadERC20Balance,
  useReadStargateAllowance,
  useReadStargateRouterContract,
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

  // Read Stargate router address from DepositManager
  const { data: stargateRouterAddress } = useReadStargateRouterContract()

  // Read USDC allowance for Stargate router
  const {
    data: stargateAllowanceRaw,
    status: stargateAllowanceStatus,
    error: stargateAllowanceError,
  } = useReadStargateAllowance(
    address ?? '0x0000000000000000000000000000000000000000',
    stargateRouterAddress as string,
    selectedToken
  )
  const stargateAllowance = stargateAllowanceRaw
    ? Number(stargateAllowanceRaw) / 1e6
    : 0

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
      <main className='max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8'>
        {isConnected && (
          <>
            {/* Deposit & Borrow Section */}
            <div className='bg-card rounded-lg shadow-sm border border-border p-6'>
              <div className='overflow-x-auto'>
                <table className='w-full'>
                  <thead>
                    <tr className='border-b border-border'>
                      <th className='text-left py-3 px-4 font-medium text-card-foreground'>
                        Asset
                      </th>
                      <th className='text-left py-3 px-4 font-medium text-card-foreground'>
                        Deposits
                      </th>
                      <th className='text-left py-3 px-4 font-medium text-card-foreground'>
                        Borrows
                      </th>
                      <th className='text-left py-3 px-4 font-medium text-card-foreground'>
                        Deposit APY
                      </th>
                      <th className='text-left py-3 px-4 font-medium text-card-foreground'>
                        Borrow APY
                      </th>
                      <th className='text-left py-3 px-4 font-medium text-card-foreground'>
                        Your Deposits
                      </th>
                      <th className='text-left py-3 px-4 font-medium text-card-foreground'>
                        Actions
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr className='border-b border-border'>
                      {/* Asset */}
                      <td className='py-4 px-4'>
                        <div className='flex items-center space-x-2'>
                          <img
                            src={selectedToken.icon}
                            alt={`${selectedToken.symbol} icon`}
                            className='w-6 h-6'
                          />
                          <div>
                            <div className='font-medium text-card-foreground'>
                              {selectedToken.symbol}
                            </div>
                            <div className='text-sm text-muted-foreground'>
                              {selectedToken.name}
                            </div>
                          </div>
                        </div>
                      </td>

                      {/* Deposits */}
                      <td className='py-4 px-4'>
                        <div className='font-mono text-card-foreground'>
                          {depositedBalance.toLocaleString(undefined, {
                            maximumFractionDigits: 6,
                          })}{' '}
                          {selectedToken.symbol}
                        </div>
                      </td>

                      {/* Borrows */}
                      <td className='py-4 px-4'>
                        <div className='font-mono text-card-foreground'>
                          0.00 {selectedToken.symbol}
                        </div>
                      </td>

                      {/* Deposit APY */}
                      <td className='py-4 px-4'>
                        <div className='text-green-600 font-medium'>2.5%</div>
                      </td>

                      {/* Borrow APY */}
                      <td className='py-4 px-4'>
                        <div className='text-red-600 font-medium'>4.2%</div>
                      </td>

                      {/* Your Deposits */}
                      <td className='py-4 px-4'>
                        <div className='font-mono text-card-foreground'>
                          {depositedBalance.toLocaleString(undefined, {
                            maximumFractionDigits: 6,
                          })}{' '}
                          {selectedToken.symbol}
                        </div>
                      </td>

                      {/* Actions */}
                      <td className='py-4 px-4'>
                        <div className='flex space-x-2'>
                          <Button
                            variant='outline'
                            size='sm'
                            onClick={() => setIsDepositModalOpen(true)}
                          >
                            Deposit
                          </Button>
                          {depositedBalance > 0 && (
                            <Button
                              variant='outline'
                              size='sm'
                              onClick={() => setIsWithdrawModalOpen(true)}
                            >
                              Withdraw
                            </Button>
                          )}
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
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
          stargateAllowance={stargateAllowance}
          stargateRouterAddress={stargateRouterAddress as string | undefined}
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
