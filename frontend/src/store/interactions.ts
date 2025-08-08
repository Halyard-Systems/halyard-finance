import { fromWei } from '@/lib/utils'
import {
  getHighestPrice,
  getLowestPrice,
  getPrices,
  type PriceUpdate,
} from '../lib/prices'
import { setMaxBorrow } from './reducers/borrowManager'
import type { AppDispatch } from './store'

interface TokenBalances {
  eth: bigint
  usdc: bigint
  usdt: bigint
}

export const maxBorrow = async (
  priceIds: string[],
  deposits: TokenBalances,
  borrows: TokenBalances,
  dispatch: AppDispatch
) => {
  const priceUpdates: PriceUpdate = await getPrices(priceIds)

  console.log('prices', priceUpdates.parsed)
  const ethPrice = priceUpdates.parsed[0].price
  const usdcPrice = priceUpdates.parsed[1].price
  const usdtPrice = priceUpdates.parsed[2].price

  const ethLowestPrice = getLowestPrice(ethPrice)
  const usdcLowestPrice = getLowestPrice(usdcPrice)
  const usdtLowestPrice = getLowestPrice(usdtPrice)
  console.log('ethLowestPrice', ethLowestPrice)
  console.log('usdcLowestPrice', usdcLowestPrice)
  console.log('usdtLowestPrice', usdtLowestPrice)

  console.log('deposits.eth', deposits.eth)
  console.log('deposits.eth.fromWei', fromWei(deposits.eth, 18))

  const ethMaxBorrow = fromWei(deposits.eth, 18) * ethLowestPrice
  const usdcMaxBorrow = fromWei(deposits.usdc, 6) * usdcLowestPrice
  const usdtMaxBorrow = fromWei(deposits.usdt, 6) * usdtLowestPrice

  // TODO: set based on contract rate model
  const maxBorrow = (ethMaxBorrow + usdcMaxBorrow + usdtMaxBorrow) * 0.8
  console.log('maxBorrow', maxBorrow)

  const ethHighestPrice = getHighestPrice(ethPrice)
  const usdcHighestPrice = getHighestPrice(usdcPrice)
  const usdtHighestPrice = getHighestPrice(usdtPrice)

  const ethBorrowUsed = fromWei(borrows.eth, 18) * ethHighestPrice
  const usdcBorrowUsed = fromWei(borrows.usdc, 6) * usdcHighestPrice
  const usdtBorrowUsed = fromWei(borrows.usdt, 6) * usdtHighestPrice

  const usedBorrow = ethBorrowUsed + usdcBorrowUsed + usdtBorrowUsed

  const availableBorrow = maxBorrow - usedBorrow

  // TODO: maxBorrow should be in terms of the token being borrowed
  dispatch(setMaxBorrow(availableBorrow))
}
