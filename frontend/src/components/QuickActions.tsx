import { Button } from './ui/button'
import { Plus, Minus, TrendingUp, TrendingDown } from 'lucide-react'

interface QuickActionsProps {
  onDeposit: () => void
  onWithdraw: () => void
  onBorrow: () => void
  onRepay: () => void
}

export function QuickActions({
  onDeposit,
  onWithdraw,
  onBorrow,
  onRepay,
}: QuickActionsProps) {
  return (
    <div className='mb-8'>
      <div className='flex justify-between w-full'>
        <Button
          onClick={onDeposit}
          variant='outline'
          size='lg'
          className='flex-1 mx-2'
        >
          <Plus className='w-5 h-5 mr-2' />
          Lend
        </Button>
        <Button
          onClick={onWithdraw}
          variant='outline'
          size='lg'
          className='flex-1 mx-2'
        >
          <Minus className='w-5 h-5 mr-2' />
          Withdraw
        </Button>
        <Button
          onClick={onBorrow}
          variant='outline'
          size='lg'
          className='flex-1 mx-2'
        >
          <TrendingUp className='w-5 h-5 mr-2' />
          Borrow
        </Button>
        <Button
          onClick={onRepay}
          variant='outline'
          size='lg'
          className='flex-1 mx-2'
        >
          <TrendingDown className='w-5 h-5 mr-2' />
          Repay
        </Button>
      </div>
    </div>
  )
}
