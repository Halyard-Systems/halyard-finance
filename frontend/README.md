# Halyard Finance Frontend

A React + TypeScript frontend for the Halyard Finance protocol, built with Vite and wagmi.js.

## Features

- 🔗 Wallet connection (MetaMask, WalletConnect, Coinbase Wallet)
- 💰 Deposit functionality
- 📊 Balance display
- 🎨 Modern UI with Tailwind CSS

## Setup

1. **Install dependencies:**
   ```bash
   pnpm install
   ```

2. **Configure WalletConnect:**
   - Get a project ID from [WalletConnect Cloud](https://cloud.walletconnect.com)
   - Update the `VITE_WALLET_CONNECT_PROJECT_ID` environment variable with your project ID

3. **Update contract addresses:**
   - Deploy your DepositManager contract
   - Update `VITE_DEPOSIT_MANAGER_ADDRESS` in `src/App.tsx`
   - Deploy your BorrowManager contract
   - Update `VITE_BORROW_MANAGER_ADDRESS` in `src/App.tsx`

## Development

```bash
# Start development server
pnpm dev

# Build for production
pnpm build

# Preview production build
pnpm preview
```

## Environment Variables

Create a `.env` file in the `frontend/` directory.
The values below will work for a standard local Forge instance:

```env
VITE_BORROW_MANAGER_ADDRESS=0x5f9dD176ea5282d392225ceC5c2E7A24d5d02672
VITE_DEPOSIT_MANAGER_ADDRESS=0x2e590d65Dd357a7565EfB5ffB329F8465F18c494
VITE_NODE_URL="http://localhost:8545"
# The local deployment script will deploy this contract
VITE_MOCK_PYTH_ADDRESS=0x6c7Df3575f1d69eb3B245A082937794794C2b82E
# Tells the front end to update the mock price stream before calling contract functions that use pricing data
VITE_USE_MOCK_PYTH=true
VITE_WALLET_CONNECT_PROJECT_ID=<<your-project-id-here>>
# Network selection: "mainnet" (default) or "sepolia"
VITE_NETWORK=mainnet
```

## Tech Stack

- **React 19** - UI framework
- **TypeScript** - Type safety
- **Vite** - Build tool
- **wagmi.js** - Ethereum hooks
- **viem** - Ethereum client
- **Tailwind CSS** - Styling
