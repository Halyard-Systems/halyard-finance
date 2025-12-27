import type { MockChainData } from "@/sample-data";

interface ChainPickerProps {
  portfolioData: MockChainData[];
  selectedChain: MockChainData;
  onChainSelect?: (chain: MockChainData) => void;
}

export function ChainPicker({
  portfolioData,
  selectedChain,
  onChainSelect,
}: ChainPickerProps) {
  const handleChainClick = (chain: MockChainData) => {
    onChainSelect?.(chain);
  };

  return (
    <>
      <label className="block text-sm font-medium text-card-foreground mb-2">
        Chain
      </label>
      <div className="flex items-center gap-4">
        {portfolioData.map((chain) => (
          <div
            key={chain.name}
            onClick={() => handleChainClick(chain)}
            className={`flex items-center gap-2 p-2 rounded-md cursor-pointer transition-colors ${
              selectedChain?.name === chain.name
                ? "border-2 border-primary bg-muted"
                : "border-2 border-transparent hover:border-muted"
            }`}
            title={chain.name}
          >
            <img src={chain.logo} alt={chain.name} className="w-6 h-6" />
          </div>
        ))}
      </div>
    </>
  );
}
