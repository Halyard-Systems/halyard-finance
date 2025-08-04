import type { PublicClient } from 'viem'
import { getPrices, type PriceUpdate } from '../lib/prices'
import { getSupportedTokenIds, getAsset, getBalanceOf } from '../lib/queries'
import { setMaxBorrow } from './reducers/borrowManager'
import type { AppDispatch } from './store'
import { getBalance } from 'viem/actions'

export const maxBorrow = async (priceIds: string[], dispatch: AppDispatch) => {
  const priceUpdates: PriceUpdate = await getPrices(priceIds)

  console.log('prices', priceUpdates.parsed)
  dispatch(setMaxBorrow(1))
}

// export const getTokens = async (
//   publicClient: PublicClient,
//   account: `0x${string}`,
//   dispatch: AppDispatch
// ) => {
//   //   const { data: data } = useReadSupportedTokens()
//   //   console.log('data', data)
//   //   const supportedTokenIds = data as `0x${string}`[]

//   //   supportedTokenIds.forEach((tokenId) => {
//   //     const { data: asset } = useReadAsset(tokenId)
//   //     console.log('asset', asset)
//   //   })

//   // Get supported token ids
//   const tokens = await getSupportedTokenIds(publicClient)
//   console.log('tokens', tokens)

//   // Get asset data for each token
//   const assetData = await Promise.all(
//     tokens.map(async (tokenId) => {
//       const asset = await getAsset(tokenId, publicClient)
//       console.log('asset', asset)
//       return asset
//     })
//   )

//   console.log('assetData', assetData)

//   // Get deposits for each token
//   const deposits = await Promise.all(
//     tokens.map(async (tokenId) => {
//       const deposits = await getBalanceOf(tokenId, account, publicClient)
//       console.log('deposits', deposits)
//       return deposits
//     })
//   )

//   console.log('deposits', deposits)

//   //dispatch(setTokens(tokens))
// }
