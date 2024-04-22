// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import { Constants } from "../../global/Constants.sol";
import { Deployments } from "@deployments/Deployments.sol";
import { 
    BaseStakingVault,
    WithdrawRequest,
    RedeemParams
} from "./BaseStakingVault.sol";
import {
    ITradingModule,
    Trade,
    TradeType
} from "@interfaces/trading/ITradingModule.sol";

struct DepositParams {
    uint16 dexId;
    uint256 minPurchaseAmount;
    uint32 deadline;
    bytes exchangeData;
    uint256 minPtOut;
    IPRouter.ApproxParams approxParams;
}

contract PendlePrincipalTokenVault is BaseStakingVault {
    IPOracle immutable ORACLE = IPOracle(0x66a1096C6366b2529274dF4f5D8247827fe4CEA8);
    IPRouter immutable ROUTER = IPRouter(0x00000000005BBB0EF59571E58418F9a4357b68A0);
    // // TODO: can use this to get estimations for trading amounts and bypass their SDK
    // IPStaticRouter immutable STATIC_ROUTER = IPStaticRouter(0x263833d47eA3fA4a30f269323aba6a107f9eB14C);
    address immutable TOKEN_IN_SY;
    address immutable TOKEN_OUT_SY;
    IStandardizedYield immutable SY;
    IPPrincipalToken immutable PT;
    IPYieldToken immutable YT;
    uint256 PT_PRECISION;
    IPMarket immutable MARKET;
    uint32 immutable TWAP_DURATION;
    bool immutable USE_SY_ORACLE_RATE;

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("Staking:PendlePT:PROTOCOL_NAME"));
    }

    constructor(
        address market,
        address tokenInSY,
        address tokenOutSY,
        address borrowToken,
        uint32 twapDuration,
        bool useSyOracleRate
    ) BaseStakingVault(
        Deployments.NOTIONAL,
        Deployments.TRADING_MODULE,
        address(PT),
        borrowToken
    ) {
        MARKET = IPMarket(market);
        (address sy, address pt, address yt) = MARKET.readTokens();
        SY = IStandardizedYield(sy);
        PT = IPPrincipalToken(pt);
        YT = IPYieldToken(yt);
        require(SY.isValidTokenIn(tokenInSY));
        // This may not be the same as valid token in, for LRT you can
        // put ETH in but you would only get weETH or eETH out
        require(SY.isValidTokenOut(tokenOutSY));

        TOKEN_IN_SY = tokenInSY;
        TOKEN_OUT_SY = tokenOutSY;

        // PT decimals vary with the underlying SY precision
        PT_PRECISION = 10 ** PT.decimals();

        TWAP_DURATION = twapDuration;
        USE_SY_ORACLE_RATE = useSyOracleRate;
        (
            bool increaseCardinalityRequired,
            /* */,
            bool oldestObservationSatisfied
        ) = ORACLE.getOracleState(market, twapDuration);
        require(!increaseCardinalityRequired && oldestObservationSatisfied, "Oracle Init");
    }

    function getExchangeRate(uint256 maturity) public view override returns (int256) {
        uint256 ptRate = USE_SY_ORACLE_RATE ? 
            ORACLE.getPtToSyRate(address(MARKET), TWAP_DURATION) :
            ORACLE.getPtToAssetRate(address(MARKET), TWAP_DURATION);

        // TODO: may need to also get the rate from the sy or asset token
        // back to the borrowed currency....
        int256 stakeAssetPrice = super.getExchangeRate(maturity);

        // TODO: add safeint here...
        return int256(ptRate) * stakeAssetPrice / int256(EXCHANGE_RATE_PRECISION);
    }

    function _stakeTokens(
        address /* account */,
        uint256 depositUnderlyingExternal,
        uint256 /* maturity */,
        bytes calldata data
    ) internal override returns (uint256 vaultShares) {
        require(!PT.isExpired());

        DepositParams memory params = abi.decode(data, (DepositParams));
        uint256 tokenInAmount;

        if (TOKEN_IN_SY != BORROW_TOKEN) {
            Trade memory trade = Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: BORROW_TOKEN,
                buyToken: TOKEN_IN_SY,
                amount: depositUnderlyingExternal,
                limit: params.minPurchaseAmount,
                deadline: block.timestamp,
                exchangeData: params.exchangeData
            });

            // Executes a trade on the given Dex, the vault must have permissions set for
            // each dex and token it wants to sell.
            (/* */, tokenInAmount) = _executeTrade(params.dexId, trade);
        } else {
            tokenInAmount = depositUnderlyingExternal;
        }

        IPRouter.SwapData memory EMPTY_SWAP;
        IPRouter.LimitOrderData memory EMPTY_LIMIT;
        (uint256 ptReceived, /* */, /* */) = ROUTER.swapExactTokenForPt(
            address(this),
            address(MARKET),
            params.minPtOut,
            params.approxParams,
            // When tokenIn == tokenMintSy then the swap router can be set to
            // empty data. This means that the vault must hold the underlying sy
            // token when we begin the execution.
            IPRouter.TokenInput({
                tokenIn: TOKEN_IN_SY,
                netTokenIn: tokenInAmount,
                tokenMintSy: TOKEN_IN_SY,
                pendleSwap: address(0),
                swapData: EMPTY_SWAP
            }),
            EMPTY_LIMIT
        );

        return ptReceived * uint256(Constants.INTERNAL_TOKEN_PRECISION) / PT_PRECISION;
    }

    function _getValueOfWithdrawRequest(
        WithdrawRequest memory w,
        uint256 /* stakeAssetPrice */
    ) internal override view returns (uint256 usdEValue) {
        // TODO: this will be weETH and will only occur if we are unable
        // to execute an instant redemption
    }

    function _initiateWithdrawImpl(
        address /* account */, uint256 vaultSharesToRedeem, bool /* isForced */
    ) internal override returns (uint256 requestId) {
        // first sell PT
        // then initiate withdraw on Ethena or EtherFi
    }

    function _finalizeWithdrawImpl(
        address account,
        uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        // TODO
    }

    function _redeemPT(uint256 netPtIn) internal returns (uint256 netTokenOut) {
        uint256 netSyOut;
        if (PT.isExpired()) {
            PT.transfer(address(YT), netPtIn);
            netSyOut = YT.redeemPY(address(SY));
        } else {
            // safeTransfer not required
            PT.transfer(address(MARKET), netPtIn);
            (netSyOut, ) = MARKET.swapExactPtForSy(
                address(SY), // better gas optimization to transfer SY directly to itself and burn
                netPtIn,
                ""
            );
        }

        netTokenOut = SY.redeem(address(this), netSyOut, TOKEN_OUT_SY, 0, true);
    }

    function _executeInstantRedemption(
        address /* account */,
        uint256 vaultShares,
        uint256 /* maturity */,
        bytes calldata data
    ) internal override returns (uint256 borrowedCurrencyAmount) {
        uint256 netPtIn = vaultShares * PT_PRECISION / uint256(Constants.INTERNAL_TOKEN_PRECISION);
        uint256 netTokenOut = _redeemPT(netPtIn);

        if (TOKEN_OUT_SY != BORROW_TOKEN) {
            RedeemParams memory params = abi.decode(data, (RedeemParams));

            Trade memory trade = Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: TOKEN_OUT_SY,
                buyToken: BORROW_TOKEN,
                amount: netTokenOut,
                limit: params.minPurchaseAmount,
                deadline: block.timestamp,
                exchangeData: params.exchangeData
            });

            // Executes a trade on the given Dex, the vault must have permissions set for
            // each dex and token it wants to sell.
            (/* */, borrowedCurrencyAmount) = _executeTrade(params.dexId, trade);
        } else {
            borrowedCurrencyAmount = netTokenOut;
        }
    }

    function _checkReentrancyContext() internal override {
        // NO-OP
    }
}

