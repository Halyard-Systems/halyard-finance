import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { injected } from 'wagmi/connectors'
import { Button } from './ui/button'

export function Connect() {
  const { isConnected } = useAccount()
  const { connect } = useConnect()
  const { disconnect } = useDisconnect()

  return (
    <div className='bg-card rounded-lg shadow-sm border border-border p-6 text-center'>
      <h2 className='text-xl font-semibold text-card-foreground mb-4'>
        Welcome to Halyard Finance
      </h2>
      <p className='text-muted-foreground mb-6'>
        Connect your wallet to start depositing and managing your funds.
      </p>
      {!isConnected ? (
        <Button onClick={() => connect({ connector: injected() })} size='lg'>
          Connect Wallet
        </Button>
      ) : (
        <Button onClick={() => disconnect()} size='lg'>
          Disconnect Wallet
        </Button>
      )}
    </div>
  )
}
