import { useState } from "react";
import type { SpokeAsset, SpokeConfig } from "../lib/contracts";

export interface AssetPickerProps {
  selectedSpoke: SpokeConfig;
  selectedAsset: SpokeAsset;
  onAssetSelect: (asset: SpokeAsset) => void;
}

export function AssetPicker({
  selectedSpoke,
  selectedAsset,
  onAssetSelect,
}: AssetPickerProps) {
  const [isAssetDropdownOpen, setIsAssetDropdownOpen] = useState(false);

  return (
    <div className="w-full min-w-0">
      <label className="block text-sm font-medium text-card-foreground mb-2">
        Asset
      </label>
      <div className="relative" data-asset-dropdown>
        <button
          type="button"
          onClick={() => setIsAssetDropdownOpen(!isAssetDropdownOpen)}
          className="w-full px-3 py-2 border border-input rounded-md focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring bg-background text-foreground text-left flex items-center justify-between"
        >
          <div className="flex items-center space-x-2">
            <img
              src={selectedAsset.icon}
              alt={`${selectedAsset.symbol} icon`}
              className="w-4 h-4"
            />
            <span>{selectedAsset.symbol}</span>
          </div>
          <svg
            className={`w-4 h-4 transition-transform ${
              isAssetDropdownOpen ? "rotate-180" : ""
            }`}
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M19 9l-7 7-7-7"
            />
          </svg>
        </button>

        {isAssetDropdownOpen && (
          <div className="absolute z-10 w-full mt-1 bg-background border border-input rounded-md shadow-lg max-h-60 overflow-y-auto">
            {selectedSpoke.assets.map((asset) => (
              <button
                key={asset.symbol}
                type="button"
                onClick={() => {
                  onAssetSelect(asset);
                  setIsAssetDropdownOpen(false);
                }}
                className="w-full px-3 py-2 text-left hover:bg-muted flex items-center space-x-2"
              >
                <img
                  src={asset.icon}
                  alt={`${asset.symbol} icon`}
                  className="w-4 h-4"
                />
                <span>{asset.symbol}</span>
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
