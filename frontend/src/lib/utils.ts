import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

// Tailwind merge - autogen from shadcn
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

// Convert amount to wei using token decimals
export const toWei = (amount: number, decimals: number) => {
  return BigInt(Math.floor(amount * Math.pow(10, decimals)))
}

export const fromWei = (amount: bigint, decimals: number) => {
  if (!amount) return 0
  // For better precision, we can multiply by a precision factor first
  // This preserves more decimal places during the conversion
  const precisionFactor = 10 ** 6 // 6 decimal places of precision
  const scaledAmount = amount * BigInt(precisionFactor)
  const dividedAmount = scaledAmount / BigInt(10 ** decimals)
  return Number(dividedAmount) / precisionFactor
}
