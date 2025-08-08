import { useState, useEffect } from 'react'
import { useSelector, useDispatch } from 'react-redux'
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
  useWriteContract,
  useWaitForTransactionReceipt,
  usePublicClient,
  useAccount,
} from 'wagmi'

import BORROW_MANAGER_ABI from '../abis/BorrowManager.json'
import { toWei, formatTransactionError } from '../lib/utils'
import type { Token } from '../lib/types'
import MOCK_PYTH_ABI from '../abis/MockPyth.json'
import type { RootState } from '../store/store'
import { maxBorrow } from '@/store/interactions'
import { useReadDepositManagerBalances } from '@/lib/hooks'

const USE_MOCK_PYTH = import.meta.env.VITE_USE_MOCK_PYTH === 'true'
const ETH_USDC_USDT_PRICE_IDS = [
  '0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace', // ETH/USD
  '0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a', // USDC/USD
  '0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b', // USDT/USD
]

// Helper to fetch Pyth update data for a given priceId using Hermes API
async function fetchPythUpdateDataFromHermes(
  priceIds: string[]
): Promise<string[]> {
  const url = `https://hermes.pyth.network/api/latest_vaas?ids[]=${priceIds.join(
    '&ids[]='
  )}&binary=true`
  const response = await fetch(url)
  if (!response.ok) throw new Error('Failed to fetch Pyth update data')
  const arrayBuffer = await response.arrayBuffer()
  const hex =
    '0x' +
    Array.from(new Uint8Array(arrayBuffer))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('')
  return [hex]
}

interface BorrowFormProps {
  isOpen: boolean
  onClose: () => void
  selectedToken: Token
  tokenId?: `0x${string}`
  tokenIds?: `0x${string}`[]
  borrows?: bigint[]
  onTransactionComplete?: () => void
  onTransactionError?: (error: string) => void
}

