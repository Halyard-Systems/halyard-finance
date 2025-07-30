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

export const getPrices = async (priceIds: string[]) => {
  // Latest price updates
  const priceUpdates = await connection.getLatestPriceUpdates(priceIds)
  console.log(priceUpdates)
  return priceUpdates
}
