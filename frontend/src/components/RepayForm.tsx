import { useState, useEffect } from 'react'
import { Button } from './ui/button'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogDescription,
} from './ui/dialog'

import ERC20_ABI from '../abis/ERC20.json'
import BORROW_MANAGER_ABI from '../abis/BorrowManager.json'
import type { Token } from '../lib/types'
import { toWei, fromWei, formatTransactionError } from '../lib/utils'
import { portfolioData } from '@/lib/sample-data'

import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useBalance,
} from 'wagmi'
import {
  useReadDepositManagerAllowance,
  useReadERC20Balance,
} from '@/lib/hooks'

interface RepayFormProps {
  isOpen: boolean
  onClose: () => void
  borrows: bigint[]
  onTransactionComplete?: () => void
  onTransactionError?: (error: string) => void
}

export function RepayForm({
  isOpen,
  onClose,
  borrows,
  onTransactionComplete,
  onTransactionError,
}: RepayFormProps) {
  const { address } = useAccount()

  // Chain and asset selection state
  const [selectedChain, setSelectedChain] = useState(portfolioData[0])
  const [selectedAsset, setSelectedAsset] = useState(selectedChain.assets[0])
  const [isChainDropdownOpen, setIsChainDropdownOpen] = useState(false)
  const [isAssetDropdownOpen, setIsAssetDropdownOpen] = useState(false)

  // Update selected asset when chain changes
  useEffect(() => {
    setSelectedAsset(selectedChain.assets[0])
  }, [selectedChain])

  // Close dropdowns when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      const target = event.target as Element
      if (
        !target.closest('[data-chain-dropdown]') &&
        !target.closest('[data-asset-dropdown]')
      ) {
        setIsChainDropdownOpen(false)
        setIsAssetDropdownOpen(false)
      }
    }

    if (isChainDropdownOpen || isAssetDropdownOpen) {
      document.addEventListener('mousedown', handleClickOutside)
    }

    return () => {
      document.removeEventListener('mousedown', handleClickOutside)
    }
  }, [isChainDropdownOpen, isAssetDropdownOpen])

  // Create a mock Token object from the selected asset
  const selectedToken: Token = {
    symbol: selectedAsset.asset,
    name: selectedAsset.asset,
    icon: `/public/${selectedAsset.logo}`,
    decimals: 18, // Default to 18 decimals, would need to be mapped properly in real implementation
    address:
      selectedAsset.asset === 'ETH'
        ? '0x0000000000000000000000000000000000000000'
        : '0x' + '0'.repeat(40), // Mock address
  }

  let borrowedAmount = 0
  if (borrows?.length > 0) {
    if (selectedToken.symbol === 'ETH') {
      borrowedAmount = fromWei(borrows[0], selectedToken.decimals) as number
    } else if (selectedToken.symbol === 'USDC') {
      borrowedAmount = fromWei(borrows[1], selectedToken.decimals) as number
    } else {
      borrowedAmount = fromWei(borrows[2], selectedToken.decimals) as number
    }
  }

  let walletBalance = 0

  if (selectedToken.symbol === 'ETH') {
    const { data: walletBalanceData } = useBalance({
      address: address! as `0x${string}`,
    })
    walletBalance = fromWei(
      walletBalanceData?.value || BigInt(0),
      selectedToken.decimals
    )
  } else {
    const { data: walletBalanceData } = useReadERC20Balance(
      selectedToken,
      address! as `0x${string}`
    )
    walletBalance = fromWei(walletBalanceData as any, selectedToken.decimals)
  }

  const { data: allowance, refetch: refetchAllowance } =
    useReadDepositManagerAllowance(address! as `0x${string}`, selectedToken)

  const [repayAmount, setRepayAmount] = useState('')

  // Check if approval is needed (only for ERC20 tokens, not ETH)
  const repayAmountNumber = Number(repayAmount) || 0
  const isETH =
    selectedToken.address === '0x0000000000000000000000000000000000000000'

  // Convert allowance to a number for comparison
  const allowanceNumber = allowance
    ? fromWei(allowance as bigint, selectedToken.decimals)
    : 0

  const needsApproval =
    !isETH && repayAmountNumber > 0 && repayAmountNumber > allowanceNumber

  console.log('Repay amount:', repayAmountNumber)
  console.log('Allowance number:', allowanceNumber)
  console.log('Needs approval:', needsApproval)

  const {
    writeContract: writeApproval,
    isPending: isApproving,
    error: approvalError,
    data: approvalData,
  } = useWriteContract()

  const {
    writeContract: writeRepay,
    isPending: isRepaying,
    error: repayError,
    data: repayData,
  } = useWriteContract()

  // Wait for transaction receipts and handle completion
  const {
    isLoading: isApprovalConfirming,
    isSuccess: isApprovalConfirmed,
    isError: isApprovalError,
    error: approvalTransactionError,
  } = useWaitForTransactionReceipt({
    hash: approvalData,
  })

  const {
    isLoading: isRepayConfirming,
    isSuccess: isRepayConfirmed,
    isError: isRepayError,
    error: repayTransactionError,
  } = useWaitForTransactionReceipt({
    hash: repayData,
  })

  // Handle approval completion
  useEffect(() => {
    if (isApprovalConfirmed) {
      // Refetch allowance data to update the UI
      refetchAllowance()
      // Optionally trigger data refresh in parent
      onTransactionComplete?.()
    }
  }, [isApprovalConfirmed, refetchAllowance, onTransactionComplete])

  // Handle deposit completion
  useEffect(() => {
    if (isRepayConfirmed) {
      // Clear the input after successful deposit
      setRepayAmount('')
      onClose()
      // Optionally trigger data refresh in parent
      onTransactionComplete?.()
    }
  }, [isRepayConfirmed, onTransactionComplete, onClose])

  // Handle transaction errors
  useEffect(() => {
    if (isApprovalError && approvalTransactionError) {
      const formattedError = formatTransactionError(
        approvalTransactionError.message
      )
      onTransactionError?.(formattedError)
    }
  }, [isApprovalError, approvalTransactionError, onTransactionError])

  useEffect(() => {
    if (isRepayError && repayTransactionError) {
      const formattedError = formatTransactionError(
        repayTransactionError.message
      )
      onTransactionError?.(formattedError)
    }
  }, [isRepayError, repayTransactionError, onTransactionError])

  const handleApproval = async () => {
    if (!repayAmount || !address || isETH) {
      console.error('Invalid repay amount, address, or trying to approve ETH')
      return
    }

    try {
      const amountInWei = toWei(Number(repayAmount), selectedToken.decimals)

      // Call the approve function for DepositManager (BorrowManager uses DepositManager for transfers)
      await writeApproval({
        address: selectedToken.address as `0x${string}`,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [
          import.meta.env.VITE_DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
          amountInWei,
        ],
      })
    } catch (error) {
      console.error('Approval failed:', error)
    }
  }

  const handleRepay = async () => {
    if (!repayAmount || !address) {
      console.error('Invalid repay amount or address')
      return
    }

    try {
      if (isETH) {
        // Handle ETH repay
        const amountInWei = toWei(Number(repayAmount), selectedToken.decimals)

        await writeRepay({
          address: import.meta.env.VITE_BORROW_MANAGER_ADDRESS as `0x${string}`,
          abi: BORROW_MANAGER_ABI,
          functionName: 'repay',
          args: [('0x' + '0'.repeat(64)) as `0x${string}`, amountInWei], // Mock token ID
          value: amountInWei, // Send ETH with the transaction
        })
      } else {
        // Handle ERC20 token repay
        const amountInWei = toWei(Number(repayAmount), selectedToken.decimals)

        await writeRepay({
          address: import.meta.env.VITE_BORROW_MANAGER_ADDRESS as `0x${string}`,
          abi: BORROW_MANAGER_ABI,
          functionName: 'repay',
          args: [('0x' + '0'.repeat(64)) as `0x${string}`, amountInWei], // Mock token ID
        })
      }
    } catch (error) {
      console.error('Repay failed:', error)
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className='max-h-[90vh] overflow-y-auto sm:max-w-6xl'>
        <DialogHeader>
          <DialogTitle>Repay {selectedToken.symbol}</DialogTitle>
          <DialogDescription>
            Enter the amount of {selectedToken.symbol} you want to repay.
          </DialogDescription>
        </DialogHeader>

        <div className='space-y-4 w-full min-w-0'>
          {/* Chain Selection */}
          <div className='w-full min-w-0'>
            <label className='block text-sm font-medium text-card-foreground mb-2'>
              Chain
            </label>
            <div className='relative' data-chain-dropdown>
              <button
                type='button'
                onClick={() => setIsChainDropdownOpen(!isChainDropdownOpen)}
                className='w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground text-left flex items-center justify-between'
              >
                <div className='flex items-center space-x-2'>
                  <img
                    src={`/public/${selectedChain.logo}`}
                    alt={`${selectedChain.chain} icon`}
                    className='w-4 h-4'
                  />
                  <span>{selectedChain.chain}</span>
                </div>
                <svg
                  className={`w-4 h-4 transition-transform ${
                    isChainDropdownOpen ? 'rotate-180' : ''
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

              {isChainDropdownOpen && (
                <div className='absolute z-10 w-full mt-1 bg-background border border-input rounded-md shadow-lg max-h-60 overflow-y-auto'>
                  {portfolioData.map((chain) => (
                    <button
                      key={chain.chain}
                      type='button'
                      onClick={() => {
                        setSelectedChain(chain)
                        setIsChainDropdownOpen(false)
                      }}
                      className='w-full px-3 py-2 text-left hover:bg-muted flex items-center space-x-2'
                    >
                      <img
                        src={`/public/${chain.logo}`}
                        alt={`${chain.chain} icon`}
                        className='w-4 h-4'
                      />
                      <span>{chain.chain}</span>
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Asset Selection */}
          <div className='w-full min-w-0'>
            <label className='block text-sm font-medium text-card-foreground mb-2'>
              Asset
            </label>
            <div className='relative' data-asset-dropdown>
              <button
                type='button'
                onClick={() => setIsAssetDropdownOpen(!isAssetDropdownOpen)}
                className='w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground text-left flex items-center justify-between'
              >
                <div className='flex items-center space-x-2'>
                  <img
                    src={selectedToken.icon}
                    alt={`${selectedToken.symbol} icon`}
                    className='w-4 h-4'
                  />
                  <span>{selectedAsset.asset}</span>
                </div>
                <svg
                  className={`w-4 h-4 transition-transform ${
                    isAssetDropdownOpen ? 'rotate-180' : ''
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

              {isAssetDropdownOpen && (
                <div className='absolute z-10 w-full mt-1 bg-background border border-input rounded-md shadow-lg max-h-60 overflow-y-auto'>
                  {selectedChain.assets.map((asset) => (
                    <button
                      key={asset.asset}
                      type='button'
                      onClick={() => {
                        setSelectedAsset(asset)
                        setIsAssetDropdownOpen(false)
                      }}
                      className='w-full px-3 py-2 text-left hover:bg-muted flex items-center space-x-2'
                    >
                      <img
                        src={`/public/${asset.logo}`}
                        alt={`${asset.asset} icon`}
                        className='w-4 h-4'
                      />
                      <span>{asset.asset}</span>
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Amount Input */}
          <div className='min-w-0'>
            <label className='block text-sm font-medium text-card-foreground mb-2'>
              Amount ({selectedToken.symbol})
            </label>
            <p className='text-sm text-muted-foreground mb-2 break-words'>
              Owed:{' '}
              {borrowedAmount.toLocaleString(undefined, {
                maximumFractionDigits: 6,
              })}
            </p>
            <p className='text-sm text-muted-foreground mb-2 break-words'>
              Available:{' '}
              {walletBalance.toLocaleString(undefined, {
                maximumFractionDigits: 6,
              })}
            </p>
            <input
              type='number'
              value={repayAmount}
              onChange={(e) => setRepayAmount(e.target.value)}
              placeholder={`0.00 ${selectedToken.symbol}`}
              className='w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground'
              disabled={
                isRepaying ||
                isRepayConfirming ||
                isApproving ||
                isApprovalConfirming
              }
            />
          </div>

          {/* Approval Status */}
          {repayAmount && !isETH && (
            <div className='text-sm text-muted-foreground p-3 bg-muted rounded-md w-full min-w-0'>
              <div className='space-y-2 w-full min-w-0'>
                <div className='flex justify-between items-center w-full min-w-0'>
                  <span className='truncate mr-2'>
                    DepositManager allowance:
                  </span>
                  <span className='font-mono text-right flex-shrink-0'>
                    {allowanceNumber.toLocaleString(undefined, {
                      maximumFractionDigits: 6,
                    })}{' '}
                    {selectedToken.symbol}
                  </span>
                </div>
              </div>
              {needsApproval && (
                <div className='mt-2 text-yellow-600 break-words'>
                  ⚠️ Approval required before deposit
                </div>
              )}
            </div>
          )}

          {/* Error Display */}
          {(approvalError || repayError) && (
            <div className='text-sm text-red-500 bg-red-50 dark:bg-red-900/20 p-3 rounded-md min-w-0'>
              <div className='flex items-start space-x-2'>
                <div className='flex-shrink-0 mt-0.5'>
                  <svg
                    className='w-4 h-4'
                    fill='currentColor'
                    viewBox='0 0 20 20'
                  >
                    <path
                      fillRule='evenodd'
                      d='M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z'
                      clipRule='evenodd'
                    />
                  </svg>
                </div>
                <div className='flex-1 break-words leading-relaxed'>
                  {formatTransactionError(
                    (approvalError || repayError)?.message || ''
                  )}
                </div>
              </div>
            </div>
          )}
        </div>

        <DialogFooter className='flex space-x-2'>
          <Button variant='outline' onClick={onClose} className='flex-1'>
            Cancel
          </Button>
          {needsApproval && repayAmount && (
            <Button
              onClick={handleApproval}
              disabled={!repayAmount || isApproving || isApprovalConfirming}
              className='flex-1'
            >
              {isApproving
                ? 'Approving...'
                : isApprovalConfirming
                ? 'Confirming Approval...'
                : `Approve ${selectedToken.symbol} for DepositManager`}
            </Button>
          )}
          <Button
            onClick={handleRepay}
            disabled={
              !repayAmount ||
              isRepaying ||
              isRepayConfirming ||
              isApproving ||
              isApprovalConfirming ||
              needsApproval
            }
            className='flex-1'
          >
            {isRepaying
              ? 'Repaying...'
              : isRepayConfirming
              ? 'Confirming Repay...'
              : `Repay ${selectedToken.symbol}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
