// ERC20 token
export interface Token {
  symbol: string
  name: string
  icon: string
  decimals: number
  address: string
}

// Market asset
export interface Asset {
  symbol: string
  tokenAddress: string
  decimals: number
  isActive: boolean
  liquidityIndex: bigint
  lastUpdateTimestamp: bigint
  totalScaledSupply: bigint
  totalDeposits: bigint
  totalBorrows: bigint
  // Interest rate model parameters
  baseRate: bigint
  slope1: bigint
  slope2: bigint
  kink: bigint
  reserveFactor: bigint
}
