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

interface WithdrawFormProps {
  isOpen: boolean
  onClose: () => void
  selectedToken: Token
  tokenId?: `0x${string}`
  onTransactionComplete?: () => void
  onTransactionError?: (error: string) => void
}

export function WithdrawForm({
  isOpen,
  onClose,
  selectedToken,
  tokenId,
  onTransactionComplete,
  onTransactionError,
}: WithdrawFormProps) {
  const { address } = useAccount()

  const { data: depositedBalanceData } = useReadDepositManagerBalance(
    address! as `0x${string}`,
    tokenId!
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
      <DialogContent className='sm:max-w-md max-h-[90vh] overflow-y-auto'>
        <DialogHeader>
          <DialogTitle>Withdraw {selectedToken.symbol}</DialogTitle>
          <DialogDescription>
            Enter the amount of {selectedToken.symbol} you want to withdraw from
            your deposited collateral.
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
