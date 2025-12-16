import { portfolioData } from '@/sample-data'
import { Card, CardContent, CardHeader, CardTitle } from './ui/card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from './ui/table'

export function Portfolio() {
  return (
    <div className='mb-8'>
      <Card>
        <CardHeader>
          <CardTitle>Portfolio Overview</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className='w-[150px]'>Chain</TableHead>
                <TableHead className='w-[200px]'>Asset</TableHead>
                <TableHead className='w-[120px] text-right'>Supplied</TableHead>
                <TableHead className='w-[120px] text-right'>Borrowed</TableHead>
                <TableHead className='w-[100px] text-right'>APY</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {portfolioData.map((chainData) => (
                <TableRow key={chainData.name}>
                  <TableCell className='font-medium align-top'>
                    <div className='flex items-center'>
                      <img
                        src={`/${chainData.logo}`}
                        alt={`${chainData.name} logo`}
                        className='w-6 h-6 mr-3'
                      />
                      <span className='text-lg font-semibold'>
                        {chainData.name}
                      </span>
                    </div>
                  </TableCell>
                  <TableCell colSpan={4} className='p-0'>
                    <Table>
                      <TableBody>
                        {chainData.assets.map((asset, assetIndex) => (
                          <TableRow
                            key={asset.ticker}
                            className={
                              assetIndex === chainData.assets.length - 1
                                ? 'border-b-0'
                                : ''
                            }
                          >
                            <TableCell className='w-[200px] pl-8'>
                              <div className='flex items-center'>
                                <img
                                  src={`/${asset.logo}`}
                                  alt={`${asset.ticker} logo`}
                                  className='w-3 h-3 mr-2'
                                />
                                {asset.ticker}
                              </div>
                            </TableCell>
                            <TableCell className='w-[120px] text-right font-medium'>
                              {asset.supplied}
                            </TableCell>
                            <TableCell className='w-[120px] text-right font-medium'>
                              {asset.borrowed}
                            </TableCell>
                            <TableCell className='w-[100px] text-right font-medium text-green-600'>
                              {asset.apy}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  )
}
