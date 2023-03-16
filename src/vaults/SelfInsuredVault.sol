// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { ERC20 } from  "openzeppelin/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import { IYieldSource } from "../interfaces/IYieldSource.sol";
import { ISelfInsuredVault } from "../interfaces/ISelfInsuredVault.sol";
import { IInsuranceProvider } from "../interfaces/IInsuranceProvider.sol";

contract SelfInsuredVault is ISelfInsuredVault, ERC20 {
    using SafeERC20 for IERC20;

    // ----

    // NOTE: Epoch ID's are assumed to be synchronized across providers
    struct UserEpochTracker {
        uint256 startEpochId;
        uint256 shares;

        uint256 nextEpochId;
        uint256 nextShares;

        uint256 accumulatdPayouts;
    }
    // user address -> tracker
    mapping(address => UserEpochTracker) public userEpochTrackers;

    // ----

    struct EpochInfo {
        uint256 epochId;      // Timestamp of epoch start
        uint256 totalShares;  // Total shares during this epoch
        uint256 payout;       // Payout of this epoch, if any
        uint256 premiumPaid;  // If zero, insurance has not yet been purchased
    }
    // provider address -> epoch info
    mapping(address => EpochInfo[]) public providerEpochs;

    struct UserEpochInfo {
        uint256 shares;   // Number of shares for the user
        uint256 claimed;  // Amount paid out to the user
    }
    struct UserInfo {
        // Yield from underlying
        uint256 accumulatedYieldPerToken;
        uint256 accumulatedYield;
    }
    mapping(address => UserInfo) public userInfos;
    // Epoch accounting, epoch id => info
    mapping(address => mapping(uint256 => UserEpochInfo)) public userEpochs;

    uint256 public constant PRECISION_FACTOR = 10**18;

    address public admin;
    IInsuranceProvider[] public providers;
    uint256[] public weights;
    address[] public rewardTokens;

    IYieldSource public immutable yieldSource;

    // Rewards accounting
    uint256 public yieldPerTokenStored;
    uint256 public lastUpdateBlock;
    uint256 public lastUpdateCumulativeYield;
    uint256 public harvestedYield;

    modifier onlyAdmin {
        require(msg.sender == admin, "SIV: only admin");
        _;
    }

    constructor(string memory name_, string memory symbol_, address yieldSource_) ERC20(name_, symbol_) {
        admin = msg.sender;

        yieldSource = IYieldSource(yieldSource_);
        rewardTokens = new address[](1);
        rewardTokens[0] = IYieldSource(yieldSource_).yieldToken();
    }

    function providersLength() public view returns (uint256) {
        return providers.length;
    }

    function epochsLength(address provider) public view returns (uint256) {
        return providerEpochs[provider].length;
    }

    // -- ERC4642: Asset -- //
    function _asset() private view returns (address) {
        return yieldSource.generatorToken();
    }

    function asset() external view returns (address) {
        return _asset();
    }

    function totalAssets() external view returns (uint256) {
        return this.totalSupply();
    }

    // -- ERC4642: Share conversion -- //
    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        return 0;
    }

    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        return 0;
    }

    // -- ERC4642: Deposit -- //
    function maxDeposit(address receiver) external view returns (uint256 shares) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        shares = assets;
    }

    function _harvest() internal {
        uint256 pending = yieldSource.amountPending(address(this));
        yieldSource.harvest();
        harvestedYield += pending;
    }

    function cumulativeYield() external view returns (uint256) {
        return _cumulativeYield();
    }

    function _cumulativeYield() private view returns (uint256) {
        uint256 ap = yieldSource.amountPending(address(this));
        return harvestedYield + ap;
    }

    function _yieldPerToken() internal view returns (uint256) {
        if (this.totalAssets() == 0) return yieldPerTokenStored;
        if (block.number == lastUpdateBlock) return yieldPerTokenStored;
        
        uint256 deltaYield = _cumulativeYield() - lastUpdateCumulativeYield;
        return yieldPerTokenStored + (deltaYield * PRECISION_FACTOR) / this.totalAssets();
    }

    function _calculatePendingYield(address user) internal view returns (uint256) {
        UserInfo storage info = userInfos[user];
        uint256 ypt = _yieldPerToken();
        return ((this.balanceOf(user) * (ypt - info.accumulatedYieldPerToken))) / PRECISION_FACTOR
            + info.accumulatedYield;
    }

    function calculatePendingYield(address user) external view returns (uint256) {
        return _calculatePendingYield(user);
    }

    function _updateYield(address user) internal {
        if (block.number != lastUpdateBlock) {
            yieldPerTokenStored = _yieldPerToken();
            lastUpdateBlock = block.number;
            lastUpdateCumulativeYield = _cumulativeYield();
        }

        userInfos[user].accumulatedYield = _calculatePendingYield(user);
        userInfos[user].accumulatedYieldPerToken = yieldPerTokenStored;
    }

    function _accumulateDepegRewards(address user) {
        UserEpochTracker storage tracker = userEpochTrackers[user];
        if (tracker.startEpochId == 0) return;
        if (tracker.shares == 0) return;

        for (uint256 i = 0; i < providers.length; i++) {
            IInsuranceProvider storage provider = providers[i];
            uint256 nextEpochId = provider.nextEpoch();
            EpochInfo[] storage infos = providerEpochs[address(provider)];
            // TODO: Use nextId field + mapping instead of list
            EpochInfo storage info;
            for (uint256 j = 0; j < infos.length; j++) {
                info = infos[j];
                if (info.epochId < tracker.startEpochId) continue;
                if (info.epochId >= tracker.nextEpochId) break;
                if (info.epochId == currentEpochId) break;
                tracker.accumulatdPayouts += (tracker.shares * info.payout) / info.totalShares;
            }
            tracker.startEpochId = info.epochId;
        }
    }

    function _updateUserEpochTracker(address user, int256 deltaShares) internal {
        UserEpochTracker storage tracker = userEpochTrackers[user];
        uint256 nextEpochId = provider.nextEpoch();

        // (1) See if we need to shift nextEpoch into start/end epoch segment
        if (nextEpochId != tracker.nextEpochId) {
            _accumulateDepegRewards(user);

            tracker.startEpochId = tracker.nextEpochId;
            tracker.shares = tracker.nextEpochShares;

            tracker.nextEpochShares = tracker.nextEpochId;
            tracker.nextShares = deltaShares > 0
                ? info.shares + uint256(deltaShares)
                : info.shares - uint256(-deltaShares);
        }

            // (2) Update nextEpoch
        }
    }

    function _updateUserEpochInfo(address user, int256 deltaShares) internal {
        for (uint256 i = 0; i < providers.length; i++) {
            // Update for the user
            uint256 nextEpochId = providers[i].nextEpoch();
            UserEpochInfo storage info = userEpochs[user][nextEpochId];
            info.shares = deltaShares > 0
                ? info.shares + uint256(deltaShares)
                : info.shares - uint256(-deltaShares);

            // Update for everyone
            EpochInfo[] storage epochs = providerEpochs[address(providers[i])];
            if (epochs.length == 0 || epochs[epochs.length - 1].epochId != nextEpochId) {
                epochs.push(EpochInfo(nextEpochId, 0, 0, 0));
            }
            EpochInfo storage epochInfo = epochs[epochs.length - 1];
            epochInfo.totalShares = deltaShares > 0
                ? epochInfo.totalShares + uint256(deltaShares)
                : epochInfo.totalShares - uint256(-deltaShares);
        }
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(assets <= this.maxDeposit(receiver), "SIV: max deposit");
        require(assets >= PRECISION_FACTOR, "SIV: min deposit");

        _updateYield(receiver);
        _updateUserEpochInfo(receiver, int256(assets));
        _updateUserEpochTracker(receiver, int256(assets), );

        IERC20(_asset()).safeTransferFrom(msg.sender, address(this), assets);
        shares = assets;
        _mint(receiver, shares);
    }

    // -- ERC4642: Mint -- //
    function maxMint(address receiver) external view returns (uint256 maxShares) {
        return 0;
    }

    function previewMint(uint256 shares) external view returns (uint256 assets) {
        return 0;
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        return 0;
    }

    // -- ERC4642: Withdraw -- //
    function maxWithdraw(address owner) external view returns (uint256 maxAssets) {
        return 0;
    }

    function previewWithdraw(uint256 assets) external view returns (uint256 shares) {
        return 0;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        return 0;
    }

    // -- ERC4642: Redeem -- //
    function maxRedeem(address owner) external view returns (uint256 maxShares) {
        return 0;
    }

    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        return 0;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        return 0;
    }

    // -- Rewards -- //
    function _previewClaimRewards(address who) internal returns (uint256[] memory result) {
        result = new uint256[](1);
        result[0] = _calculatePendingYield(who);
        return result;
    }

    function previewClaimRewards(address who) external returns (uint256[] memory result) {
        return _previewClaimRewards(who);
    }

    function claimRewards() external returns (uint256[] memory) {
        _harvest();

        uint256[] memory owed = _previewClaimRewards(msg.sender);

        require(owed.length == rewardTokens.length, "SIV: claim1");
        require(rewardTokens[0] == yieldSource.yieldToken(), "SIV: claim2");

        _updateYield(msg.sender);
        require(owed[0] == userInfos[msg.sender].accumulatedYield, "SIV: claim3");

        userInfos[msg.sender].accumulatedYield = 0;

        for (uint8 i = 0; i < uint8(owed.length); i++) {
            IERC20(rewardTokens[i]).safeTransfer(msg.sender, owed[i]);
        }
        return owed;
    }

    // -- Admin only -- //
    function setAdmin(address) external onlyAdmin {
    }

    function setInsuranceProviders(IInsuranceProvider[] calldata providers_, uint256[] calldata weights_) external onlyAdmin {
        // TODO: changing this mid-epoch will cause problems, find a solution.
        // TODO: possible fix is to only allow adding new providers, and adjusting
        // the weights of previous ones to 0
        providers = providers_;
        weights = weights_;
    }

    function _projectEpochYield() internal returns (uint256) {
        // Assume all providers have same epoch duration
        IInsuranceProvider provider0 = providers[0];
        uint256 epochDuration = provider0.epochDuration();

        // TODO: For now, this is hard coding the forward looking yield rate.
        // We need to add a way to estimate this, either let the admin account
        // set it, or estimate it based on historical data.
        uint256 yieldPerUnderlyingPerSecond = (100 * PRECISION_FACTOR) / 10e10;

        return (epochDuration * this.totalSupply() * yieldPerUnderlyingPerSecond) / PRECISION_FACTOR;
    }

    function _purchaseForNextEpoch(uint256 i, uint256 projectedYield) internal {
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
        uint256 amount = (weight * projectedYield) / 100_00;
        console.log("Purchase", amount);
        console.log("paymentToken", address(provider.paymentToken()));
        console.log("paymentToken balance", provider.paymentToken().balanceOf(address(this)));

        IERC20(provider.paymentToken()).approve(address(provider), amount);
        provider.purchaseForNextEpoch(amount);
        epochInfo.premiumPaid = amount;
    }

    function purchaseForNextEpoch() external onlyAdmin {
        uint256 projectedYield = _projectEpochYield();
        console.log("projectedYield", projectedYield);

        for (uint256 i = 0; i < providers.length; i++) {
            _purchaseForNextEpoch(i, projectedYield);
        }
    }
}
