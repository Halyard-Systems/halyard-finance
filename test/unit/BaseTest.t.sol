// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "lib/forge-std/src/Test.sol";

import {BorrowManager} from "../../src/BorrowManager.sol";
import {DepositManager} from "../../src/DepositManager.sol";
import {AssetRegistry} from "../../src/hub/AssetRegistry.sol";
import {HubAccessManager} from "../../src/hub/HubAccessManager.sol";
import {HubController} from "../../src/hub/HubController.sol";
import {PositionBook} from "../../src/hub/PositionBook.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract BaseTest is Test {
    BorrowManager public borrowManager;
    DepositManager public depositManager;
    // MockERC20 public mockUSDC;
    // MockERC20 public mockUSDT;
    HubAccessManager public hubAccessManager;
    HubController public hubController;
    AssetRegistry public assetRegistry;
    PositionBook public positionBook;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public mockLzEndpoint = makeAddr("lzEndpoint");
    //address public mockPyth = address(0x456);

    // uint256 public constant RAY = 1e27;
    // uint256 public constant YEAR = 365 days;
    // uint256 public constant USDC_DECIMALS = 1e6;
    // uint256 public constant ETH_DECIMALS = 1e18;

    // Token IDs
    // bytes32 public constant ETH_TOKEN_ID = keccak256(abi.encodePacked("ETH"));
    // bytes32 public constant USDC_TOKEN_ID = keccak256(abi.encodePacked("USDC"));
    // bytes32 public constant USDT_TOKEN_ID = keccak256(abi.encodePacked("USDT"));

    function setUp() public virtual {
        console.log("BaseTest setUp");
        
        // Deploy HubAccessManager
        hubAccessManager = new HubAccessManager(address(this));
        console.log("HubAccessManager deployed at:", address(hubAccessManager));

        // Deploy mock tokens
        //mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        //mockUSDT = new MockERC20("Tether USD", "USDT", 6);

        // Deploy HubController
        // Put bytecode at mock addresses so calls don't fail with "non-contract address"
        vm.etch(mockLzEndpoint, hex"00");
        //vm.etch(mockPyth, hex"00");

        // Mock LZ endpoint setDelegate (called in OAppCore constructor)
        vm.mockCall(mockLzEndpoint, abi.encodeWithSignature("setDelegate(address)"), abi.encode());

        hubController = new HubController(address(this), mockLzEndpoint);
        console.log("HubController deployed at:", address(hubController));

        // Deploy AssetRegistry 
        assetRegistry = new AssetRegistry(address(hubAccessManager));
        //hubAccessManager.grantAccess(address(hubController), address(assetRegistry));

        assetRegistry.setCollateralConfig(1, address(0x123), AssetRegistry.CollateralConfig({
            isSupported: true,
            ltvBps: 8000,
            liqThresholdBps: 8500,
            liqBonusBps: 500,
            decimals: 18,
            supplyCap: 0
        }));

        assetRegistry.setCollateralConfig(2, address(0x124), AssetRegistry.CollateralConfig({
            isSupported: true,
            ltvBps: 8000,
            liqThresholdBps: 8500,
            liqBonusBps: 500,
            decimals: 18,
            supplyCap: 0
        }));

        assetRegistry.setDebtConfig(1, address(0x123), AssetRegistry.DebtConfig({
            isSupported: true,
            decimals: 18,
            borrowCap: 0
        }));

        assetRegistry.setDebtConfig(2, address(0x124), AssetRegistry.DebtConfig({
            isSupported: true,
            decimals: 18,
            borrowCap: 0
        }));

        assetRegistry.setBorrowRateApr(1, address(0x123), 1000);
        assetRegistry.setBorrowRateApr(2, address(0x124), 500);

        // Deploy PositionBook
        positionBook = new PositionBook(address(hubAccessManager));

        // Set permissions for the contracts
        hubAccessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.creditCollateral.selector),
            hubAccessManager.ROLE_HUB_CONTROLLER()
        );
        hubAccessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.reserveCollateral.selector),
            hubAccessManager.ROLE_RISK_ENGINE()
        );
        hubAccessManager.setTargetFunctionRole(
            address(assetRegistry),
            buildFunctionSelector(positionBook.unreserveCollateral.selector),
            hubAccessManager.ROLE_HUB_CONTROLLER()
        );
        hubAccessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.clearBorrowReservation.selector),
            hubAccessManager.ROLE_HUB_CONTROLLER()
        );
        hubAccessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.createPendingWithdraw.selector),
            hubAccessManager.ROLE_RISK_ENGINE()
        );
        hubAccessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.finalizePendingWithdraw.selector),
            hubAccessManager.ROLE_HUB_CONTROLLER()
        );
        hubAccessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.createPendingLiquidation.selector),
            hubAccessManager.ROLE_LIQUIDATION_ENGINE()
        );

        hubAccessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.finalizePendingLiquidation.selector),
            hubAccessManager.ROLE_HUB_CONTROLLER()
        );

        // Grant roles to the contracts
        hubAccessManager.grantRole(hubAccessManager.ROLE_HUB_CONTROLLER(), address(hubController), 0);
        hubAccessManager.grantRole(hubAccessManager.ROLE_ASSET_REGISTRY(), address(assetRegistry), 0);


        // Mock Stargate router address and pool ID for testing
        //uint256 mockPoolId = 1;
        //depositManager = new DepositManager(mockStargateRouter, mockPoolId, mockLzEndpoint, address(this));

        // Deploy BorrowManager
        //borrowManager = new BorrowManager(address(depositManager), mockPyth, 0.5e18);

        // Set up the test contract as the BorrowManager for testing
        //depositManager.setBorrowManager(address(borrowManager));

        // Initialize tokens with default interest rate parameters
        // depositManager.addToken(
        //     "ETH",
        //     address(0), // ETH is represented as address(0)
        //     18,
        //     0.01e27, // 1% base rate
        //     0.04e27, // 4% slope1
        //     0.08e27, // 8% slope2
        //     0.8e18, // 80% utilization kink
        //     0.1e27 // 10% reserve factor
        // );

        // depositManager.addToken(
        //     "USDC",
        //     address(mockUSDC), // Use mock USDC address
        //     6,
        //     0.02e27, // 2% base rate
        //     0.06e27, // 6% slope1
        //     0.12e27, // 12% slope2
        //     0.8e18, // 80% utilization kink
        //     0.1e27 // 10% reserve factor
        // );

        // depositManager.addToken(
        //     "USDT",
        //     address(mockUSDT), // Use mock USDT address
        //     6,
        //     0.015e27, // 1.5% base rate
        //     0.05e27, // 5% slope1
        //     0.1e27, // 10% slope2
        //     0.8e18, // 80% utilization kink
        //     0.1e27 // 10% reserve factor
        // );

        // // Mock the Stargate router addLiquidity call to always succeed
        // vm.mockCall(mockStargateRouter, abi.encodeWithSelector(IStargateRouter.addLiquidity.selector), abi.encode());

        // // Mock Pyth oracle calls
        // // Mock getUpdateFee to return 0 (no fee for empty data)
        // vm.mockCall(mockPyth, abi.encodeWithSignature("getUpdateFee(bytes[])", new bytes[](0)), abi.encode(uint256(0)));

        // // Mock updatePriceFeeds to succeed
        // vm.mockCall(mockPyth, abi.encodeWithSignature("updatePriceFeeds(bytes[])"), abi.encode());

        // Mock getPriceNoOlderThan for each price ID to return a valid PythStructs.Price
        // Return the struct fields directly as abi.encode does

        // ETH price: $1000
        // bytes memory mockEthPriceData = abi.encode(
        //     int64(100000000000), // $1000 * 1e8 (Pyth uses 8 decimals)
        //     uint64(0), // confidence
        //     int32(-8), // exponent
        //     uint256(block.timestamp) // publish time
        // );

        // // USDC price: $1
        // bytes memory mockUsdcPriceData = abi.encode(
        //     int64(100000000), // $1 * 1e8 (Pyth uses 8 decimals)
        //     uint64(0), // confidence
        //     int32(-8), // exponent
        //     uint256(block.timestamp) // publish time
        // );

        // // USDT price: $1
        // bytes memory mockUsdtPriceData = abi.encode(
        //     int64(100000000), // $1 * 1e8 (Pyth uses 8 decimals)
        //     uint64(0), // confidence
        //     int32(-8), // exponent
        //     uint256(block.timestamp) // publish time
        // );

        // Map price IDs to their respective price data
        // Assuming price ID 1 = ETH, 2 = USDC, 3 = USDT
        // Mock getPriceNoOlderThan for each price ID - the second parameter is the max age in seconds
        // BorrowManager calls with 60 * 5 = 300 seconds
        // vm.mockCall(
        //     mockPyth,
        //     abi.encodeWithSignature("getPriceNoOlderThan(bytes32,uint256)", bytes32(uint256(1)), uint256(300)),
        //     mockEthPriceData
        // );
        // vm.mockCall(
        //     mockPyth,
        //     abi.encodeWithSignature("getPriceNoOlderThan(bytes32,uint256)", bytes32(uint256(2)), uint256(300)),
        //     mockUsdcPriceData
        // );
        // vm.mockCall(
        //     mockPyth,
        //     abi.encodeWithSignature("getPriceNoOlderThan(bytes32,uint256)", bytes32(uint256(3)), uint256(300)),
        //     mockUsdtPriceData
        // );

        // Give users some tokens
        // mockUSDC.mint(alice, 10000 * USDC_DECIMALS);
        // mockUSDC.mint(bob, 10000 * USDC_DECIMALS);
        // mockUSDC.mint(charlie, 10000 * USDC_DECIMALS);

        // mockUSDT.mint(alice, 10000 * USDC_DECIMALS);
        // mockUSDT.mint(bob, 10000 * USDC_DECIMALS);
        // mockUSDT.mint(charlie, 10000 * USDC_DECIMALS);

        // // Give users some ETH
        // vm.deal(alice, 100 ether);
        // vm.deal(bob, 100 ether);
        // vm.deal(charlie, 100 ether);

        // Approve DepositManager to spend tokens
        // vm.prank(alice);
        // mockUSDC.approve(address(depositManager), type(uint256).max);
        // vm.prank(bob);
        // mockUSDC.approve(address(depositManager), type(uint256).max);
        // vm.prank(charlie);
        // mockUSDC.approve(address(depositManager), type(uint256).max);

        // vm.prank(alice);
        // mockUSDT.approve(address(depositManager), type(uint256).max);
        // vm.prank(bob);
        // mockUSDT.approve(address(depositManager), type(uint256).max);
        // vm.prank(charlie);
        // mockUSDT.approve(address(depositManager), type(uint256).max);
    }

    function buildFunctionSelector(bytes4 selector) internal pure returns (bytes4[] memory) {
        bytes4[] memory addfuncs = new bytes4[](1);
        addfuncs[0] = selector;
        return addfuncs;
    }
}
