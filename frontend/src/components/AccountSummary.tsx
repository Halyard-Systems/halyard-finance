import { Card, CardContent } from './ui/card'

export function AccountSummary() {
  return (
    <div className='mb-8'>
      <Card>
        <CardContent className='p-6'>
          <div className='grid grid-cols-1 md:grid-cols-4 gap-6'>
            {/* Total Supplied */}
            <div className='flex flex-col items-center justify-center text-center'>
              <div className='text-sm font-medium text-muted-foreground mb-2'>
                Total Supplied
              </div>
              <div className='text-2xl font-bold'>$12,000</div>
            </div>

            {/* Total Borrowed */}
            <div className='flex flex-col items-center justify-center text-center'>
              <div className='text-sm font-medium text-muted-foreground mb-2'>
                Total Borrowed
              </div>
              <div className='text-2xl font-bold'>$5,000</div>
            </div>

            {/* Net APY */}
            <div className='flex flex-col items-center justify-center text-center'>
              <div className='text-sm font-medium text-muted-foreground mb-2'>
                Net APY
              </div>
              <div className='text-2xl font-bold'>3.5%</div>
            </div>

            {/* Health Factor & Auto-Repay */}
            <div className='flex flex-col justify-center'>
              <div className='space-y-3'>
                <div className='flex justify-end items-center mr-4'>
                  <div className='text-sm font-medium text-muted-foreground mr-4'>
                    Health Factor:
                  </div>
                  <div className='text-2xl font-bold text-green-600 w-5'>
                    1.5
                  </div>
                </div>
                <div className='flex justify-end items-center mr-4'>
                  <div className='text-sm font-medium text-muted-foreground mr-4'>
                    Auto-Repay:
                  </div>
                  <div className='text-sm font-semibold text-green-600 w-5'>
                    On
                  </div>
                </div>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
