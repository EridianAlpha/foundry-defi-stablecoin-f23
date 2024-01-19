// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DSC} from "./DSC.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 *  @title DSCEngine
 *  @author EridianAlpha
 *
 *  The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 *  This is a stablecoin with the properties:
 *  - Exogenously Collateralized
 *  - Dollar Pegged
 *  - Algorithmically Stable
 *
 *  It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 *  The DSC system should always be "over-collateralized" and at no point should the value of all
 *  collateral be less than the value of all DSC.
 *
 *  @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 *  for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 *  @notice This contract is loosely based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    // ================================================================
    // │                            ERRORS                            │
    // ================================================================
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAndPriceFeedAddressesDiffLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__CollateralDepositFailed();
    error DSCEngine__HealthFactorIsBelowMinimum(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__CollateralRedeemFailed();
    error DSCEngine__BurnDscTransferFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    // ================================================================
    // │                        STATE VARIABLES                       │
    // ================================================================
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% collateralization
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidators

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DSC private immutable i_dsc;

    // ================================================================
    // │                            EVENTS                            │
    // ================================================================
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    // ================================================================
    // │                           MODIFIERS                          │
    // ================================================================
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) revert DSCEngine__NeedsMoreThanZero();
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) revert DSCEngine__TokenNotAllowed();
        _;
    }

    // ================================================================
    // │                           FUNCTIONS                          │
    // ================================================================
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // Check array lengths are equal
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAndPriceFeedAddressesDiffLength();
        }

        // Set price feeds
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        // Set DSC contract address
        i_dsc = DSC(dscAddress);
    }

    // ================================================================
    // │                     FUNCTIONS - EXTERNAL                     │
    // ================================================================
    /**
     * @notice Follows CEI pattern
     *  @param tokenCollateralAddress The address of the ERC20 token to be used as collateral
     *  @param amountCollateral The amount of collateral to be deposited
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert DSCEngine__CollateralDepositFailed();
    }

    /**
     * @notice Follows CEI pattern
     *  @param amountDscToMint The amount of DSC to mint
     *  @notice They must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) revert DSCEngine__MintFailed();
    }

    /**
     * @notice This function will deposit collateral and mint DSC in one transaction
     *  @param tokenCollateralAddress The address of the ERC20 token to be used as collateral
     *  @param amountCollateral The amount of collateral to be deposited
     *  @param amountDscToMint The amount of DSC to mint
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice The health factor must be over 1 after collateral has been redeemed
     *  @param tokenCollateralAddress The address of the ERC20 token to be used as collateral
     *  @param amountCollateral The amount of collateral to be redeemed
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *  @notice This function will redeem collateral and burn DSC in one transaction
     *  @param tokenCollateralAddress The address of the ERC20 token to be used as collateral
     *  @param amountCollateral The amount of collateral to be redeemed
     *  @param amountDscToBurn The amount of DSC to burn
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        public
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral); // Checks health factor
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(msg.sender, msg.sender, amount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *  @notice This function will redeem collateral and burn DSC in one transaction
     *  @notice You can partially liquidate a user
     *  @notice You will get a liquidation bonus if you liquidate a user
     *  @notice This function working assumes the protocol will be overcollateralized
     *  @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivize the liquidators
     *
     *  @param collateral The address of the ERC20 token to liquidate
     *  @param user The address of the user to liquidate who has an unsafe health factor
     *  @param debtToCover The amount of DSC to burn to improve the health factor
     *
     *  Follows CEI: Checks, Effects, Interactions
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        public
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorOk();

        // We want to burn their DSC "debt" and take their collateral
        // If Bad User has $140 ETH, $100 DSC
        // deptToCover = $40
        // $100 of DSC = ?? ETH

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        // and give the liquidator a 10% bonus
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);

        // Burn the DSC debt
        _burnDsc(user, msg.sender, debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor >= startingUserHealthFactor) revert DSCEngine__HealthFactorNotImproved();

        // This stops the liquidator causing their own health factor to become unsafe through during the
        // liquidation of this other user. It's not strictly necessary, but a UX improvement.
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() public view {}

    // ================================================================
    // │               FUNCTIONS - PRIVATE AND INTERNAL VIEW          │
    // ================================================================
    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        // Solidity will catch this revert if the user doesn't have enough collateral
        // as in newer versions it doesn't allow unsafe math
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) revert DSCEngine__CollateralRedeemFailed();
    }

    /**
     * @dev Low-level private function, do not call unless the function calling it is checking for health factors being broken
     * @param onBehalfOf //TODO
     * @param dscFrom //TODO
     * @param amountDscToBurn //TODO
     */
    function _burnDsc(address onBehalfOf, address dscFrom, uint256 amountDscToBurn) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) revert DSCEngine__BurnDscTransferFailed();
        i_dsc.burn(amountDscToBurn);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /* 
    * Returns how close to liquidation a user is.
    * If the health factor is 1, then the user is at the liquidation threshold.
    * //TODO: Find the bug
    */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_THRESHOLD;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorIsBelowMinimum(userHealthFactor);
    }

    // ================================================================
    // │               FUNCTIONS - PUBLIC AND EXTERNAL VIEW           │
    // ================================================================
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }
}
