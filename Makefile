deploy-local:
	forge script script/DepositManager.s.sol:DepositManagerScript \
		--rpc-url http://127.0.0.1:8545 \
		--sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
		--broadcast \
		-vvvv
node:
	anvil --fork-url https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY}
tests:
	forge test