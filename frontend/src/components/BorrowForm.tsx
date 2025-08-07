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
import { toWei } from '../lib/utils'
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

// Helper to create MockPyth update data - simplified approach
// async function createMockPythUpdateData(
//   publicClient: any,
//   priceId: string
// ): Promise<string> {
//   // Example arguments for the mock; adjust as needed
//   const price = 123 * 1e8 // Price in fixed-point format (123 USD with 8 decimals)
//   const conf = 100 // Confidence interval
//   const expo = -8 // Exponent for fixed-point representation
//   const emaPrice = 123 * 1e8 // EMA price in fixed-point format
//   const emaConf = 100 // EMA confidence interval
//   const publishTime = Math.floor(Date.now() / 1000)
//   const prevPublishTime = publishTime - 60

//   // Create the price feed data manually to match what updatePriceFeeds expects
//   // MockPyth.updatePriceFeeds expects just the PriceFeed struct, not (PriceFeed, prevPublishTime)
//   const priceFeed = {
//     id: priceId,
//     price: {
//       price: price,
//       conf: conf,
//       expo: expo,
//       publishTime: publishTime,
//     },
//     emaPrice: {
//       price: emaPrice,
//       conf: emaConf,
//       expo: expo,
//       publishTime: publishTime,
//     },
//   }

//   // For now, let's use a simpler approach - just return empty data
//   // and rely on the price feeds that are already set up in deployment
//   console.log('Creating mock price feed data for:', priceId)
//   console.log('Price feed:', priceFeed)

//   // Return empty data to avoid the encoding issue
//   // The price feeds should already be set up in the deployment script
//   return '0x'
// }

interface BorrowFormProps {
  isOpen: boolean
  onClose: () => void
  selectedToken: Token
  tokenId?: `0x${string}`
  tokenIds?: `0x${string}`[]
  borrows?: bigint[]
  onTransactionComplete?: () => void
}

export function BorrowForm({
  isOpen,
  onClose,
  selectedToken,
  tokenId,
  tokenIds,
  borrows,
  onTransactionComplete,
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
  const { isLoading: isConfirming, isSuccess: isConfirmed } =
    useWaitForTransactionReceipt({
      hash: borrowData,
    })

  const [borrowAmount, setBorrowAmount] = useState('')

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
      // Clear the input after successful borrow
      setBorrowAmount('')
      onClose()
      // Trigger data refresh
      onTransactionComplete?.()
    }
  }, [isConfirmed, onTransactionComplete, onClose])

  const handleBorrow = async () => {
    try {
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
        pythUpdateData = await fetchPythUpdateDataFromHermes(
          ETH_USDC_USDT_PRICE_IDS
        )
      }

      // Calculate the required fee for Pyth update
      let fee: bigint
      if (USE_MOCK_PYTH) {
        // For MockPyth with empty update data, fee is 0
        fee = 0n
      } else {
        fee = (await publicClient.readContract({
          address: import.meta.env.VITE_MOCK_PYTH_ADDRESS as `0x${string}`,
          abi: MOCK_PYTH_ABI,
          functionName: 'getUpdateFee',
          args: [pythUpdateData],
        })) as bigint
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
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className='sm:max-w-md'>
        <DialogHeader>
          <DialogTitle>Borrow {selectedToken.symbol}</DialogTitle>
          <DialogDescription>
            Enter the amount of {selectedToken.symbol} you want to borrow. Make
            sure you have sufficient collateral.
          </DialogDescription>
        </DialogHeader>

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
          {borrowError && (
            <div className='text-sm text-red-500 bg-red-50 dark:bg-red-900/20 p-3 rounded-md'>
              Error: {borrowError?.message}
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
