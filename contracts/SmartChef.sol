pragma solidity 0.6.12;

// based on PanCakeSwap SmartChef contract
// added functionnalities by the iethereum's devs
//
// - possibility to update reward per block
// - possibility to update end bonus block
// - possibility to update and add deposit fees

import "./SafeMath.sol";
import "./Ownable.sol";
import "./IBEP20.sol";
import "./SafeBEP20.sol";
import "./GUITAToken.sol";

contract SmartChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. GUITAs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that GUITAs distribution occurs.
        uint256 accGuitaPerShare; // Accumulated GUITAs per share, times 1e12. See below.
        uint16 depositFeeBP;      // V1 Deposit fee in basis points
    }

    // The GUITA TOKEN!
    GuitaToken public guita;
    IBEP20 public rewardToken;
    uint256 public rewardTokenDecimals;

    // GUITA tokens created per block.
    uint256 public rewardPerBlock;
    
    // V1
    // Deposit burn address
    address public burnAddress;
    // V1
    // Deposit fee to burn
    uint16 public depositFeeToBurn;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (address => UserInfo) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 private totalAllocPoint = 0;
    // The block number when GUITA mining starts.
    uint256 public startBlock;
    // The block number when GUITA mining ends.
    uint256 public bonusEndBlock;
    // Deposited amount GUITA in SmartChef
    uint256 public depositedGuita;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(
        GuitaToken _guita,
        IBEP20 _rewardToken,
        uint256 _rewardTokenDecimals,
        uint256 _rewardPerBlock,
        address _burnAddress, // V1
        uint16 _depositFeeBP, // V1
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        guita = _guita;
        rewardToken = _rewardToken;
        rewardTokenDecimals = _rewardTokenDecimals;
        rewardPerBlock = _rewardPerBlock;
        burnAddress = _burnAddress; // V1
        depositFeeToBurn = _depositFeeBP; // V1
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
    }

    function add(IBEP20 _lpToken) public onlyOwner {        
        require(poolInfo.length < 1, 'add : pool is exist');

        // V1 / Deposit fee limited to 10% No way for contract owner to set higher deposit fee
        require(depositFeeToBurn <= 1000, "contract: invalid deposit fee basis points");

        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accGuitaPerShare: 0,
            depositFeeBP: depositFeeToBurn
        }));

        totalAllocPoint = 1000;
    }

    function stopReward() public onlyOwner {
        bonusEndBlock = block.number;
    }


    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from);
        }
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[_user];
        uint256 accGuitaPerShare = pool.accGuitaPerShare;
        // uint256 lpSupply = pool.lpToken.balanceOf(address(this));
	uint256 lpSupply = depositedGuita;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 guitaReward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accGuitaPerShare = accGuitaPerShare.add(guitaReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accGuitaPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        // uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        uint256 lpSupply = depositedGuita;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 guitaReward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accGuitaPerShare = pool.accGuitaPerShare.add(guitaReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Stake GUITA tokens to TheBushV1
    function deposit(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];

        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accGuitaPerShare).div(1e12).sub(user.rewardDebt);
            uint256 pendingReward = pending.mul(10**rewardTokenDecimals).div(1e18);
            if(pending > 0) {
                rewardToken.safeTransfer(address(msg.sender), pendingReward);
            }
        }
        // V0
        //if(_amount > 0) {
        //    pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        //    user.amount = user.amount.add(_amount);
        //}
        // V1 Add the possibility of deposit fees sent to burn address
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if(pool.depositFeeBP > 0){
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                uint256 transferTax = _amount.mul(guita.transferTaxRate()).div(10000);
                pool.lpToken.safeTransfer(burnAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee).sub(transferTax);
                depositedGuita = depositedGuita.add(_amount).sub(depositFee).sub(transferTax);
            }else{
                uint256 transferTax = _amount.mul(guita.transferTaxRate()).div(10000);
                user.amount = user.amount.add(_amount).sub(transferTax);
                depositedGuita = depositedGuita.add(_amount).sub(transferTax);
            }
        }        
        
        
        user.rewardDebt = user.amount.mul(pool.accGuitaPerShare).div(1e12);

        emit Deposit(msg.sender, _amount);
    }

    // Withdraw GUITA tokens from STAKING.
    function withdraw(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accGuitaPerShare).div(1e12).sub(user.rewardDebt);
        uint256 pendingReward = pending.mul(10**rewardTokenDecimals).div(1e18);
        if(pending > 0) {
            rewardToken.safeTransfer(address(msg.sender), pendingReward);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            depositedGuita = depositedGuita.sub(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accGuitaPerShare).div(1e12);

        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) public onlyOwner {
        require(_amount < rewardToken.balanceOf(address(this)), 'not enough token');
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }
    
    // V1 Add a function to update rewardPerBlock. Can only be called by the owner.
    function updateRewardPerBlock(uint256 _rewardPerBlock) public onlyOwner {
        rewardPerBlock = _rewardPerBlock;
        //Automatically updatePool 0
        updatePool(0);        
    } 
    
    // V1 Add a function to update bonusEndBlock. Can only be called by the owner.
    function updateBonusEndBlock(uint256 _bonusEndBlock) public onlyOwner {
        bonusEndBlock = _bonusEndBlock;
    }   
    
    // V1 Update the given pool's deposit fee. Can only be called by the owner.
    function updateDepositFeeBP(uint256 _pid, uint16 _depositFeeBP) public onlyOwner {
        require(_depositFeeBP <= 10000, "updateDepositFeeBP: invalid deposit fee basis points");
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        depositFeeToBurn = _depositFeeBP;
    }    
}