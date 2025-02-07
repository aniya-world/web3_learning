// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
/*
视图和纯函数

view 函数声明不会更改任何状态。
pure函数声明不会更改或读取任何状态变量。

view 和 pure 的区别
    view 函数:
        可以读取合约的状态变量，但不能修改它们。
        适用于需要访问合约状态但不改变状态的场景。
    pure 函数:
        既不能读取也不能修改合约的状态。
        适用于只依赖于输入参数进行计算的场景。

扩展知识：
    Getter 函数可以声明为 view，也可以声明为 Pure。
        Solidity 自动为每个公共状态变量生成一个 getter 函数，因此开发者通常不需要手动编写 getter 函数
*/

// ViewAndPure 合约展示了如何在 Solidity 中使用 view 和 pure 函数。通过合理使用这两种函数类型，可以提高合约的安全性和可读性，确保函数的行为符合预期
contract ViewAndPure {
    uint256 public x = 1;

    // Promise not to modify the state. 函数接受一个参数 y，并返回 x 和 y 的和。它可以读取状态变量 x，但不能修改它
    function addToX(uint256 y) public view returns (uint256) {
        return x + y;
    }

    // Promise not to modify or read from the state. 不能修改或者读它们。函数接受两个参数 i 和 j，并返回它们的和。它不依赖于合约的状态变量x
    function add(uint256 i, uint256 j) public pure returns (uint256) {
        return i + j;
    }
}