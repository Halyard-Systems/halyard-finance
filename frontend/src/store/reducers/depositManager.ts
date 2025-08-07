import { createSlice } from '@reduxjs/toolkit'
import type { PayloadAction } from '@reduxjs/toolkit'

interface DepositState {
  deposits: Record<string, number>
}

const initialState: DepositState = {
  deposits: {},
}

const depositManager = createSlice({
  name: 'depositManager',
  initialState,
  reducers: {
    addDeposit: (
      state,
      action: PayloadAction<{ id: string; amount: number }>
    ) => {
      const { id, amount } = action.payload
      state.deposits[id] = amount
    },
    setAllDeposits: (state, action: PayloadAction<Record<string, number>>) => {
      state.deposits = action.payload
    },
    removeDeposit: (state, action: PayloadAction<string>) => {
      delete state.deposits[action.payload]
    },
    clearDeposits: (state) => {
      state.deposits = {}
    },
  },
})

export const { addDeposit, setAllDeposits, removeDeposit, clearDeposits } =
  depositManager.actions

export default depositManager.reducer
