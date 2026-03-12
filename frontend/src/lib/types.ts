// ERC20 token (kept from old codebase, extended)
export interface Token {
  symbol: string;
  name: string;
  icon: string;
  decimals: number;
  address: string;
  chainId?: number;
  canonicalAddress?: `0x${string}`;
}

// Chain + asset identifier used by PositionBook and DebtManager
export interface ChainAsset {
  eid: number;
  asset: `0x${string}`;
}

// Alias types matching contract struct names
export type CollateralSlot = ChainAsset;
export type DebtSlot = ChainAsset;

// LayerZero messaging fee
export interface MessagingFee {
  nativeFee: bigint;
  lzTokenFee: bigint;
}

// Account data from RiskEngine.accountData()
export interface AccountData {
  collateralValueE18: bigint;
  borrowPowerE18: bigint;
  liquidationValueE18: bigint;
  debtValueE18: bigint;
  healthFactorE18: bigint;
}

// Collateral position detail
export interface CollateralPosition {
  eid: number;
  asset: `0x${string}`;
  balance: bigint;
  available: bigint;
  reserved: bigint;
}

// Debt position detail
export interface DebtPosition {
  eid: number;
  asset: `0x${string}`;
  debt: bigint;
}

// Transaction states for the UI state machine
export type TransactionStatus =
  | "idle"
  | "switching-chain"
  | "approving"
  | "quoting"
  | "sending"
  | "pending"
  | "confirmed"
  | "failed";

// Pending cross-chain transaction
export interface PendingTransaction {
  id: string;
  type: "borrow" | "withdraw" | "deposit" | "repay" | "liquidation";
  status: "pending" | "confirmed" | "failed";
  user: `0x${string}`;
  dstEid?: number;
  asset: `0x${string}`;
  amount: bigint;
  txHash: `0x${string}`;
  timestamp: number;
}

export type ActionName = "Borrow" | "Repay" | "Withdraw" | "Deposit";
