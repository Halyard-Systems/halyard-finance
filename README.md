## Halyard Finance

<img width="1071" height="430" alt="Screenshot from 2025-08-20 01-08-23" src="https://github.com/user-attachments/assets/b40790c9-1194-45c8-97c9-e49086d941b1" />

<img width="1071" height="430" alt="Screenshot from 2025-08-20 01-11-57" src="https://github.com/user-attachments/assets/f5f651e3-0bef-431f-94d2-d8923c915a98" />

## Development

The local development environment is based on a node with a mainnet fork; see the Makefile for more details.

Alchemy is recommended for the node connection; set the ALCHEMY_API_KEY before running the node to fork for a deployable environment.

#### Start the Development Environment

Three terminals/processes are required:

### 1. Start the local Anvil node

```shell
$ make node
```

### 2. Deploy the contracts and transfer USDC to the development account

```shell
$ make deploy-local
$ make transfer-usdc
```

### 3. Start the front end (the frontend README must be followed first!)

```shell
$ cd frontend
$ pnpm i
$ pnpm run dev
```

See [frontend/README.md](frontend/README.md) for detailed frontend documentation.

## Sepolia Testnet Deployment

### 1. Create the `.env.sepolia` file in the project root and replace the dummy data:

```shell
# Alchemy API Key for Sepolia testnet
ALCHEMY_API_KEY=your-alchemy-api-key-here

# Deployer wallet address (must have ETH for gas)
TESTNET_DEPLOYER_ADDRESS=0x1234567890123456789012345678901234567890

# Deployer private key (keep this secret!)
TESTNET_DEPLOYER_PRIVATE_KEY=0x1234567890123456789012345678901234567890123456789012345678901234

# MockERC20 configuration for testnet deployment
TOKEN_NAME="My Test Token"
TOKEN_SYMBOL="MTT"
TOKEN_DECIMALS=6
```

### 2. Deploy mock ERC20 contracts (if not already done)

***The following MockERC20 contracts are already deployed and allow open minting***
```
USDC: 0x6e2622F28a0ba92fb398B3232399C3BEc2fe43e7
USDT: 0x6fa28d30Becf5Ab2568cFAE11f9f83D5E8A5B013
```


On testnet, accounts with funds are needed for the ERC20 tokens that are configured
into the application. The easiest way to do this is to deploy your own. Update the
`.env.sepolia` file with the token parameters, and run the script:

```
# Alchemy API Key for Sepolia testnet
ALCHEMY_API_KEY=your-alchemy-api-key-here

# Deployer wallet address (must have ETH for gas)
TESTNET_DEPLOYER_ADDRESS=0x1234567890123456789012345678901234567890

# Deployer private key (keep this secret!)
TESTNET_DEPLOYER_PRIVATE_KEY=0x1234567890123456789012345678901234567890123456789012345678901234

# MockERC20 configuration for testnet deployment
TOKEN_NAME="My Test Token"
TOKEN_SYMBOL="MTT"
TOKEN_DECIMALS=6
```