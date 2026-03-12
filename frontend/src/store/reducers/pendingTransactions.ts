import { createSlice } from "@reduxjs/toolkit";
import type { PayloadAction } from "@reduxjs/toolkit";
import type { PendingTransaction } from "../../lib/types";

interface PendingTransactionsState {
  transactions: PendingTransaction[];
}

const initialState: PendingTransactionsState = {
  transactions: [],
};

const pendingTransactionsSlice = createSlice({
  name: "pendingTransactions",
  initialState,
  reducers: {
    addPendingTransaction: (state, action: PayloadAction<PendingTransaction>) => {
      state.transactions.push(action.payload);
    },
    updateTransactionStatus: (
      state,
      action: PayloadAction<{
        txHash: `0x${string}`;
        status: PendingTransaction["status"];
      }>
    ) => {
      const tx = state.transactions.find(
        (t) => t.txHash === action.payload.txHash
      );
      if (tx) {
        tx.status = action.payload.status;
      }
    },
    clearConfirmedTransactions: (state) => {
      state.transactions = state.transactions.filter(
        (t) => t.status === "pending"
      );
    },
    removeTransaction: (state, action: PayloadAction<string>) => {
      state.transactions = state.transactions.filter(
        (t) => t.id !== action.payload
      );
    },
  },
});

export const {
  addPendingTransaction,
  updateTransactionStatus,
  clearConfirmedTransactions,
  removeTransaction,
} = pendingTransactionsSlice.actions;

export default pendingTransactionsSlice.reducer;
