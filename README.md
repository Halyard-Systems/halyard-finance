## Halyard Finance

**Multichain money market**

## Development

A Sepolia node fork is required, and this project is built using Alchemy. Set the ALCHEMY_API_KEY before running the node to fork for a deployable environment.

### Start the local Anvil node

```shell
$ make node
```

### Deploy the contracts

```shell
$ make deploy-local
```

## Frontend

A React + TypeScript frontend is included in the `frontend/` directory.

### Setup Frontend

```shell
cd frontend
pnpm install
pnpm dev
```

See [frontend/README.md](frontend/README.md) for detailed frontend documentation.


