import { configureStore } from '@reduxjs/toolkit'

import borrowManager from './reducers/borrowManager'
import depositManager from './reducers/depositManager'

export const store = configureStore({
  reducer: {
    borrowManager,
    depositManager,
  },
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware({
      serializableCheck: false,
    }),
})

export type RootState = ReturnType<typeof store.getState>
export type AppDispatch = typeof store.dispatch

export default store
