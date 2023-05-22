// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";

import {IYieldSource} from "../interfaces/IYieldSource.sol";
import {IInsuranceProvider} from "../interfaces/IInsuranceProvider.sol";

// TODO Shortfalls
// - other emissions
// - accurate share calculation(shares deposited during epoch is not eligible for that epoch)
// - calc payout based on deposited rewards

/// @title Self Insured Vault(SIV) contract
/// @author Delorean Exchange x Y2K Finance
/// @dev All function calls are currently implemented without side effects
contract SelfInsuredVault is Ownable {
    using SafeERC20 for IERC20;
    using SafeCast for int256;

    struct UserInfo {
        uint256 share;
        int256 payoutDebt;
    }

    uint256 public constant PRECISION_FACTOR = 10 ** 18;
    uint256 public constant MAX_COMBINED_WEIGHT = 20_00;
    uint256 public constant MAX_PROVIDERS = 10;

    // -- Global State -- //

    /// @notice Token for yield
    IERC20 public immutable depositToken;

    /// @notice Token to be paid in for insurance
    IERC20 public immutable paymentToken;

    /// @notice Yield source contract
    IYieldSource public immutable yieldSource;

    /// @notice Array of Insurance Providers, i.e strategies for different vaults
    IInsuranceProvider[] public providers;

    /// @notice Weight of each insurance vaults
    uint256[] public weights;

    /// @notice Total weight
    uint256 public totalWeight;

    // -- Share and Payout Info -- //

    /// @notice Global payout per share
    uint256 public accPayoutPerShare;

    /// @notice User Share info
    mapping(address => UserInfo) public userInfos;

    /// @notice Epoch Id when deposit, provider => epochId
    mapping(address => uint256) public depositEpochIds;

    // -- Events -- //

    /// @notice Emitted when `user` claimed payout
    event ClaimPayouts(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Contract constructor
     * @param _paymentToken Token used for premium
     * @param _yieldSource Yield source contract address
     */
    constructor(address _paymentToken, address _yieldSource) {
        require(_yieldSource != address(0), "SIV: zero source");

        depositToken = IYieldSource(_yieldSource).sourceToken();
        paymentToken = IERC20(_paymentToken);
        yieldSource = IYieldSource(_yieldSource);
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN OPERATIONS
    //////////////////////////////////////////////////////////////*/

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

        totalWeight += _weight;
        require(totalWeight < MAX_COMBINED_WEIGHT, "SIV: max weight");

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
        totalWeight = totalWeight + _weight - weights[index];
        require(totalWeight < MAX_COMBINED_WEIGHT, "SIV: max weight");
        weights[index] = _weight;
    }

    /**
     * @notice Purchase Insurance
     */
    function purchaseInsuranceForNextEpoch() external onlyOwner {
        if (totalWeight == 0) return;

        uint256 totalYield = yieldSource.pendingYield();
        (, uint256 actualOut) = yieldSource.harvestAndConvert(
            paymentToken,
            totalYield
        );

        // Purchase insurance via Y2K
        for (uint256 i = 0; i < providers.length; i++) {
            uint256 amount = (actualOut * weights[i]) / totalWeight;
            if (amount > 0) {
                _purchaseForNextEpoch(i, amount);
            }
        }
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
     * @notice Returns pending payouts of an insurance
     */
    function pendingInsurancePayouts() public view returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < providers.length; i++) {
            sum += providers[i].pendingPayouts();
        }
        return sum;
    }

    /**
     * @notice Returns claimable payouts of `user`
     * @param user address for payout
     */
    function pendingPayouts(
        address user
    ) public view returns (uint256 pending) {
        // TODO: take care of depositEpochIDs

        UserInfo storage info = userInfos[user];
        uint256 newAccPayoutPerShare = accPayoutPerShare;
        uint256 totalShares = yieldSource.totalDeposit();
        if (totalShares != 0) {
            uint256 newPayout = pendingInsurancePayouts();
            newAccPayoutPerShare =
                newAccPayoutPerShare +
                (newPayout * PRECISION_FACTOR) /
                totalShares;
        }
        pending = (int256(
            (info.share * newAccPayoutPerShare) / PRECISION_FACTOR
        ) - info.payoutDebt).toUint256();
    }

    /*//////////////////////////////////////////////////////////////
                                USER OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit to SIV
     * @param amount of `paymentToken`
     * @param receiver for share
     */
    function deposit(uint256 amount, address receiver) public {
        claimVaultPayouts();

        // TODO: update depositEpochIds

        UserInfo storage user = userInfos[receiver];
        user.share += amount;
        user.payoutDebt =
            user.payoutDebt +
            int256((amount * accPayoutPerShare) / PRECISION_FACTOR);

        depositToken.safeTransferFrom(msg.sender, address(this), amount);
        if (depositToken.allowance(address(this), address(yieldSource)) != 0) {
            depositToken.safeApprove(address(yieldSource), 0);
        }
        depositToken.safeApprove(address(yieldSource), amount);
        yieldSource.deposit(amount);
    }

    /**
     * @notice Withdraw assets
     * @param amount to withdraw
     * @param to receiver address
     */
    function withdraw(uint256 amount, address to) public {
        claimVaultPayouts();

        UserInfo storage user = userInfos[msg.sender];
        user.payoutDebt =
            user.payoutDebt -
            int256((amount * accPayoutPerShare) / PRECISION_FACTOR);
        user.share -= amount;

        yieldSource.withdraw(amount, false, to);
    }

    /**
     * @notice Claim payouts
     */
    function claimPayouts() public {
        // TODO: take care of depositEpochIDs

        claimVaultPayouts();

        UserInfo storage user = userInfos[msg.sender];
        int256 accPayout = int256(
            (user.share * accPayoutPerShare) / PRECISION_FACTOR
        );
        uint256 pending = (accPayout - user.payoutDebt).toUint256();
        user.payoutDebt = accPayout;

        paymentToken.safeTransfer(msg.sender, pending);

        emit ClaimPayouts(msg.sender, pending);
    }

    /**
     * @notice Claim payout of a vault
     */
    function claimVaultPayouts() public {
        uint256 totalShares = yieldSource.totalDeposit();
        uint256 newPayout;
        for (uint256 i = 0; i < providers.length; i++) {
            newPayout += providers[i].claimPayouts();
        }
        if (totalShares != 0) {
            accPayoutPerShare =
                accPayoutPerShare +
                (newPayout * PRECISION_FACTOR) /
                totalShares;
        }
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Purchase next epoch
     * @param i Index of provider
     * @param amount of tokens for purchase
     */
    function _purchaseForNextEpoch(uint256 i, uint256 amount) internal {
        IInsuranceProvider provider = providers[i];
        require(provider.isNextEpochPurchasable(), "SIV: not purchasable");

        if (paymentToken.allowance(address(this), address(provider)) != 0) {
            paymentToken.safeApprove(address(provider), 0);
        }
        paymentToken.safeApprove(address(provider), amount);
        provider.purchaseForNextEpoch(amount);
    }
}
