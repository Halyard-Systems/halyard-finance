import { configureStore } from "@reduxjs/toolkit";
import pendingTransactions from "./reducers/pendingTransactions";

export const store = configureStore({
  reducer: {
    pendingTransactions,
  },
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware({
      serializableCheck: false,
    }),
});

export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;

export default store;
