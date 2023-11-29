// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./TierToken.sol";
import "./SyrupBar.sol";

interface IMigratorChef {
	// Perform LP token migration from legacy TierSwap to TierSwap.
	// Take the current LP token address and return the new LP token address.
	// Migrator should have full access to the caller's LP token.
	// Return the new LP token address.
	//
	// XXX Migrator must have allowance access to TierSwap LP tokens.
	// TierSwap must mint EXACTLY the same amount of TierSwap LP tokens or
	// else something bad will happen. Traditional TierSwap does not
	// do that so be careful!
	function migrate(IERC20 token) external returns (IERC20);
}

// MasterChef is the master of Tier. He can make Tier and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Tier is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
	using SafeMath for uint256;
	using SafeERC20 for IERC20;

	// Info of each user.
	struct UserInfo {
		uint256 amount; // How many LP tokens the user has provided.
		uint256 rewardDebt; // Reward debt. See explanation below.
		//
		// We do some fancy math here. Basically, any point in time, the amount of TIEs
		// entitled to a user but is pending to be distributed is:
		//
		//   pending reward = (user.amount * pool.accTierPerShare) - user.rewardDebt
		//
		// Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
		//   1. The pool's `accTierPerShare` (and `lastRewardBlock`) gets updated.
		//   2. User receives the pending reward sent to his/her address.
		//   3. User's `amount` gets updated.
		//   4. User's `rewardDebt` gets updated.
	}

	// Info of each pool.
	struct PoolInfo {
		IERC20 lpToken; // Address of LP token contract.
		uint256 allocPoint; // How many allocation points assigned to this pool. TIEs to distribute per block.
		uint256 lastRewardBlock; // Last block number that TIEs distribution occurs.
		uint256 accTierPerShare; // Accumulated TIEs per share, times 1e12. See below.
	}

	// The TIE TOKEN!
	TierToken public tier;
	// The SYRUP TOKEN!
	SyrupBar public syrup;
	// Dev address.
	address public devaddr;
	// TIE tokens created per block.
	uint256 public tierPerBlock;
	// Bonus muliplier for early tier makers.
	uint256 public BONUS_MULTIPLIER = 1;
	// The migrator contract. It has a lot of power. Can only be set through governance (owner).
	IMigratorChef public migrator;

	// Info of each pool.
	PoolInfo[] public poolInfo;
	// Info of each user that stakes LP tokens.
	mapping(uint256 => mapping(address => UserInfo)) public userInfo;
	// Total allocation points. Must be the sum of all allocation points in all pools.
	uint256 public totalAllocPoint = 0;
	// The block number when TIE mining starts.
	uint256 public startBlock;

	event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
	event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
	event EmergencyWithdraw(
		address indexed user,
		uint256 indexed pid,
		uint256 amount
	);

	constructor(
		TierToken _tier,
		SyrupBar _syrup,
		address _devaddr,
		uint256 _tierPerBlock,
		uint256 _startBlock
	) public {
		tier = _tier;
		syrup = _syrup;
		devaddr = _devaddr;
		tierPerBlock = _tierPerBlock;
		startBlock = _startBlock;

		// staking pool
		poolInfo.push(
			PoolInfo({
				lpToken: _tier,
				allocPoint: 1000,
				lastRewardBlock: startBlock,
				accTierPerShare: 0
			})
		);

		totalAllocPoint = 1000;
	}

	function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
		BONUS_MULTIPLIER = multiplierNumber;
	}

	function poolLength() external view returns (uint256) {
		return poolInfo.length;
	}

	// Add a new lp to the pool. Can only be called by the owner.
	// XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
	function add(
		uint256 _allocPoint,
		IERC20 _lpToken,
		bool _withUpdate
	) public onlyOwner {
		if (_withUpdate) {
			massUpdatePools();
		}
		uint256 lastRewardBlock = block.number > startBlock
			? block.number
			: startBlock;
		totalAllocPoint = totalAllocPoint.add(_allocPoint);
		poolInfo.push(
			PoolInfo({
				lpToken: _lpToken,
				allocPoint: _allocPoint,
				lastRewardBlock: lastRewardBlock,
				accTierPerShare: 0
			})
		);
		updateStakingPool();
	}

	// Update the given pool's TIE allocation point. Can only be called by the owner.
	function set(
		uint256 _pid,
		uint256 _allocPoint,
		bool _withUpdate
	) public onlyOwner {
		if (_withUpdate) {
			massUpdatePools();
		}
		uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
		poolInfo[_pid].allocPoint = _allocPoint;
		if (prevAllocPoint != _allocPoint) {
			totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(
				_allocPoint
			);
			updateStakingPool();
		}
	}

	function updateStakingPool() internal {
		uint256 length = poolInfo.length;
		uint256 points = 0;
		for (uint256 pid = 1; pid < length; ++pid) {
			points = points.add(poolInfo[pid].allocPoint);
		}
		if (points != 0) {
			points = points.div(3);
			totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(
				points
			);
			poolInfo[0].allocPoint = points;
		}
	}

	// Set the migrator contract. Can only be called by the owner.
	function setMigrator(IMigratorChef _migrator) public onlyOwner {
		migrator = _migrator;
	}

	// Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
	function migrate(uint256 _pid) public {
		require(address(migrator) != address(0), "migrate: no migrator");
		PoolInfo storage pool = poolInfo[_pid];
		IERC20 lpToken = pool.lpToken;
		uint256 bal = lpToken.balanceOf(address(this));
		lpToken.safeApprove(address(migrator), bal);
		IERC20 newLpToken = migrator.migrate(lpToken);
		require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
		pool.lpToken = newLpToken;
	}

	// Return reward multiplier over the given _from to _to block.
	function getMultiplier(
		uint256 _from,
		uint256 _to
	) public view returns (uint256) {
		return _to.sub(_from).mul(BONUS_MULTIPLIER);
	}

	// View function to see pending TIEs on frontend.
	function pendingTier(
		uint256 _pid,
		address _user
	) external view returns (uint256) {
		PoolInfo storage pool = poolInfo[_pid];
		UserInfo storage user = userInfo[_pid][_user];
		uint256 accTierPerShare = pool.accTierPerShare;
		uint256 lpSupply = pool.lpToken.balanceOf(address(this));
		if (block.number > pool.lastRewardBlock && lpSupply != 0) {
			uint256 multiplier = getMultiplier(
				pool.lastRewardBlock,
				block.number
			);
			uint256 tierReward = multiplier
				.mul(tierPerBlock)
				.mul(pool.allocPoint)
				.div(totalAllocPoint);
			accTierPerShare = accTierPerShare.add(
				tierReward.mul(1e12).div(lpSupply)
			);
		}
		return user.amount.mul(accTierPerShare).div(1e12).sub(user.rewardDebt);
	}

	// Update reward variables for all pools. Be careful of gas spending!
	function massUpdatePools() public {
		uint256 length = poolInfo.length;
		for (uint256 pid = 0; pid < length; ++pid) {
			updatePool(pid);
		}
	}

	// Update reward variables of the given pool to be up-to-date.
	function updatePool(uint256 _pid) public {
		PoolInfo storage pool = poolInfo[_pid];
		if (block.number <= pool.lastRewardBlock) {
			return;
		}
		uint256 lpSupply = pool.lpToken.balanceOf(address(this));
		if (lpSupply == 0) {
			pool.lastRewardBlock = block.number;
			return;
		}
		uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
		uint256 tierReward = multiplier
			.mul(tierPerBlock)
			.mul(pool.allocPoint)
			.div(totalAllocPoint);
		tier.mint(devaddr, tierReward.div(10));
		tier.mint(address(syrup), tierReward);
		pool.accTierPerShare = pool.accTierPerShare.add(
			tierReward.mul(1e12).div(lpSupply)
		);
		pool.lastRewardBlock = block.number;
	}

	// Deposit LP tokens to MasterChef for TIE allocation.
	function deposit(uint256 _pid, uint256 _amount) public {
		require(_pid != 0, "deposit TIE by staking");

		PoolInfo storage pool = poolInfo[_pid];
		UserInfo storage user = userInfo[_pid][msg.sender];
		updatePool(_pid);
		if (user.amount > 0) {
			uint256 pending = user
				.amount
				.mul(pool.accTierPerShare)
				.div(1e12)
				.sub(user.rewardDebt);
			if (pending > 0) {
				safeTierTransfer(msg.sender, pending);
			}
		}
		if (_amount > 0) {
			pool.lpToken.safeTransferFrom(
				address(msg.sender),
				address(this),
				_amount
			);
			user.amount = user.amount.add(_amount);
		}
		user.rewardDebt = user.amount.mul(pool.accTierPerShare).div(1e12);
		emit Deposit(msg.sender, _pid, _amount);
	}

	// Withdraw LP tokens from MasterChef.
	function withdraw(uint256 _pid, uint256 _amount) public {
		require(_pid != 0, "withdraw TIE by unstaking");
		PoolInfo storage pool = poolInfo[_pid];
		UserInfo storage user = userInfo[_pid][msg.sender];
		require(user.amount >= _amount, "withdraw: not good");

		updatePool(_pid);
		uint256 pending = user.amount.mul(pool.accTierPerShare).div(1e12).sub(
			user.rewardDebt
		);
		if (pending > 0) {
			safeTierTransfer(msg.sender, pending);
		}
		if (_amount > 0) {
			user.amount = user.amount.sub(_amount);
			pool.lpToken.safeTransfer(address(msg.sender), _amount);
		}
		user.rewardDebt = user.amount.mul(pool.accTierPerShare).div(1e12);
		emit Withdraw(msg.sender, _pid, _amount);
	}

	// Stake TIE tokens to MasterChef
	function enterStaking(uint256 _amount) public {
		PoolInfo storage pool = poolInfo[0];
		UserInfo storage user = userInfo[0][msg.sender];
		updatePool(0);
		if (user.amount > 0) {
			uint256 pending = user
				.amount
				.mul(pool.accTierPerShare)
				.div(1e12)
				.sub(user.rewardDebt);
			if (pending > 0) {
				safeTierTransfer(msg.sender, pending);
			}
		}
		if (_amount > 0) {
			pool.lpToken.safeTransferFrom(
				address(msg.sender),
				address(this),
				_amount
			);
			user.amount = user.amount.add(_amount);
		}
		user.rewardDebt = user.amount.mul(pool.accTierPerShare).div(1e12);

		syrup.mint(msg.sender, _amount);
		emit Deposit(msg.sender, 0, _amount);
	}

	// Withdraw TIE tokens from STAKING.
	function leaveStaking(uint256 _amount) public {
		PoolInfo storage pool = poolInfo[0];
		UserInfo storage user = userInfo[0][msg.sender];
		require(user.amount >= _amount, "withdraw: not good");
		updatePool(0);
		uint256 pending = user.amount.mul(pool.accTierPerShare).div(1e12).sub(
			user.rewardDebt
		);
		if (pending > 0) {
			safeTierTransfer(msg.sender, pending);
		}
		if (_amount > 0) {
			user.amount = user.amount.sub(_amount);
			pool.lpToken.safeTransfer(address(msg.sender), _amount);
		}
		user.rewardDebt = user.amount.mul(pool.accTierPerShare).div(1e12);

		syrup.burn(msg.sender, _amount);
		emit Withdraw(msg.sender, 0, _amount);
	}

	// Withdraw without caring about rewards. EMERGENCY ONLY.
	function emergencyWithdraw(uint256 _pid) public {
		PoolInfo storage pool = poolInfo[_pid];
		UserInfo storage user = userInfo[_pid][msg.sender];
		pool.lpToken.safeTransfer(address(msg.sender), user.amount);
		emit EmergencyWithdraw(msg.sender, _pid, user.amount);
		user.amount = 0;
		user.rewardDebt = 0;
	}

	// Safe tier transfer function, just in case if rounding error causes pool to not have enough TIES.
	function safeTierTransfer(address _to, uint256 _amount) internal {
		syrup.safeTierTransfer(_to, _amount);
	}

	// Update dev address by the previous dev.
	function dev(address _devaddr) public {
		require(msg.sender == devaddr, "dev: wut?");
		devaddr = _devaddr;
	}
}
