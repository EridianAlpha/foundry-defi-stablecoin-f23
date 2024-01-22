// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {DSC} from "../../src/DSC.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {CollateralDepositFailedHelper} from "../testHelperContracts/CollateralDepositFailedHelper.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is StdCheats, Test {
    DeployDSC deployer;
    DSC dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    // ================================================================
    // │                       CONSTRUCTOR TESTS                      │
    // ================================================================
    function test_RevertsIfTokenLengthDoesNotMatchPriceFeedLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAndPriceFeedAddressesDiffLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function test_GetPriceFeedForToken() public {
        assertEq(dscEngine.getPriceFeedForToken(weth), ethUsdPriceFeed);
    }

    function test_GetDscAddress() public {
        assertEq(dscEngine.getDscAddress(), address(dsc));
    }

    // ================================================================
    // │                        PRICE FEED TESTS                      │
    // ================================================================
    function test_GetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 2_000/ETH = 30_000e18
        uint256 expectedUsdValue = 30000e18;
        uint256 actualUsdValue = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(actualUsdValue, expectedUsdValue);
    }

    function test_GetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    // ================================================================
    // │                     DEPOSIT COLLATERAL TEST                  │
    // ================================================================
    function test_RevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_RevertIfCollateralTransferNotApproved() public {
        vm.startPrank(USER);
        vm.expectRevert("ERC20: insufficient allowance");
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_CollateralNotErc20Standard() public {
        // This test requires a helper contract that reverts on transferFrom with false
        CollateralDepositFailedHelper collateralDepositFailedHelper = new CollateralDepositFailedHelper();
        address invalidTokenAddress = address(collateralDepositFailedHelper);

        tokenAddresses.push(invalidTokenAddress);
        priceFeedAddresses.push(ethUsdPriceFeed);
        DSCEngine brokenDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__CollateralDepositFailed.selector);
        brokenDscEngine.depositCollateral(invalidTokenAddress, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_RevertWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock("Random", "Random", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
    }

    function test_CanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    // ================================================================
    // │                          MINT DSC TEST                       │
    // ================================================================
    function test_CanMintDsc() public depositedCollateral {
        vm.startPrank(USER);
        uint256 usdAmount = 10;
        dscEngine.mintDsc(usdAmount);
        assertEq(dsc.balanceOf(USER), usdAmount);
        vm.stopPrank();
    }

    function test_MintFailsIfHealthFactorIsBroken() public depositedCollateral {
        // Try to mint double the amount of DSC that would break the health factor
        uint256 healthFactorBreakingMultiplier = 2;
        uint256 usdAmount = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL) * healthFactorBreakingMultiplier;
        bytes memory encodedRevert = abi.encodeWithSelector(
            DSCEngine.DSCEngine__HealthFactorIsBelowMinimum.selector,
            dscEngine.getMinHealthFactor() / (healthFactorBreakingMultiplier * 2)
        );

        vm.startPrank(USER);
        vm.expectRevert(encodedRevert);
        dscEngine.mintDsc(usdAmount);
        vm.stopPrank();
    }

    function test_DepositCollateralAndMintDsc() public {
        uint256 usdAmount = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, usdAmount / 2);
        assertEq(dsc.balanceOf(USER), usdAmount / 2);
        vm.stopPrank();
    }
}
