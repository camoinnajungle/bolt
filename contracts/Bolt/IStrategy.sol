pragma solidity 0.7.3;

// For interacting with our own strategy
interface IStrategy {
    // Total want tokens managed by stratfegy
    function DepositedLockedTotal() external view returns (uint256); 

    // Transfer want tokens yetiFarm -> strategy
    function deposit(uint256 _wantAmt)
        external
        returns (uint256);

    // Transfer want tokens strategy -> yetiFarm
    function withdraw(uint256 _wantAmt)
        external
        returns (uint256);

    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) external;
}