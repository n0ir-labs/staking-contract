# N0IR Staking Contract

On-chain staking contract for the **$N0IR** token, built on the battle-tested [Synthetix StakingRewards](https://github.com/Synthetix-io/synthetix/blob/develop/contracts/StakingRewards.sol) model. Deployed on **Base** (EVM).

## Overview

The N0IR Staking Contract allows $N0IR holders to stake their tokens and earn rewards proportionally. Rewards are distributed on-chain via a time-based reward rate — the same mechanism used by Synthetix, Curve, and many other leading DeFi protocols.

### Key Features

- **Proportional Reward Distribution** — Rewards accrue per second, proportional to each staker's share of the total staked pool.
- **Owner-Funded Reward Periods** — The contract owner funds discrete reward periods (default: 30 days) by calling `notifyRewardAmount()`. Leftover rewards from an active period roll into the next.
- **Cooldown Unstaking** — Unstaking requires a cooldown period (default: 14 days) to prevent flash-stake attacks and ensure protocol stability.
- **Cancel Unstake** — Users can cancel a pending unstake to re-stake their tokens without waiting for cooldown.
- **Non-Upgradeable** — Simple, auditable, immutable contract with no proxy pattern.

## Architecture

```
Owner funds reward period
        │
        ▼
notifyRewardAmount(reward)
        │
        ▼
rewardRate = reward / duration
        │
        ▼
┌───────────────────────────────────┐
│  Reward Period (30 days default)  │
│                                   │
│  rewardPerToken accumulates       │
│  proportional to time × rate      │
│  divided by totalStaked           │
└───────────────────────────────────┘
        │
        ▼
Users call claimReward() anytime
```

### Staking Flow

1. **Stake** — User approves and stakes $N0IR tokens. Staked balance accrues rewards immediately.
2. **Earn** — Rewards accrue every second based on the user's share of the pool.
3. **Claim** — User calls `claimReward()` to collect accrued $N0IR rewards at any time.
4. **Unstake** — User calls `requestUnstake()` to begin cooldown, then `completeUnstake()` after the cooldown period.

### Reward Mechanics (Synthetix Model)

The contract tracks a global `rewardPerToken` value that increases over time:

```
rewardPerToken += (elapsed × rewardRate × 1e18) / totalStaked
```

Each user's earned rewards are calculated as:

```
earned = stakedBalance × (rewardPerToken - userRewardPerTokenPaid) / 1e18 + rewards
```

This ensures:
- Rewards are distributed proportionally to stake size
- New stakers don't dilute past rewards
- Users can claim at any time without affecting others
- Gas-efficient (no loops over stakers)

## Contract Interface

### User Functions

| Function | Description |
|----------|-------------|
| `stake(uint256 amount)` | Stake $N0IR tokens |
| `requestUnstake(uint256 amount)` | Begin unstake cooldown |
| `completeUnstake()` | Withdraw tokens after cooldown |
| `cancelUnstake()` | Cancel pending unstake, re-stake tokens |
| `claimReward()` | Claim all accrued $N0IR rewards |

### View Functions

| Function | Returns |
|----------|---------|
| `getStakedBalance(address)` | User's staked balance |
| `getPendingUnstake(address)` | Pending unstake amount and availability timestamp |
| `getTotalStaked()` | Total $N0IR staked in the contract |
| `earned(address)` | User's unclaimed reward balance |
| `getRewardForDuration()` | Total rewards for the current period |
| `rewardPerToken()` | Current cumulative reward per staked token |

### Owner Functions

| Function | Description |
|----------|-------------|
| `setToken(address)` | Set $N0IR token address (one-time) |
| `notifyRewardAmount(uint256)` | Fund a new reward period |
| `setRewardsDuration(uint256)` | Change reward period length (only between periods) |
| `setCooldownPeriod(uint256)` | Update unstake cooldown duration |

## Security

- **OpenZeppelin Ownable** — Owner-only administrative functions
- **OpenZeppelin ReentrancyGuard** — Protection against reentrancy on all state-changing functions
- **SafeERC20** — Safe token transfer wrappers
- **One-Time Token Set** — Token address can only be configured once via `setToken()`
- **Cooldown Enforcement** — Unstaking requires waiting the full cooldown period
- **No Proxy / No Upgradeability** — Contract is immutable once deployed

## Configuration Defaults

| Parameter | Default | Configurable |
|-----------|---------|--------------|
| Cooldown Period | 14 days | Yes (owner) |
| Rewards Duration | 30 days | Yes (owner, between periods) |
| Token Address | Set post-deploy | One-time only |

## Dependencies

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) v4.x
  - `IERC20`, `SafeERC20`, `Ownable`, `ReentrancyGuard`

## License

MIT
