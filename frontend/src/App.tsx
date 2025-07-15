import { useState } from 'react'
import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { injected } from 'wagmi/connectors'
import { Button } from './components/ui/button'
import halyardLogo from './assets/halyard-finance-navbar-logo.png'

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
    <div className='min-h-screen bg-gray-50'>
      {/* Header */}
      <header className='bg-white shadow-sm border-b sticky top-0 z-50'>
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
                <Button
                  onClick={() => connect({ connector: injected() })}
                  className='bg-blue-600 hover:bg-blue-700 text-white'
                >
                  Connect Wallet
                </Button>
              ) : (
                <div className='flex items-center space-x-3'>
                  <div className='text-sm text-gray-600'>
                    <span className='font-medium'>Connected:</span>
                    <span className='ml-1 font-mono text-xs'>
                      {address?.slice(0, 6)}...{address?.slice(-4)}
                    </span>
                  </div>
                  <Button onClick={() => disconnect()}>Disconnect</Button>
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
            <div className='bg-white rounded-lg shadow-sm border p-6 mb-6'>
              <h2 className='text-xl font-semibold text-gray-900 mb-4'>
                Deposit
              </h2>

              <div className='space-y-4'>
                <div>
                  <label className='block text-sm font-medium text-gray-700 mb-2'>
                    Amount (in wei)
                  </label>
                  <input
                    type='number'
                    value={depositAmount}
                    onChange={(e) => setDepositAmount(e.target.value)}
                    placeholder='1000000000000000000'
                    className='w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500'
                  />
                </div>

                <Button
                  onClick={handleDeposit}
                  disabled={!depositAmount}
                  className='w-full bg-green-600 hover:bg-green-700 disabled:bg-gray-400 disabled:cursor-not-allowed text-white'
                >
                  Deposit
                </Button>
              </div>
            </div>

            {/* Balance Section */}
            <div className='bg-white rounded-lg shadow-sm border p-6'>
              <h2 className='text-xl font-semibold text-gray-900 mb-4'>
                Balance
              </h2>
              <p className='text-lg'>
                Your balance: <span className='font-mono'>0 wei</span>
              </p>
            </div>
          </>
        )}

        {!isConnected && (
          <div className='bg-white rounded-lg shadow-sm border p-6 text-center'>
            <h2 className='text-xl font-semibold text-gray-900 mb-4'>
              Welcome to Halyard Finance
            </h2>
            <p className='text-gray-600 mb-6'>
              Connect your wallet to start depositing and managing your funds.
            </p>
            <Button
              onClick={() => connect({ connector: injected() })}
              className='bg-blue-600 hover:bg-blue-700 text-white'
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
