import { useState, useEffect } from 'react'
import { Button } from './ui/button'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from './ui/dialog'

import ERC20_ABI from '../abis/ERC20.json'
import DEPOSIT_MANAGER_ABI from '../abis/DepositManager.json'
import type { Token } from '../lib/types'

import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
} from 'wagmi'

interface DepositFormProps {
  isOpen: boolean
  onClose: () => void
  selectedToken: Token
  usdcBalance: number
  allowance: number
  onTransactionComplete?: () => void
}

export function DepositForm({
  isOpen,
  onClose,
  selectedToken,
  usdcBalance,
  allowance,
  onTransactionComplete,
}: DepositFormProps) {
  const { address } = useAccount()
  const [approvalStep, setApprovalStep] = useState<'none' | 'depositManager'>(
    'none'
  )
  const [depositAmount, setDepositAmount] = useState('')

  // Check if approval is needed
  const depositAmountNumber = Number(depositAmount) || 0
  const needsApproval = depositAmountNumber > allowance

  const {
    writeContract: writeApproval,
    isPending: isApproving,
    error: approvalError,
    data: approvalData,
  } = useWriteContract()

  const {
    writeContract: writeDeposit,
    isPending: isDepositing,
    error: depositError,
    data: depositData,
  } = useWriteContract()

  // Wait for transaction receipts and handle completion
  const { isLoading: isApprovalConfirming, isSuccess: isApprovalConfirmed } =
    useWaitForTransactionReceipt({
      hash: approvalData,
    })

  const { isLoading: isDepositConfirming, isSuccess: isDepositConfirmed } =
    useWaitForTransactionReceipt({
      hash: depositData,
    })

  // Handle approval completion
  useEffect(() => {
    if (isApprovalConfirmed) {
      setApprovalStep('none')
      // Trigger data refresh after approval
      onTransactionComplete?.()
    }
  }, [isApprovalConfirmed, onTransactionComplete])

  // Handle deposit completion
  useEffect(() => {
    if (isDepositConfirmed) {
      // Clear the input after successful deposit
      setDepositAmount('')
      onClose()
      // Trigger data refresh
      onTransactionComplete?.()
    }
  }, [isDepositConfirmed, onTransactionComplete, onClose])

  const getApprovalButtonText = () => {
    if (isApproving) {
      return 'Approving for DepositManager...'
    }
    return `Approve ${selectedToken.symbol} for DepositManager`
  }

  const handleApproval = async () => {
    if (!depositAmount || !address) {
      console.error('Invalid deposit amount or address')
      return
    }

    try {
      // Convert amount to wei (USDC has 6 decimals)
      const amountInWei = BigInt(Math.floor(Number(depositAmount) * 1e6))

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
    } catch (error) {
      console.error('Deposit failed:', error)
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className='sm:max-w-xl w-[95vw] max-w-[600px]'>
        <DialogHeader>
          <DialogTitle>Deposit</DialogTitle>
        </DialogHeader>

        <div className='space-y-4 w-full'>
          {/* Token Display */}
          <div className='w-full'>
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
          <div>
            <label className='block text-sm font-medium text-card-foreground mb-2'>
              Amount ({selectedToken.symbol})
            </label>
            <p className='text-sm text-muted-foreground mb-2'>
              Available:{' '}
              {usdcBalance.toLocaleString(undefined, {
                maximumFractionDigits: 6,
              })}
            </p>
            <input
              type='number'
              value={depositAmount}
              onChange={(e) => setDepositAmount(e.target.value)}
              placeholder={`0.00 ${selectedToken.symbol}`}
              className='w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground'
              disabled={
                isDepositing ||
                isDepositConfirming ||
                isApproving ||
                isApprovalConfirming
              }
            />
          </div>

          {/* Approval Status */}
          {depositAmount && (
            <div className='text-sm text-muted-foreground p-3 bg-muted rounded-md w-full'>
              <div className='space-y-2 w-full'>
                <div className='flex justify-between items-center w-full min-w-0'>
                  <span className='truncate mr-2'>
                    DepositManager allowance:
                  </span>
                  <span className='font-mono text-right flex-shrink-0'>
                    {allowance.toLocaleString(undefined, {
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
          {(approvalError || depositError) && (
            <div className='text-sm text-red-500 bg-red-50 dark:bg-red-900/20 p-3 rounded-md'>
              Error: {(approvalError || depositError)?.message}
            </div>
          )}
        </div>

        <DialogFooter className='flex space-x-2'>
          <Button variant='outline' onClick={onClose} className='flex-1'>
            Cancel
          </Button>
          {needsApproval && depositAmount && (
            <Button
              onClick={handleApproval}
              disabled={!depositAmount || isApproving || isApprovalConfirming}
              className='flex-1'
            >
              {isApproving
                ? 'Approving...'
                : isApprovalConfirming
                ? 'Confirming Approval...'
                : getApprovalButtonText()}
            </Button>
          )}
          <Button
            onClick={handleDeposit}
            disabled={
              !depositAmount ||
              isDepositing ||
              isDepositConfirming ||
              isApproving ||
              isApprovalConfirming ||
              needsApproval
            }
            className='flex-1'
          >
            {isDepositing
              ? 'Depositing...'
              : isDepositConfirming
              ? 'Confirming Deposit...'
              : `Deposit ${selectedToken.symbol}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
