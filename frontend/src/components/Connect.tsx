import { Button } from './ui/button'

export function Connect() {
  return (
    <div className='bg-card rounded-lg shadow-sm border border-border p-6 text-center'>
      <h2 className='text-xl font-semibold text-card-foreground mb-4'>
        Welcome to Halyard Finance
      </h2>
      <p className='text-muted-foreground mb-6'>
        Connect your wallet to start depositing and managing your funds.
      </p>
      <Button
        onClick={() => {
          // This will be handled by the Header component
        }}
        size='lg'
      >
        Connect Wallet
      </Button>
    </div>
  )
}
