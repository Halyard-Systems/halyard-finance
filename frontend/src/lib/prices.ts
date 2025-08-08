import { HermesClient } from '@pythnetwork/hermes-client'

const connection = new HermesClient('https://hermes.pyth.network', {})

// const priceIds = [
//   // You can find the ids of prices at https://docs.pyth.network/price-feeds/price-feeds
//   '0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43', // BTC/USD price id
//   '0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace', // ETH/USD price id
// ]

// Get price feeds
// You can also fetch price feeds for other assets by specifying the asset name and asset class.
// const priceFeeds = await connection.getPriceFeeds('btc', 'crypto')
// console.log(priceFeeds)

// // Latest price updates
// const priceUpdates = await connection.getLatestPriceUpdates(priceIds)
// console.log(priceUpdates)

export type PriceUpdate = {
  binary: PriceUpdateBinary
  parsed: PriceUpdateParsed[]
}

export type PriceUpdateBinary = {
  data: string[]
  encoding: string
}

export type PriceUpdateParsed = {
  ema_price: Price
  id: string
  metadata: {
    prev_publish_time?: number | null
    proof_available_time?: number | null
    slot?: number | null
  }
  price: Price
}

export type Price = {
  conf: string
  expo: number
  price: string
  publish_time: number
}

export const getPrices = async (priceIds: string[]): Promise<PriceUpdate> => {
  // Latest price updates
  return (await connection.getLatestPriceUpdates(priceIds)) as PriceUpdate
}

export const getHighestPrice = (price: Price) => {
  const priceValue = parseFloat(price.price) * Math.pow(10, price.expo)
  const confidence = parseFloat(price.conf) * Math.pow(10, price.expo)

  const highestPrice = priceValue + confidence

  return highestPrice
}

export const getLowestPrice = (price: Price) => {
  // Calculate the lowest acceptable price based on confidence interval
  // Use the exponent to properly scale the values
  const priceValue = parseFloat(price.price) * Math.pow(10, price.expo)
  const confidence = parseFloat(price.conf) * Math.pow(10, price.expo)

  // The lowest price is the current price minus the confidence interval
  // This accounts for the uncertainty in the price feed
  const lowestPrice = priceValue - confidence

  return Math.max(lowestPrice, 0) // Ensure price doesn't go negative
}
