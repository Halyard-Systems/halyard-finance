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
