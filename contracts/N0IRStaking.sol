// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title N0IRStaking
 * @notice Staking contract for $N0IR with on-chain reward distribution (Synthetix model).
 *         Stake tokens, earn rewards proportionally, unstake with cooldown.
 *         Owner funds reward periods via notifyRewardAmount().
 */
contract N0IRStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public n0irToken;
    bool public tokenSet;
    uint256 public cooldownPeriod = 14 days;
    uint256 public totalStaked;

    // --- Reward state (Synthetix pattern) ---
    uint256 public rewardRate;           // Tokens per second
    uint256 public rewardsDuration = 30 days;
    uint256 public periodFinish;         // When current reward period ends
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    struct StakeInfo {
        uint256 stakedBalance;
        uint256 pendingUnstakeAmount;
        uint256 unstakeRequestedAt;
    }

    mapping(address => StakeInfo) public stakes;

    event Staked(address indexed user, uint256 amount);
    event UnstakeRequested(address indexed user, uint256 amount, uint256 availableAt);
    event UnstakeCompleted(address indexed user, uint256 amount);
    event UnstakeCancelled(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardPeriodStarted(uint256 reward, uint256 duration);
    event CooldownPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event RewardsDurationUpdated(uint256 newDuration);
    event TokenSet(address token);

    constructor() {}

    // --- Reward accounting modifier ---

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    // --- Token setup ---

    function setToken(address _n0irToken) external onlyOwner {
        require(!tokenSet, "Token already set");
        require(_n0irToken != address(0), "Invalid token address");
        n0irToken = IERC20(_n0irToken);
        tokenSet = true;
        emit TokenSet(_n0irToken);
    }

    // --- Staking ---

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(tokenSet, "Token not set");
        require(amount > 0, "Amount must be > 0");

        n0irToken.safeTransferFrom(msg.sender, address(this), amount);

        stakes[msg.sender].stakedBalance += amount;
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    function requestUnstake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        StakeInfo storage info = stakes[msg.sender];
        require(amount > 0, "Amount must be > 0");
        require(info.stakedBalance >= amount, "Insufficient staked balance");
        require(info.pendingUnstakeAmount == 0, "Existing unstake pending");

        info.stakedBalance -= amount;
        info.pendingUnstakeAmount = amount;
        info.unstakeRequestedAt = block.timestamp;
        totalStaked -= amount;

        emit UnstakeRequested(msg.sender, amount, block.timestamp + cooldownPeriod);
    }

    function completeUnstake() external nonReentrant {
        StakeInfo storage info = stakes[msg.sender];
        require(info.pendingUnstakeAmount > 0, "No pending unstake");
        require(
            block.timestamp >= info.unstakeRequestedAt + cooldownPeriod,
            "Cooldown not elapsed"
        );

        uint256 amount = info.pendingUnstakeAmount;
        info.pendingUnstakeAmount = 0;
        info.unstakeRequestedAt = 0;

        n0irToken.safeTransfer(msg.sender, amount);

        emit UnstakeCompleted(msg.sender, amount);
    }

    function cancelUnstake() external nonReentrant updateReward(msg.sender) {
        StakeInfo storage info = stakes[msg.sender];
        require(info.pendingUnstakeAmount > 0, "No pending unstake");

        uint256 amount = info.pendingUnstakeAmount;
        info.pendingUnstakeAmount = 0;
        info.unstakeRequestedAt = 0;
        info.stakedBalance += amount;
        totalStaked += amount;

        emit UnstakeCancelled(msg.sender, amount);
    }

    // --- Rewards ---

    function claimReward() external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No rewards to claim");
        rewards[msg.sender] = 0;
        n0irToken.safeTransfer(msg.sender, reward);
        emit RewardClaimed(msg.sender, reward);
    }

    // --- View functions ---

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (
            (lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / totalStaked
        );
    }

    function earned(address account) public view returns (uint256) {
        return (
            stakes[account].stakedBalance * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18
        ) + rewards[account];
    }

    function getStakedBalance(address account) external view returns (uint256) {
        return stakes[account].stakedBalance;
    }

    function getPendingUnstake(address account) external view returns (uint256 amount, uint256 availableAt) {
        StakeInfo storage info = stakes[account];
        amount = info.pendingUnstakeAmount;
        availableAt = info.pendingUnstakeAmount > 0
            ? info.unstakeRequestedAt + cooldownPeriod
            : 0;
    }

    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    // --- Owner functions ---

    /**
     * @notice Fund a new reward period. Transfers N0IR from caller into the contract.
     * @param reward Amount of N0IR tokens to distribute over rewardsDuration
     */
    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0)) {
        require(tokenSet, "Token not set");
        n0irToken.safeTransferFrom(msg.sender, address(this), reward);

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        require(rewardRate > 0, "Reward rate = 0");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;

        emit RewardPeriodStarted(reward, rewardsDuration);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(block.timestamp > periodFinish, "Period not finished");
        require(_rewardsDuration > 0, "Duration must be > 0");
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(_rewardsDuration);
    }

    function setCooldownPeriod(uint256 _cooldownPeriod) external onlyOwner {
        emit CooldownPeriodUpdated(cooldownPeriod, _cooldownPeriod);
        cooldownPeriod = _cooldownPeriod;
    }
}
