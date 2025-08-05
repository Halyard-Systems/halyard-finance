import { getPrices, type PriceUpdate } from '../lib/prices'
import { setMaxBorrow } from './reducers/borrowManager'
import type { AppDispatch } from './store'

export const maxBorrow = async (priceIds: string[], dispatch: AppDispatch) => {
  const priceUpdates: PriceUpdate = await getPrices(priceIds)

  console.log('prices', priceUpdates.parsed)
  dispatch(setMaxBorrow(1))
}
