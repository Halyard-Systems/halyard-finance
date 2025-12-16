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
import DEPOSIT_MANAGER_ABI from '../abis/DepositManager.json'
import type { Token } from '../lib/types'
import { toWei, fromWei, formatTransactionError } from '../lib/utils'
import { portfolioData } from '@/sample-data'

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
import { AssetPicker } from './AssetPicker'

interface DepositFormProps {
  isOpen: boolean
  onClose: () => void
  onTransactionComplete?: () => void
  onTransactionError?: (error: string) => void
}

export function DepositForm({
  isOpen,
  onClose,
  onTransactionComplete,
  onTransactionError,
}: DepositFormProps) {
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
    symbol: selectedAsset.ticker,
    name: selectedAsset.ticker,
    icon: selectedAsset.logo,
    decimals: 18, // Default to 18 decimals, would need to be mapped properly in real implementation
    address:
      selectedAsset.ticker === 'ETH'
        ? '0x0000000000000000000000000000000000000000'
        : '0x' + '0'.repeat(40), // Mock address
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

  const { data: allowance } = useReadDepositManagerAllowance(
    address! as `0x${string}`,
    selectedToken
  )

  const [depositAmount, setDepositAmount] = useState('')

  // Check if approval is needed (only for ERC20 tokens, not ETH)
  const depositAmountNumber = Number(depositAmount) || 0
  const isETH =
    selectedToken.address === '0x0000000000000000000000000000000000000000'
  const needsApproval =
    !isETH &&
    depositAmountNumber >
    fromWei((allowance as any) || BigInt(0), selectedToken.decimals)

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
  const {
    isLoading: isApprovalConfirming,
    isSuccess: isApprovalConfirmed,
    isError: isApprovalError,
    error: approvalTransactionError,
  } = useWaitForTransactionReceipt({
    hash: approvalData,
  })

  const {
    isLoading: isDepositConfirming,
    isSuccess: isDepositConfirmed,
    isError: isDepositError,
    error: depositTransactionError,
  } = useWaitForTransactionReceipt({
    hash: depositData,
  })

  // Handle approval completion
  useEffect(() => {
    if (isApprovalConfirmed) {
      // Optionally trigger data refresh in parent
      onTransactionComplete?.()
    }
  }, [isApprovalConfirmed, onTransactionComplete])

  // Handle deposit completion
  useEffect(() => {
    if (isDepositConfirmed) {
      // Clear the input after successful deposit
      setDepositAmount('')
      onClose()
      // Optionally trigger data refresh in parent
      onTransactionComplete?.()
    }
  }, [isDepositConfirmed, onTransactionComplete, onClose])

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
    if (isDepositError && depositTransactionError) {
      const formattedError = formatTransactionError(
        depositTransactionError.message
      )
      onTransactionError?.(formattedError)
    }
  }, [isDepositError, depositTransactionError, onTransactionError])

  const handleApproval = async () => {
    if (!depositAmount || !address || isETH) {
      console.error('Invalid deposit amount, address, or trying to approve ETH')
      return
    }

    try {
      const amountInWei = toWei(Number(depositAmount), selectedToken.decimals)

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
    }
  }

  const handleDeposit = async () => {
    if (!depositAmount || !address) {
      console.error('Invalid deposit amount or address')
      return
    }

    try {
      if (isETH) {
        // Handle ETH deposit
        const amountInWei = toWei(Number(depositAmount), selectedToken.decimals)

        await writeDeposit({
          address: import.meta.env
            .VITE_DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
          abi: DEPOSIT_MANAGER_ABI,
          functionName: 'deposit',
          args: ['0x' + '0'.repeat(64), amountInWei], // Mock token ID
          value: amountInWei, // Send ETH with the transaction
        })
      } else {
        // Handle ERC20 token deposit
        const amountInWei = toWei(Number(depositAmount), selectedToken.decimals)

        await writeDeposit({
          address: import.meta.env
            .VITE_DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
          abi: DEPOSIT_MANAGER_ABI,
          functionName: 'deposit',
          args: ['0x' + '0'.repeat(64), amountInWei], // Mock token ID
        })
      }
    } catch (error) {
      console.error('Deposit failed:', error)
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className='max-h-[90vh] overflow-y-auto sm:max-w-6xl'>
        <DialogHeader>
          <DialogTitle>Deposit {selectedToken.symbol}</DialogTitle>
          <DialogDescription>
            Enter the amount of {selectedToken.symbol} you want to deposit as
            collateral.
          </DialogDescription>
        </DialogHeader>

        <AssetPicker portfolioData={portfolioData} actionContract={null as any} />

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
                  : `Approve ${selectedToken.symbol} for DepositManager`}
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
