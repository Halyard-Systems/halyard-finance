import { encodePacked } from "viem";
import type { MessagingFee } from "./types";

// LayerZero V2 executor option types
const EXECUTOR_WORKER_ID = 1;
const OPTION_TYPE_LZRECEIVE = 1;

/**
 * Build LayerZero V2 executor options for lzReceive gas.
 * Format: 0x0003 (options type 3) + executor options
 * Executor option: workerId(uint8) + optionLength(uint16) + optionType(uint8) + gas(uint128) + value(uint128)
 */
export function buildLzOptions(executorGasLimit: bigint, nativeDropValue: bigint = 0n): `0x${string}` {
  if (nativeDropValue > 0n) {
    // TYPE 3 options with gas + native value
    const executorOption = encodePacked(
      ["uint8", "uint16", "uint8", "uint128", "uint128"],
      [EXECUTOR_WORKER_ID, 33, OPTION_TYPE_LZRECEIVE, executorGasLimit, nativeDropValue]
    );
    return encodePacked(["uint16", "bytes"], [3, executorOption]);
  }

  // TYPE 3 options with gas only
  const executorOption = encodePacked(
    ["uint8", "uint16", "uint8", "uint128"],
    [EXECUTOR_WORKER_ID, 17, OPTION_TYPE_LZRECEIVE, executorGasLimit]
  );
  return encodePacked(["uint16", "bytes"], [3, executorOption]);
}

// Default gas limits for different operation types
export const GAS_LIMITS = {
  deposit: 200_000n,
  repay: 200_000n,
  borrow: 300_000n,
  withdraw: 300_000n,
  liquidation: 400_000n,
} as const;

/** Apply a percentage buffer to a quoted LZ fee (default 10%) */
export function applyFeeBuffer(fee: MessagingFee, bufferBps = 1000n): MessagingFee {
  return {
    nativeFee: fee.nativeFee + (fee.nativeFee * bufferBps) / 10000n,
    lzTokenFee: fee.lzTokenFee,
  };
}
