// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "lib/forge-std/src/Test.sol";

import {AssetRegistry} from "../../../src/hub/AssetRegistry.sol";
import {DebtManager} from "../../../src/hub/DebtManager.sol";
import {HubAccessManager} from "../../../src/hub/HubAccessManager.sol";
import {HubController} from "../../../src/hub/HubController.sol";
import {LiquidationEngine} from "../../../src/hub/LiquidationEngine.sol";
import {PositionBook} from "../../../src/hub/PositionBook.sol";
import {RiskEngine} from "../../../src/hub/RiskEngine.sol";
import {MockERC20} from "../../../src/mocks/MockERC20.sol";

contract BaseTest is Test {
    // MockERC20 public mockUSDC;
    // MockERC20 public mockUSDT;
    HubAccessManager public hubAccessManager;
    HubController public hubController;
    AssetRegistry public assetRegistry;
    PositionBook public positionBook;
    RiskEngine public riskEngine;
    LiquidationEngine public liquidationEngine;
    DebtManager public debtManager;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public mockLzEndpoint = makeAddr("lzEndpoint");

    address public tempDebtManager = makeAddr("debtManager");
    address public mockOracle = makeAddr("oracle");

    // TODO: replace with a router implementation
    address public router = address(this);
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

        assetRegistry.setCollateralConfig(
            1,
            address(0x123),
            AssetRegistry.CollateralConfig({
                isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
            })
        );

        assetRegistry.setCollateralConfig(
            2,
            address(0x124),
            AssetRegistry.CollateralConfig({
                isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
            })
        );

        assetRegistry.setDebtConfig(
            1, address(0x123), AssetRegistry.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0})
        );

        assetRegistry.setDebtConfig(
            2, address(0x124), AssetRegistry.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0})
        );

        assetRegistry.setBorrowRateApr(1, address(0x123), 1000);
        assetRegistry.setBorrowRateApr(2, address(0x124), 500);

        // Deploy PositionBook
        positionBook = new PositionBook(address(hubAccessManager));

        // Deploy RiskEngine
        riskEngine = new RiskEngine(address(hubAccessManager));
        riskEngine.setDependencies(
            address(positionBook),
            address(tempDebtManager), // or mock address if DebtManager not deployed
            address(assetRegistry),
            mockOracle
        );

        liquidationEngine = new LiquidationEngine(address(hubAccessManager));
        liquidationEngine.setCollateralConfig(
            1,
            address(0x123),
            LiquidationEngine.CollateralConfig({
                isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
            })
        );
        liquidationEngine.setCollateralConfig(
            2,
            address(0x124),
            LiquidationEngine.CollateralConfig({
                isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
            })
        );
        liquidationEngine.setDebtConfig(
            address(0x123), LiquidationEngine.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0})
        );
        liquidationEngine.setDebtConfig(
            address(0x124), LiquidationEngine.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0})
        );

        debtManager = new DebtManager(address(hubAccessManager), address(assetRegistry));
        debtManager.setAssetRegistry(address(assetRegistry));
        // debtManager.setBorrowRatePerSecondRay(address(0x123), 1000);
        // debtManager.setBorrowRatePerSecondRay(address(0x124), 500);

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
        // TODO: should be router? verify that router calls validateAndCreateBorrow and createPendingBorrow
        hubAccessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.createPendingBorrow.selector),
            //hubAccessManager.ROLE_ROUTER()
            hubAccessManager.ROLE_RISK_ENGINE()
            //hubAccessManager.ROLE_HUB_CONTROLLER()
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

        hubAccessManager.setTargetFunctionRole(
            address(riskEngine),
            buildFunctionSelector(riskEngine.validateAndCreateBorrow.selector),
            hubAccessManager.ROLE_ROUTER()
        );

        hubAccessManager.setTargetFunctionRole(
            address(riskEngine),
            buildFunctionSelector(riskEngine.validateAndCreateWithdraw.selector),
            hubAccessManager.ROLE_ROUTER()
        );

        // Grant roles to the contracts
        hubAccessManager.grantRole(hubAccessManager.ROLE_HUB_CONTROLLER(), address(hubController), 0);
        hubAccessManager.grantRole(hubAccessManager.ROLE_ASSET_REGISTRY(), address(assetRegistry), 0);
        hubAccessManager.grantRole(hubAccessManager.ROLE_RISK_ENGINE(), address(riskEngine), 0);
        // TODO: implement router solution
        hubAccessManager.grantRole(hubAccessManager.ROLE_ROUTER(), router, 0);
    }

    function buildFunctionSelector(bytes4 selector) internal pure returns (bytes4[] memory) {
        bytes4[] memory addfuncs = new bytes4[](1);
        addfuncs[0] = selector;
        return addfuncs;
    }
}
