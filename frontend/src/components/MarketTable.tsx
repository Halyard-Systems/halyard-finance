import { Button } from './ui/button'
import type { Token } from '../lib/types'

export interface MarketRow {
  token: Token
  deposits: bigint
  borrows: bigint
  depositApy: number
  borrowApy: number
  userDeposit: bigint
  onDeposit: () => void
  onWithdraw: () => void
  onBorrow: () => void
}

interface MarketTableProps {
  rows: MarketRow[]
}

const tokenValueDisplay = (value: bigint | number, decimals: number) => {
  return (Number(value) / Math.pow(10, decimals)).toLocaleString(undefined, {
    maximumFractionDigits: 6,
  })
}

export function MarketTable({ rows }: MarketTableProps) {
  // Determine if the user has any deposits in any asset
  const anyDeposits = rows.some((row) => row.userDeposit > 0)
  return (
    <div className='bg-card rounded-lg shadow-sm border border-border p-6'>
      <div className='overflow-x-auto'>
        <table className='w-full'>
          <thead>
            <tr className='border-b border-border'>
              <th className='text-left py-3 px-4 font-medium text-card-foreground'>
                Asset
              </th>
              <th className='text-left py-3 px-4 font-medium text-card-foreground'>
                Deposits
              </th>
              <th className='text-left py-3 px-4 font-medium text-card-foreground'>
                Borrows
              </th>
              <th className='text-left py-3 px-4 font-medium text-card-foreground'>
                Deposit APY
              </th>
              <th className='text-left py-3 px-4 font-medium text-card-foreground'>
                Borrow APY
              </th>
              <th className='text-left py-3 px-4 font-medium text-card-foreground'>
                Your Deposits
              </th>
              <th className='text-left py-3 px-4 font-medium text-card-foreground'>
                Actions
              </th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row, index) => (
              <tr key={index} className='border-b border-border'>
                {/* Asset */}
                <td className='py-4 px-4'>
                  <div className='flex items-center space-x-2'>
                    <img
                      src={row.token.icon}
                      alt={`${row.token.symbol} icon`}
                      className='w-6 h-6'
                    />
                    <div>
                      <div className='font-medium text-card-foreground'>
                        {row.token.symbol}
                      </div>
                      <div className='text-sm text-muted-foreground'>
                        {row.token.name}
                      </div>
                    </div>
                  </div>
                </td>

                {/* Deposits */}
                <td className='py-4 px-4'>
                  <div className='font-mono text-card-foreground'>
                    {tokenValueDisplay(row.deposits, row.token.decimals)}{' '}
                    {row.token.symbol}
                  </div>
                </td>

                {/* Borrows */}
                <td className='py-4 px-4'>
                  <div className='font-mono text-card-foreground'>
                    {tokenValueDisplay(row.borrows, row.token.decimals)}{' '}
                    {row.token.symbol}
                  </div>
                </td>

                {/* Deposit APY */}
                <td className='py-4 px-4'>
                  <div className='text-green-600 font-medium'>
                    {row.depositApy.toFixed(1)}%
                  </div>
                </td>

                {/* Borrow APY */}
                <td className='py-4 px-4'>
                  <div className='text-red-600 font-medium'>
                    {row.borrowApy.toFixed(1)}%
                  </div>
                </td>

                {/* Your Deposits */}
                <td className='py-4 px-4'>
                  <div className='font-mono text-card-foreground'>
                    {tokenValueDisplay(row.userDeposit, row.token.decimals)}{' '}
                    {row.token.symbol}
                  </div>
                </td>

                {/* Actions */}
                <td className='py-4 px-4'>
                  <div className='flex space-x-2'>
                    <Button variant='outline' size='sm' onClick={row.onDeposit}>
                      Deposit
                    </Button>
                    {anyDeposits && (
                      <Button
                        variant='outline'
                        size='sm'
                        onClick={row.onBorrow}
                      >
                        Borrow
                      </Button>
                    )}
                    {row.userDeposit > 0 && (
                      <Button
                        variant='outline'
                        size='sm'
                        onClick={row.onWithdraw}
                      >
                        Withdraw
                      </Button>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
