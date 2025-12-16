import {
  useReadContract,
  type UseReadContractReturnType,
  useReadContracts,
  type UseReadContractsReturnType,
  useWriteContract,
  type UseWriteContractReturnType,
} from 'wagmi'
import type { Abi } from 'viem'

import DEPOSIT_MANAGER_ABI from '../abis/DepositManager.json'
import BORROW_MANAGER_ABI from '../abis/BorrowManager.json'
import ERC20_ABI from '../abis/ERC20.json'
import type { Token } from './types'
import type { AssetData } from '@/sample-data'

const DEPOSIT_MANAGER_ADDRESS = import.meta.env.VITE_DEPOSIT_MANAGER_ADDRESS
const BORROW_MANAGER_ADDRESS = import.meta.env.VITE_BORROW_MANAGER_ADDRESS

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

// Read borrow index for a specific token
export const useReadBorrowIndex = (
  tokenId: `0x${string}`
): UseReadContractReturnType => {
  return useReadContract({
    address: BORROW_MANAGER_ADDRESS as `0x${string}`,
    abi: BORROW_MANAGER_ABI,
    functionName: 'borrowIndex',
    args: [tokenId],
  })
}

// Read RAY constant from DepositManager
export const useReadRay = (): UseReadContractReturnType => {
  return useReadContract({
    address: DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
    abi: DEPOSIT_MANAGER_ABI,
    functionName: 'RAY',
    args: [],
  })
}

export const useReadBorrowManagerBalances = (
  address: `0x${string}`,
  tokenIds: `0x${string}`[]
): UseReadContractsReturnType => {
  if (!tokenIds) tokenIds = []

  return useReadContracts({
    contracts: tokenIds.map((tokenId) => ({
      address: BORROW_MANAGER_ADDRESS as `0x${string}`,
      abi: BORROW_MANAGER_ABI as Abi,
      functionName: 'userBorrowScaled',
      args: [tokenId, address],
    })),
    query: {
      enabled:
        tokenIds.length > 0 && tokenIds !== undefined && address !== undefined,
    },
  })
}

// Read borrow indices for all tokens
export const useReadBorrowIndices = (
  tokenIds: `0x${string}`[]
): UseReadContractsReturnType => {
  if (!tokenIds) tokenIds = []

  return useReadContracts({
    contracts: tokenIds.map((tokenId) => ({
      address: BORROW_MANAGER_ADDRESS as `0x${string}`,
      abi: BORROW_MANAGER_ABI as Abi,
      functionName: 'borrowIndex',
      args: [tokenId],
    })),
    query: {
      enabled: tokenIds.length > 0 && tokenIds !== undefined,
    },
  })
}
