import { Card, CardContent } from "./ui/card";
import type { AccountData } from "../lib/types";

interface AccountSummaryProps {
  accountData?: AccountData;
  isLoading?: boolean;
}

function formatE18(value: bigint): string {
  const num = Number(value) / 1e18;
  return num.toLocaleString(undefined, {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 2,
  });
}

function formatHealthFactor(value: bigint): string {
  if (value === 0n) return "--";
  // max uint256 means infinite (no debt)
  if (value >= BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")) return "∞";
  const num = Number(value) / 1e18;
  return num.toFixed(2);
}

function healthFactorColor(value: bigint): string {
  if (value === 0n) return "text-muted-foreground";
  const num = Number(value) / 1e18;
  if (num >= 1e18) return "text-green-600"; // infinity
  if (num > 1.5) return "text-green-600";
  if (num >= 1.0) return "text-yellow-500";
  return "text-red-600";
}

export function AccountSummary({ accountData, isLoading }: AccountSummaryProps) {
  const collateralValue = accountData?.collateralValueE18 ?? 0n;
  const debtValue = accountData?.debtValueE18 ?? 0n;
  const borrowPower = accountData?.borrowPowerE18 ?? 0n;
  const healthFactor = accountData?.healthFactorE18 ?? 0n;

  return (
    <div className="mb-8">
      <Card>
        <CardContent className="p-6">
          <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
            {/* Total Supplied */}
            <div className="flex flex-col items-center justify-center text-center">
              <div className="text-sm font-medium text-muted-foreground mb-2">
                Total Supplied
              </div>
              <div className="text-2xl font-bold">
                {isLoading ? "..." : formatE18(collateralValue)}
              </div>
            </div>

            {/* Total Borrowed */}
            <div className="flex flex-col items-center justify-center text-center">
              <div className="text-sm font-medium text-muted-foreground mb-2">
                Total Borrowed
              </div>
              <div className="text-2xl font-bold">
                {isLoading ? "..." : formatE18(debtValue)}
              </div>
            </div>

            {/* Borrow Power */}
            <div className="flex flex-col items-center justify-center text-center">
              <div className="text-sm font-medium text-muted-foreground mb-2">
                Borrow Power
              </div>
              <div className="text-2xl font-bold">
                {isLoading ? "..." : formatE18(borrowPower)}
              </div>
            </div>

            {/* Health Factor */}
            <div className="flex flex-col justify-center">
              <div className="space-y-3">
                <div className="flex justify-end items-center mr-4">
                  <div className="text-sm font-medium text-muted-foreground mr-4">
                    Health Factor:
                  </div>
                  <div
                    className={`text-2xl font-bold w-12 text-right ${healthFactorColor(healthFactor)}`}
                  >
                    {isLoading ? "..." : formatHealthFactor(healthFactor)}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
