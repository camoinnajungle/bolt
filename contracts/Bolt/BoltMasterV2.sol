/**
 *Submitted for verification at BscScan.com on 2020-09-22
*/

pragma solidity 0.6.12;


//LICENCING
contract BoltMasterV2 is ReentrancyGuard, Pausable, IBoltMaster {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 wantDepositAmount;     // How many tokens the user has provided.
        address addr;
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 wantToken;           // Address of oken contract.
        uint256 wantTotalDeposit;
        address strategy;
    }

    uint256 public feeNumerator = 200;
    uint256 public feeDenominator = 1000;
    uint256 public maxFeeNumerator = 500;
    address public feeTo = 0x0000dead;

    PoolInfo[] public poolInfo; // Info of each pool.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo; //poolid -> addr ->  userrinfo
    mapping (uint256 => UserInfo[]) public poolUsers;//pool id -> users. improve gas pls, used to reflect rewards

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor( address _firstStrategy ) public {
        addStrategy( {_wantToken: 0x000000000dead, _strategy: _firstStrategy } );
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function addStrategy(IBEP20 _wantToken, address _strategy) public onlyOwner {
        poolInfo.push(PoolInfo({
            wantToken: _wantToken,
            wantTotalDeposit: 0,
            strategy: _strategy
        }));
    }

    //DONE
    function editStrategy(uint256 _pid, address _newStrategy) public onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];

        IBoltStrategy oldStrat = IBoltStrategy(pool.strategy);
        IBoltStrategy newStrat = IBoltStrategy(_newStrategy);

        require(oldStrat.wantToken == newStrat.wantToken, "!wantToken");

        oldStrat.withdraw(pool.wantTotalDeposit);
        oldStrat.collectYield();
        distributeYield(_pid);
        pool.strategy = newStrat;

        IBEP20(newStrat.wantToken).safeIncreaseAllowance(newStrat, pool.wantTotalDeposit );
        newStrat.deposit(pool.wantTotalDeposit);

    }

    // TODO.
    function pendingYield(uint256 _pid, address _user) external view returns (uint256) {
        return 0;
    }

    //TODO take taxes
    function distributeYield(uint256 _pid) private {
        PoolInfo memory pool = poolInfo[_pid];
        IBoltStrategy strategy = IBoltStrategy(pool.strategy);
        if (strategy.pendingYield() > 0) {
            uint256 harvested = strategy.harvestYield(); //strategy sells eg cake for btd and sends to master (this)
            uint256 fee = harvested.mul(feeNumerator).div(feeDenominator);
            
            harvested = harvested.sub(fee);

            IBEP20(pool.yieldToken).safeTransfer(feeTo, fee);

            UserInfo[] memory users = poolUsers[_pid];
            for (uint256 i = 0; i < users.length; i++) {
                UserInfo memory user = users[i];
                if ( user.wantDepositAmount > 0 ) {
                    uint256 userYield = user.wantDepositAmount.mul(harvested).div(pool.wantTotalDeposit);
                    IBEP20(pool.yieldToken).safeTransfer(user.addr, userYield);
                }
            }
        }
    }

    function increaseDeposit(uint256 _pid, uint256 _amount) private {
        if (_amount > 0) {
            PoolInfo storage pool = poolInfo[_pid];
            UserInfo storage userViaAddress = userInfo[_pid][msg.sender];

            userViaAddress.wantDepositAmount.add(_amount);
            pool.wantTotalDeposit.add(_amount);
            
            {
                bool poolUserUpdated = false;
                for (uint256 i = 0; i < poolUsers.length; i++) {
                    UserInfo storage userViaPool = poolUsers[i];
                    if (userViaPool.addr == msg.sender) {
                        userViaPool.wantDepositAmount.add(_amount);
                        poolUserUpdated = true;
                    }           
                }

                if (!poolUserUpdated) {
                    poolUsers.push(
                        UserInfo({
                            wantDepositAmount: _amount,
                            addr: msg.sender
                        })
                    );
                }
            } 

            IBEP20(pool.wantToken).safeTransferFrom(msg.sender, this, _amount);
            IBEP20(pool.wantToken).safeIncreaseAllowance(pool.strategy, _amount);
            IBoltStrategy(pool.strategy).deposit(_amount);
        }
    }

    function decreaseDeposit(uint256 _pid, uint256 _amount) private {
        if (_amount > 0) {
            PoolInfo storage pool = poolInfo[_pid];
            UserInfo storage userViaAddress = userInfo[_pid][msg.sender];

            require (userViaAddress.wantDepositAmount >= _amount, "cant withdraw what you don't have");

            userViaAddress.wantDepositAmount.sub(_amount);
            pool.wantTotalDeposit.sub(_amount);
        
            bool poolUserUpdated = false;

            for (uint256 i = 0; i < poolUsers.length; i++) {
                UserInfo storage userViaPool = poolUsers[i];
                if (userViaPool.addr == msg.sender) {
                    require (userViaPool.wantDepositAmount >= _amount, "cant withdraw what you don't have");
                    userViaPool.wantDepositAmount.sub(_amount);
                    poolUserUpdated = true;
                }           
            }

            require (poolUserUpdated, "cant withdraw what you don't have");

            IBoltStrategy(pool.strategy).withdraw(_amount);
            IBEP20(pool.wantToken).safeTransfer(msg.sender, _amount);      
        }
    }

    // Deposit LP tokens to MasterChef for CAKE allocation.
    function deposit(uint256 _pid, uint256 _amount) public whenNotPaused {
        distributeYield(_pid);
        increaseDeposit(_pid, _amount);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public whenNotPaused {
        distributeYield(_pid);
        decreaseDeposit(_pid, _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function setFeeParams(uint256 _newFee, address _newFeeTo) public onlyOwner {
        require(_newFee <= maxFeeNumerator);
        feeNumerator = _newFee;
        feeTo = _newFeeTo;
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        uint256 amt = userInfo[_pid][msg.sender].wantDepositAmount;
        decreaseDeposit(_pid, amt);
        emit EmergencyWithdraw(msg.sender, _pid, amt);
    }

}