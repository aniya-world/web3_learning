// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
/*

*/
// 是一个简单的银行账户实现，包含存款和取款功能
contract Account {
    uint256 public balance;
    uint256 public constant MAX_UINT = 2 ** 256 - 1;

    // 存款 函数允许用户向账户中添加资金。
    function deposit(uint256 _amount) public {
        uint256 oldBalance = balance;
        uint256 newBalance = balance + _amount;

        // balance + _amount does not overflow if balance + _amount >= balance
        // 使用 require 语句检查溢出是一个良好的实践。然而，从 Solidity 0.8.0 开始，算术运算在溢出和下溢时会自动回退，因此显式检查在这种情况下是不必要的
        require(newBalance >= oldBalance, "Overflow");

        balance = newBalance;
        //assert 语句用于确保余额确实增加
        assert(balance >= oldBalance);
    }

    // 函数允许用户从账户中提取资金。
    function withdraw(uint256 _amount) public {
        uint256 oldBalance = balance;

        // balance - _amount does not underflow if balance >= _amount  检查余额是否足够进行取款
        require(balance >= _amount, "Underflow");

        // if 语句和 revert 语句是多余的，因为在前面的 require 语句已经确保了余额足够。可以直接删除这部分代码
        if (balance < _amount) {
            revert("Underflow");
        }

        balance -= _amount;
        
        // assert 语句用于确保余额减少
        assert(balance <= oldBalance);
    }
}