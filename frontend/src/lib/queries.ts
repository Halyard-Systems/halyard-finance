import {
  useReadContract,
  useBalance,
  type UseReadContractReturnType,
} from 'wagmi'
import { useMemo } from 'react'

import DEPOSIT_MANAGER_ABI from '../abis/DepositManager.json'
import ERC20_ABI from '../abis/ERC20.json'
import type { Token, Asset } from './types'

const DEPOSIT_MANAGER_ADDRESS = import.meta.env.VITE_DEPOSIT_MANAGER_ADDRESS

// Helper function to check if a token is native ETH
const isNativeETH = (token: Token): boolean => {
  return token.address === '0x0000000000000000000000000000000000000000'
}

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

// Read asset configuration for a specific token
export const useReadAsset = (
  tokenId: `0x${string}`
): UseReadContractReturnType => {
  return useReadContract({
    address: DEPOSIT_MANAGER_ADDRESS as `0x${string}`,
    abi: DEPOSIT_MANAGER_ABI,
    functionName: 'getAsset',
    args: [tokenId],
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

// Custom hook to get all token data
export const useTokenData = (tokens: Token[], userAddress: string) => {
  // First, get the supported token IDs from the contract
  const { data: supportedTokenIds, isLoading: isLoadingTokens } =
    useReadSupportedTokens()

  // Create a mapping from token symbols to their IDs
  const tokenIdMap = useMemo(() => {
    const tokenMap = new Map<string, `0x${string}`>()
    if (!supportedTokenIds || !Array.isArray(supportedTokenIds)) return tokenMap

    // TODO: decouple this
    // The order matches our tokens array since the contract adds them in the same order
    tokens.forEach((token, index) => {
      const tokenId = supportedTokenIds[index]
      if (tokenId) {
        tokenMap.set(token.symbol, tokenId as `0x${string}`)
      }
    })
    return tokenMap
  }, [supportedTokenIds, tokens])

  // Get asset data for each token
  const assetQueries = tokens.map((token) => {
    const tokenId = tokenIdMap.get(token.symbol)
    return useReadAsset(tokenId as `0x${string}`)
  })

  // Get user's deposited balance for each token
  const userDepositsQueries = tokens.map((token) => {
    const tokenId = tokenIdMap.get(token.symbol)
    return useReadDepositManagerBalance(userAddress, tokenId as `0x${string}`)
  })

  // Get user's wallet balance for each token
  const walletBalanceQueries = tokens.map((token) => {
    if (isNativeETH(token)) {
      // Use useBalance for native ETH
      return useBalance({
        address: userAddress as `0x${string}`,
      })
    } else {
      // Use useReadERC20Balance for ERC20 tokens
      return useReadERC20Balance(token, userAddress)
    }
  })

  // Get user's allowance for each token (only for ERC20 tokens)
  const allowanceQueries = tokens.map((token) => {
    if (isNativeETH(token)) {
      // Return a mock query result for ETH (no allowance needed)
      return {
        data: undefined,
        isLoading: false,
        error: undefined,
      }
    } else {
      // Use useReadDepositManagerAllowance for ERC20 tokens
      return useReadDepositManagerAllowance(userAddress, token)
    }
  })

  // TODO: Replace with contract interest rate model
  // Calculate APY from asset data
  const calculateAPY = (
    asset: Asset | undefined
  ): { depositApy: number; borrowApy: number } => {
    if (!asset || asset.totalDeposits === 0n) {
      return { depositApy: 0, borrowApy: 0 }
    }

    // Calculate utilization rate
    const utilization =
      Number((asset.totalBorrows * 10000n) / asset.totalDeposits) / 10000

    // Simple APY calculation based on utilization
    // In a real implementation, you'd use the contract's interest rate model
    const baseRate = 0.025 // 2.5% base rate
    const utilizationMultiplier = 1 + utilization * 2 // Higher utilization = higher rates

    const depositApy = baseRate * utilizationMultiplier * 100
    const borrowApy = depositApy * 1.5 // Borrow rate is typically higher than deposit rate

    return { depositApy, borrowApy }
  }

  // Process all the data
  const tokenData = useMemo(() => {
    return tokens.map((token, index) => {
      const tokenId = tokenIdMap.get(token.symbol)
      const asset = assetQueries[index]?.data as Asset | undefined
      const userDeposits = userDepositsQueries[index]?.data
      const walletBalance = walletBalanceQueries[index]?.data
      const allowance = allowanceQueries[index]?.data

      // Calculate APY from asset data
      const { depositApy, borrowApy } = calculateAPY(asset)

      // Convert bigint values to numbers for display
      const deposits = asset
        ? Number(asset.totalDeposits) / Math.pow(10, asset.decimals)
        : 0
      const borrows = asset
        ? Number(asset.totalBorrows) / Math.pow(10, asset.decimals)
        : 0
      const userDepositsValue = userDeposits
        ? Number(userDeposits) / Math.pow(10, token.decimals)
        : 0

      // Handle wallet balance conversion based on token type
      let walletBalanceValue = 0
      if (isNativeETH(token)) {
        // For native ETH, use the formatted value from useBalance
        walletBalanceValue = walletBalance
          ? Number(walletBalance) / Math.pow(10, token.decimals)
          : 0
      } else {
        // For ERC20 tokens, use the data property from useReadERC20Balance
        walletBalanceValue = walletBalance
          ? Number(walletBalance) / Math.pow(10, token.decimals)
          : 0
      }

      const allowanceValue = allowance
        ? Number(allowance) / Math.pow(10, token.decimals)
        : 0

      const isLoading =
        isLoadingTokens ||
        assetQueries[index]?.isLoading ||
        userDepositsQueries[index]?.isLoading ||
        walletBalanceQueries[index]?.isLoading ||
        allowanceQueries[index]?.isLoading

      return {
        token,
        tokenId,
        deposits,
        borrows,
        depositApy,
        borrowApy,
        userDeposits: userDepositsValue,
        walletBalance: walletBalanceValue,
        allowance: allowanceValue,
        isLoading,
        error: undefined,
      }
    })
  }, [
    tokens,
    tokenIdMap,
    assetQueries,
    userDepositsQueries,
    walletBalanceQueries,
    allowanceQueries,
    isLoadingTokens,
  ])

  return tokenData
}
