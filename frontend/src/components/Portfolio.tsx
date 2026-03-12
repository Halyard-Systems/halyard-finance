import { Card, CardContent, CardHeader, CardTitle } from "./ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "./ui/table";
import { getSpokeByEid, spokeConfigs } from "../lib/contracts";
import type { CollateralPosition, DebtPosition } from "../lib/types";
import { fromWei } from "../lib/utils";

interface PortfolioProps {
  collateralPositions: CollateralPosition[];
  debtPositions: DebtPosition[];
  isLoading?: boolean;
}

// Group positions by eid (chain)
function groupByEid<T extends { eid: number }>(items: T[]): Map<number, T[]> {
  const map = new Map<number, T[]>();
  for (const item of items) {
    const group = map.get(item.eid) ?? [];
    group.push(item);
    map.set(item.eid, group);
  }
  return map;
}

export function Portfolio({
  collateralPositions,
  debtPositions,
  isLoading,
}: PortfolioProps) {
  const hasPositions = collateralPositions.length > 0 || debtPositions.length > 0;

  if (!hasPositions && !isLoading) {
    return (
      <div className="mb-8">
        <Card>
          <CardHeader>
            <CardTitle>Portfolio Overview</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-muted-foreground text-center py-4">
              No positions yet. Deposit collateral to get started.
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  // Collect all unique eids
  const collateralByEid = groupByEid(collateralPositions);
  const debtByEid = groupByEid(debtPositions);
  const allEids = new Set([...collateralByEid.keys(), ...debtByEid.keys()]);

  return (
    <div className="mb-8">
      <Card>
        <CardHeader>
          <CardTitle>Portfolio Overview</CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <p className="text-muted-foreground text-center py-4">Loading positions...</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[150px]">Chain</TableHead>
                  <TableHead className="w-[200px]">Asset</TableHead>
                  <TableHead className="w-[120px] text-right">Collateral</TableHead>
                  <TableHead className="w-[120px] text-right">Available</TableHead>
                  <TableHead className="w-[120px] text-right">Debt</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {[...allEids].map((eid) => {
                  const spoke = getSpokeByEid(eid);
                  const chainName = spoke?.name ?? `Chain ${eid}`;
                  const chainLogo = spoke?.logo ?? "ethereum-eth-logo.svg";

                  const collaterals = collateralByEid.get(eid) ?? [];
                  const debts = debtByEid.get(eid) ?? [];

                  // Merge by asset address
                  const assetMap = new Map<string, { collateral?: CollateralPosition; debt?: DebtPosition }>();
                  for (const c of collaterals) {
                    const key = c.asset.toLowerCase();
                    assetMap.set(key, { ...assetMap.get(key), collateral: c });
                  }
                  for (const d of debts) {
                    const key = d.asset.toLowerCase();
                    assetMap.set(key, { ...assetMap.get(key), debt: d });
                  }

                  const entries = [...assetMap.entries()];

                  return entries.map(([assetAddr, { collateral, debt }], i) => {
                    // Find asset symbol from spoke config
                    const spokeAsset = spoke?.assets.find(
                      (a) => a.canonicalAddress.toLowerCase() === assetAddr
                    );
                    const symbol = spokeAsset?.symbol ?? assetAddr.slice(0, 8);
                    const decimals = spokeAsset?.decimals ?? 18;
                    const icon = spokeAsset?.icon;

                    return (
                      <TableRow key={`${eid}-${assetAddr}`}>
                        {i === 0 && (
                          <TableCell
                            className="font-medium align-top"
                            rowSpan={entries.length}
                          >
                            <div className="flex items-center">
                              <img
                                src={`/${chainLogo}`}
                                alt={`${chainName} logo`}
                                className="w-6 h-6 mr-3"
                              />
                              <span className="text-lg font-semibold">
                                {chainName}
                              </span>
                            </div>
                          </TableCell>
                        )}
                        <TableCell>
                          <div className="flex items-center">
                            {icon && (
                              <img
                                src={`/${icon}`}
                                alt={`${symbol} logo`}
                                className="w-3 h-3 mr-2"
                              />
                            )}
                            {symbol}
                          </div>
                        </TableCell>
                        <TableCell className="text-right font-medium">
                          {collateral
                            ? fromWei(collateral.balance, decimals).toLocaleString(
                                undefined,
                                { maximumFractionDigits: 4 }
                              )
                            : "--"}
                        </TableCell>
                        <TableCell className="text-right font-medium">
                          {collateral
                            ? fromWei(collateral.available, decimals).toLocaleString(
                                undefined,
                                { maximumFractionDigits: 4 }
                              )
                            : "--"}
                        </TableCell>
                        <TableCell className="text-right font-medium text-red-600">
                          {debt && debt.debt > 0n
                            ? fromWei(debt.debt, decimals).toLocaleString(
                                undefined,
                                { maximumFractionDigits: 4 }
                              )
                            : "--"}
                        </TableCell>
                      </TableRow>
                    );
                  });
                })}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
