import { useReadContract, type UseReadContractReturnType } from 'wagmi'

import DEPOSIT_MANAGER_ABI from '../abis/DepositManager.json'
import ERC20_ABI from '../abis/ERC20.json'
import type { Token } from './types'

const DEPOSIT_MANAGER_ADDRESS = import.meta.env.VITE_DEPOSIT_MANAGER_ADDRESS

// Read ERC20 balance of a token
export const useReadERC20Balance = (
  token: Token
): UseReadContractReturnType => {
  return useReadContract({
    address: token.address as `0x${string}`,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [token.address],
  })
}

// Read allowance of a token for the DepositManager contract
export const useReadDepositManagerAllowance = (
  address: string,
  token: Token
): UseReadContractReturnType => {
  return useReadContract({
    address: token.address as `0x${string}`,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: [address, DEPOSIT_MANAGER_ADDRESS as `0x${string}`],
  })
}

// Read balance of a token for the DepositManager contract
export const useReadDepositManagerBalance = (
  address: string
): UseReadContractReturnType => {
  return useReadContract({
    address: DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
    abi: DEPOSIT_MANAGER_ABI,
    functionName: 'balanceOf',
    args: [address],
  })
}
