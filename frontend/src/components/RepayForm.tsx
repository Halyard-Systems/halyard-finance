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
  selectedToken: Token
  tokenId: `0x${string}`
  borrows: bigint[]
  onTransactionComplete?: () => void
  onTransactionError?: (error: string) => void
}

export function RepayForm({
  isOpen,
  onClose,
  selectedToken,
  tokenId,
  borrows,
  onTransactionComplete,
  onTransactionError,
}: RepayFormProps) {
  const { address } = useAccount()

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
    if (!repayAmount || !address || !tokenId) {
      console.error('Invalid repay amount, address, or token ID')
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
          args: [tokenId, amountInWei],
          value: amountInWei, // Send ETH with the transaction
        })
      } else {
        // Handle ERC20 token repay
        const amountInWei = toWei(Number(repayAmount), selectedToken.decimals)

        await writeRepay({
          address: import.meta.env.VITE_BORROW_MANAGER_ADDRESS as `0x${string}`,
          abi: BORROW_MANAGER_ABI,
          functionName: 'repay',
          args: [tokenId, amountInWei],
        })
      }
    } catch (error) {
      console.error('Repay failed:', error)
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className='sm:max-w-xl w-[95vw] max-w-[600px] max-h-[90vh] overflow-y-auto'>
        <DialogHeader>
          <DialogTitle>Repay {selectedToken.symbol}</DialogTitle>
          <DialogDescription>
            Enter the amount of {selectedToken.symbol} you want to repay.
          </DialogDescription>
        </DialogHeader>

        <div className='space-y-4 w-full min-w-0'>
          {/* Token Display */}
          <div className='w-full min-w-0'>
            <label className='block text-sm font-medium text-card-foreground mb-2'>
              Token
            </label>
            <div className='px-3 py-2 border border-input rounded-md bg-muted flex items-center space-x-2 w-full min-w-0'>
              <img
                src={selectedToken.icon}
                alt={`${selectedToken.symbol} icon`}
                className='w-5 h-5 flex-shrink-0'
              />
              <span className='font-medium truncate'>
                {selectedToken.symbol}
              </span>
              <span className='text-muted-foreground truncate'>
                ({selectedToken.name})
              </span>
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
              !tokenId ||
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