interface IPOracle {
    function getPtToAssetRate(address market, uint32 duration) external view returns (uint256);

    function getPtToSyRate(address market, uint32 duration) external view returns (uint256);

    function getOracleState(address market, uint32 duration) external view returns (
        bool increaseCardinalityRequired, uint16 cardinalityRequired, bool oldestObservationSatisfied
    );
}

interface IPRouter {
    struct SwapData {
        SwapType swapType;
        address extRouter;
        bytes extCalldata;
        bool needScale;
    }

    enum SwapType {
        NONE,
        KYBERSWAP,
        ONE_INCH,
        // ETH_WETH not used in Aggregator
        ETH_WETH
    }

    struct TokenInput {
        // TOKEN DATA
        address tokenIn;
        uint256 netTokenIn;
        address tokenMintSy;
        // AGGREGATOR DATA
        address pendleSwap;
        SwapData swapData;
    }

    struct TokenOutput {
        // TOKEN DATA
        address tokenOut;
        uint256 minTokenOut;
        address tokenRedeemSy;
        // AGGREGATOR DATA
        address pendleSwap;
        SwapData swapData;
    }

    struct LimitOrderData {
        address limitRouter;
        uint256 epsSkipMarket; // only used for swap operations, will be ignored otherwise
        FillOrderParams[] normalFills;
        FillOrderParams[] flashFills;
        bytes optData;
    }

    enum OrderType {
        SY_FOR_PT,
        PT_FOR_SY,
        SY_FOR_YT,
        YT_FOR_SY
    }

