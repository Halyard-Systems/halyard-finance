import { useState } from "react";
import { useAccount, useConnect, useDisconnect } from "wagmi";
import { injected } from "wagmi/connectors";
import { Button } from "./ui/button";
import halyardLogo from "../assets/halyard-finance-navbar-logo-cyan-gold.png";

const chainIcons: Record<number, { icon: string; name: string }> = {
  1: { icon: "/ethereum-eth-logo.svg", name: "Ethereum" },
  11155111: { icon: "/ethereum-eth-logo.svg", name: "Sepolia" },
  42161: { icon: "/arbitrum-arb-logo.svg", name: "Arbitrum" },
  56: { icon: "/binance-coin-bnb-logo.svg", name: "BNB Chain" },
  10: { icon: "/optimism-op-logo.svg", name: "Optimism" },
  8453: { icon: "/base-logo.svg", name: "Base" },
  137: { icon: "/polygon-matic-logo.svg", name: "Polygon" },
  31337: { icon: "/ethereum-eth-logo.svg", name: "Hardhat" },
};

export function Header() {
  const { address, isConnected, chainId } = useAccount();
  const { connect } = useConnect();
  const { disconnect } = useDisconnect();
  const [showChainTooltip, setShowChainTooltip] = useState(false);

  return (
    <header className="bg-card shadow-sm border-b border-border sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center h-16">
          {/* Logo/Title */}
          <img
            src={halyardLogo}
            alt="Halyard Finance Logo"
            className="h-10 w-auto"
          />
          {/* Wallet Connection */}
          <div className="flex items-center space-x-4">
            {!isConnected ? (
              <Button onClick={() => connect({ connector: injected() })}>
                Connect Wallet
              </Button>
            ) : (
              <div className="flex items-center space-x-8">
                <div className="text-sm text-muted-foreground flex items-center">
                  <span className="font-medium">Connected Chain:</span>
                  <span className="ml-2 flex items-center">
                    {chainId && chainIcons[chainId] ? (
                      <img
                        src={chainIcons[chainId].icon}
                        alt={chainIcons[chainId].name}
                        title={chainIcons[chainId].name}
                        className="w-5 h-5 cursor-pointer"
                      />
                    ) : (
                      <span
                        className="relative cursor-help"
                        onMouseEnter={() => setShowChainTooltip(true)}
                        onMouseLeave={() => setShowChainTooltip(false)}
                      >
                        ⚠️
                        {showChainTooltip && (
                          <span className="absolute top-full left-1/2 -translate-x-1/2 mt-2 px-3 py-2 bg-popover text-popover-foreground text-xs rounded-md shadow-lg border border-border whitespace-nowrap z-50">
                            Your wallet is connected to an unsupported network
                            {chainId ? ` (chain ID: ${chainId})` : ""}.
                            Please switch to a supported chain.
                          </span>
                        )}
                      </span>
                    )}
                  </span>
                </div>
                <div className="text-sm text-muted-foreground">
                  <span className="font-medium">Wallet Address:</span>
                  <span className="ml-1 font-mono text-xs">
                    {address?.slice(0, 6)}...{address?.slice(-4)}
                  </span>
                </div>
                <Button variant="secondary" onClick={() => disconnect()}>
                  Disconnect
                </Button>
              </div>
            )}
          </div>
        </div>
      </div>
    </header>
  );
}
