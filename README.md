## Halyard Finance

<img width="1071" height="430" alt="Screenshot from 2025-08-20 01-08-23" src="https://github.com/user-attachments/assets/b40790c9-1194-45c8-97c9-e49086d941b1" />

<img width="1071" height="430" alt="Screenshot from 2025-08-20 01-11-57" src="https://github.com/user-attachments/assets/f5f651e3-0bef-431f-94d2-d8923c915a98" />

## Development

The local development environment is based on a node with a mainnet fork; see the Makefile for more details.

Alchemy is recommended for the node connection; set the ALCHEMY_API_KEY before running the node to fork for a deployable environment.

### Setup

After cloning, configure git to use the shared hooks directory:

```shell
git config core.hooksPath .githooks
```

This enables the pre-commit hook that runs `forge fmt --check` before each commit, matching the CI formatting check.

### Start the Development Environment

Three terminals/processes are required:

### 1. In separate terminals, start the local Anvil node for each chain:

```shell
$ make eth-node
```

```shell
$ make arb-node
```

### 2. Deploy the contracts and transfer USDC to the development account

```shell
$ make deploy-local-eth
$ make transfer-tokens-eth
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

# Set after Step 3 deployment
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

**_The following MockERC20 contracts are already deployed and allow open minting, use the MockERC20Mint.s.sol script to obtain tokens._**

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

## Architecture

Halyard Finance operates with a hub-and-spoke design. Spokes manage liquidity and collateral on their respective networks, while the hub maintains a central accounting ledger across all spokes. Actions (deposit, borrow, repay, withdraw, liquidate) originate on either a spoke or the hub and require LayerZero messages to coordinate state across chains.

### Contracts

**Hub (Ethereum):**
- **HubRouter** — User-facing entrypoint for withdraw, borrow, and repay requests
- **HubController** — LayerZero message router; sends commands to and receives receipts from spokes
- **PositionBook** — Central ledger for per-user collateral balances across all chains
- **DebtManager** — Debt accounting with compound interest accrual (RAY/1e27 precision)
- **RiskEngine** — Health factor validation for borrows and withdrawals using oracle prices
- **LiquidationEngine** — Orchestrates liquidations of undercollateralized positions
- **AssetRegistry** — Configuration store for asset risk parameters (LTV, liquidation threshold, caps)
- **PythOracleAdapter** — Wraps Pyth Network oracles with freshness/confidence checks

**Spoke (Multi-chain):**
- **SpokeController** — LayerZero receiver/sender; executes hub commands and sends receipts
- **CollateralVault** — Custodian of user collateral deposits
- **LiquidityVault** — Custodian of borrowable liquidity; handles repayments

### Deposit

    1. User calls SpokeController#depositAndNotify
    2. Spoke pulls tokens from msg.sender
    3. Spoke updates user's local balance via CollateralVault#deposit
    4. Spoke sends a DEPOSIT_CREDITED message to HubController
    5. HubController calls PositionBook#creditCollateral to update the user's total balance

### Borrow

    1. User calls HubRouter#borrowAndNotify
    2. HubRouter calls RiskEngine#validateAndCreateBorrow
    3. RiskEngine accrues all debt indices, computes borrow power from collateral and oracle prices
    4. If the borrow keeps the health factor >= 1.0, PositionBook reserves the debt headroom
    5. HubController sends CMD_RELEASE_BORROW to the spoke
    6. SpokeController receives the command and calls LiquidityVault#releaseBorrow to transfer tokens to the user
    7. SpokeController sends BORROW_RELEASED receipt to HubController
    8. HubRouter#finalizeBorrow mints scaled debt via DebtManager and clears the reservation

### Repay

    1. User calls LiquidityVault#repay with the token amount
    2. LiquidityVault pulls tokens from the user
    3. SpokeController sends REPAY_RECEIVED message to HubController
    4. HubRouter#finalizeRepay calls DebtManager#burnDebt to reduce the user's scaled debt

### Withdraw

    1. User calls HubRouter#withdrawAndNotify
    2. HubRouter calls RiskEngine#validateAndCreateWithdraw
    3. RiskEngine verifies collateral is available and that the withdrawal keeps the health factor >= 1.0
    4. PositionBook reserves the collateral and creates a pending withdrawal
    5. HubController sends CMD_RELEASE_WITHDRAW to the spoke
    6. SpokeController calls CollateralVault#withdrawByController to transfer tokens to the user
    7. SpokeController sends WITHDRAW_RELEASED receipt to HubController
    8. HubRouter#finalizeWithdraw debits collateral in PositionBook and clears the reservation

### Liquidation

    1. Liquidator calls LiquidationEngine#liquidate with the undercollateralized user's debt and collateral details
    2. LiquidationEngine computes the health factor; reverts if >= 1.0
    3. Seize amount is calculated as: (debtRepayValue * (1 + liquidationBonus)) / collateralPrice
    4. PositionBook reserves the collateral to seize and creates a pending liquidation (debt burn is deferred)
    5. HubController sends CMD_SEIZE_COLLATERAL to the spoke
    6. SpokeController calls CollateralVault#seizeByController to transfer collateral to the liquidator
    7. SpokeController sends COLLATERAL_SEIZED receipt to HubController
    8. HubRouter#finalizeLiquidation burns the repaid debt via DebtManager, debits collateral in PositionBook, and clears the reservation
