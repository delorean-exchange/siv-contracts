// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import "../libraries/Math.sol";

import { ERC20 } from  "openzeppelin/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import { IYieldSource } from "dlx/src/interfaces/IYieldSource.sol";
import { NPVSwap } from "dlx/src/core/NPVSwap.sol";

import { IYieldOracle } from "../interfaces/IYieldOracle.sol";
import { ISelfInsuredVault } from "../interfaces/ISelfInsuredVault.sol";
import { IInsuranceProvider } from "../interfaces/IInsuranceProvider.sol";

contract SelfInsuredVault is ISelfInsuredVault, ERC20 {
    using SafeERC20 for IERC20;

    event Deposit(address indexed sender,
                  address indexed owner,
                  uint256 assets,
                  uint256 shares);

    event Withdraw(address indexed sender,
                   address indexed receiver,
                   address indexed owner,
                   uint256 assets,
                   uint256 shares);

    event ClaimPayouts(address indexed user,
                       uint256 amount);

    // -- Insurance payouts tracking -- //

    // NOTE: Epoch ID's are assumed to be synchronized across providers

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
    mapping(address => UserEpochTracker) public userEpochTrackers;

    // `EpochInfo` tracks payouts on a per-provider-per-epoch basis. Combine with
    // the data in `UserEpochTracker` to compute each user's payouts.
    struct EpochInfo {
        uint256 epochId;      // Timestamp of epoch start
        uint256 totalShares;  // Total shares during this epoch
        uint256 payout;       // Payout of this epoch, if any
        uint256 premiumPaid;  // If zero, insurance has not yet been purchased
    }
    mapping(address => EpochInfo[]) public providerEpochs;


    // -- Yield & rewards accounting -- //
    struct GlobalYieldInfo {
        uint256 yieldPerTokenStored;
        uint256 lastUpdateBlock;
        uint256 lastUpdateCumulativeYield;
        uint256 harvestedYield;
        uint256 claimedYield;
    }
    mapping(address => GlobalYieldInfo) public globalYieldInfos;

    // `UserYieldInfo` tracks each users yield from the underlying. Note that this
    // is separate from insurance payouts.
    struct UserYieldInfo {
        uint256 accumulatedYieldPerToken;
        uint256 accumulatedYield;
    }
    mapping(address => mapping(address => UserYieldInfo)) public userYieldInfos;

    // -- Constants, other global state -- //
    uint256 public constant PRECISION_FACTOR = 10**18;
    uint256 public constant WEIGHTS_PRECISION = 100_00;
    uint256 public constant MAX_COMBINED_WEIGHT = 20_00;
    uint256 public constant MAX_PROVIDERS = 10;

    address public admin;
    IInsuranceProvider[] public providers;
    uint256[] public weights;
    address[] public rewardTokens;
    IERC20 public immutable paymentToken;

    uint256 lastRecordedEpochId;

    uint256 dlxId;

    IYieldSource public immutable yieldSource;
    IYieldOracle public oracle;
    NPVSwap public dlxSwap;

    modifier onlyAdmin {
        require(msg.sender == admin, "SIV: only admin");
        _;
    }

    constructor(string memory name_,
                string memory symbol_,
                address paymentToken_,
                address yieldSource_,
                address oracle_,
                address dlxSwap_) ERC20(name_, symbol_) {
        require(yieldSource_ != address(0), "SIV: zero source");
        /* require(oracle_ != address(0), "SIV: zero oracle"); */

        admin = msg.sender;

        paymentToken = IERC20(paymentToken_);
        yieldSource = IYieldSource(yieldSource_);
        oracle = IYieldOracle(oracle_);
        dlxSwap = NPVSwap(dlxSwap_);
        rewardTokens = new address[](1);
        rewardTokens[0] = address(IYieldSource(yieldSource_).yieldToken());
    }

    function _min(uint256 x1, uint256 x2) private pure returns (uint256) {
        return x1 < x2 ? x1 : x2;
    }

    function providersLength() public view returns (uint256) {
        return providers.length;
    }

    function epochsLength(address provider) public view returns (uint256) {
        return providerEpochs[provider].length;
    }

    function rewardTokensLength() public view returns (uint256) {
        return rewardTokens.length;
    }

    function setOracle(address oracle_) external onlyAdmin {
        oracle = IYieldOracle(oracle_);
    }

    // -- ERC4642: Asset -- //
    function _asset() private view returns (address) {
        return address(yieldSource.generatorToken());
    }

    function asset() external view returns (address) {
        return _asset();
    }

    function totalAssets() external view returns (uint256) {
        return this.totalSupply();
    }

    // -- ERC4642: Share conversion -- //
    function convertToShares(uint256 assets) external view returns (uint256) {
        return assets;  // Non-rebasing vault, shares==assets
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return shares;  // Non-rebasing vault, shares==assets
    }

    // -- ERC4642: Deposit -- //
    function maxDeposit(address receiver) external view returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return assets;  // Non-rebasing vault, shares==assets
    }

    function deposit(uint256 assets, address receiver) external returns (uint256) {
        require(assets <= this.maxDeposit(receiver), "SIV: max deposit");

        // TODO: I don't think we actually need this min
        require(assets >= PRECISION_FACTOR, "SIV: min deposit");

        for (uint8 i = 0; i < uint8(rewardTokens.length); i++) {
            address t = address(rewardTokens[i]);
            _updateYield(receiver, t);
        }
        _updateProviderEpochs(int256(assets));
        _updateUserEpochTracker(receiver, int256(assets));

        IERC20(_asset()).safeTransferFrom(msg.sender, address(this), assets);
        IERC20(_asset()).safeApprove(address(yieldSource), 0);
        IERC20(_asset()).safeApprove(address(yieldSource), assets);
        yieldSource.deposit(assets, false);
        _mint(receiver, assets);

        emit Deposit(msg.sender, receiver, assets, assets);

        return assets;
    }

    // -- ERC4642: Withdraw -- //
    function maxWithdraw(address owner) external view returns (uint256 maxAssets) {
        uint256 available = yieldSource.amountGenerator();
        if (dlxId != 0 && dlxSwap.slice().remaining(dlxId) == 0) {
            available += dlxSwap.slice().tokens(dlxId);
        }
        return _min(available, balanceOf(owner));
    }

    function previewWithdraw(uint256 assets) external view returns (uint256) {
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256) {
        require(msg.sender == owner, "SIV: withdraw only owner");
        require(balanceOf(owner) >= assets, "SIV: withdraw insufficient balance");

        _unlockIfNeeded();

        _updateYield(owner, address(yieldSource.yieldToken()));
        _updateProviderEpochs(-int256(assets));
        _updateUserEpochTracker(owner, -int256(assets));
        yieldSource.withdraw(assets, false, receiver);
        _burn(receiver, assets);

        return assets;
    }

    // -- ERC4642: Mint -- //
    function maxMint(address receiver) external view returns (uint256) {
        return 0;  // deposit only vault
    }

    function previewMint(uint256 shares) external view returns (uint256) {
        return 0;  // deposit only vault
    }

    function mint(uint256 shares, address receiver) external returns (uint256) {
        assert(false);
        return 0;  // deposit only vault
    }

    // -- ERC4642: Redeem -- //
    function maxRedeem(address owner) external view returns (uint256 maxShares) {
        return 0;  // deposit only vault
    }

    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        return 0;  // deposit only vault
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assert(false);
        return 0;  // deposit only vault
    }

    function _harvest() internal {
        // Harvest the underlying in slot 0, which must be claimed
        uint256 pending = yieldSource.amountPending();
        yieldSource.harvest();
        globalYieldInfos[address(yieldSource.yieldToken())].harvestedYield += pending;

        // Harvest reward tokens in slots 1+, which are simply transferred into
        // the contract
        for (uint8 i = 1; i < uint8(rewardTokens.length); i++) {
            address t = address(rewardTokens[i]);
            GlobalYieldInfo storage gyInfo = globalYieldInfos[t];
            gyInfo.harvestedYield = (IERC20(t).balanceOf(address(this)) +
                                     gyInfo.claimedYield);
        }
    }

    function cumulativeYield() external view returns (uint256) {
        return _cumulativeYield(address(yieldSource.yieldToken()));
    }

    function _cumulativeYield(address yieldToken) private view returns (uint256) {
        if (yieldToken == address(yieldSource.yieldToken())) {
            return globalYieldInfos[yieldToken].harvestedYield + yieldSource.amountPending();
        } else {
            return (IERC20(yieldToken).balanceOf(address(this)) +
                    globalYieldInfos[yieldToken].claimedYield);
        }
    }

    function _yieldPerToken(address yieldToken) internal view returns (uint256) {
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
                (deltaYield * PRECISION_FACTOR) / this.totalAssets());
    }

    function _calculatePendingYield(address user, address yieldToken) public view returns (uint256) {
        UserYieldInfo storage info = userYieldInfos[user][yieldToken];
        uint256 ypt = _yieldPerToken(yieldToken);

        return ((this.balanceOf(user) * (ypt - info.accumulatedYieldPerToken)))
            / PRECISION_FACTOR
            + info.accumulatedYield;
    }

    function calculatePendingYield(address user) external view returns (uint256) {
        return _calculatePendingYield(user, address(yieldSource.yieldToken()));
    }

    function _updateYield(address user, address yieldToken) internal {
        GlobalYieldInfo storage gyInfo = globalYieldInfos[yieldToken];
        if (block.number != gyInfo.lastUpdateBlock) {
            gyInfo.yieldPerTokenStored = _yieldPerToken(yieldToken);
            gyInfo.lastUpdateBlock = block.number;
            gyInfo.lastUpdateCumulativeYield = _cumulativeYield(yieldToken);
        }

        userYieldInfos[user][yieldToken].accumulatedYield =
            _calculatePendingYield(user, yieldToken);
        userYieldInfos[user][yieldToken].accumulatedYieldPerToken =
            gyInfo.yieldPerTokenStored;
    }

    // Counts the depeg rewards for epochs between [startEpochId, nextEpochId)
    function _computeAccumulatePayouts(address user) internal view returns (uint256)  {
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
                deltaAccumulatedPayouts += (tracker.shares * info.payout) / info.totalShares;
            }
        }

        return deltaAccumulatedPayouts;
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

    function _updateUserEpochTracker(address user, int256 deltaShares) internal {
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

    // -- Rewards -- //
    function _previewClaimRewards(address who) internal view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = _calculatePendingYield(who, rewardTokens[i]);
        }
        return result;
    }

    function previewClaimRewards(address who) external view returns (uint256[] memory) {
        return _previewClaimRewards(who);
    }

    function claimRewards() external returns (uint256[] memory) {
        _harvest();

        uint256[] memory owed = _previewClaimRewards(msg.sender);

        require(owed.length == rewardTokens.length, "SIV: claim length");

        for (uint8 i = 0; i < uint8(owed.length); i++) {
            address t = address(rewardTokens[i]);

            _updateYield(msg.sender, t);
            require(owed[i] == userYieldInfos[msg.sender][t].accumulatedYield, "SIV: claim acc");

            userYieldInfos[msg.sender][t].accumulatedYield = 0;

            IERC20(rewardTokens[i]).safeTransfer(msg.sender, owed[i]);
            globalYieldInfos[t].claimedYield += owed[i];
        }

        return owed;
    }

    // -- Payouts -- //
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

                accumulatedPayouts += (tracker.nextShares * info.payout) / info.totalShares;

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

    function previewClaimPayouts(address who) external view returns (uint256) {
        return _pendingPayouts(who);
    }

    function claimPayouts() external returns (uint256) {
        uint256 amount = _pendingPayouts(msg.sender);
        paymentToken.safeTransfer(msg.sender, amount);
        userEpochTrackers[msg.sender].claimedPayouts += amount;

        emit ClaimPayouts(msg.sender, amount);

        return amount;
    }

    // -- Admin only -- //
    function setAdmin(address admin_) external onlyAdmin {
        require(admin != address(0), "SIV: zero admin");
        admin = admin_;
    }

    function addRewardToken(address rewardToken) external onlyAdmin {
        require(rewardToken != address(0), "SIV: zero reward token");
        rewardTokens.push(rewardToken);
    }

    function addInsuranceProvider(IInsuranceProvider provider_, uint256 weight_) external onlyAdmin {
        require(providers.length == 0 ||
                provider_.epochDuration() == providers[0].epochDuration(), "SIV: same duration");
        require(provider_.paymentToken() == paymentToken, "SIV: payment token");
        require(providers.length < MAX_PROVIDERS, "SIV: max providers");

        uint256 sum = weight_;
        for (uint256 i = 0; i < weights.length; i++) {
            sum += weights[i];
        }

        require(sum < MAX_COMBINED_WEIGHT, "SIV: max weight");

        providers.push(provider_);
        weights.push(weight_);
    }

    function setWeight(uint256 index, uint256 weight_) external onlyAdmin {
        require(index < providers.length, "SIV: invalid index");
        uint256 sum = weight_;
        for (uint256 i = 0; i < weights.length; i++) {
            if (i == index) continue;
            sum += weights[i];
        }

        require(sum < MAX_COMBINED_WEIGHT, "SIV: max weight");

        weights[index] = weight_;
    }

    function _projectEpochYield() internal returns (uint256) {
        // Assume all providers have same epoch duration, this is asserted elsewhere
        IInsuranceProvider provider0 = providers[0];
        uint256 epochDuration = provider0.epochDuration();
        return oracle.projectYield(yieldSource.amountGenerator(), epochDuration);
    }

    function pendingInsurancePayouts() external view returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < providers.length; i++) {
            sum += providers[i].pendingPayouts();
        }
        return sum;
    }

    function claimVaultPayouts() external {
        for (uint256 i = 0; i < providers.length; i++) {
            IERC20 pt = providers[i].paymentToken();
            uint256 before = pt.balanceOf(address(this));
            uint256 amount = providers[i].claimPayouts();
            assert(amount == pt.balanceOf(address(this)) - before);
            if (amount > 0) {
                EpochInfo[] storage infos = providerEpochs[address(providers[i])];
                infos[infos.length - 1].payout += amount;
            }
        }
    }

    function _purchaseForNextEpoch(uint256 i, uint256 amount) internal {
        IInsuranceProvider provider = providers[i];
        require(provider.isNextEpochPurchasable(), "SIV: not purchasable");

        uint256 nextEpochId = provider.nextEpoch();
        EpochInfo[] storage epochs = providerEpochs[address(provider)];
        if (epochs.length == 0 || epochs[epochs.length - 1].epochId != nextEpochId) {
            epochs.push(EpochInfo(nextEpochId, 0, 0, 0));
        }
        EpochInfo storage epochInfo = epochs[epochs.length - 1];
        require(epochInfo.premiumPaid == 0, "SIV: already purchased");

        uint256 weight = weights[i];

        IERC20(provider.paymentToken()).approve(address(provider), amount);
        provider.purchaseForNextEpoch(amount);
        epochInfo.premiumPaid = amount;
    }

    function _unlockIfNeeded() internal {
        if (dlxId == 0) return;
        if (dlxSwap.slice().remaining(dlxId) != 0) return;
        dlxSwap.slice().unlockDebtSlice(dlxId);
        dlxId = 0;
    }

    // `minBps` is the minimum yield fronted from Delorean, in terms of basis points.
    function purchaseInsuranceForNextEpoch(uint256 minBps, uint256 projectedYield) external onlyAdmin {
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
        (uint256 id,
         uint256 actualOut) = dlxSwap.lockForYield(address(this),
                                                   amountLock,
                                                   sum,
                                                   minOut,
                                                   0,
                                                   new bytes(0));
        dlxId = id;

        // Purchase insurance via Y2K
        for (uint256 i = 0; i < providers.length; i++) {
            uint256 amount = (actualOut * weights[i]) / WEIGHTS_PRECISION;
            if (amount == 0) continue;
            _purchaseForNextEpoch(i, amount);
        }
    }
}
