import type { PublicClient } from 'viem'
import DEPOSIT_MANAGER_ABI from '../abis/DepositManager.json'
import type { Asset } from './types'

const DEPOSIT_MANAGER_ADDRESS = import.meta.env.VITE_DEPOSIT_MANAGER_ADDRESS

export const getAsset = async (
  tokenId: string,
  publicClient: PublicClient
): Promise<Asset> => {
  return (await publicClient.readContract({
    address: DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
    abi: DEPOSIT_MANAGER_ABI,
    functionName: 'getAsset',
    args: [tokenId],
  })) as Asset
}

export const getBalanceOf = async (
  tokenId: string,
  address: string,
  publicClient: PublicClient
): Promise<bigint> => {
  return (await publicClient.readContract({
    address: DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
    abi: DEPOSIT_MANAGER_ABI,
    functionName: 'balanceOf',
    args: [tokenId, address as `0x${string}`],
  })) as bigint
}

export const getSupportedTokenIds = async (
  publicClient: PublicClient
): Promise<`0x${string}`[]> => {
  return (await publicClient.readContract({
    address: DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
    abi: DEPOSIT_MANAGER_ABI,
    functionName: 'getSupportedTokens',
    args: [],
  })) as `0x${string}`[]
}
