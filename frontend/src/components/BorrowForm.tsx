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
import PYTH_ABI from '../abis/IPyth.json'
import MOCK_PYTH_ABI from '../abis/MockPyth.json'
import type { RootState } from '../store/store'
import { maxBorrow } from '../store/interactions'
import { useReadDepositManagerBalances } from '../lib/hooks'
import {
  ETH_USDC_USDT_PRICE_IDS,
  createMockPriceFeedUpdateData,
  updateMockPriceFeeds,
} from '../lib/prices'

const USE_MOCK_PYTH = import.meta.env.VITE_USE_MOCK_PYTH === 'true'

// Helper to fetch Pyth update data using the Hermes client
import { HermesClient } from '@pythnetwork/hermes-client'
import { portfolioData } from '@/sample-data'

async function fetchPythUpdateDataFromHermes(
  priceIds: string[]
): Promise<`0x${string}`[]> {
  const client = new HermesClient('https://hermes.pyth.network')

  // Try to get individual price updates for each price ID
  const individualUpdates: `0x${string}`[] = []

  for (const priceId of priceIds) {
    try {
      const singlePriceUpdate = await client.getLatestPriceUpdates(
        [priceId],
        {}
      )

      if (singlePriceUpdate.binary?.data) {
        const data = singlePriceUpdate.binary.data
        if (Array.isArray(data) && data.length > 0) {
          const updateData = data[0] as string
          individualUpdates.push(
            (updateData.startsWith('0x')
              ? updateData
              : `0x${updateData}`) as `0x${string}`
          )
        } else if (typeof data === 'string') {
          const updateData = data as string
          individualUpdates.push(
            (updateData.startsWith('0x')
              ? updateData
              : `0x${updateData}`) as `0x${string}`
          )
        }
      }
    } catch (error) {
      console.error(`Failed to fetch price update for ${priceId}:`, error)
    }
  }

  if (individualUpdates.length === 0) {
    throw new Error('Failed to get any price update data from Hermes')
  }

  return individualUpdates
}

interface BorrowFormProps {
  isOpen: boolean
  onClose: () => void
  tokenIds?: `0x${string}`[]
  borrows?: bigint[]
  onTransactionComplete?: () => void
  onTransactionError?: (error: string) => void
}

export function BorrowForm({
  isOpen,
  onClose,
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

  const { writeContract: writeMockPyth } = useWriteContract()

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
  const [isUpdatingMockPyth, setIsUpdatingMockPyth] = useState(false)
  const [selectedToken, setSelectedToken] = useState(portfolioData[0].assets[0])

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

      // Check if user has sufficient deposits
      if (!deposits || deposits.length === 0) {
        throw new Error('No deposits found. Please deposit some tokens first.')
      }

      // Check if user has any deposits
      const hasDeposits = deposits.some(
        (deposit) => deposit.result && Number(deposit.result) > 0
      )
      if (!hasDeposits) {
        throw new Error('No deposits found. Please deposit some tokens first.')
      }

      // Check if max borrowable is available and sufficient
      if (maxBorrowable === undefined || maxBorrowable <= 0) {
        throw new Error(
          'Unable to calculate max borrowable amount. Please try again.'
        )
      }

      if (Number(borrowAmount) > maxBorrowable) {
        throw new Error(
          `Borrow amount exceeds maximum borrowable amount of ${maxBorrowable.toLocaleString()}`
        )
      }

      const amountInWei = toWei(Number(borrowAmount), selectedToken.decimals)

      let pythUpdateData: string[] = []
      let fee: bigint

      if (USE_MOCK_PYTH) {
        console.log('Using mock Pyth')
        const mockPythAddress = import.meta.env
          .VITE_MOCK_PYTH_ADDRESS as `0x${string}`

        try {
          setIsUpdatingMockPyth(true)

          // Get the most recent block timestamp right before creating price data
          const latestBlockNumber = await publicClient.getBlockNumber()
          const latestBlock = await publicClient.getBlock({
            blockNumber: latestBlockNumber,
          })
          console.log(
            'Latest block timestamp before price creation:',
            latestBlock.timestamp
          )

          // Create mock price feed update data with the most recent timestamp
          let pythUpdateData = await createMockPriceFeedUpdateData(
            publicClient,
            mockPythAddress
          )

          // Update all mock price feeds in a single transaction
          try {
            await updateMockPriceFeeds(
              publicClient,
              mockPythAddress,
              pythUpdateData,
              writeMockPyth
            )
          } catch (updateError) {
            console.error(
              'Failed to update mock price feeds, trying with empty data:',
              updateError
            )
            // Fallback: try with empty update data (prices might already be set up)
            pythUpdateData = []
          }

          setIsUpdatingMockPyth(false)

          // Calculate the required fee for the borrow transaction
          fee = (await publicClient.readContract({
            address: mockPythAddress,
            abi: MOCK_PYTH_ABI,
            functionName: 'getUpdateFee',
            args: [pythUpdateData],
          })) as bigint
        } catch (error) {
          setIsUpdatingMockPyth(false)
          throw new Error(
            `Failed to update mock price feeds: ${
              error instanceof Error ? error.message : 'Unknown error'
            }`
          )
        }
      } else {
        try {
          pythUpdateData = await fetchPythUpdateDataFromHermes(
            ETH_USDC_USDT_PRICE_IDS
          )

          fee = (await publicClient.readContract({
            // Pyth Sepolia
            address:
              '0xDd24F84d36BF92C65F92307595335bdFab5Bbd21' as `0x${string}`,
            abi: PYTH_ABI,
            functionName: 'getUpdateFee',
            args: [pythUpdateData],
          })) as bigint
        } catch (error) {
          throw new Error(
            `Failed to fetch price data: ${
              error instanceof Error ? error.message : 'Unknown error'
            }`
          )
        }
      }

      await writeBorrow({
        address: import.meta.env.VITE_BORROW_MANAGER_ADDRESS as `0x${string}`,
        abi: BORROW_MANAGER_ABI,
        functionName: 'borrow',
        args: [
          //tokenId, 
          amountInWei, pythUpdateData, ETH_USDC_USDT_PRICE_IDS],
        value: fee, // Send the required fee
      })
    } catch (error) {
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
          <DialogTitle>Borrow {selectedToken.ticker}</DialogTitle>
          <DialogDescription>
            Enter the amount of {selectedToken.ticker} you want to borrow. Make
            sure you have sufficient collateral.
          </DialogDescription>
        </DialogHeader>

        <div className='space-y-4 min-w-0'>
          {/* Token Info */}
          <div className='flex items-center space-x-2 p-3 bg-muted rounded-md min-w-0'>
            <img
              src={selectedToken.logo}
              alt={`${selectedToken.ticker} icon`}
              className='w-6 h-6 flex-shrink-0'
            />
            <div className='min-w-0 flex-1'>
              <div className='font-medium text-card-foreground truncate'>
                {selectedToken.ticker}
              </div>
              <div className='text-sm text-muted-foreground truncate'>
                {selectedToken.ticker}
              </div>
            </div>
          </div>

          {/* Amount Input */}
          <div className='min-w-0'>
            <label className='block text-sm font-medium text-card-foreground mb-2'>
              Amount ({selectedToken.ticker})
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
              placeholder={`0.00 ${selectedToken.ticker}`}
              className='w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground'
              disabled={isBorrowing || isConfirming || isUpdatingMockPyth}
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
              /*!tokenId || */
              isBorrowing ||
              isConfirming ||
              isUpdatingMockPyth ||
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
              : isUpdatingMockPyth
              ? 'Updating Prices...'
              : `Borrow ${selectedToken.ticker}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
