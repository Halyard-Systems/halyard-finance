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
  tokenAddress: string
  decimals: number
  isActive: boolean
  liquidityIndex: bigint
  lastUpdateTimestamp: bigint
  totalScaledSupply: bigint
  totalDeposits: bigint
  totalBorrows: bigint
}
