import type { SpokeConfig } from "../lib/contracts";

interface ChainPickerProps {
  spokes: SpokeConfig[];
  selectedSpoke: SpokeConfig;
  onChainSelect?: (spoke: SpokeConfig) => void;
}

export function ChainPicker({
  spokes,
  selectedSpoke,
  onChainSelect,
}: ChainPickerProps) {
  return (
    <>
      <label className="block text-sm font-medium text-card-foreground mb-2">
        Chain
      </label>
      <div className="flex items-center gap-4">
        {spokes.map((spoke) => (
          <div
            key={spoke.lzEid}
            onClick={() => onChainSelect?.(spoke)}
            className={`flex items-center gap-2 p-2 rounded-md cursor-pointer transition-colors ${
              selectedSpoke?.lzEid === spoke.lzEid
                ? "border-2 border-primary bg-muted"
                : "border-2 border-transparent hover:border-muted"
            }`}
            title={spoke.name}
          >
            <img src={spoke.logo} alt={spoke.name} className="w-6 h-6" />
          </div>
        ))}
      </div>
    </>
  );
}
