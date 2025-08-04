import { createSlice } from '@reduxjs/toolkit'

const borrowManager = createSlice({
  name: 'borrowManager',
  initialState: {
    maxBorrow: undefined,
  },
  reducers: {
    setMaxBorrow: (state, action) => {
      state.maxBorrow = action.payload
    },
  },
})

export const { setMaxBorrow } = borrowManager.actions

export default borrowManager.reducer
