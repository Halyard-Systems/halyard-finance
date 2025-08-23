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

### 2. Set testnet environment variables

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

# Set after deployment
DEPOSIT_MANAGER_ADDRESS=0x1234567890123456789012345678901234567890

# Settings for adding a token to DepositManager
ADD_TOKEN_SYMBOL="MTT"
ADD_TOKEN_ADDRESS=0x1234567890123456789012345678901234567890
ADD_TOKEN_DECIMALS=6
# Example: 5%
ADD_TOKEN_BASE_RATE=0.05e27
# Example: 30%
ADD_TOKEN_SLOPE1=0.3e27
# Example: 200%
ADD_TOKEN_SLOPE2=2.0e27
# Example: 80%
ADD_TOKEN_KINK=0.8e18
# Example: 10%
ADD_TOKEN_RESERVE_FACTOR=0.1e27
```

### 3. Deploy the Halyard Finance contracts

Run `make deploy-sepolia-testnet` in terminal and note the resulting addresses for the new contracts.

### 4. Deploy mock ERC20 contracts (if not already done)

***The following MockERC20 contracts are already deployed and allow open minting, use the MockERC20Mint.s.sol script to obtain tokens.***

```
USDC: 0x6e2622F28a0ba92fb398B3232399C3BEc2fe43e7
USDT: 0x6fa28d30Becf5Ab2568cFAE11f9f83D5E8A5B013
```

If you wish to add your own Mock ERC20 contracts:
1. Update the `TOKEN_NAME`, `TOKEN_SYMBOL`, and `TOKEN_DECIMALS`
2. Run `make deploy-mock-erc20`
3. Note the resulting contract address
 

### 5. Add the Mock ERC20 tokens to the DepositManager contract

The tokens that Halyard Finance supports must be added to the contract.
To add a new token, run `make add-token-testnet` with the `ADD_TOKEN_*` DepositManager environment variables set.