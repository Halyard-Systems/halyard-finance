deploy-local:
	forge script script/DepositManager.s.sol:DepositManagerScript \
		--rpc-url http://127.0.0.1:8545 \
		--sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
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