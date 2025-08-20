import { HermesClient } from '@pythnetwork/hermes-client'
import MOCK_PYTH_ABI from '../abis/MockPyth.json'

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

// Pyth price ids
export const ETH_USDC_USDT_PRICE_IDS = [
  '0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace', // ETH/USD
  '0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a', // USDC/USD
  '0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b', // USDT/USD
]

export const MOCK_PRICES = [
  {
    id: ETH_USDC_USDT_PRICE_IDS[0], // ETH/USD
    price: 3000000000n, // $3000.00 (with 8 decimals)
    conf: 1000000n, // $0.01 confidence
    expo: -8,
    emaPrice: 3000000000n,
    emaConf: 1000000n,
  },
  {
    id: ETH_USDC_USDT_PRICE_IDS[1], // USDC/USD
    price: 100000000n, // $1.00 (with 8 decimals)
    conf: 100000n, // $0.001 confidence
    expo: -8,
    emaPrice: 100000000n,
    emaConf: 100000n,
  },
  {
    id: ETH_USDC_USDT_PRICE_IDS[2], // USDT/USD
    price: 100000000n, // $1.00 (with 8 decimals)
    conf: 100000n, // $0.001 confidence
    expo: -8,
    emaPrice: 100000000n,
    emaConf: 100000n,
  },
]

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

// Helper to create mock price feed update data
export async function createMockPriceFeedUpdateData(
  publicClient: any,
  mockPythAddress: `0x${string}`
): Promise<string[]> {
  const blockNumber = await publicClient.getBlockNumber()
  const block = await publicClient.getBlock({ blockNumber })

  // Use the current block timestamp as the publish time to ensure freshness
  const publishTime = BigInt(block.timestamp)
  const prevPublishTime = publishTime - 1n

  const updateData = await Promise.all(
    MOCK_PRICES.map(async (mockPrice) => {
      const priceFeedData = await publicClient.readContract({
        address: mockPythAddress,
        abi: MOCK_PYTH_ABI,
        functionName: 'createPriceFeedUpdateData',
        args: [
          mockPrice.id,
          mockPrice.price,
          mockPrice.conf,
          mockPrice.expo,
          mockPrice.emaPrice,
          mockPrice.emaConf,
          publishTime,
          prevPublishTime,
        ],
      })
      return priceFeedData as string
    })
  )

  return updateData
}

// Helper to update mock price feeds
export async function updateMockPriceFeeds(
  publicClient: any,
  mockPythAddress: `0x${string}`,
  updateData: string[],
  writeMockPyth: any
): Promise<void> {
  const fee = await publicClient.readContract({
    address: mockPythAddress,
    abi: MOCK_PYTH_ABI,
    functionName: 'getUpdateFee',
    args: [updateData],
  })

  const result = await writeMockPyth({
    address: mockPythAddress,
    abi: MOCK_PYTH_ABI,
    functionName: 'updatePriceFeeds',
    args: [updateData],
    value: fee as bigint,
  })

  console.log(result, 'RESULT')
  // Wait for the transaction to be mined
  console.log('Waiting for mock price update transaction to be mined...')
  const receipt = await publicClient.waitForTransactionReceipt({
    hash: result.hash,
  })
  console.log(
    'Mock price feeds updated successfully, block number:',
    receipt.blockNumber
  )
}
