// ERC20 token
export interface Token {
  symbol: string
  name: string
  icon: string
  decimals: number
  address: string
}

// Aggregate token data
export interface Asset {
  token: Token
  isActive: boolean
  liquidityIndex: bigint
  lastUpdateTimestamp: bigint
  symbol: string
  totalScaledSupply: bigint
  totalDeposits: bigint
  totalBorrows: bigint
}

export interface ContractCall {
  address: `0x${string}`
  abi: any
  functionName: string
  args: any[]
}