import { useState, useMemo } from "react";
import { parseUnits } from "viem";
import { Card, CardContent, CardHeader, CardTitle } from "./ui/card";
import { Button } from "./ui/button";
import { ChainPicker } from "./ChainPicker";
import { AssetPicker } from "./AssetPicker";
import { spokeConfigs, type SpokeConfig, type SpokeAsset } from "../lib/contracts";
import {
  useUserSlots,
  useAccountData,
  useCollateralPositions,
  useDebtPositions,
  useQuoteHubCommand,
} from "../lib/hooks";
import { useTransactionFlow } from "../lib/writeHooks";
import { buildLzOptions, GAS_LIMITS, applyFeeBuffer } from "../lib/layerzero";

export function Liquidation() {
  const [targetAddress, setTargetAddress] = useState("");
  const [isLookingUp, setIsLookingUp] = useState(false);
  const [lookupAddress, setLookupAddress] = useState<`0x${string}` | undefined>();
  const [repayAmount, setRepayAmount] = useState("");

  // Debt selection
  const [debtSpoke, setDebtSpoke] = useState<SpokeConfig>(spokeConfigs[0]);
  const [debtAsset, setDebtAsset] = useState<SpokeAsset>(spokeConfigs[0]?.assets[0]);

  // Collateral (seize) selection
  const [seizeSpoke, setSeizeSpoke] = useState<SpokeConfig>(spokeConfigs[0]);
  const [seizeAsset, setSeizeAsset] = useState<SpokeAsset>(spokeConfigs[0]?.assets[0]);

  const txFlow = useTransactionFlow();

  // Lookup target user's slots and positions
  const { collateralSlots, debtSlots } = useUserSlots(lookupAddress);
  const { accountData } = useAccountData(lookupAddress, collateralSlots, debtSlots);
  const { positions: collateralPositions } = useCollateralPositions(lookupAddress, collateralSlots);
  const { positions: debtPositions } = useDebtPositions(lookupAddress, debtSlots);

  const isLiquidatable = useMemo(() => {
    if (!accountData) return false;
    // Health factor < 1e18 means liquidatable
    return accountData.healthFactorE18 < BigInt("1000000000000000000");
  }, [accountData]);

  const healthFactor = accountData
    ? (Number(accountData.healthFactorE18) / 1e18).toFixed(4)
    : "--";

  const handleLookup = () => {
    if (targetAddress.startsWith("0x") && targetAddress.length === 42) {
      setLookupAddress(targetAddress as `0x${string}`);
      setIsLookingUp(true);
    }
  };

  // Dynamic fee quoting for liquidation
  const liquidationOptions = useMemo(() => buildLzOptions(GAS_LIMITS.liquidation), []);
  const liqQuote = useQuoteHubCommand(seizeSpoke?.lzEid, liquidationOptions);
  const liqFee = useMemo(
    () => (liqQuote.fee ? applyFeeBuffer(liqQuote.fee) : undefined),
    [liqQuote.fee]
  );

  const handleLiquidate = async () => {
    if (!lookupAddress || !debtAsset || !seizeAsset || !repayAmount || !liqFee) return;

    const parsedRepay = parseUnits(repayAmount, debtAsset.decimals);

    await txFlow.liquidate(
      lookupAddress,
      debtSpoke.lzEid,
      debtAsset.canonicalAddress,
      parsedRepay,
      seizeSpoke.lzEid,
      seizeAsset.canonicalAddress,
      collateralSlots,
      debtSlots,
      liqFee
    );
  };

  return (
    <div className="mb-8">
      <Card>
        <CardHeader>
          <CardTitle>Liquidation</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {/* Address Input */}
          <div className="flex gap-2">
            <input
              type="text"
              value={targetAddress}
              onChange={(e) => setTargetAddress(e.target.value)}
              placeholder="Enter user address (0x...)"
              className="flex-1 px-3 py-2 border border-input rounded-md bg-background text-foreground"
            />
            <Button onClick={handleLookup} variant="outline">
              Lookup
            </Button>
          </div>

          {/* User Position Display */}
          {isLookingUp && lookupAddress && (
            <div className="space-y-4">
              {/* Health Factor */}
              <div className="flex items-center gap-4">
                <span className="text-sm text-muted-foreground">Health Factor:</span>
                <span
                  className={`text-lg font-bold ${
                    isLiquidatable ? "text-red-600" : "text-green-600"
                  }`}
                >
                  {healthFactor}
                </span>
                {isLiquidatable && (
                  <span className="text-xs bg-red-100 text-red-700 px-2 py-1 rounded">
                    LIQUIDATABLE
                  </span>
                )}
              </div>

              {/* Collateral Positions */}
              {collateralPositions.length > 0 && (
                <div>
                  <div className="text-sm font-medium mb-2">Collateral</div>
                  <div className="text-xs space-y-1">
                    {collateralPositions.map((pos) => (
                      <div key={`${pos.eid}-${pos.asset}`} className="flex justify-between">
                        <span className="font-mono">
                          EID {pos.eid}: {pos.asset.slice(0, 10)}...
                        </span>
                        <span>{(Number(pos.balance) / 1e18).toFixed(4)}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Debt Positions */}
              {debtPositions.length > 0 && (
                <div>
                  <div className="text-sm font-medium mb-2">Debt</div>
                  <div className="text-xs space-y-1">
                    {debtPositions.map((pos) => (
                      <div key={`${pos.eid}-${pos.asset}`} className="flex justify-between">
                        <span className="font-mono">
                          EID {pos.eid}: {pos.asset.slice(0, 10)}...
                        </span>
                        <span className="text-red-600">
                          {(Number(pos.debt) / 1e18).toFixed(4)}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Liquidation Form */}
              {isLiquidatable && (
                <div className="border-t pt-4 space-y-3">
                  <div className="text-sm font-medium">Execute Liquidation</div>

                  {/* Debt to repay */}
                  <div>
                    <label className="text-xs text-muted-foreground">Debt to Repay</label>
                    {spokeConfigs.length > 0 && (
                      <ChainPicker
                        spokes={spokeConfigs}
                        selectedSpoke={debtSpoke}
                        onChainSelect={(s) => {
                          setDebtSpoke(s);
                          setDebtAsset(s.assets[0]);
                        }}
                      />
                    )}
                    {debtSpoke && debtAsset && (
                      <AssetPicker
                        selectedSpoke={debtSpoke}
                        selectedAsset={debtAsset}
                        onAssetSelect={setDebtAsset}
                      />
                    )}
                    <input
                      type="number"
                      value={repayAmount}
                      onChange={(e) => setRepayAmount(e.target.value)}
                      placeholder="Amount to repay"
                      className="w-full mt-2 px-3 py-2 border border-input rounded-md bg-background text-foreground text-sm"
                    />
                  </div>

                  {/* Collateral to seize */}
                  <div>
                    <label className="text-xs text-muted-foreground">Collateral to Seize</label>
                    {spokeConfigs.length > 0 && (
                      <ChainPicker
                        spokes={spokeConfigs}
                        selectedSpoke={seizeSpoke}
                        onChainSelect={(s) => {
                          setSeizeSpoke(s);
                          setSeizeAsset(s.assets[0]);
                        }}
                      />
                    )}
                    {seizeSpoke && seizeAsset && (
                      <AssetPicker
                        selectedSpoke={seizeSpoke}
                        selectedAsset={seizeAsset}
                        onAssetSelect={setSeizeAsset}
                      />
                    )}
                  </div>

                  {/* Fee estimate */}
                  <div className="text-xs text-muted-foreground">
                    {liqQuote.isLoading ? (
                      <span className="animate-pulse">Quoting cross-chain fee...</span>
                    ) : liqQuote.isError ? (
                      <span className="text-red-500">Unable to quote fee</span>
                    ) : liqFee ? (
                      <>Estimated fee: ~{(Number(liqFee.nativeFee) / 1e18).toFixed(4)} ETH</>
                    ) : null}
                  </div>

                  {/* Error */}
                  {txFlow.error && (
                    <div className="text-sm text-red-500">{txFlow.error}</div>
                  )}

                  <Button
                    onClick={handleLiquidate}
                    variant="destructive"
                    disabled={!repayAmount || txFlow.status !== "idle" || liqQuote.isLoading || !liqFee}
                  >
                    {txFlow.status === "idle"
                      ? "Execute Liquidation"
                      : txFlow.status}
                  </Button>
                </div>
              )}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
