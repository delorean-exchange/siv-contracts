// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IYieldSource.sol";
import "../interfaces/ISelfInsuredVault.sol";

import "forge-std/console.sol";

contract SelfInsuredVault is ISelfInsuredVault, ERC20 {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 accumulatedYieldPerToken;
        uint256 accumulatedYield;
    }
    mapping(address => UserInfo) public userInfos;

    uint256 public constant PRECISION_FACTOR = 10**18;

    address public admin;
    address[] public insurances;
    uint256[] public ratios;
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

    constructor(string memory name_,
                string memory symbol_,
                address yieldSource_) ERC20(name_, symbol_) {
        yieldSource = IYieldSource(yieldSource_);
        rewardTokens = new address[](1);
        rewardTokens[0] = IYieldSource(yieldSource_).yieldToken();
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

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(assets <= this.maxDeposit(receiver), "SIV: max deposit");
        require(assets >= PRECISION_FACTOR, "SIV: min deposit");

        _updateYield(receiver);

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
    function _previewClaim(address who) internal returns (uint256[] memory result) {
        result = new uint256[](1);
        result[0] = _calculatePendingYield(who);
        return result;
    }

    function previewClaim(address who) external returns (uint256[] memory result) {
        return _previewClaim(who);
    }

    function claim() external returns (uint256[] memory) {
        _harvest();

        uint256[] memory owed = _previewClaim(msg.sender);

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

    function setInsurances(address[] calldata, uint256[] calldata) external onlyAdmin {
    }
}
