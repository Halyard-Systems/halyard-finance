import { useState } from 'react'

export function TestnetInstructions() {
  const [isExpanded, setIsExpanded] = useState(false)

  return (
    <div className='bg-card rounded-lg shadow-sm border border-border p-6'>
      <div className='overflow-hidden'>
        <button
          onClick={() => setIsExpanded(!isExpanded)}
          className='flex items-center justify-between w-full text-left mb-4'
        >
          <h2 className='text-lg font-bold'>Testnet Instructions</h2>
          <svg
            className={`w-5 h-5 transition-transform duration-200 ${
              isExpanded ? 'rotate-180' : ''
            }`}
            fill='none'
            stroke='currentColor'
            viewBox='0 0 24 24'
          >
            <path
              strokeLinecap='round'
              strokeLinejoin='round'
              strokeWidth={2}
              d='M19 9l-7 7-7-7'
            />
          </svg>
        </button>

        <div
          className={`transition-all duration-200 ease-in-out ${
            isExpanded
              ? 'max-h-screen opacity-100'
              : 'max-h-0 opacity-0 overflow-hidden'
          }`}
        >
          <div className='space-y-4'>
            <p className='mb-4'>
              This is a testnet version of the app. To use the app, you need to
              have mock assets.
            </p>
            <p className='mb-4'>
              You can mint your own ERC20 tokens from the mock contracts using
              the following Foundry commands:
            </p>
            <p className='text-sm mb-4'>
              Mint 1000 USDC tokens to your address
              <br />
              <code className='text-sm text-gray-500'>
                cast send 0x6e2622F28a0ba92fb398B3232399C3BEc2fe43e7
                "mint(address,uint256)" YOUR_ADDRESS 1000000000 --rpc-url
                SEPOLIA_RPC_URL --private-key YOUR_PRIVATE_KEY
              </code>
            </p>
            <p className='text-sm mb-4'>
              Mint 1000 USDT tokens to your address
              <br />
              <code className='text-sm text-gray-500'>
                cast send 0x6fa28d30Becf5Ab2568cFAE11f9f83D5E8A5B013
                "mint(address,uint256)" YOUR_ADDRESS 1000000000 --rpc-url
                SEPOLIA_RPC_URL --private-key YOUR_PRIVATE_KEY
              </code>
            </p>
            <p className='mb-2 mt-8'>
              If you prefer, you may use ethers.js instead:
            </p>
            <p className='text-sm mb-4'>
              Mint 1000 USDC tokens to your address
              <pre className='text-gray-500 bg-gray-100 p-4 rounded text-sm overflow-x-auto'>
                {`node -e "
const { ethers } = require('ethers');
const provider = new ethers.JsonRpcProvider('SEPOLIA_RPC_URL');
const wallet = new ethers.Wallet('YOUR_PRIVATE_KEY', provider);
const usdcAddress = '0x6e2622F28a0ba92fb398B3232399C3BEc2fe43e7';
const usdcAbi = ['function mint(address to, uint256 amount) external'];
const usdc = new ethers.Contract(usdcAddress, usdcAbi, wallet);
usdc.mint(wallet.address, ethers.parseUnits('1000', 6)).then(() => console.log('Minted!'));
"`}
              </pre>
            </p>
            <p className='text-sm mb-4'>
              Mint 1000 USDT tokens to your address
              <pre className='text-gray-500 bg-gray-100 p-4 rounded text-sm overflow-x-auto'>
                {`node -e "
const { ethers } = require('ethers');
const provider = new ethers.JsonRpcProvider('SEPOLIA_RPC_URL');
const wallet = new ethers.Wallet('YOUR_PRIVATE_KEY', provider);
const usdcAddress = '0x6fa28d30Becf5Ab2568cFAE11f9f83D5E8A5B013';
const usdcAbi = ['function mint(address to, uint256 amount) external'];
const usdc = new ethers.Contract(usdcAddress, usdcAbi, wallet);
usdc.mint(wallet.address, ethers.parseUnits('1000', 6)).then(() => console.log('Minted!'));
"`}
              </pre>
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}
