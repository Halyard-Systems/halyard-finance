import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { injected } from 'wagmi/connectors'
import { Button } from './ui/button'
import halyardLogo from '../assets/halyard-finance-navbar-logo-cyan-gold.png'

export function Header() {
  const { address, isConnected } = useAccount()
  const { connect } = useConnect()
  const { disconnect } = useDisconnect()

  return (
    <header className='bg-card shadow-sm border-b border-border sticky top-0 z-50'>
      <div className='max-w-7xl mx-auto px-4 sm:px-6 lg:px-8'>
        <div className='flex justify-between items-center h-16'>
          {/* Logo/Title */}
          <img
            src={halyardLogo}
            alt='Halyard Finance Logo'
            className='h-10 w-auto'
          />
          {/* Wallet Connection */}
          <div className='flex items-center space-x-4'>
            {!isConnected ? (
              <Button onClick={() => connect({ connector: injected() })}>
                Connect Wallet
              </Button>
            ) : (
              <div className='flex items-center space-x-3'>
                <div className='text-sm text-muted-foreground'>
                  <span className='font-medium'>Connected:</span>
                  <span className='ml-1 font-mono text-xs'>
                    {address?.slice(0, 6)}...{address?.slice(-4)}
                  </span>
                </div>
                <Button variant='secondary' onClick={() => disconnect()}>
                  Disconnect
                </Button>
              </div>
            )}
          </div>
        </div>
      </div>
    </header>
  )
}