export function BorrowForm({
  isOpen,
  onClose,
  selectedToken,
  tokenId,
  tokenIds,
  borrows,
  onTransactionComplete,
  onTransactionError,
}: BorrowFormProps) {
  const { address } = useAccount()
  const { data: deposits } = useReadDepositManagerBalances(
    address! as `0x${string}`,
    tokenIds!
  )
  console.log('deposits', deposits)
  const dispatch = useDispatch()
  const maxBorrowable = useSelector(
    (state: RootState) => state.borrowManager.maxBorrow
  )

  const publicClient = usePublicClient()

  const {
    writeContract: writeBorrow,
    isPending: isBorrowing,
    error: borrowError,
    data: borrowData,
  } = useWriteContract()

  // Wait for transaction receipt and handle completion
  const {
    isLoading: isConfirming,
    isSuccess: isConfirmed,
    isError: isTransactionError,
    error: transactionError,
  } = useWaitForTransactionReceipt({
    hash: borrowData,
  })

  const [borrowAmount, setBorrowAmount] = useState('')
  const [customError, setCustomError] = useState<string | null>(null)

  // Calculate max borrowable when component mounts or when maxBorrowable is 0
  useEffect(() => {
    //if (maxBorrowable === undefined) {
    maxBorrow(
      ETH_USDC_USDT_PRICE_IDS,
      {
        eth: deposits?.[0].result as bigint,
        usdc: deposits?.[1].result as bigint,
        usdt: deposits?.[2].result as bigint,
      },
      {
        eth: borrows?.[0] as bigint,
        usdc: borrows?.[1] as bigint,
        usdt: borrows?.[2] as bigint,
      },
      dispatch
    )
    //}
  }, [maxBorrowable, dispatch])

  // Handle transaction completion
  useEffect(() => {
    if (isConfirmed) {
      // Clear the input and errors after successful borrow
      setBorrowAmount('')
      setCustomError(null)
      onClose()
      // Trigger data refresh
      onTransactionComplete?.()
    }
  }, [isConfirmed, onTransactionComplete, onClose])

  // Handle transaction errors
  useEffect(() => {
    if (isTransactionError && transactionError) {
      const formattedError = formatTransactionError(transactionError.message)
      setCustomError(formattedError)
      onTransactionError?.(formattedError)
    }
  }, [isTransactionError, transactionError, onTransactionError])

  // Clear errors when modal opens/closes
  useEffect(() => {
    if (isOpen) {
      setCustomError(null)
    }
  }, [isOpen])

  const handleBorrow = async () => {
    try {
      // Clear any previous errors
      setCustomError(null)

      if (!publicClient) {
        throw new Error('Public client not available')
      }

      const amountInWei = toWei(Number(borrowAmount), selectedToken.decimals)

      let pythUpdateData: string[]
      if (USE_MOCK_PYTH) {
        console.log('Using mock Pyth')
        // Use empty arrays since price feeds are already set up in deployment
        pythUpdateData = []
      } else {
        try {
          pythUpdateData = await fetchPythUpdateDataFromHermes(
            ETH_USDC_USDT_PRICE_IDS
          )
        } catch (error) {
          throw new Error(
            `Failed to fetch price data: ${
              error instanceof Error ? error.message : 'Unknown error'
            }`
          )
        }
      }

      // Calculate the required fee for Pyth update
      let fee: bigint
      if (USE_MOCK_PYTH) {
        // For MockPyth with empty update data, fee is 0
        fee = 0n
      } else {
        try {
          fee = (await publicClient.readContract({
            address: import.meta.env.VITE_MOCK_PYTH_ADDRESS as `0x${string}`,
            abi: MOCK_PYTH_ABI,
            functionName: 'getUpdateFee',
            args: [pythUpdateData],
          })) as bigint
        } catch (error) {
          throw new Error(
            `Failed to calculate fee: ${
              error instanceof Error ? error.message : 'Unknown error'
            }`
          )
        }
      }

      await writeBorrow({
        address: import.meta.env.VITE_BORROW_MANAGER_ADDRESS as `0x${string}`,
        abi: BORROW_MANAGER_ABI,
        functionName: 'borrow',
        args: [tokenId, amountInWei, pythUpdateData, ETH_USDC_USDT_PRICE_IDS],
        value: fee, // Send the required fee
      })
    } catch (error) {
      console.error('Borrow failed:', error)
      const rawErrorMessage =
        error instanceof Error ? error.message : 'Unknown error'
      const formattedError = formatTransactionError(rawErrorMessage)
      setCustomError(formattedError)
      onTransactionError?.(formattedError)
    }
  }

  // Combine all error sources (prefer formatted customError; otherwise format raw messages)
  let displayError: string | null = null
  if (customError) {
    displayError = customError
  } else if (borrowError?.message) {
    displayError = formatTransactionError(borrowError.message)
  } else if (transactionError?.message) {
    displayError = formatTransactionError(transactionError.message)
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className='sm:max-w-md max-h-[90vh] overflow-y-auto overflow-x-hidden'>
        <DialogHeader>
          <DialogTitle>Borrow {selectedToken.symbol}</DialogTitle>
          <DialogDescription>
            Enter the amount of {selectedToken.symbol} you want to borrow. Make
            sure you have sufficient collateral.
          </DialogDescription>
        </DialogHeader>

        <div className='space-y-4 min-w-0'>
          {/* Token Info */}
          <div className='flex items-center space-x-2 p-3 bg-muted rounded-md min-w-0'>
            <img
              src={selectedToken.icon}
              alt={`${selectedToken.symbol} icon`}
              className='w-6 h-6 flex-shrink-0'
            />
            <div className='min-w-0 flex-1'>
              <div className='font-medium text-card-foreground truncate'>
                {selectedToken.symbol}
              </div>
              <div className='text-sm text-muted-foreground truncate'>
                {selectedToken.name}
              </div>
            </div>
          </div>

          {/* Amount Input */}
          <div className='min-w-0'>
            <label className='block text-sm font-medium text-card-foreground mb-2'>
              Amount ({selectedToken.symbol})
            </label>
            <p className='text-sm text-muted-foreground mb-2 break-words'>
              Max borrowable:{' '}
              {maxBorrowable !== undefined
                ? (maxBorrowable as number).toLocaleString(undefined, {
                    maximumFractionDigits: 6,
                  })
                : 'Loading...'}
            </p>
            <input
              type='number'
              value={borrowAmount}
              onChange={(e) => setBorrowAmount(e.target.value)}
              placeholder={`0.00 ${selectedToken.symbol}`}
              className='w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground'
              disabled={isBorrowing || isConfirming}
              max={maxBorrowable}
            />
          </div>

          {/* Error Display */}
          {displayError && (
            <div className='text-sm text-red-500 bg-red-50 dark:bg-red-900/20 p-3 rounded-md min-w-0 overflow-x-hidden'>
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
                <div className='flex-1 break-words break-all whitespace-pre-wrap leading-relaxed'>
                  {displayError}
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
            onClick={handleBorrow}
            disabled={
              !borrowAmount ||
              !tokenId ||
              isBorrowing ||
              isConfirming ||
              Number(borrowAmount) > Number(maxBorrowable) ||
              Number(borrowAmount) <= 0 ||
              maxBorrowable === undefined
            }
            className='flex-1'
          >
            {isBorrowing
              ? 'Borrowing...'
              : isConfirming
              ? 'Confirming...'
              : `Borrow ${selectedToken.symbol}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
