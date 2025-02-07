// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
/*

函数修饰符

修饰符是可以在函数调用之前和 / 或之后运行的代码。
修饰符可用于：
    限制访问 Restrict access
    确认输入 Validate inputs
    防止可重入性黑客攻击  against reentrancy hack
*/

// 展示了如何使用函数修饰符（function modifiers）来增强合约的功能和安全性
contract FunctionModifier {
    // We will use these variables to demonstrate how to use modifiers.
    
    address public owner;  // 存储合约的所有者地址 
    uint256 public x = 10; // 一个简单的状态变量，初始值为 10。
    bool public locked;    // 用于防止重入攻击的锁定标志

    // 构造函数
    constructor() {
        // Set the transaction sender as the owner of the contract. 在合约部署时执行，将合约的所有者设置为部署者的地址（msg.sender）
        owner = msg.sender;
    }

    // Modifier to check that the caller is the owner of the contract.
    // 该修饰符确保只有合约的所有者 可以调用被修饰的函数
    modifier onlyOwner() {
        // 使用 require 语句检查调用者是否为所有者，如果不是，则抛出错误。
        require(msg.sender == owner, "Not owner");
        // Underscore is a special character only used inside
        // a function modifier and it tells Solidity to
        // execute the rest of the code.
        _; //是一个特殊字符，表示在修饰符中执行的代码的占位符，表示在修饰符的逻辑完成后继续执行被修饰的函数。
    }

    // Modifiers can take inputs. This modifier checks that the
    // address passed in is not the zero address.
    modifier validAddress(address _addr) {
        // 该修饰符检查传入的地址是否为零地址（address(0)），如果是，则抛出错误。
        require(_addr != address(0), "Not valid address");
        _;
    }

    // 该函数允许合约的所有者更改合约的所有者地址
    function changeOwner(address _newOwner)
        public
        onlyOwner                    // 使用 onlyOwner 修饰符确保只有所有者可以调用此函数。
        validAddress(_newOwner)      // 使用 validAddress 修饰符确保新地址不是零地址
    {
        owner = _newOwner;
    }

    // Modifiers can be called before and / or after a function.
    // This modifier prevents a function from being called while
    // it is still executing. 该修饰符用于防止重入攻击（reentrancy attack），确保在函数执行期间不会再次调用该函数
    modifier noReentrancy() {
        // 用 locked 变量来标记函数是否正在执行，确保在函数执行期间不会被重
        require(!locked, "No reentrancy");
        //在函数开始时将 locked 设置为 true，在函数结束时将其重置为 false
        locked = true;
        _;
        locked = false;
    }

    // 该函数递归地减少 x 的值  使用 noReentrancy 修饰符防止重入攻击
    function decrement(uint256 i) public noReentrancy {
        // uint256 x=10
        x -= i;
        // 如果 i 大于 1，则递归调用 decrement 函数
        if (i > 1) {
            decrement(i - 1);
        }
    }
}

