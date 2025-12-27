import { type ClassValue, clsx } from 'clsx'
import { twMerge } from 'tailwind-merge'
import type { MockAssetData } from '@/sample-data'

// Helper for Shadcn components
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function toWei(amount: number, decimals: number): bigint {
  return BigInt(Math.floor(amount * Math.pow(10, decimals)))
}

export function fromWei(amount: bigint, decimals: number): number {
  return Number(amount) / Math.pow(10, decimals)
}

// Helper function to format transaction error messages for better UX
export function formatTransactionError(errorMessage: string): string {
  // Extract the main error reason
  const reasonMatch = errorMessage.match(/reason: ([^.]+)/)
  const revertMatch = errorMessage.match(/execution reverted: ([^.]+)/)

  if (reasonMatch) {
    const reason = reasonMatch[1].trim()
    return formatErrorReason(reason)
  } else if (revertMatch) {
    const reason = revertMatch[1].trim()
    return formatErrorReason(reason)
  }

  // If no specific reason found, return a generic message
  return 'Transaction failed. Please try again or check your input.'
}

export function isNativeToken(token: MockAssetData): boolean {
  return token.address === '0x0000000000000000000000000000000000000000'
}

// Helper function to format specific error reasons
export function formatErrorReason(reason: string): string {
  const errorMap: Record<string, string> = {
    'No collateral': 'Not enough liquidity available for this borrow.',
    'Insufficient collateral':
      'Your collateral is not sufficient for this borrow amount. Please deposit more or borrow less.',
    'Insufficient liquidity':
      'There is not enough liquidity available for this borrow. Please try a smaller amount.',
    'Invalid amount': 'The borrow amount is invalid. Please check your input.',
    'User not found': 'User account not found. Please connect your wallet.',
    'Token not supported': 'This token is not supported for borrowing.',
    'Borrow limit exceeded':
      'You have exceeded your borrow limit. Please repay some existing borrows first.',
    'Health factor too low':
      'Your health factor is too low. Please add more collateral or repay some borrows.',
    'Price feed error': 'Unable to get current price data. Please try again.',
    'Invalid price': 'Price data is invalid or outdated. Please try again.',
    'Oracle error': 'Price oracle error. Please try again later.',
    'Contract paused': 'Borrowing is currently paused. Please try again later.',
    'Invalid token': 'Invalid token address. Please try again.',
    'Amount too small':
      'Borrow amount is too small. Please increase the amount.',
    'Amount too large': 'Borrow amount is too large. Please reduce the amount.',
    'Insufficient balance':
      'Insufficient balance for this transaction. Please check your available funds.',
    'Allowance too low':
      'Token allowance is too low. Please approve more tokens first.',
    'Gas estimation failed':
      'Unable to estimate gas for this transaction. Please try again.',
    'Network error':
      'Network connection error. Please check your connection and try again.',
    'User rejected': 'Transaction was rejected by the user.',
    'Nonce too low': 'Transaction nonce is too low. Please try again.',
    'Nonce too high': 'Transaction nonce is too high. Please try again.',
    'Insufficient funds':
      'Insufficient funds for gas. Please add more ETH to your wallet.',
    'Contract not found':
      'Contract not found. Please check the contract address.',
    'Function not found':
      'Function not found in contract. Please check the function name.',
    'Invalid parameters':
      'Invalid function parameters. Please check your input.',
    'Access denied':
      'Access denied. You do not have permission to perform this action.',
    Paused: 'This function is currently paused. Please try again later.',
    Reentrancy: 'Reentrancy detected. Please try again.',
    Overflow: 'Arithmetic overflow detected. Please try a smaller amount.',
    Underflow: 'Arithmetic underflow detected. Please check your input.',
    PriceStale: 'Price data is too old. Please try again.',
    '0x19abf40e': 'Price data is too old. Please try again.',
  }

  // Try to find a user-friendly message for the reason
  for (const [key, message] of Object.entries(errorMap)) {
    if (reason.toLowerCase().includes(key.toLowerCase())) {
      return message
    }
  }

  // If no specific match, return a formatted version of the reason
  return `Transaction failed: ${reason.charAt(0).toUpperCase() + reason.slice(1).toLowerCase()
    }`
}