    struct Order {
        uint256 salt;
        uint256 expiry;
        uint256 nonce;
        OrderType orderType;
        address token;
        address YT;
        address maker;
        address receiver;
        uint256 makingAmount;
        uint256 lnImpliedRate;
        uint256 failSafeRate;
        bytes permit;
    }

    struct FillOrderParams {
        Order order;
        bytes signature;
        uint256 makingAmount;
    }

    struct ApproxParams {
        uint256 guessMin;
        uint256 guessMax;
        uint256 guessOffchain; // pass 0 in to skip this variable
        uint256 maxIteration; // every iteration, the diff between guessMin and guessMax will be divided by 2
        uint256 eps; // the max eps between the returned result & the correct result, base 1e18. Normally this number will be set
        // to 1e15 (1e18/1000 = 0.1%)
    }

    function swapExactTokenForPt(
        address receiver,
        address market,
        uint256 minPtOut,
        ApproxParams calldata guessPtOut,
        TokenInput calldata input,
        LimitOrderData calldata limit
    ) external payable returns (uint256 netPtOut, uint256 netSyFee, uint256 netSyInterm);

    function swapExactPtForToken(
        address receiver,
        address market,
        uint256 exactPtIn,
        TokenOutput calldata output,
        LimitOrderData calldata limit
    ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm);

    function redeemPyToToken(
        address receiver,
        address YT,
        uint256 netPyIn,
        TokenOutput calldata output
    ) external returns (uint256 netTokenOut, uint256 netSyInterm);
}

interface IPMarket {
    function mint(
        address receiver,
        uint256 netSyDesired,
        uint256 netPtDesired
    ) external returns (uint256 netLpOut, uint256 netSyUsed, uint256 netPtUsed);

    function burn(
        address receiverSy,
        address receiverPt,
        uint256 netLpToBurn
    ) external returns (uint256 netSyOut, uint256 netPtOut);

    function swapExactPtForSy(
        address receiver,
        uint256 exactPtIn,
        bytes calldata data
    ) external returns (uint256 netSyOut, uint256 netSyFee);

    function swapSyForExactPt(
        address receiver,
        uint256 exactPtOut,
        bytes calldata data
    ) external returns (uint256 netSyIn, uint256 netSyFee);

    function redeemRewards(address user) external returns (uint256[] memory);

    // function readState(address router) external view returns (MarketState memory market);

    function observe(uint32[] memory secondsAgos) external view returns (uint216[] memory lnImpliedRateCumulative);

    function increaseObservationsCardinalityNext(uint16 cardinalityNext) external;

    function readTokens() external view returns (address _SY, address _PT, address _YT);

    function getRewardTokens() external view returns (address[] memory);

    function isExpired() external view returns (bool);

    function expiry() external view returns (uint256);

    function observations(
        uint256 index
    ) external view returns (uint32 blockTimestamp, uint216 lnImpliedRateCumulative, bool initialized);

