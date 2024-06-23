// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/ISalesFactory.sol";

contract AllocationStaking is OwnableUpgradeable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.每个用户的信息
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.用户提供了多少 LP 代币。
        uint256 rewardDebt; // Reward debt. Current reward debt when user joined farm. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of ERC20s
        // entitled to a user but is pending to be distributed is:
        //奖励债务。用户加入农场时的当前奖励债务。见下文解释
        //我们在这里做了一些花哨的数学运算。基本上，在任何时间点，用户有权获得但待分配的 ERC20 数量是：
        //
        //   pending reward = (user.amount * pool.accERC20PerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //每当用户将 LP 代币存入或提取到池中时。以下是发生的事情：
        //   1. The pool's `accERC20PerShare` (and `lastRewardBlock`) gets updated.池的 `accERC20PerShare`（和 `lastRewardBlock`）会更新。
        //   2. User receives the pending reward sent to his/her address.用户收到发送到其地址的待定奖励。
        //   3. User's `amount` gets updated.用户的 `amount` 会更新
        //   4. User's `rewardDebt` gets updated.用户的 `rewardDebt` 会更新。
        uint256 tokensUnlockTime; // If user registered for sale, returns when tokens are getting unlocked。如果用户注册出售，则在代币解锁时返回
        address [] salesRegistered;
    }

    // Info of each pool.每个池的信息
    struct PoolInfo {
        IERC20 lpToken;             // Address of LP token contract.LP 代币合约的地址。
        uint256 allocPoint;         // How many allocation points assigned to this pool. ERC20s to distribute per block.分配给此池的分配点数。每个区块分配的 ERC20。
        uint256 lastRewardTimestamp;    // Last timstamp that ERC20s distribution occurs.ERC20 分配发生的最后时间戳。
        uint256 accERC20PerShare;   // Accumulated ERC20s per share, times 1e36.每股累计 ERC20，乘以 1e36。
        uint256 totalDeposits; // Total amount of tokens deposited at the moment (staked)。当前存入的代币总量（质押）
    }


    // Address of the ERC20 Token contract.ERC20 代币合约的地址。
    IERC20 public erc20;
    // The total amount of ERC20 that's paid out as reward.作为奖励支付的 ERC20 总量。
    uint256 public paidOut;
    // ERC20 tokens rewarded per second.每秒奖励的 ERC20 代币。
    uint256 public rewardPerSecond;
    // Total rewards added to farm。添加到农场的总奖励
    uint256 public totalRewards;
    // Address of sales factory contract。销售工厂合约的地址
    ISalesFactory public salesFactory;
    // Info of each pool.每个池的信息。
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.质押 LP 代币的每个用户的信息。
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.总分配点。必须是所有池中所有分配点的总和。
    uint256 public totalAllocPoint;

    // The timestamp when farming starts.农场开始的时间戳。
    uint256 public startTimestamp;
    // The timestamp when farming ends.农场结束的时间戳。
    uint256 public endTimestamp;

    // Events
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);//存款
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);//取款
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);//紧急取款
    event CompoundedEarnings(address indexed user, uint256 indexed pid, uint256 amountAdded, uint256 totalDeposited);//复合收益

    // Restricting calls to only verified sales。限制仅对经过验证的销售进行调用
    modifier onlyVerifiedSales {
        require(salesFactory.isSaleCreatedThroughFactory(msg.sender), "Sale not created through factory.");
        _;
    }

    function initialize(
        address _ownable,
        IERC20 _erc20,
        uint256 _rewardPerSecond,
        uint256 _startTimestamp,
        address _salesFactory
    )
    initializer
    public
    {
        __Ownable_init(_ownable);

        erc20 = _erc20;
        rewardPerSecond = _rewardPerSecond;
        startTimestamp = _startTimestamp;
        endTimestamp = _startTimestamp;
        // Create sales factory contract
        salesFactory = ISalesFactory(_salesFactory);
    }

    // Function where owner can set sales factory in case of upgrading some of smart-contracts
    //所有者可以在升级某些智能合约时设置销售工厂的功能
    function setSalesFactory(address _salesFactory) external onlyOwner {
        require(_salesFactory != address(0));
        salesFactory = ISalesFactory(_salesFactory);
    }

    // Number of LP pools
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Fund the farm, increase the end block。给farm注资,设定结束时间
    function fund(uint256 _amount) public {
        require(block.timestamp < endTimestamp, "fund: too late, the farm is closed");
        erc20.safeTransferFrom(address(msg.sender), address(this), _amount);
        endTimestamp += _amount.div(rewardPerSecond);
        totalRewards = totalRewards.add(_amount);
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    //添加新的 LP 池中。只能由所有者调用。
    //请勿多次添加相同的 LP 代币。如果这样做，奖励将会混乱。
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        // Push new PoolInfo
        poolInfo.push(
            PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardTimestamp : lastRewardTimestamp,
        accERC20PerShare : 0,
        totalDeposits : 0
        })
        );
    }

    // Update the given pool's ERC20 allocation point. Can only be called by the owner.
    //更新给定池的 ERC20 分配点。只能由所有者调用。
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // View function to see deposited LP for a user.
    function deposited(uint256 _pid, address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.amount;
    }

    // View function to see pending ERC20s for a user.查看用户的pending ERC20。
    function pending(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accERC20PerShare = pool.accERC20PerShare;

        uint256 lpSupply = pool.totalDeposits;

        // Compute pending ERC20s
        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 lastTimestamp = block.timestamp < endTimestamp ? block.timestamp : endTimestamp;
            uint256 nrOfSeconds = lastTimestamp.sub(pool.lastRewardTimestamp);
            uint256 erc20Reward = nrOfSeconds.mul(rewardPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accERC20PerShare = accERC20PerShare.add(erc20Reward.mul(1e36).div(lpSupply));
        }
        return user.amount.mul(accERC20PerShare).div(1e36).sub(user.rewardDebt);
    }

    // View function for total reward the farm has yet to pay out.
    // NOTE: this is not necessarily the sum of all pending sums on all pools and users
    //      example 1: when tokens have been wiped by emergency withdraw
    //      example 2: when one pool has no LP supply
    //查看农场尚未支付的总奖励的函数。
    //注意：这不一定是所有池和用户的所有待处理金额的总和
    //示例 1：当代币已被紧急提款清除时
    //示例 2：当一个池没有 LP 供应时
    function totalPending() external view returns (uint256) {
        if (block.timestamp <= startTimestamp) {
            return 0;
        }

        uint256 lastTimestamp = block.timestamp < endTimestamp ? block.timestamp : endTimestamp;
        return rewardPerSecond.mul(lastTimestamp - startTimestamp).sub(paidOut);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    //更新所有池的奖励变量。小心 gas 支出！
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function setTokensUnlockTime(uint256 _pid, address _user, uint256 _tokensUnlockTime) external onlyVerifiedSales {
        UserInfo storage user = userInfo[_pid][_user];
        // Require that tokens are currently unlocked.要求代币当前处于解锁状态
        require(user.tokensUnlockTime <= block.timestamp);
        user.tokensUnlockTime = _tokensUnlockTime;
        // Add sale to the array of sales user registered for.将销售添加到用户注册的销售数组中。
        user.salesRegistered.push(msg.sender);
    }

    // Update reward variables of the given pool to be up-to-date.
    //更新给定池的奖励变量(accERC20PerShare)以保持最新
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 lastTimestamp = block.timestamp < endTimestamp ? block.timestamp : endTimestamp;

        if (lastTimestamp <= pool.lastRewardTimestamp) {
            lastTimestamp = pool.lastRewardTimestamp;
        }

        uint256 lpSupply = pool.totalDeposits;

        if (lpSupply == 0) {
            pool.lastRewardTimestamp = lastTimestamp;
            return;
        }

        uint256 nrOfSeconds = lastTimestamp.sub(pool.lastRewardTimestamp);
        uint256 erc20Reward = nrOfSeconds.mul(rewardPerSecond).mul(pool.allocPoint).div(totalAllocPoint);

        // Update pool accERC20PerShare
        pool.accERC20PerShare = pool.accERC20PerShare.add(erc20Reward.mul(1e36).div(lpSupply));

        // Update pool lastRewardTimestamp
        pool.lastRewardTimestamp = lastTimestamp;
    }

    // Deposit LP tokens to Farm for ERC20 allocation.将 LP 代币存入 Farm 以获得 ERC20 分配。
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 depositAmount = _amount;

        // Update pool
        updatePool(_pid);

        // Transfer pending amount to user if already staking。如果已经质押，则将待定金额转移给用户
        if (user.amount > 0) {
            uint256 pendingAmount = user.amount.mul(pool.accERC20PerShare).div(1e36).sub(user.rewardDebt);
            erc20Transfer(msg.sender, pendingAmount);
        }

        // Safe transfer lpToken from user。安全从用户转移 lpToken
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        // Add deposit to total deposits
        pool.totalDeposits = pool.totalDeposits.add(depositAmount);
        // Add deposit to user's amount
        user.amount = user.amount.add(depositAmount);
        // Compute reward debt
        user.rewardDebt = user.amount.mul(pool.accERC20PerShare).div(1e36);
        // Emit relevant event
        emit Deposit(msg.sender, _pid, depositAmount);
    }

    // Withdraw LP tokens from Farm.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        //您注册的上一次销售尚未完成。
        require(user.tokensUnlockTime <= block.timestamp, "Last sale you registered for is not finished yet.");
        require(user.amount >= _amount, "withdraw: can't withdraw more than deposit");

        // Update pool
        updatePool(_pid);

        // Compute user's pending amount
        uint256 pendingAmount = user.amount.mul(pool.accERC20PerShare).div(1e36).sub(user.rewardDebt);

        // Transfer pending amount to user
        erc20Transfer(msg.sender, pendingAmount);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accERC20PerShare).div(1e36);

        // Transfer withdrawal amount to user
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        pool.totalDeposits = pool.totalDeposits.sub(_amount);

        if (_amount > 0) {
            // Reset the tokens unlock time
            user.tokensUnlockTime = 0;
        }

        // Emit relevant event
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Function to compound earnings into deposit.将收益复利存入存款
    function compound(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= 0, "User does not have anything staked.");

        // Update pool
        updatePool(_pid);

        uint256 pendingAmount = user.amount.mul(pool.accERC20PerShare).div(1e36).sub(user.rewardDebt);

        // Increase amount user is staking
        user.amount = user.amount.add(pendingAmount);
        user.rewardDebt = user.amount.mul(pool.accERC20PerShare).div(1e36);

        // Increase pool's total deposits
        pool.totalDeposits = pool.totalDeposits.add(pendingAmount);
        emit CompoundedEarnings(msg.sender, _pid, pendingAmount, user.amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.无需关心奖励即可提款。仅用于紧急情况。
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        //在销售和冷却期间阻止紧急提款
        require(user.tokensUnlockTime <= block.timestamp,
            "Emergency withdraw blocked during sale and cooldown period.");

        // Perform safeTransfer
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        // Adapt contract states
        pool.totalDeposits = pool.totalDeposits.sub(user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.tokensUnlockTime = 0;
    }

    // Transfer ERC20 and update the required ERC20 to payout all rewards
    //支付奖励
    function erc20Transfer(address _to, uint256 _amount) internal {
        erc20.transfer(_to, _amount);
        paidOut += _amount;
    }

    // Function to fetch deposits and earnings at one call for multiple users for passed pool id.
    function getPendingAndDepositedForUsers(address [] memory users, uint pid)
    external
    view
    returns (uint256 [] memory, uint256 [] memory)
    {
        uint256 [] memory deposits = new uint256[](users.length);
        uint256 [] memory earnings = new uint256[](users.length);

        // Get deposits and earnings for selected users
        for (uint i = 0; i < users.length; i++) {
            deposits[i] = deposited(pid, users[i]);
            earnings[i] = pending(pid, users[i]);
        }

        return (deposits, earnings);
    }


}
