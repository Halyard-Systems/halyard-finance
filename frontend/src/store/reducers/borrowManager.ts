import { createSlice } from '@reduxjs/toolkit'

interface BorrowState {
  maxBorrow: number | undefined
}

const initialState: BorrowState = {
  maxBorrow: undefined,
}

const borrowManager = createSlice({
  name: 'borrowManager',
  initialState,
  reducers: {
    setMaxBorrow: (state, action) => {
      state.maxBorrow = action.payload
    },
  },
})

export const { setMaxBorrow } = borrowManager.actions

export default borrowManager.reducer