    function _storage()
        external
        view
        returns (
            int128 totalPt,
            int128 totalSy,
            uint96 lastLnImpliedRate,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext
        );
}

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IStandardizedYield is IERC20Metadata {
    /// @dev Emitted when any base tokens is deposited to mint shares
    event Deposit(
        address indexed caller,
        address indexed receiver,
        address indexed tokenIn,
        uint256 amountDeposited,
        uint256 amountSyOut
    );

    /// @dev Emitted when any shares are redeemed for base tokens
    event Redeem(
        address indexed caller,
        address indexed receiver,
        address indexed tokenOut,
        uint256 amountSyToRedeem,
        uint256 amountTokenOut
    );

    /// @dev check `assetInfo()` for more information
    enum AssetType {
        TOKEN,
        LIQUIDITY
    }

    /// @dev Emitted when (`user`) claims their rewards
    event ClaimRewards(address indexed user, address[] rewardTokens, uint256[] rewardAmounts);

    /**
     * @notice mints an amount of shares by depositing a base token.
     * @param receiver shares recipient address
     * @param tokenIn address of the base tokens to mint shares
     * @param amountTokenToDeposit amount of base tokens to be transferred from (`msg.sender`)
     * @param minSharesOut reverts if amount of shares minted is lower than this
     * @return amountSharesOut amount of shares minted
     * @dev Emits a {Deposit} event
     *
     * Requirements:
     * - (`tokenIn`) must be a valid base token.
     */
    function deposit(
        address receiver,
        address tokenIn,
        uint256 amountTokenToDeposit,
        uint256 minSharesOut
    ) external payable returns (uint256 amountSharesOut);

    /**
     * @notice redeems an amount of base tokens by burning some shares
     * @param receiver recipient address
     * @param amountSharesToRedeem amount of shares to be burned
     * @param tokenOut address of the base token to be redeemed
     * @param minTokenOut reverts if amount of base token redeemed is lower than this
     * @param burnFromInternalBalance if true, burns from balance of `address(this)`, otherwise burns from `msg.sender`
     * @return amountTokenOut amount of base tokens redeemed
     * @dev Emits a {Redeem} event
     *
     * Requirements:
     * - (`tokenOut`) must be a valid base token.
     */
    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256 minTokenOut,
        bool burnFromInternalBalance
    ) external returns (uint256 amountTokenOut);

    /**
     * @notice exchangeRate * syBalance / 1e18 must return the asset balance of the account
     * @notice vice-versa, if a user uses some amount of tokens equivalent to X asset, the amount of sy
     he can mint must be X * exchangeRate / 1e18
     * @dev SYUtils's assetToSy & syToAsset should be used instead of raw multiplication
     & division
     */
    function exchangeRate() external view returns (uint256 res);

    /**
     * @notice claims reward for (`user`)
     * @param user the user receiving their rewards
     * @return rewardAmounts an array of reward amounts in the same order as `getRewardTokens`
     * @dev
     * Emits a `ClaimRewards` event
     * See {getRewardTokens} for list of reward tokens
     */
    function claimRewards(address user) external returns (uint256[] memory rewardAmounts);

    /**
     * @notice get the amount of unclaimed rewards for (`user`)
     * @param user the user to check for
     * @return rewardAmounts an array of reward amounts in the same order as `getRewardTokens`
     */
    function accruedRewards(address user) external view returns (uint256[] memory rewardAmounts);

    function rewardIndexesCurrent() external returns (uint256[] memory indexes);

    function rewardIndexesStored() external view returns (uint256[] memory indexes);

    /**
     * @notice returns the list of reward token addresses
     */
    function getRewardTokens() external view returns (address[] memory);

    /**
     * @notice returns the address of the underlying yield token
     */
    function yieldToken() external view returns (address);

    /**
     * @notice returns all tokens that can mint this SY
     */
    function getTokensIn() external view returns (address[] memory res);

    /**
     * @notice returns all tokens that can be redeemed by this SY
     */
    function getTokensOut() external view returns (address[] memory res);

    function isValidTokenIn(address token) external view returns (bool);

    function isValidTokenOut(address token) external view returns (bool);

    function previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) external view returns (uint256 amountSharesOut);

    function previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) external view returns (uint256 amountTokenOut);

    /**
     * @notice This function contains information to interpret what the asset is
     * @return assetType the type of the asset (0 for ERC20 tokens, 1 for AMM liquidity tokens,
        2 for bridged yield bearing tokens like wstETH, rETH on Arbi whose the underlying asset doesn't exist on the chain)
     * @return assetAddress the address of the asset
     * @return assetDecimals the decimals of the asset
     */
    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals);
}

interface IPPrincipalToken is IERC20Metadata {
    function burnByYT(address user, uint256 amount) external;

    function mintByYT(address user, uint256 amount) external;

    function initialize(address _YT) external;

    function SY() external view returns (address);

    function YT() external view returns (address);

    function factory() external view returns (address);

    function expiry() external view returns (uint256);

    function isExpired() external view returns (bool);
}

interface IPYieldToken is IERC20Metadata {
    event NewInterestIndex(uint256 indexed newIndex);

    event Mint(
        address indexed caller,
        address indexed receiverPT,
        address indexed receiverYT,
        uint256 amountSyToMint,
        uint256 amountPYOut
    );

    event Burn(address indexed caller, address indexed receiver, uint256 amountPYToRedeem, uint256 amountSyOut);

    event RedeemRewards(address indexed user, uint256[] amountRewardsOut);

    event RedeemInterest(address indexed user, uint256 interestOut);

    event CollectRewardFee(address indexed rewardToken, uint256 amountRewardFee);

    function mintPY(address receiverPT, address receiverYT) external returns (uint256 amountPYOut);

    function redeemPY(address receiver) external returns (uint256 amountSyOut);

    function redeemPYMulti(
        address[] calldata receivers,
        uint256[] calldata amountPYToRedeems
    ) external returns (uint256[] memory amountSyOuts);

    function redeemDueInterestAndRewards(
        address user,
        bool redeemInterest,
        bool redeemRewards
    ) external returns (uint256 interestOut, uint256[] memory rewardsOut);

    function rewardIndexesCurrent() external returns (uint256[] memory);

    function pyIndexCurrent() external returns (uint256);

    function pyIndexStored() external view returns (uint256);

    function getRewardTokens() external view returns (address[] memory);

    function SY() external view returns (address);

    function PT() external view returns (address);

    function factory() external view returns (address);

    function expiry() external view returns (uint256);

    function isExpired() external view returns (bool);

    function doCacheIndexSameBlock() external view returns (bool);

    function pyIndexLastUpdatedBlock() external view returns (uint128);
}