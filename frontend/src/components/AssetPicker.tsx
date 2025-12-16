import type { MockAssetData, MockChainData } from "@/sample-data"
import { useState } from "react"
import { isNativeToken, fromWei, formatTransactionError } from "@/lib/utils"
import type { ContractCall } from "@/lib/types"
import ERC20_ABI from '../abis/ERC20.json'
import { useAccount, useWriteContract } from "wagmi"
import { useReadDepositManagerAllowance } from "@/lib/hooks"

// const approvalContractCall = (selectedAsset: MockAssetData, amountInWei: bigint) => {
//   return {
//     address: selectedAsset.ticker as `0x${string}`,
//     abi: ERC20_ABI,
//     functionName: 'approve',
//     args: [
//       import.meta.env.VITE_DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
//       amountInWei,
//     ],
//   }
// }

export interface AssetPickerProps {
  portfolioData: MockChainData[]
  // Any action this menu handles, such as deposit, withdraw, borrow, repay, etc.
  actionContract: ContractCall
}

// TODO: disable input on isDepositing, isDepositConfirming, isApproving, isApprovalConfirming
export function AssetPicker({
  portfolioData
}: AssetPickerProps) {
  const { address } = useAccount()

  // TODO: handle approval and deposit errors
  const [approvalError, setApprovalError] = useState<Error | null>(null)
  const [depositError, setDepositError] = useState<Error | null>(null)
  const [needsApproval, setNeedsApproval] = useState(false)

  
  const [isAssetDropdownOpen, setIsAssetDropdownOpen] = useState(false)
  const [isChainDropdownOpen, setIsChainDropdownOpen] = useState(false)
  const [selectedChain, setSelectedChain] = useState(portfolioData[0])
  const [selectedAsset, setSelectedAsset] = useState(selectedChain.assets[0])
  const [depositAmount, setDepositAmount] = useState('')

  const { data: allowance } = useReadDepositManagerAllowance(
    address! as `0x${string}`,
    {
      symbol: selectedAsset.ticker,
      name: selectedAsset.ticker,
      icon: selectedAsset.logo,
      decimals: selectedAsset.decimals,
      address: selectedAsset.ticker as `0x${string}`,
    }
  )


  const {
    writeContract: writeContract,
    isPending: writeContractPending,
    error: writeContractError,
    data: writeContractData,
  } = useWriteContract()

  const handleAction = async (actionContract: ContractCall) => {
    await writeContract(actionContract)
  }

  const handleApproval = async () => {

    if (!depositAmount || isNativeToken(selectedAsset)) {
      console.error('Invalid deposit amount, address, or trying to approve ETH')
      return
    }

    await writeContract(approvalContractCall(selectedAsset, BigInt(depositAmount)))
  }



  return (
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
                src={selectedChain.logo}
                alt={`${selectedChain.name} icon`}
                className='w-4 h-4'
              />
              <span>{selectedChain.name}</span>
            </div>
            <svg
              className={`w-4 h-4 transition-transform ${isChainDropdownOpen ? 'rotate-180' : ''
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
                  key={chain.name}
                  type='button'
                  onClick={() => {
                    setSelectedChain(chain)
                    setIsChainDropdownOpen(false)
                  }}
                  className='w-full px-3 py-2 text-left hover:bg-muted flex items-center space-x-2'
                >
                  <img
                    src={chain.logo}
                    alt={`${chain.name} icon`}
                    className='w-4 h-4'
                  />
                  <span>{chain.name}</span>
                </button>
              ))}
            </div>
          )}
        </div>
      </div>
      {/* Asset Dropdown */}
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
                src={selectedAsset.logo}
                alt={`${selectedAsset.logo} icon`}
                className='w-4 h-4'
              />
              <span>{selectedAsset.ticker}</span>
            </div>
            <svg
              className={`w-4 h-4 transition-transform ${isAssetDropdownOpen ? 'rotate-180' : ''
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
                  key={asset.ticker}
                  type='button'
                  onClick={() => {
                    setSelectedAsset(asset)
                    setIsAssetDropdownOpen(false)
                  }}
                  className='w-full px-3 py-2 text-left hover:bg-muted flex items-center space-x-2'
                >
                  <img
                    src={asset.logo}
                    alt={`${asset.ticker} icon`}
                    className='w-4 h-4'
                  />
                  <span>{asset.ticker}</span>
                </button>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Amount Input */}
      <div className='min-w-0'>
        <label className='block text-sm font-medium text-card-foreground mb-2'>
          Amount ({selectedAsset.ticker})
        </label>
        <p className='text-sm text-muted-foreground mb-2 break-words'>
          Available: 100.00
        </p>
        <input
          type='number'
          value={depositAmount}
          onChange={(e) => setDepositAmount(e.target.value)}
          placeholder={`0.00 ${selectedAsset.ticker}`}
          className='w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground'
        />
      </div>
      {/* Approval Status */}
      {depositAmount && !isNativeToken(selectedAsset) && (
        <div className='text-sm text-muted-foreground p-3 bg-muted rounded-md w-full min-w-0'>
          <div className='space-y-2 w-full min-w-0'>
            <div className='flex justify-between items-center w-full min-w-0'>
              <span className='truncate mr-2'>
                DepositManager allowance:
              </span>
              <span className='font-mono text-right flex-shrink-0'>
                {fromWei(
                  (allowance as any) || BigInt(0),
                  selectedAsset.decimals
                ).toLocaleString(undefined, {
                  maximumFractionDigits: 6,
                })}{' '}
                {selectedAsset.ticker}
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
                (approvalError || depositError)?.message || ''
              )}
            </div>
          </div>
        </div>
      )}
    </div>

  )
}