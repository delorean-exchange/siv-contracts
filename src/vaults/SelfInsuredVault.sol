// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import "../libraries/Math.sol";

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "openzeppelin/token/ERC20/extensions/ERC4626.sol";

import {IYieldSource} from "dlx/src/interfaces/IYieldSource.sol";
import {NPVSwap} from "dlx/src/core/NPVSwap.sol";

import {IYieldOracle} from "../interfaces/IYieldOracle.sol";
import {ISelfInsuredVault} from "../interfaces/ISelfInsuredVault.sol";
import {IInsuranceProvider} from "../interfaces/IInsuranceProvider.sol";

/// @title Self Insured Vault(SIV) contract
/// @author Delorean Exchange x Y2K Finance
/// @dev All function calls are currently implemented without side effects
contract SelfInsuredVault is ISelfInsuredVault, ERC4626, Ownable {
    using SafeERC20 for IERC20;

    // -- Constants, other global state -- //
    uint256 public constant PRECISION_FACTOR = 10 ** 18;
    uint256 public constant WEIGHTS_PRECISION = 100_00;
    uint256 public constant MAX_COMBINED_WEIGHT = 20_00;
    uint256 public constant MAX_PROVIDERS = 10;

    // NOTE: Epoch ID's are assumed to be synchronized across providers

    // -- Insurance payouts tracking -- //

    // `UserEpochTracker` tracks shares and payouts on a per-use basis.
    // It updates and accumulates each time the user's shares change, and
    // tracks positions in three ways:
    //
    // (1) It tracks the start of the "next" epoch, and the user's balance
    //     in this epoch. `nextEpochId` indicates the start of the "next"
    //     epoch. In that epoch, and all subsequent epochs, the user has
    //     `nextShares` number of shares.
    // (2) It tracks the epoch range before the "next" epoch. These are
    //     the epochs between [startEpochId, nextEpochId). In this range,
    //     the user has `shares` number of shares.
    // (3) It tracks previously accumulated payouts in the `accumulatedPayouts`
    //     field. This is the amount of `paymentToken` that the user is
    //     entitled to. This field is updated whenever the number of shares
    //     changes, and it is set to the value of payouts in the range
    //     [startEpochId, nextEpochId).
    //
    // The `claimedPayouts` field indicates what the user has already claimed.
    struct UserEpochTracker {
        uint256 startEpochId;
        uint256 shares;
        uint256 nextEpochId;
        uint256 nextShares;
        uint256 accumulatedPayouts;
        uint256 claimedPayouts;
    }

    // `EpochInfo` tracks payouts on a per-provider-per-epoch basis. Combine with
    // the data in `UserEpochTracker` to compute each user's payouts.
    struct EpochInfo {
        uint256 epochId; // Timestamp of epoch start
        uint256 totalShares; // Total shares during this epoch
        uint256 payout; // Payout of this epoch, if any
        uint256 premiumPaid; // If zero, insurance has not yet been purchased
    }

    // -- Yield & rewards accounting -- //
    struct GlobalYieldInfo {
        uint256 yieldPerTokenStored;
        uint256 lastUpdateBlock;
        uint256 lastUpdateCumulativeYield;
        uint256 harvestedYield;
        uint256 claimedYield;
    }

    // `UserYieldInfo` tracks each users yield from the underlying. Note that this
    // is separate from insurance payouts.
    struct UserYieldInfo {
        uint256 accumulatedYieldPerToken;
        uint256 accumulatedYield;
    }

    /// @notice User => Epoch Tracker
    mapping(address => UserEpochTracker) public userEpochTrackers;

    /// @notice Provider => EpochInfo
    mapping(address => EpochInfo[]) public providerEpochs;

    /// @notice Yield Token => Epoch Tracker
    mapping(address => GlobalYieldInfo) public globalYieldInfos;

    /// @notice User => Yield Token => User's yield info
    mapping(address => mapping(address => UserYieldInfo)) public userYieldInfos;

    /// TODO: struct { provider, weight }, add totalWeight

    /// @notice Array of Insurance Providers, i.e strategies for different vaults
    IInsuranceProvider[] public providers;

    /// @notice Weight of each insurance vaults
    uint256[] public weights;

    /// @notice Reward tokens by SIV
    address[] public rewardTokens;

    /// @notice Token to be paid in for insurance
    IERC20 public immutable paymentToken;

    /// TODO: NOT USED!
    uint256 lastRecordedEpochId;

    /// TODO: gerneralize this
    uint256 dlxId;

    /// @notice Yield source contract
    IYieldSource public immutable yieldSource;

    /// @notice Yield oracles
    IYieldOracle public oracle;

    /// @notice Delorean swap contract TODO: generalize this
    NPVSwap public dlxSwap;

    /// @notice Emitted when `user` claimed payout
    event ClaimPayouts(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    // TODO: refactor ERC4626 input
    /**
     * @notice Contract constructor
     * @param _name Name of share token
     * @param _symbol Symbol of share token
     * @param _paymentToken Token used for premium
     * @param _yieldSource Yield source contract address
     * @param _oracle Yield oracle contract address
     * @param _dlxSwap Delorean swap contract
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _paymentToken,
        address _yieldSource,
        address _oracle,
        address _dlxSwap
    )
        ERC20(_name, _symbol)
        ERC4626(IERC20(address(IYieldSource(_yieldSource).generatorToken())))
    {
        require(_yieldSource != address(0), "SIV: zero source");
        /* require(oracle_ != address(0), "SIV: zero oracle"); */

        paymentToken = IERC20(_paymentToken);
        yieldSource = IYieldSource(_yieldSource);
        oracle = IYieldOracle(_oracle);
        dlxSwap = NPVSwap(_dlxSwap);
        rewardTokens.push(address(IYieldSource(_yieldSource).yieldToken()));
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets oracle contract
     * @param _oracle Yield oracle contract address
     */
    function setOracle(address _oracle) external onlyOwner {
        oracle = IYieldOracle(_oracle);
    }

    /**
     * @notice Add a new reward token
     * @param rewardToken New reward token
     */
    function addRewardToken(address rewardToken) external onlyOwner {
        require(rewardToken != address(0), "SIV: zero reward token");
        rewardTokens.push(rewardToken);
    }

    /**
     * @notice Add a new insurance provider
     * @dev We assume the epoch duration of every vault are the same TODO: why?
     * @param _provider New insurance provider
     * @param _weight Weight of new insurance provider
     */
    function addInsuranceProvider(
        IInsuranceProvider _provider,
        uint256 _weight
    ) external onlyOwner {
        require(
            providers.length == 0 ||
                _provider.epochDuration() == providers[0].epochDuration(),
            "SIV: same duration"
        );
        require(_provider.paymentToken() == paymentToken, "SIV: payment token");
        require(providers.length < MAX_PROVIDERS, "SIV: max providers");

        uint256 sum = _weight;
        for (uint256 i = 0; i < weights.length; i++) {
            sum += weights[i];
        }
        require(sum < MAX_COMBINED_WEIGHT, "SIV: max weight");

        providers.push(_provider);
        weights.push(_weight);
    }

    /**
     * @notice Set weight of insurance provider
     * @param index of insurance provider
     * @param _weight new weight
     */
    function setWeight(uint256 index, uint256 _weight) external onlyOwner {
        require(index < providers.length, "SIV: invalid index");
        uint256 sum = _weight;
        for (uint256 i = 0; i < weights.length; i++) {
            if (i == index) continue;
            sum += weights[i];
        }
        require(sum < MAX_COMBINED_WEIGHT, "SIV: max weight");

        weights[index] = _weight;
    }

    /*//////////////////////////////////////////////////////////////
                                VIEWERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns count of providers
     */
    function providersLength() public view returns (uint256) {
        return providers.length;
    }

    /**
     * @notice Returns count of epochs for a specific provider
     * @param provider address
     */
    function epochsLength(address provider) public view returns (uint256) {
        return providerEpochs[provider].length;
    }

    /**
     * @notice Returns count of reward tokens
     */
    function rewardTokensLength() public view returns (uint256) {
        return rewardTokens.length;
    }

    /**
     * @notice Returns global cumulative yield
     */
    function cumulativeYield() external view returns (uint256) {
        return _cumulativeYield(address(yieldSource.yieldToken()));
    }

    /**
     * @notice Returns pending yield of `user`
     * @param user address
     */
    function calculatePendingYield(
        address user
    ) external view returns (uint256) {
        return _calculatePendingYield(user, address(yieldSource.yieldToken()));
    }

    /**
     * @notice Returns claimable payouts of `who`
     * @param who address for payout
     */
    function previewClaimPayouts(address who) external view returns (uint256) {
        return _pendingPayouts(who);
    }

    /**
     * @notice Returns pending payouts of an insurance
     */
    function pendingInsurancePayouts() external view returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < providers.length; i++) {
            sum += providers[i].pendingPayouts();
        }
        return sum;
    }

    /**
     * @notice Returns claimable rewards of `who`
     * @param who address
     */
    function previewClaimRewards(
        address who
    ) external view returns (uint256[] memory) {
        return _previewClaimRewards(who);
    }

    /*//////////////////////////////////////////////////////////////
                                OPERATIONS
    //////////////////////////////////////////////////////////////*/

    // -- ERC4642: Deposit -- //

    /**
     * @notice Deposit to SIV
     * @param assets amount of `paymentToken`
     * @param receiver for share
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public override returns (uint256) {
        for (uint8 i = 0; i < uint8(rewardTokens.length); i++) {
            address t = address(rewardTokens[i]);
            _updateYield(receiver, t);
        }
        _updateProviderEpochs(int256(assets));
        _updateUserEpochTracker(receiver, int256(assets));

        super.deposit(assets, receiver);
        IERC20(asset()).safeApprove(address(yieldSource), 0);
        IERC20(asset()).safeApprove(address(yieldSource), assets);
        yieldSource.deposit(assets, false);

        return assets;
    }

    // -- ERC4642: Withdraw -- //

    /**
     * @notice Returns maximum withrawable amount
     * @param owner address
     */
    function maxWithdraw(
        address owner
    ) public override view returns (uint256 maxAssets) {
        uint256 balance = balanceOf(owner);
        uint256 available = yieldSource.amountGenerator();
        if (dlxId != 0 && dlxSwap.slice().remaining(dlxId) == 0) {
            available += dlxSwap.slice().tokens(dlxId);
        }
        return available < balance ? available : balance;
    }

    /**
     * @notice Withdraw assets
     * @param assets share amount
     * @param receiver address
     * @param owner of share
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256) {
        require(msg.sender == owner, "SIV: withdraw only owner");
        require(
            balanceOf(owner) >= assets,
            "SIV: withdraw insufficient balance"
        );

        _unlockIfNeeded();

        _updateYield(owner, address(yieldSource.yieldToken()));
        _updateProviderEpochs(-int256(assets));
        _updateUserEpochTracker(owner, -int256(assets));
        yieldSource.withdraw(assets, false, receiver);
        _burn(receiver, assets);

        return assets;
    }

    // -- ERC4642: Mint -- //

    /**
     * @notice Mint shares to `receiver`
     * @dev disabled mint
     */
    function mint(uint256 shares, address receiver) public override returns (uint256) {
        assert(false);
        return 0;
    }

    // -- ERC4642: Redeem -- //

    /**
     * @notice Mint shares to `receiver`
     * @dev disabled redeem
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        assert(false);
        return 0; // deposit only vault
    }

    /**
     * @notice Claim payouts
     */
    function claimPayouts() external returns (uint256) {
        uint256 amount = _pendingPayouts(msg.sender);
        paymentToken.safeTransfer(msg.sender, amount);
        userEpochTrackers[msg.sender].claimedPayouts += amount;

        emit ClaimPayouts(msg.sender, amount);

        return amount;
    }

    /**
     * @notice Claim payout of a vault
     */
    function claimVaultPayouts() external {
        for (uint256 i = 0; i < providers.length; i++) {
            IERC20 pt = providers[i].paymentToken();
            uint256 before = pt.balanceOf(address(this));
            uint256 amount = providers[i].claimPayouts();
            assert(amount == pt.balanceOf(address(this)) - before);
            if (amount > 0) {
                EpochInfo[] storage infos = providerEpochs[
                    address(providers[i])
                ];
                infos[infos.length - 1].payout += amount;
            }
        }
    }

    /**
     * @notice Claim payout of a vault
     * @param minBps is the minimum yield fronted from Delorean, in terms of basis points.
     * @param projectedYield ???
     */
    function purchaseInsuranceForNextEpoch(
        uint256 minBps,
        uint256 projectedYield
    ) external onlyOwner {
        /* uint256 projectedYield = _projectEpochYield(); */

        // Get epoch's yield upfront via Delorean
        uint256 sum = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            sum += (projectedYield * weights[i]) / WEIGHTS_PRECISION;
        }
        uint256 minOut = (sum * minBps) / 100_00;

        // Lock half generating tokens, leave other half for withdrawals until position
        // unlocks. If more than half those tokens are reqeusted to withdraw, they must
        // wait until the position repays itself, a function of the sum of weights,
        // yield rate, and epoch duration. If 10% of yield is devoted to insurance
        // purchase for 1 week epochs, it should take around 20% * 7 days = 1.4 days.
        uint256 amountLock = yieldSource.amountGenerator() / 2;
        yieldSource.withdraw(amountLock, false, address(this));
        yieldSource.generatorToken().approve(address(dlxSwap), amountLock);

        _unlockIfNeeded();
        require(dlxId == 0, "SIV: active delorean position");
        (uint256 id, uint256 actualOut) = dlxSwap.lockForYield(
            address(this),
            amountLock,
            sum,
            minOut,
            0,
            new bytes(0)
        );
        dlxId = id;

        // Purchase insurance via Y2K
        for (uint256 i = 0; i < providers.length; i++) {
            uint256 amount = (actualOut * weights[i]) / WEIGHTS_PRECISION;
            if (amount == 0) continue;
            _purchaseForNextEpoch(i, amount);
        }
    }

    /**
     * @notice Claim rewards
     */
    function claimRewards() external returns (uint256[] memory) {
        _harvest();

        uint256[] memory owed = _previewClaimRewards(msg.sender);

        require(owed.length == rewardTokens.length, "SIV: claim length");

        for (uint8 i = 0; i < uint8(owed.length); i++) {
            address t = address(rewardTokens[i]);

            _updateYield(msg.sender, t);
            require(
                owed[i] == userYieldInfos[msg.sender][t].accumulatedYield,
                "SIV: claim acc"
            );

            userYieldInfos[msg.sender][t].accumulatedYield = 0;

            IERC20(rewardTokens[i]).safeTransfer(msg.sender, owed[i]);
            globalYieldInfos[t].claimedYield += owed[i];
        }

        return owed;
    }


    function pprintEpochs() external {
        for (uint256 i = 0; i < providers.length; i++) {
            IInsuranceProvider provider = providers[i];
            EpochInfo[] storage epochs = providerEpochs[address(provider)];
            for (uint256 j = 0; j < epochs.length; j++) {
                console.log("----");
                console.log("Epoch", j);
                console.log("- epochId    ", epochs[j].epochId);
                console.log("- totalShares", epochs[j].totalShares);
                console.log("- payout     ", epochs[j].payout);
                console.log("- premiumPaid", epochs[j].premiumPaid);
            }
        }
        console.log("----");
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns gobal cumulative yield amount of `yieldToken`
     * @param yieldToken Yield Token
     */
    function _cumulativeYield(
        address yieldToken
    ) private view returns (uint256) {
        if (yieldToken == address(yieldSource.yieldToken())) {
            return
                globalYieldInfos[yieldToken].harvestedYield +
                yieldSource.amountPending();
        } else {
            return (IERC20(yieldToken).balanceOf(address(this)) +
                globalYieldInfos[yieldToken].claimedYield);
        }
    }

    /**
     * @notice Returns yield amount per token
     * @param yieldToken Yield Token
     */
    function _yieldPerToken(
        address yieldToken
    ) internal view returns (uint256) {
        GlobalYieldInfo storage gyInfo = globalYieldInfos[yieldToken];
        if (this.totalAssets() == 0) {
            return gyInfo.yieldPerTokenStored;
        }
        if (block.number == gyInfo.lastUpdateBlock) {
            return gyInfo.yieldPerTokenStored;
        }

        uint256 deltaYield = (_cumulativeYield(yieldToken) -
            gyInfo.lastUpdateCumulativeYield);

        return (gyInfo.yieldPerTokenStored +
            (deltaYield * PRECISION_FACTOR) /
            this.totalAssets());
    }

    /**
     * @notice Returns pending yield of `user`
     * @param user address
     * @param yieldToken Yield Token
     */
    function _calculatePendingYield(
        address user,
        address yieldToken
    ) public view returns (uint256) {
        UserYieldInfo storage info = userYieldInfos[user][yieldToken];
        uint256 ypt = _yieldPerToken(yieldToken);

        return
            ((this.balanceOf(user) * (ypt - info.accumulatedYieldPerToken))) /
            PRECISION_FACTOR +
            info.accumulatedYield;
    }

    /**
     * @notice Counts the depeg rewards for epochs between [startEpochId, nextEpochId)
     * @param user address
     */
    function _computeAccumulatePayouts(
        address user
    ) internal view returns (uint256) {
        UserEpochTracker storage tracker = userEpochTrackers[user];
        if (tracker.startEpochId == 0) return 0;
        if (tracker.shares == 0) return 0;

        uint256 deltaAccumulatedPayouts;

        for (uint256 i = 0; i < providers.length; i++) {
            IInsuranceProvider provider = providers[i];
            uint256 nextEpochId = provider.nextEpoch();
            uint256 currentEpochId = provider.currentEpoch();
            EpochInfo[] storage infos = providerEpochs[address(provider)];

            // TODO: GAS: Use nextId field + mapping instead of list
            for (uint256 j = 0; j < infos.length; j++) {
                EpochInfo storage info = infos[j];
                if (info.epochId < tracker.startEpochId) continue;
                if (info.epochId >= tracker.nextEpochId) break;
                if (info.epochId == currentEpochId) break;
                deltaAccumulatedPayouts +=
                    (tracker.shares * info.payout) /
                    info.totalShares;
            }
        }

        return deltaAccumulatedPayouts;
    }

    /**
     * @notice Updates provider epochs
     * @param who address
     */
    function _previewClaimRewards(
        address who
    ) internal view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = _calculatePendingYield(who, rewardTokens[i]);
        }
        return result;
    }

    /**
     * @notice Pending payout of `who`
     * @param who address
     */
    function _pendingPayouts(address who) internal view returns (uint256) {
        uint256 deltaAccumulatdPayouts = _computeAccumulatePayouts(who);

        // `deltaAccumulatdPayouts` includes [startEpochId, nextEpochId), but we
        // also want [nextEpochId, currentEpochId].
        uint256 accumulatedPayouts;
        UserEpochTracker storage tracker = userEpochTrackers[who];
        for (uint256 i = 0; i < providers.length; i++) {
            IInsuranceProvider provider = providers[i];
            uint256 currentEpochId = provider.currentEpoch();

            EpochInfo[] storage infos = providerEpochs[address(provider)];

            // TODO: GAS: Use nextId field + mapping instead of list
            for (uint256 j = 0; j < infos.length; j++) {
                EpochInfo storage info = infos[j];
                if (info.epochId < tracker.nextEpochId) continue;

                accumulatedPayouts +=
                    (tracker.nextShares * info.payout) /
                    info.totalShares;

                // Check below expected to be redundant, since the last element
                // should be for the current epoch
                if (info.epochId == currentEpochId) break;
            }
        }

        return (userEpochTrackers[who].accumulatedPayouts +
            accumulatedPayouts +
            deltaAccumulatdPayouts -
            userEpochTrackers[who].claimedPayouts);
    }

    /**
     * @notice Returns yield to be distributed per next epoch
     */
    function _projectEpochYield() internal view returns (uint256) {
        // Assume all providers have same epoch duration, this is asserted elsewhere
        IInsuranceProvider provider0 = providers[0];
        uint256 epochDuration = provider0.epochDuration();
        return
            oracle.projectYield(yieldSource.amountGenerator(), epochDuration);
    }

    /**
     * @notice Harvest rewards.
     */
    function _harvest() internal {
        // Harvest the underlying in slot 0, which must be claimed
        uint256 pending = yieldSource.amountPending();
        yieldSource.harvest();
        globalYieldInfos[address(yieldSource.yieldToken())]
            .harvestedYield += pending;

        // Harvest reward tokens in slots 1+, which are simply transferred into
        // the contract
        for (uint8 i = 1; i < uint8(rewardTokens.length); i++) {
            address t = address(rewardTokens[i]);
            GlobalYieldInfo storage gyInfo = globalYieldInfos[t];
            gyInfo.harvestedYield = (IERC20(t).balanceOf(address(this)) +
                gyInfo.claimedYield);
        }
    }

    /**
     * @notice Returns pending yield of `user`
     * @param user address
     * @param yieldToken Yield Token
     */
    function _updateYield(address user, address yieldToken) internal {
        GlobalYieldInfo storage gyInfo = globalYieldInfos[yieldToken];
        if (block.number != gyInfo.lastUpdateBlock) {
            gyInfo.yieldPerTokenStored = _yieldPerToken(yieldToken);
            gyInfo.lastUpdateBlock = block.number;
            gyInfo.lastUpdateCumulativeYield = _cumulativeYield(yieldToken);
        }

        userYieldInfos[user][yieldToken]
            .accumulatedYield = _calculatePendingYield(user, yieldToken);
        userYieldInfos[user][yieldToken].accumulatedYieldPerToken = gyInfo
            .yieldPerTokenStored;
    }

    /**
     * @notice Updates provider epochs
     * @param deltaShares shares amount for update
     */
    function _updateProviderEpochs(int256 deltaShares) internal {
        for (uint256 i = 0; i < providers.length; i++) {
            IInsuranceProvider provider = providers[i];
            EpochInfo[] storage epochs = providerEpochs[address(provider)];

            // Create first EpochInfo, if needed
            if (epochs.length == 0) {
                epochs.push(EpochInfo(provider.nextEpoch(), 0, 0, 0));
            }
            EpochInfo storage epochInfo = epochs[epochs.length - 1];
            uint256 totalShares = epochInfo.totalShares;

            // Add new EpochInfo's, if needed
            uint256 id = provider.followingEpoch(epochInfo.epochId);
            while (id != 0) {
                epochs.push(EpochInfo(id, totalShares, 0, 0));
                epochInfo = epochs[epochs.length - 1];
                id = provider.followingEpoch(id);
            }

            epochInfo.totalShares = deltaShares > 0
                ? epochInfo.totalShares + uint256(deltaShares)
                : epochInfo.totalShares - uint256(-deltaShares);
        }
    }

    /**
     * @notice Updates provider epochs
     * @param user address
     * @param deltaShares shares amount for update
     */
    function _updateUserEpochTracker(
        address user,
        int256 deltaShares
    ) internal {
        if (providers.length == 0) return;

        UserEpochTracker storage tracker = userEpochTrackers[user];

        // Assuming synchronized epoch ID's, this is asserted elsewhere
        uint256 nextEpochId = providers[0].nextEpoch();

        // See if we need to shift nextEpoch into start/end epoch segment
        if (nextEpochId != tracker.nextEpochId) {
            uint256 deltaAccumulatdPayouts = _computeAccumulatePayouts(user);

            tracker.accumulatedPayouts += deltaAccumulatdPayouts;

            tracker.startEpochId = tracker.nextEpochId;
            tracker.nextEpochId = nextEpochId;
            tracker.shares = tracker.nextShares;
        }

        // Update the shares starting with the next epoch
        tracker.nextShares = deltaShares > 0
            ? tracker.nextShares + uint256(deltaShares)
            : tracker.nextShares - uint256(-deltaShares);
    }

    /**
     * @notice Purchase next epoch
     * @param i Index of provider
     * @param amount of tokens for purchase
     */
    function _purchaseForNextEpoch(uint256 i, uint256 amount) internal {
        IInsuranceProvider provider = providers[i];
        require(provider.isNextEpochPurchasable(), "SIV: not purchasable");

        uint256 nextEpochId = provider.nextEpoch();
        EpochInfo[] storage epochs = providerEpochs[address(provider)];
        if (
            epochs.length == 0 ||
            epochs[epochs.length - 1].epochId != nextEpochId
        ) {
            epochs.push(EpochInfo(nextEpochId, 0, 0, 0));
        }
        EpochInfo storage epochInfo = epochs[epochs.length - 1];
        require(epochInfo.premiumPaid == 0, "SIV: already purchased");

        uint256 weight = weights[i];

        IERC20(provider.paymentToken()).approve(address(provider), amount);
        provider.purchaseForNextEpoch(amount);
        epochInfo.premiumPaid = amount;
    }

    /**
     * @notice Unlock dlx swap
     */
    function _unlockIfNeeded() internal {
        if (dlxId == 0) return;
        if (dlxSwap.slice().remaining(dlxId) != 0) return;
        dlxSwap.slice().unlockDebtSlice(dlxId);
        dlxId = 0;
    }
}
