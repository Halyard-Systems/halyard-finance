## Halyard Finance

<img width="1094" height="698" alt="Screenshot from 2025-08-16 02-15-26" src="https://github.com/user-attachments/assets/6ec7ed7c-1a80-4b8b-b8a2-e110bb6f1aa1" />


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


