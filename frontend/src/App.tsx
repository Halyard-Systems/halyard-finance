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
  {
    type: 'function',
    name: 'allowance',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
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
    name: 'withdraw',
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
  {
    type: 'function',
    name: 'stargateRouter',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
  },
]

// Contract addresses - youll need to update these with your deployed contract addresses
const DEPOSIT_MANAGER_ADDRESS = '0x2e590d65Dd357a7565EfB5ffB329F8465F18c494'
function App() {
  const [depositAmount, setDepositAmount] = useState('')
  const [withdrawAmount, setWithdrawAmount] = useState('')
  const [selectedToken, setSelectedToken] = useState(TOKENS[0])
  const [isDropdownOpen, setIsDropdownOpen] = useState(false)
  const [depositedBalance, setDepositedBalance] = useState(0)
  const [isDepositModalOpen, setIsDepositModalOpen] = useState(false)
  const [isWithdrawModalOpen, setIsWithdrawModalOpen] = useState(false)
  const [approvalStep, setApprovalStep] = useState<
    'none' | 'depositManager' | 'stargate'
  >('none')
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

  // Read USDC allowance for DepositManager contract
  const {
    data: allowanceRaw,
    status: allowanceStatus,
    error: allowanceError,
  } = useReadContract({
    address: selectedToken.address as `0x${string}`,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: [
      address ?? '0x0000000000000000000000000000000000000000',
      DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
    ],
  })
  const allowance = allowanceRaw ? Number(allowanceRaw) / 1e6 : 0

  // Read Stargate router address from DepositManager
  const { data: stargateRouterAddress } = useReadContract({
    address: DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
    abi: DEPOSIT_MANAGER_ABI,
    functionName: 'stargateRouter',
  })

  // Read USDC allowance for Stargate router
  const {
    data: stargateAllowanceRaw,
    status: stargateAllowanceStatus,
    error: stargateAllowanceError,
  } = useReadContract({
    address: selectedToken.address as `0x${string}`,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: [
      address ?? '0x0000000000000000000000000000000000000000',
      stargateRouterAddress ?? '0x0000000000000000000000000000000000000000',
    ],
  })
  const stargateAllowance = stargateAllowanceRaw
    ? Number(stargateAllowanceRaw) / 1e6
    : 0

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

  // Write contract hook for approval
  const {
    writeContract: writeApproval,
    isPending: isApproving,
    error: approvalError,
  } = useWriteContract()

  // Write contract hook for deposit
  const {
    writeContract: writeDeposit,
    isPending: isDepositing,
    error: depositError,
  } = useWriteContract()

  // Write contract hook for withdraw
  const {
    writeContract: writeWithdraw,
    isPending: isWithdrawing,
    error: withdrawError,
  } = useWriteContract()

  const handleApproval = async () => {
    if (!depositAmount || !address) {
      console.error('Invalid deposit amount or address')
      return
    }

    try {
      // Convert amount to wei (USDC has 6 decimals)
      const amountInWei = BigInt(Math.floor(Number(depositAmount) * 1e6))

      // Determine which approval is needed
      const depositAmountNumber = Number(depositAmount)
      const needsDepositManagerApproval = depositAmountNumber > allowance
      const needsStargateApproval = depositAmountNumber > stargateAllowance

      if (needsDepositManagerApproval) {
        setApprovalStep('depositManager')
        // Call the approve function for DepositManager
        await writeApproval({
          address: selectedToken.address as `0x${string}`,
          abi: ERC20_ABI,
          functionName: 'approve',
          args: [DEPOSIT_MANAGER_ADDRESS as `0x${string}`, amountInWei],
        })
      } else if (needsStargateApproval && stargateRouterAddress) {
        setApprovalStep('stargate')
        // Call the approve function for Stargate router
        await writeApproval({
          address: selectedToken.address as `0x${string}`,
          abi: ERC20_ABI,
          functionName: 'approve',
          args: [stargateRouterAddress as `0x${string}`, amountInWei],
        })
      }

      setApprovalStep('none')
    } catch (error) {
      console.error('Approval failed:', error)
      setApprovalStep('none')
    }
  }

  const handleDeposit = async () => {
    if (!depositAmount || !address) {
      console.error('Invalid deposit amount or address')
      return
    }

    try {
      // Convert amount to wei (USDC has 6 decimals)
      const amountInWei = BigInt(Math.floor(Number(depositAmount) * 1e6))

      // Call the deposit function
      await writeDeposit({
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

  const handleWithdraw = async () => {
    if (!withdrawAmount || !address) {
      console.error('Invalid withdraw amount or address')
      return
    }

    try {
      // Convert amount to wei (USDC has 6 decimals)
      const amountInWei = BigInt(Math.floor(Number(withdrawAmount) * 1e6))

      // Call the withdraw function
      await writeWithdraw({
        address: DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
        abi: DEPOSIT_MANAGER_ABI,
        functionName: 'withdraw',
        args: [amountInWei],
      })

      // Clear the input after successful withdraw
      setWithdrawAmount('')
      setIsWithdrawModalOpen(false)
    } catch (error) {
      console.error('Withdraw failed:', error)
    }
  }

  // Check if approval is needed
  const depositAmountNumber = Number(depositAmount) || 0
  const needsDepositManagerApproval = depositAmountNumber > allowance
  const needsStargateApproval = depositAmountNumber > stargateAllowance
  const needsApproval = needsDepositManagerApproval || needsStargateApproval

  // Get approval button text
  const getApprovalButtonText = () => {
    if (isApproving) {
      if (approvalStep === 'depositManager') {
        return 'Approving for DepositManager...'
      } else if (approvalStep === 'stargate') {
        return 'Approving for Stargate...'
      }
      return 'Approving...'
    }

    if (needsDepositManagerApproval) {
      return `Approve ${selectedToken.symbol} for DepositManager`
    } else if (needsStargateApproval) {
      return `Approve ${selectedToken.symbol} for Stargate`
    }
    return `Approve ${selectedToken.symbol}`
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
        {isDepositModalOpen && (
          <div className='fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50'>
            <div className='bg-card rounded-lg shadow-lg border border-border p-6 w-full max-w-md mx-4'>
              <div className='flex justify-between items-center mb-4'>
                <h2 className='text-xl font-semibold text-card-foreground'>
                  Deposit
                </h2>
                <button
                  onClick={() => setIsDepositModalOpen(false)}
                  className='text-muted-foreground hover:text-foreground'
                >
                  <svg
                    className='w-6 h-6'
                    fill='none'
                    stroke='currentColor'
                    viewBox='0 0 24 24'
                  >
                    <path
                      strokeLinecap='round'
                      strokeLinejoin='round'
                      strokeWidth={2}
                      d='M6 18L18 6M6 6l12 12'
                    />
                  </svg>
                </button>
              </div>

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
                    Available:{' '}
                    {usdcBalance.toLocaleString(undefined, {
                      maximumFractionDigits: 6,
                    })}
                  </p>
                  <input
                    type='number'
                    value={depositAmount}
                    onChange={(e) => setDepositAmount(e.target.value)}
                    placeholder={`0.00 ${selectedToken.symbol}`}
                    className='w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground'
                    disabled={isDepositing || isApproving}
                  />
                </div>

                {/* Approval Status */}
                {depositAmount && (
                  <div className='text-sm text-muted-foreground p-3 bg-muted rounded-md'>
                    <div className='space-y-2'>
                      <div className='flex justify-between items-center'>
                        <span>DepositManager allowance:</span>
                        <span className='font-mono'>
                          {allowance.toLocaleString(undefined, {
                            maximumFractionDigits: 6,
                          })}{' '}
                          {selectedToken.symbol}
                        </span>
                      </div>
                      {stargateRouterAddress ? (
                        <div className='flex justify-between items-center'>
                          <span>Stargate allowance:</span>
                          <span className='font-mono'>
                            {stargateAllowance.toLocaleString('en-US', {
                              maximumFractionDigits: 6,
                            })}{' '}
                            {selectedToken.symbol}
                          </span>
                        </div>
                      ) : null}
                    </div>
                    {needsApproval && (
                      <div className='mt-2 text-yellow-600'>
                        ⚠️ Approval required before deposit
                        {needsDepositManagerApproval &&
                          needsStargateApproval && (
                            <span> (both DepositManager and Stargate)</span>
                          )}
                        {needsDepositManagerApproval &&
                          !needsStargateApproval && (
                            <span> (DepositManager)</span>
                          )}
                        {!needsDepositManagerApproval &&
                          needsStargateApproval && <span> (Stargate)</span>}
                      </div>
                    )}
                  </div>
                )}

                {/* Error Display */}
                {(approvalError || depositError) && (
                  <div className='text-sm text-red-500 bg-red-50 dark:bg-red-900/20 p-3 rounded-md'>
                    Error: {(approvalError || depositError)?.message}
                  </div>
                )}

                {/* Action Buttons */}
                <div className='flex space-x-2 pt-4'>
                  <Button
                    variant='outline'
                    onClick={() => setIsDepositModalOpen(false)}
                    className='flex-1'
                  >
                    Cancel
                  </Button>
                  {needsApproval && depositAmount && (
                    <Button
                      onClick={handleApproval}
                      disabled={!depositAmount || isApproving}
                      className='flex-1'
                    >
                      {getApprovalButtonText()}
                    </Button>
                  )}
                  <Button
                    onClick={handleDeposit}
                    disabled={
                      !depositAmount ||
                      isDepositing ||
                      isApproving ||
                      needsApproval
                    }
                    className='flex-1'
                  >
                    {isDepositing
                      ? 'Depositing...'
                      : `Deposit ${selectedToken.symbol}`}
                  </Button>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Withdraw Modal */}
        {isWithdrawModalOpen && (
          <div className='fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50'>
            <div className='bg-card rounded-lg shadow-lg border border-border p-6 w-full max-w-md mx-4'>
              <div className='flex justify-between items-center mb-4'>
                <h2 className='text-xl font-semibold text-card-foreground'>
                  Withdraw
                </h2>
                <button
                  onClick={() => setIsWithdrawModalOpen(false)}
                  className='text-muted-foreground hover:text-foreground'
                >
                  <svg
                    className='w-6 h-6'
                    fill='none'
                    stroke='currentColor'
                    viewBox='0 0 24 24'
                  >
                    <path
                      strokeLinecap='round'
                      strokeLinejoin='round'
                      strokeWidth={2}
                      d='M6 18L18 6M6 6l12 12'
                    />
                  </svg>
                </button>
              </div>

              <div className='space-y-4'>
                {/* Token Info */}
                <div className='flex items-center space-x-2 p-3 bg-muted rounded-md'>
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

                {/* Amount Input */}
                <div>
                  <label className='block text-sm font-medium text-card-foreground mb-2'>
                    Amount ({selectedToken.symbol})
                  </label>
                  <p className='text-sm text-muted-foreground mb-2'>
                    Available to withdraw:{' '}
                    {depositedBalance.toLocaleString(undefined, {
                      maximumFractionDigits: 6,
                    })}
                  </p>
                  <input
                    type='number'
                    value={withdrawAmount}
                    onChange={(e) => setWithdrawAmount(e.target.value)}
                    placeholder={`0.00 ${selectedToken.symbol}`}
                    className='w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground'
                    disabled={isWithdrawing}
                    max={depositedBalance}
                  />
                </div>

                {/* Error Display */}
                {withdrawError && (
                  <div className='text-sm text-red-500 bg-red-50 dark:bg-red-900/20 p-3 rounded-md'>
                    Error: {withdrawError?.message}
                  </div>
                )}

                {/* Action Buttons */}
                <div className='flex space-x-2 pt-4'>
                  <Button
                    variant='outline'
                    onClick={() => setIsWithdrawModalOpen(false)}
                    className='flex-1'
                  >
                    Cancel
                  </Button>
                  <Button
                    onClick={handleWithdraw}
                    disabled={
                      !withdrawAmount ||
                      isWithdrawing ||
                      Number(withdrawAmount) > depositedBalance ||
                      Number(withdrawAmount) <= 0
                    }
                    className='flex-1'
                  >
                    {isWithdrawing
                      ? 'Withdrawing...'
                      : `Withdraw ${selectedToken.symbol}`}
                  </Button>
                </div>
              </div>
            </div>
          </div>
        )}
      </main>
    </div>
  )
}

export default App
