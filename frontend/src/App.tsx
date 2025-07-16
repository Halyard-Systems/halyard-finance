import { useState } from 'react'
import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { injected } from 'wagmi/connectors'
import { Button } from './components/ui/button'
import halyardLogo from './assets/halyard-finance-navbar-logo-cyan-gold.png'

function App() {
  const [depositAmount, setDepositAmount] = useState('')
  const { address, isConnected } = useAccount()
  const { connect } = useConnect()
  const { disconnect } = useDisconnect()

  const handleDeposit = () => {
    if (!depositAmount) return
    console.log(depositAmount)
  }

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
            {/* Deposit Section */}
            <div className='bg-card rounded-lg shadow-sm border border-border p-6 mb-6'>
              <h2 className='text-xl font-semibold text-card-foreground mb-4'>
                Deposit
              </h2>
              <div className='space-y-4'>
                <div>
                  <label className='block text-sm font-medium text-card-foreground mb-2'>
                    Amount (in wei)
                  </label>
                  <input
                    type='number'
                    value={depositAmount}
                    onChange={(e) => setDepositAmount(e.target.value)}
                    placeholder='1000000000000000000'
                    className='w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground'
                  />
                </div>
                <Button
                  onClick={handleDeposit}
                  disabled={!depositAmount}
                  className='w-full'
                >
                  Deposit
                </Button>
              </div>
            </div>
            {/* Balance Section */}
            <div className='bg-card rounded-lg shadow-sm border border-border p-6'>
              <h2 className='text-xl font-semibold text-card-foreground mb-4'>
                Balance
              </h2>
              <p className='text-lg text-card-foreground'>
                Your balance: <span className='font-mono'>0 wei</span>
              </p>
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
      </main>
    </div>
  )
}

export default App
