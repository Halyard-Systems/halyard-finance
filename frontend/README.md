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

2. **Configure WalletConnect (optional):**
   - Get a project ID from [WalletConnect Cloud](https://cloud.walletconnect.com)
   - Update `src/lib/wagmi.ts` with your project ID

3. **Update contract address:**
   - Deploy your DepositManager contract
   - Update `DEPOSIT_MANAGER_ADDRESS` in `src/App.tsx`

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

Create a `.env` file in the frontend directory:

```env
VITE_WALLET_CONNECT_PROJECT_ID=your_project_id_here
VITE_DEPOSIT_MANAGER_ADDRESS=your_contract_address_here
```

## Tech Stack

- **React 19** - UI framework
- **TypeScript** - Type safety
- **Vite** - Build tool
- **wagmi.js** - Ethereum hooks
- **viem** - Ethereum client
- **Tailwind CSS** - Styling

## Project Structure

```
src/
├── lib/
│   └── wagmi.ts          # wagmi configuration
├── App.tsx               # Main app component
├── main.tsx              # App entry point
└── index.css             # Global styles
```
