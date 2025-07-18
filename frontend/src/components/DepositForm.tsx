import { Button } from './ui/button'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from './ui/dialog'

import TOKENS from '../tokens.json'

interface Token {
  symbol: string
  name: string
  icon: string
  decimals: number
  address: string
}

interface DepositFormProps {
  isOpen: boolean
  onClose: () => void
  selectedToken: Token
  depositAmount: string
  setDepositAmount: (amount: string) => void
  usdcBalance: number
  allowance: number
  stargateAllowance: number
  stargateRouterAddress?: string | undefined
  needsApproval: boolean
  needsDepositManagerApproval: boolean
  needsStargateApproval: boolean
  isDropdownOpen: boolean
  setIsDropdownOpen: (open: boolean) => void
  setSelectedToken: (token: Token) => void
  approvalError?: any
  depositError?: any
  isApproving: boolean
  isDepositing: boolean
  onApproval: () => void
  onDeposit: () => void
  getApprovalButtonText: () => string
}

export function DepositForm({
  isOpen,
  onClose,
  selectedToken,
  depositAmount,
  setDepositAmount,
  usdcBalance,
  allowance,
  stargateAllowance,
  stargateRouterAddress,
  needsApproval,
  needsDepositManagerApproval,
  needsStargateApproval,
  isDropdownOpen,
  setIsDropdownOpen,
  setSelectedToken,
  approvalError,
  depositError,
  isApproving,
  isDepositing,
  onApproval,
  onDeposit,
  getApprovalButtonText,
}: DepositFormProps) {
  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className='sm:max-w-md'>
        <DialogHeader>
          <DialogTitle>Deposit</DialogTitle>
        </DialogHeader>

        <div className='space-y-4'>
          {/* Token Selection */}
          <div>
            <label className='block text-sm font-medium text-card-foreground mb-2'>
              Token
            </label>
            <div className='relative'>
              <button
                type='button'
                onClick={() => setIsDropdownOpen(!isDropdownOpen)}
                className='w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground flex items-center justify-between'
              >
                <div className='flex items-center space-x-2'>
                  <img
                    src={selectedToken.icon}
                    alt={`${selectedToken.symbol} icon`}
                    className='w-5 h-5'
                  />
                  <span>{selectedToken.symbol}</span>
                </div>
                <svg
                  className={`w-4 h-4 transition-transform ${
                    isDropdownOpen ? 'rotate-180' : ''
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
              {isDropdownOpen && (
                <div className='absolute z-10 w-full mt-1 bg-background border border-border rounded-md shadow-lg'>
                  {TOKENS.map((token: Token) => (
                    <button
                      key={token.symbol}
                      onClick={() => {
                        setSelectedToken(token)
                        setIsDropdownOpen(false)
                      }}
                      className='w-full px-3 py-2 text-left hover:bg-accent hover:text-accent-foreground flex items-center space-x-2'
                    >
                      <img
                        src={token.icon}
                        alt={`${token.symbol} icon`}
                        className='w-5 h-5'
                      />
                      <span>{token.symbol}</span>
                    </button>
                  ))}
                </div>
              )}
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
              disabled={isDepositing || isApproving}
            />
          </div>

          {/* Approval Status */}
          {depositAmount && (
            <div className='text-sm text-muted-foreground p-3 bg-muted rounded-md'>
              <div className='space-y-2'>
                <div className='flex justify-between items-center'>
                  <span>DepositManager allowance:</span>
                  <span className='font-mono'>
                    {allowance.toLocaleString(undefined, {
                      maximumFractionDigits: 6,
                    })}{' '}
                    {selectedToken.symbol}
                  </span>
                </div>
                {stargateRouterAddress ? (
                  <div className='flex justify-between items-center'>
                    <span>Stargate allowance:</span>
                    <span className='font-mono'>
                      {stargateAllowance.toLocaleString('en-US', {
                        maximumFractionDigits: 6,
                      })}{' '}
                      {selectedToken.symbol}
                    </span>
                  </div>
                ) : null}
              </div>
              {needsApproval && (
                <div className='mt-2 text-yellow-600'>
                  ⚠️ Approval required before deposit
                  {needsDepositManagerApproval && needsStargateApproval && (
                    <span> (both DepositManager and Stargate)</span>
                  )}
                  {needsDepositManagerApproval && !needsStargateApproval && (
                    <span> (DepositManager)</span>
                  )}
                  {!needsDepositManagerApproval && needsStargateApproval && (
                    <span> (Stargate)</span>
                  )}
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
              onClick={onApproval}
              disabled={!depositAmount || isApproving}
              className='flex-1'
            >
              {getApprovalButtonText()}
            </Button>
          )}
          <Button
            onClick={onDeposit}
            disabled={
              !depositAmount || isDepositing || isApproving || needsApproval
            }
            className='flex-1'
          >
            {isDepositing ? 'Depositing...' : `Deposit ${selectedToken.symbol}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
