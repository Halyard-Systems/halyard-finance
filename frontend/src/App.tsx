import { useState } from 'react'
import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { useReadContract, useWriteContract } from 'wagmi'
import { injected } from 'wagmi/connectors'
import { Button } from './components/ui/button'
import halyardLogo from './assets/halyard-finance-navbar-logo-cyan-gold.png'
import React from 'react' // Added missing import for React

// Token data
const TOKENS = [
  {
    symbol: 'USDC',
    name: 'USD Coin',
    icon: '/usd-coin-usdc-logo.svg',
    decimals: 6,
    address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
  },
]

const ERC20_ABI = [
  {
    type: 'function',
    name: 'balanceOf',
    stateMutability: 'view',
    inputs: [{ name: 'owner', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'decimals',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint8' }],
  },
  {
    type: 'function',
    name: 'approve',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
]

// DepositManager contract ABI
const DEPOSIT_MANAGER_ABI = [
  {
    type: 'function',
    name: 'deposit',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'amount', type: 'uint256' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'balanceOf',
    stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
]

// Contract addresses - you'll need to update these with your deployed contract addresses
//const DEPOSIT_MANAGER_ADDRESS = '0x...' // Replace with your deployed contract address
const DEPOSIT_MANAGER_ADDRESS = '0x2e590d65Dd357a7565EfB5ffB329F8465F18c494'

function App() {
  const [depositAmount, setDepositAmount] = useState('')
  const [selectedToken, setSelectedToken] = useState(TOKENS[0])
  const [isDropdownOpen, setIsDropdownOpen] = useState(false)
  const [depositedBalance, setDepositedBalance] = useState(0)
  const { address, isConnected } = useAccount()
  const { connect } = useConnect()
  const { disconnect } = useDisconnect()

  // Read USDC balance for connected account using useReadContract
  const {
    data: usdcBalanceRaw,
    status: usdcStatus,
    error: usdcError,
  } = useReadContract({
    address: selectedToken.address as `0x${string}`,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [address ?? '0x0000000000000000000000000000000000000000'],
  })
  const usdcBalance = usdcBalanceRaw ? Number(usdcBalanceRaw) / 1e6 : 0

  // Read deposited balance from DepositManager contract
  const { data: depositedBalanceRaw } = useReadContract({
    address: DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
    abi: DEPOSIT_MANAGER_ABI,
    functionName: 'balanceOf',
    args: [address ?? '0x0000000000000000000000000000000000000000'],
  })

  // Update deposited balance when data changes
  React.useEffect(() => {
    if (depositedBalanceRaw) {
      setDepositedBalance(Number(depositedBalanceRaw) / 1e6)
    }
  }, [depositedBalanceRaw])

  // Write contract hook for deposit
  const {
    writeContract,
    isPending: isDepositing,
    error: depositError,
  } = useWriteContract()

  const handleDeposit = async () => {
    if (
      !depositAmount ||
      !address ||
      !DEPOSIT_MANAGER_ADDRESS ||
      DEPOSIT_MANAGER_ADDRESS === '0x...'
    ) {
      console.error('Invalid deposit amount, address, or contract not deployed')
      return
    }

    try {
      // Convert amount to wei (USDC has 6 decimals)
      const amountInWei = BigInt(Math.floor(Number(depositAmount) * 1e6))

      // Call the deposit function
      await writeContract({
        address: DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
        abi: DEPOSIT_MANAGER_ABI,
        functionName: 'deposit',
        args: [amountInWei],
      })

      // Clear the input after successful deposit
      setDepositAmount('')
    } catch (error) {
      console.error('Deposit failed:', error)
    }
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
                {/* Token Selection */}
                <div>
                  <label className='block text-sm font-medium text-card-foreground mb-2'>
                    Token
                  </label>
                  <div className='relative'>
                    <button
                      type='button'
                      onClick={() => setIsDropdownOpen(!isDropdownOpen)}
                      className='w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground flex items-center justify-between'
                    >
                      <div className='flex items-center space-x-2'>
                        <img
                          src={selectedToken.icon}
                          alt={`${selectedToken.symbol} icon`}
                          className='w-5 h-5'
                        />
                        <span>{selectedToken.symbol}</span>
                      </div>
                      <svg
                        className={`w-4 h-4 transition-transform ${
                          isDropdownOpen ? 'rotate-180' : ''
                        }`}
                        fill='none'
                        stroke='currentColor'
                        viewBox='0 0 24 24'
                      >
                        <path
                          strokeLinecap='round'
                          strokeLinejoin='round'
                          strokeWidth={2}
                          d='M19 9l-7 7-7-7'
                        />
                      </svg>
                    </button>
                    {isDropdownOpen && (
                      <div className='absolute z-10 w-full mt-1 bg-background border border-border rounded-md shadow-lg'>
                        {TOKENS.map((token) => (
                          <button
                            key={token.symbol}
                            onClick={() => {
                              setSelectedToken(token)
                              setIsDropdownOpen(false)
                            }}
                            className='w-full px-3 py-2 text-left hover:bg-accent hover:text-accent-foreground flex items-center space-x-2'
                          >
                            <img
                              src={token.icon}
                              alt={`${token.symbol} icon`}
                              className='w-5 h-5'
                            />
                            <span>{token.symbol}</span>
                          </button>
                        ))}
                      </div>
                    )}
                  </div>
                </div>

                {/* Amount Input */}
                <div>
                  <label className='block text-sm font-medium text-card-foreground mb-2'>
                    Amount ({selectedToken.symbol})
                  </label>
                  <p className='text-sm text-muted-foreground mb-2'>
                    Available to deposit:{' '}
                    <span className='font-mono'>
                      {usdcBalance.toLocaleString(undefined, {
                        maximumFractionDigits: 6,
                      })}{' '}
                      {selectedToken.symbol}
                    </span>
                  </p>
                  <input
                    type='number'
                    value={depositAmount}
                    onChange={(e) => setDepositAmount(e.target.value)}
                    placeholder={`0.00 ${selectedToken.symbol}`}
                    className='w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground'
                    disabled={isDepositing}
                  />
                </div>

                {/* Error Display */}
                {depositError && (
                  <div className='text-sm text-red-500 bg-red-50 dark:bg-red-900/20 p-3 rounded-md'>
                    Error: {depositError.message}
                  </div>
                )}

                <Button
                  onClick={handleDeposit}
                  disabled={
                    !depositAmount ||
                    isDepositing ||
                    DEPOSIT_MANAGER_ADDRESS === '0x...'
                  }
                  className='w-full'
                >
                  {isDepositing
                    ? 'Depositing...'
                    : `Deposit ${selectedToken.symbol}`}
                </Button>

                {/* Contract Not Deployed Warning */}
                {DEPOSIT_MANAGER_ADDRESS === '0x...' && (
                  <div className='text-sm text-yellow-600 bg-yellow-50 dark:bg-yellow-900/20 p-3 rounded-md'>
                    ⚠️ Contract not deployed. Please deploy the DepositManager
                    contract first.
                  </div>
                )}
              </div>
            </div>

            {/* Balance Section */}
            <div className='bg-card rounded-lg shadow-sm border border-border p-6 mb-6'>
              <h2 className='text-xl font-semibold text-card-foreground mb-4'>
                Deposited Balance
              </h2>
              <div className='flex justify-between items-center'>
                <p className='text-lg text-card-foreground'>
                  <span className='font-mono'>
                    {depositedBalance.toLocaleString(undefined, {
                      maximumFractionDigits: 6,
                    })}{' '}
                    {selectedToken.symbol}
                  </span>
                </p>
                {depositedBalance > 0 && (
                  <Button
                    variant='outline'
                    size='sm'
                    onClick={() => console.log('Withdraw clicked')}
                  >
                    Withdraw
                  </Button>
                )}
              </div>
            </div>

            {/* Borrow Section */}
            <div className='bg-card rounded-lg shadow-sm border border-border p-6'>
              <h2 className='text-xl font-semibold text-card-foreground mb-4'>
                Borrow
              </h2>
              <p className='text-muted-foreground'>
                Deposit collateral to enable borrowing.
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
