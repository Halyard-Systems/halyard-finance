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
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
} from 'wagmi'

import DEPOSIT_MANAGER_ABI from '../abis/DepositManager.json'
import { fromWei, toWei, formatTransactionError } from '../lib/utils'
import { useReadDepositManagerBalance } from '../lib/hooks'
import type { Token } from '../lib/types'
import { portfolioData } from '@/lib/sample-data'

interface WithdrawFormProps {
  isOpen: boolean
  onClose: () => void
  onTransactionComplete?: () => void
  onTransactionError?: (error: string) => void
}

export function WithdrawForm({
  isOpen,
  onClose,
  onTransactionComplete,
  onTransactionError,
}: WithdrawFormProps) {
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

  const { data: depositedBalanceData } = useReadDepositManagerBalance(
    address! as `0x${string}`,
    ('0x' + '0'.repeat(64)) as `0x${string}` // Mock token ID
  )

  const depositedBalance = fromWei(
    (depositedBalanceData as bigint) || BigInt(0),
    selectedToken.decimals
  )

  const [withdrawAmount, setWithdrawAmount] = useState('')

  const {
    writeContract: writeWithdraw,
    isPending: isWithdrawing,
    error: withdrawError,
    data: withdrawData,
  } = useWriteContract()

  // Wait for transaction receipt and handle completion
  const {
    isLoading: isConfirming,
    isSuccess: isConfirmed,
    isError: isTransactionError,
    error: transactionError,
  } = useWaitForTransactionReceipt({
    hash: withdrawData,
  })

  // Handle transaction completion
  useEffect(() => {
    if (isConfirmed) {
      // Clear the input after successful withdraw
      setWithdrawAmount('')
      onClose()
      // Trigger data refresh
      onTransactionComplete?.()
    }
  }, [isConfirmed, onTransactionComplete, onClose])

  // Handle transaction errors
  useEffect(() => {
    if (isTransactionError && transactionError) {
      const formattedError = formatTransactionError(transactionError.message)
      onTransactionError?.(formattedError)
    }
  }, [isTransactionError, transactionError, onTransactionError])

  const handleWithdraw = async () => {
    if (!withdrawAmount || !address) {
      console.error('Invalid withdraw amount or address')
      return
    }

    try {
      // Convert amount to wei using token decimals
      const amountInWei = toWei(Number(withdrawAmount), selectedToken.decimals)

      // Call the withdraw function
      await writeWithdraw({
        address: import.meta.env.VITE_DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
        abi: DEPOSIT_MANAGER_ABI,
        functionName: 'withdraw',
        args: ['0x' + '0'.repeat(64), amountInWei], // Mock token ID
      })
    } catch (error) {
      console.error('Withdraw failed:', error)
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className='max-h-[90vh] overflow-y-auto sm:max-w-6xl'>
        <DialogHeader>
          <DialogTitle>Withdraw {selectedToken.symbol}</DialogTitle>
          <DialogDescription>
            Enter the amount of {selectedToken.symbol} you want to withdraw from
            your deposited collateral.
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
              disabled={isWithdrawing || isConfirming}
              max={depositedBalance}
            />
          </div>

          {/* Error Display */}
          {withdrawError && (
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
                  {formatTransactionError(withdrawError?.message || '')}
                </div>
              </div>
            </div>
          )}
        </div>

        <DialogFooter className='flex space-x-2'>
          <Button variant='outline' onClick={onClose} className='flex-1'>
            Cancel
          </Button>
          <Button
            onClick={handleWithdraw}
            disabled={
              !withdrawAmount ||
              isWithdrawing ||
              isConfirming ||
              Number(withdrawAmount) > depositedBalance ||
              Number(withdrawAmount) <= 0
            }
            className='flex-1'
          >
            {isWithdrawing
              ? 'Withdrawing...'
              : isConfirming
              ? 'Confirming...'
              : `Withdraw ${selectedToken.symbol}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
