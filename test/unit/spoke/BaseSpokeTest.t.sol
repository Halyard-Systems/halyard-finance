// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "lib/forge-std/src/Test.sol";

import {SpokeController} from "../../../src/spoke/SpokeController.sol";
import {CollateralVault} from "../../../src/spoke/CollateralVault.sol";
import {LiquidityVault} from "../../../src/spoke/LiquidityVault.sol";
import {MockERC20} from "../../../src/mocks/MockERC20.sol";

contract BaseSpokeTest is Test {
    SpokeController public spokeController;
    CollateralVault public collateralVault;
    LiquidityVault public liquidityVault;
    MockERC20 public mockToken;

    // Canonical address for the token (used in hub mappings)
    address public canonicalToken = address(0x1);

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public mockLzEndpoint = makeAddr("lzEndpoint");

    function setUp() public virtual {
        // Put bytecode at mock address so calls don't fail with "non-contract address"
        vm.etch(mockLzEndpoint, hex"00");
        vm.mockCall(mockLzEndpoint, abi.encodeWithSignature("setDelegate(address)"), abi.encode());

        // Deploy mock token
        mockToken = new MockERC20("Mock Token", "MTK", 18);

        spokeController = new SpokeController(address(this), mockLzEndpoint);
        collateralVault = new CollateralVault(address(this), address(spokeController));
        liquidityVault = new LiquidityVault(address(this), address(spokeController));

        spokeController.configureHub(1, bytes32("test"));
        spokeController.configureSpokeEid(1);
        // Set the OApp peer for the hub EID (required for _lzSend)
        spokeController.setPeer(1, bytes32("test"));
        spokeController.setCollateralVault(address(collateralVault));
        spokeController.setLiquidityVault(address(liquidityVault));
        // Map canonical token address to the spoke token (mockToken)
        spokeController.setTokenMapping(canonicalToken, address(mockToken));

        // Mint tokens to spokeController and approve collateralVault
        // (depositAndNotify calls vault.deposit, where msg.sender is spokeController)
        mockToken.mint(address(spokeController), 1_000_000e18);
        vm.prank(address(spokeController));
        mockToken.approve(address(collateralVault), type(uint256).max);

        mockToken.mint(alice, 1_000_000e18);
        vm.prank(alice);
        mockToken.approve(address(collateralVault), type(uint256).max);
        vm.prank(alice);
        mockToken.approve(address(liquidityVault), type(uint256).max);

        vm.mockCall(
            mockLzEndpoint,
            abi.encodeWithSelector(bytes4(keccak256("send((uint32,bytes32,bytes,bytes,bool),address)"))),
            abi.encode(bytes32(0), uint64(0), uint256(0), uint256(0))
        );
    }
}
