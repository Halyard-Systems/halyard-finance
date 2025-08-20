## Halyard Finance

<img width="1088" height="430" alt="Screenshot from 2025-08-20 00-47-27" src="https://github.com/user-attachments/assets/21afb97a-d748-4b3d-9c50-045f62e9c5b2" />

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

### 3. Start the front end

```shell
$ cd frontend
$ pnpm i
$ pnpm run dev
```

See [frontend/README.md](frontend/README.md) for detailed frontend documentation.


