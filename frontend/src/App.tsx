import React, { useEffect, useState } from 'react'
import {
  useAccount,
  useConnect,
  useDisconnect,
  useReadContract,
  useWriteContract,
} from 'wagmi'
import { injected } from 'wagmi/connectors'
import { Button } from './components/ui/button'
import { DepositForm } from './components/DepositForm'
import { WithdrawForm } from './components/WithdrawForm'
import halyardLogo from './assets/halyard-finance-navbar-logo-cyan-gold.png'

import TOKENS from './tokens.json'
import ERC20_ABI from './abis/ERC20.json'
import DEPOSIT_MANAGER_ABI from './abis/DepositManager.json'

// Contract addresses - youll need to update these with your deployed contract addresses
//const DEPOSIT_MANAGER_ADDRESS = '0x2e590d65Dd357a7565EfB5ffB329F8465F18c494'

function App() {
  const [depositAmount, setDepositAmount] = useState('')
  //const [withdrawAmount, setWithdrawAmount] = useState('')
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
      import.meta.env.VITE_DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
    ],
  })
  const allowance = allowanceRaw ? Number(allowanceRaw) / 1e6 : 0

  // Read Stargate router address from DepositManager
  const { data: stargateRouterAddress } = useReadContract({
    address: import.meta.env.VITE_DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
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
    address: import.meta.env.VITE_DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
    abi: DEPOSIT_MANAGER_ABI,
    functionName: 'balanceOf',
    args: [address ?? '0x0000000000000000000000000000000000000000'],
  })

  // Update deposited balance when data changes
  useEffect(() => {
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
  // const {
  //   writeContract: writeWithdraw,
  //   isPending: isWithdrawing,
  //   error: withdrawError,
  // } = useWriteContract()

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
          args: [
            import.meta.env.VITE_DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
            amountInWei,
          ],
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
        address: import.meta.env.VITE_DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
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

  // const handleWithdraw = async () => {
  //   if (!withdrawAmount || !address) {
  //     console.error('Invalid withdraw amount or address')
  //     return
  //   }

  //   try {
  //     // Convert amount to wei (USDC has 6 decimals)
  //     const amountInWei = BigInt(Math.floor(Number(withdrawAmount) * 1e6))

  //     // Call the withdraw function
  //     await writeWithdraw({
  //       address: VITE_DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
  //       abi: DEPOSIT_MANAGER_ABI,
  //       functionName: 'withdraw',
  //       args: [amountInWei],
  //     })

  //     // Clear the input after successful withdraw
  //     setWithdrawAmount('')
  //     setIsWithdrawModalOpen(false)
  //   } catch (error) {
  //     console.error('Withdraw failed:', error)
  //   }
  // }

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
        <DepositForm
          isOpen={isDepositModalOpen}
          onClose={() => setIsDepositModalOpen(false)}
          selectedToken={selectedToken}
          depositAmount={depositAmount}
          setDepositAmount={setDepositAmount}
          usdcBalance={usdcBalance}
          allowance={allowance}
          stargateAllowance={stargateAllowance}
          stargateRouterAddress={stargateRouterAddress as string | undefined}
          needsApproval={needsApproval}
          needsDepositManagerApproval={needsDepositManagerApproval}
          needsStargateApproval={needsStargateApproval}
          isDropdownOpen={isDropdownOpen}
          setIsDropdownOpen={setIsDropdownOpen}
          setSelectedToken={setSelectedToken}
          approvalError={approvalError}
          depositError={depositError}
          isApproving={isApproving}
          isDepositing={isDepositing}
          onApproval={handleApproval}
          onDeposit={handleDeposit}
          getApprovalButtonText={getApprovalButtonText}
        />

        {/* Withdraw Modal */}
        <WithdrawForm
          isOpen={isWithdrawModalOpen}
          //setIsWithdrawModalOpen={setIsWithdrawModalOpen}
          onClose={() => setIsWithdrawModalOpen(false)}
          selectedToken={selectedToken}
          //withdrawAmount={withdrawAmount}
          //setWithdrawAmount={setWithdrawAmount}
          depositedBalance={depositedBalance}
          //withdrawError={withdrawError}
          //isWithdrawing={isWithdrawing}
          //onWithdraw={handleWithdraw}
        />
      </main>
    </div>
  )
}

export default App
