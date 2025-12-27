export interface MockAssetData {
  ticker: string
  supplied: string
  borrowed: string
  apy: string
  logo: string
  decimals: number
  address: `0x${string}`
}

export interface MockChainData {
  name: string
  logo: string
  assets: MockAssetData[]
}

export const portfolioData: MockChainData[] = [
  {
    name: 'Ethereum',
    logo: 'ethereum-eth-logo.svg',
    assets: [
      {
        ticker: 'ETH',
        supplied: '$5,000',
        borrowed: '$0',
        apy: '2.5%',
        logo: 'ethereum-eth-logo.svg',
        decimals: 18,
        address: '0x0000000000000000000000000000000000000000',
      },
      {
        ticker: 'USDC',
        supplied: '$3,000',
        borrowed: '$0',
        apy: '4.2%',
        logo: 'usd-coin-usdc-logo.svg',
        decimals: 6,
        address: '0x0000000000000000000000000000000000000000',
      },
      {
        ticker: 'WBTC',
        supplied: '$4,000',
        borrowed: '$0',
        apy: '3.8%',
        logo: 'wrapped-bitcoin-wbtc-logo.svg',
        decimals: 8,
        address: '0x0000000000000000000000000000000000000000',
      },
    ],
  },
  {
    name: 'Arbitrum',
    logo: 'arbitrum-arb-logo.svg',
    assets: [
      {
        ticker: 'ARB',
        supplied: '$1,500',
        borrowed: '$0',
        apy: '5.1%',
        logo: 'arbitrum-arb-logo.svg',
        decimals: 18,
        address: '0x0000000000000000000000000000000000000000',
      },
      {
        ticker: 'WETH',
        supplied: '$2,000',
        borrowed: '$0',
        apy: '3.2%',
        logo: 'wrapped-ethereum-weth-logo.svg',
        decimals: 18,
        address: '0x0000000000000000000000000000000000000000',
      },
      {
        ticker: 'USDC',
        supplied: '$1,000',
        borrowed: '$0',
        apy: '4.5%',
        logo: 'usd-coin-usdc-logo.svg',
        decimals: 6,
        address: '0x0000000000000000000000000000000000000000',
      },
    ],
  },
  {
    name: 'BNB',
    logo: 'binance-coin-bnb-logo.svg',
    assets: [
      {
        ticker: 'BNB',
        supplied: '$800',
        borrowed: '$0',
        apy: '6.2%',
        logo: 'binance-coin-bnb-logo.svg',
        decimals: 18,
        address: '0x0000000000000000000000000000000000000000',
      },
      {
        ticker: 'WBTC',
        supplied: '$1,200',
        borrowed: '$0',
        apy: '4.8%',
        logo: 'wrapped-bitcoin-wbtc-logo.svg',
        decimals: 8,
        address: '0x0000000000000000000000000000000000000000',
      },
      {
        ticker: 'USDT',
        supplied: '$500',
        borrowed: '$0',
        apy: '3.9%',
        logo: 'tether-usdt-logo.svg',
        decimals: 6,
        address: '0x0000000000000000000000000000000000000000',
      },
    ],
  },
]



