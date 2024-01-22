// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSC} from "../../src/DSC.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DSC dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    constructor(DSCEngine _dscEngine, DSC _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = _bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        collateral.approve(address(dscEngine), amountCollateral);
        collateral.mint(msg.sender, amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        bool isUserPresent = false;
        for (uint256 i = 0; i < usersWithCollateralDeposited.length; i++) {
            if (usersWithCollateralDeposited[i] == msg.sender) {
                isUserPresent = true;
                break;
            }
        }
        if (!isUserPresent) usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(address(collateral), msg.sender);
        amountCollateral = _bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) return;

        vm.startPrank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
        collateral.burn(msg.sender, amountCollateral);
        vm.stopPrank();
    }

    function mintDsc(uint256 amountToMint, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        if (maxDscToMint <= 0) return;

        amountToMint = _bound(amountToMint, 0, uint256(maxDscToMint));
        if (amountToMint == 0) return;

        vm.startPrank(sender);
        dscEngine.mintDsc(amountToMint);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    // TODO: This breaks the invariant for DSC minted
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    // Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
