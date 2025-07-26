import { useState, useEffect } from 'react'
import { Button } from './ui/button'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from './ui/dialog'
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  usePublicClient,
} from 'wagmi'

import BORROW_MANAGER_ABI from '../abis/BorrowManager.json'
import { toWei } from '../lib/utils'
import type { Token } from '../lib/types'
import TOKENS from '../tokens.json'
import PYTH_ABI from '../abis/IPyth.json'
import MOCK_PYTH_ABI from '../abis/MockPyth.json'

const USE_MOCK_PYTH = import.meta.env.VITE_USE_MOCK_PYTH === 'true'
const MOCK_PYTH_ADDRESS = import.meta.env
  .VITE_MOCK_PYTH_ADDRESS as `0x${string}`

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

// Helper to create MockPyth update data using the contract's createPriceFeedUpdateData function
async function createMockPythUpdateData(
  publicClient: any,
  priceId: string
): Promise<string> {
  // Example arguments for the mock; adjust as needed
  const price = 123 * 1e8 // Price in fixed-point format (123 USD with 8 decimals)
  const conf = 100 // Confidence interval
  const expo = -8 // Exponent for fixed-point representation
  const emaPrice = 123 * 1e8 // EMA price in fixed-point format
  const emaConf = 100 // EMA confidence interval
  const publishTime = Math.floor(Date.now() / 1000)
  const prevPublishTime = publishTime - 60

  const updateData = await publicClient.readContract({
    address: MOCK_PYTH_ADDRESS,
    abi: MOCK_PYTH_ABI,
    functionName: 'createPriceFeedUpdateData',
    args: [
      priceId,
      price,
      conf,
      expo,
      emaPrice,
      emaConf,
      publishTime,
      prevPublishTime,
    ],
  })

  return updateData as string
}

interface BorrowFormProps {
  isOpen: boolean
  onClose: () => void
  selectedToken: Token
  tokenId?: `0x${string}`
  maxBorrowable: number
  onTransactionComplete?: () => void
}

export function BorrowForm({
  isOpen,
  onClose,
  selectedToken,
  tokenId,
  maxBorrowable,
  onTransactionComplete,
}: BorrowFormProps) {
  const [borrowAmount, setBorrowAmount] = useState('')
  const { address } = useAccount()
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
      const priceIds = [
        '0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace',
      ]
      let pythUpdateData: string[]
      if (USE_MOCK_PYTH) {
        console.log('Using mock Pyth')
        pythUpdateData = [
          await createMockPythUpdateData(publicClient, priceIds[0]),
        ]
      } else {
        pythUpdateData = await fetchPythUpdateDataFromHermes(priceIds)
      }

      // Calculate the required fee for Pyth update
      const fee = (await publicClient.readContract({
        address: import.meta.env.VITE_MOCK_PYTH_ADDRESS as `0x${string}`,
        abi: MOCK_PYTH_ABI,
        functionName: 'getUpdateFee',
        args: [pythUpdateData],
      })) as bigint

      console.log('pythUpdateData', pythUpdateData)
      console.log('priceIds', priceIds)
      console.log('tokenId', tokenId)
      console.log('amountInWei', amountInWei)
      console.log('Pyth fee required:', fee.toString())

      await writeBorrow({
        address: import.meta.env.VITE_BORROW_MANAGER_ADDRESS as `0x${string}`,
        abi: BORROW_MANAGER_ABI,
        functionName: 'borrow',
        args: [tokenId, amountInWei, pythUpdateData, priceIds],
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
              {maxBorrowable.toLocaleString(undefined, {
                maximumFractionDigits: 6,
              })}
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
              Number(borrowAmount) > maxBorrowable ||
              Number(borrowAmount) <= 0
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
