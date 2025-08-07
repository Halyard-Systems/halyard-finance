import {
  useReadContract,
  type UseReadContractReturnType,
  useReadContracts,
  type UseReadContractsReturnType,
} from 'wagmi'
import type { Abi } from 'viem'

import DEPOSIT_MANAGER_ABI from '../abis/DepositManager.json'
import ERC20_ABI from '../abis/ERC20.json'
import type { Token } from './types'

const DEPOSIT_MANAGER_ADDRESS = import.meta.env.VITE_DEPOSIT_MANAGER_ADDRESS

// Read ERC20 balance of a token
export const useReadERC20Balance = (
  token: Token,
  userAddress: string
): UseReadContractReturnType => {
  return useReadContract({
    address: token.address as `0x${string}`,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [userAddress as `0x${string}`],
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

// Read user's deposited balance for a specific token
export const useReadDepositManagerBalance = (
  address: string,
  tokenId: `0x${string}`
): UseReadContractReturnType => {
  return useReadContract({
    address: DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
    abi: DEPOSIT_MANAGER_ABI,
    functionName: 'balanceOf',
    args: [tokenId, address as `0x${string}`],
  })
}

export const useReadDepositManagerBalances = (
  address: `0x${string}`,
  tokenIds: `0x${string}`[]
): UseReadContractsReturnType => {
  if (!tokenIds) tokenIds = []

  return useReadContracts({
    contracts: tokenIds.map((tokenId) => ({
      address: DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
      abi: DEPOSIT_MANAGER_ABI as Abi,
      functionName: 'balanceOf',
      args: [tokenId, address],
    })),
    query: {
      enabled:
        tokenIds.length > 0 && tokenIds !== undefined && address !== undefined,
    },
  })
}

// Read all assets
export const useReadAssets = (
  tokenIds: `0x${string}`[]
): UseReadContractsReturnType => {
  if (!tokenIds) tokenIds = []

  return useReadContracts({
    contracts: tokenIds.map((tokenId) => ({
      address: DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
      abi: DEPOSIT_MANAGER_ABI as Abi,
      functionName: 'getAsset',
      args: [tokenId],
    })),
    query: {
      enabled: tokenIds.length > 0 || tokenIds !== undefined,
    },
  })
}

// Read all supported tokens
export const useReadSupportedTokens = (): UseReadContractReturnType => {
  return useReadContract({
    address: DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
    abi: DEPOSIT_MANAGER_ABI,
    functionName: 'getSupportedTokens',
    args: [],
  })
}
