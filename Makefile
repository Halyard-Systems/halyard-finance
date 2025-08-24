SHELL := /bin/bash
.ONESHELL:

# Testnet Deployment via Alchemy
define deploy_testnet_script
	set -a; source .env.sepolia; set +a
	if [ -z "$$ALCHEMY_API_KEY" ]; then \
		echo "Error: ALCHEMY_API_KEY environment variable is required"; \
		exit 1; \
	fi
	if [ -z "$$TESTNET_DEPLOYER_ADDRESS" ]; then \
		echo "Error: TESTNET_DEPLOYER_ADDRESS environment variable is required"; \
		exit 1; \
	fi
	if [ -z "$$TESTNET_DEPLOYER_PRIVATE_KEY" ]; then \
		echo "Error: TESTNET_DEPLOYER_PRIVATE_KEY environment variable is required"; \
		exit 1; \
	fi
	forge script $(1) \
		--rpc-url https://eth-sepolia.g.alchemy.com/v2/$$ALCHEMY_API_KEY \
		--sender $$TESTNET_DEPLOYER_ADDRESS \
		--private-key $$TESTNET_DEPLOYER_PRIVATE_KEY \
		--broadcast \
		-vvvv
endef

add-token-testnet:
	$(call deploy_testnet_script,script/AddTokenToDepositManager.s.sol:AddTokenToDepositManagerScript)

check-tokens-testnet:
	set -a; source .env.sepolia; set +a; \
	forge script script/CheckDepositManagerTokens.s.sol:CheckDepositManagerTokensScript \
		--rpc-url https://eth-sepolia.g.alchemy.com/v2/$$ALCHEMY_API_KEY \
		--sender $$TESTNET_DEPLOYER_ADDRESS \
		--private-key $$TESTNET_DEPLOYER_PRIVATE_KEY \
		-vvvv

deploy-local:
	forge script script/LocalDeployment.s.sol:LocalDeploymentScript \
		--rpc-url http://127.0.0.1:8545 \
		--sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
		--broadcast \
		-vvvv

deploy-mock-erc20:
	$(call deploy_testnet_script,script/MockERC20Deployment.s.sol:MockERC20DeploymentScript)

deploy-sepolia-testnet:
	$(call deploy_testnet_script,script/TestnetDeployment.s.sol:TestnetDeploymentScript)

mint-mock-erc20:
	set -a; source .env.sepolia; set +a; \
	# Replace with the address of a mock ERC20 contract
	export TOKEN_ADDRESS=0x6fa28d30Becf5Ab2568cFAE11f9f83D5E8A5B013; \
	# Replace with the address of the recipient, or remove this line to use the sender address
	#export RECIPIENT_ADDRESS=0x1234567890123456789012345678901234567890; \
	# Replace with the amount of tokens to mint, or remove to default to 1000
	export MINT_AMOUNT=5000000000000; \
	forge script script/MockERC20Mint.s.sol:MockERC20MintScript \
		--rpc-url https://eth-sepolia.g.alchemy.com/v2/$$ALCHEMY_API_KEY \
		--sender $$TESTNET_DEPLOYER_ADDRESS \
		--private-key $$TESTNET_DEPLOYER_PRIVATE_KEY \
		--gas-price 30000000000 \
		--broadcast \
		-vvvv

node:
	anvil --fork-url https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY} --fork-block-number 22900000

tests:
	forge test

transfer-tokens:
	cast rpc anvil_impersonateAccount 0x64F23F66C82e6B77916ad435f09511d608fD8EEa --rpc-url http://127.0.0.1:8545 > /dev/null && \
	cast rpc anvil_impersonateAccount 0xF977814e90dA44bFA03b6295A0616a897441aceC --rpc-url http://127.0.0.1:8545 > /dev/null && \
	forge script script/TransferTokens.s.sol:TransferTokens \
		--rpc-url http://127.0.0.1:8545 \
		--broadcast \
		--unlocked 0x64F23F66C82e6B77916ad435f09511d608fD8EEa 0xF977814e90dA44bFA03b6295A0616a897441aceC \
		-vvvv