// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


contract Immutable {
    // coding convention to uppercase constant variables 大写常量变量的编码约定
    address public immutable MY_ADDR = 0x777788889999AaAAbBbbCcccddDdeeeEfFFfCcCc;
    uint256 public immutable MY_UINT = 123;

    constructor(uint256 _myUint) {
        MY_ADDR = msg.sender;
        MY_UINT = _myUint;
    }


/*
immutable 和 constants区别
在 Solidity 中，immutable 和 constant 都是用于定义不可变的变量，但它们之间有一些重要的区别：

1. constant
定义：constant 关键字用于定义一个在编译时就确定值的变量。它的值在合约部署后不能被更改。
类型：constant 变量必须在声明时初始化，并且只能是基本数据类型（如 uint, int, bool, address, bytes 等）。
存储：constant 变量的值在合约的字节码中直接嵌入，因此在运行时访问时不需要存储在合约的状态中，这使得它的访问成本更低。

2. immutable
定义：immutable 关键字用于定义一个在合约构造函数中初始化的变量。它的值在合约部署后不能被更改，但可以在构造函数中设置。
类型：immutable 变量可以是任何类型，包括复杂数据类型（如结构体、数组等）。
存储：immutable 变量的值在合约的状态中存储，虽然它在运行时的访问成本比 constant 略高，但仍然比普通状态变量低。

总结
初始化时机：constant 必须在声明时初始化，而 immutable 可以在构造函数中初始化。
类型限制：constant 只能是基本数据类型，而 immutable 可以是任何类型。
存储方式：constant 的值直接嵌入字节码中，而 immutable 的值存储在合约的状态中。
这两者的选择取决于具体的需求和使用场景。
*/
}

