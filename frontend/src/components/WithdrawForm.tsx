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
} from 'wagmi'

import DEPOSIT_MANAGER_ABI from '../abis/DepositManager.json'
import { toWei } from '../lib/utils'
import type { Token } from '../lib/types'

interface WithdrawFormProps {
  isOpen: boolean
  onClose: () => void
  selectedToken: Token
  tokenId?: `0x${string}`
  depositedBalance: number
  onTransactionComplete?: () => void
}

export function WithdrawForm({
  isOpen,
  onClose,
  selectedToken,
  tokenId,
  depositedBalance,
  onTransactionComplete,
}: WithdrawFormProps) {
  const [withdrawAmount, setWithdrawAmount] = useState('')

  const { address } = useAccount()

  const {
    writeContract: writeWithdraw,
    isPending: isWithdrawing,
    error: withdrawError,
    data: withdrawData,
  } = useWriteContract()

  // Wait for transaction receipt and handle completion
  const { isLoading: isConfirming, isSuccess: isConfirmed } =
    useWaitForTransactionReceipt({
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

  const handleWithdraw = async () => {
    if (!withdrawAmount || !address || !tokenId) {
      console.error('Invalid withdraw amount, address, or token ID')
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
        args: [tokenId, amountInWei],
      })
    } catch (error) {
      console.error('Withdraw failed:', error)
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className='sm:max-w-md'>
        <DialogHeader>
          <DialogTitle>Withdraw {selectedToken.symbol}</DialogTitle>
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
            <div className='text-sm text-red-500 bg-red-50 dark:bg-red-900/20 p-3 rounded-md'>
              Error: {withdrawError?.message}
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
              !tokenId ||
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
