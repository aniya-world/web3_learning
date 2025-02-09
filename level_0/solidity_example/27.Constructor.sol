// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
/*

构造函数的调用顺序：
    在 Solidity 中，父合约的构造函数总是按照继承顺序调用，而不是按照在子合约构造函数中调用的顺序。
    这意味着即使在子合约的构造函数中先调用 Y 的构造函数，X 的构造函数仍然会先执行。

参数传递：可以通过两种方式初始化父合约的构造函数：在继承列表中直接传递参数，或者在子合约的构造函数中传递参数。

继承的灵活性：这种灵活性使得在复杂的合约结构中能够更好地管理和初始化状态变量。

*/

// 展示了如何在 Solidity 中使用继承和构造函数来初始化父合约
// Base contract X  基合约 X：
contract X {
    string public name;
    // 构造函数，接受一个字符串参数并将其赋值给 name。
    constructor(string memory _name) {
        name = _name;
    }
}

// Base contract Y  基合约 Y
contract Y {
    string public text;

    constructor(string memory _text) {
        text = _text;
    }
}

// There are 2 ways to initialize parent contract with parameters.

// Pass the parameters here in the inheritance list.
// 通过在`继承列表`中直接传递参数来初始化父合约 X 和 Y。在合约 B 部署时，X 和 Y 的构造函数将被调用，分别传入 "Input to X" 和 "Input to Y"。
// is 继承列表的语法 在 Solidity 中，继承列表是在合约声明时指定的，使用 is 关键字来表示, 下边is x , y ,多重继承，顺序就是先x 再y
contract B is X("Input to X"), Y("Input to Y") {}

// 继承顺序是根据合约声明时 is 关键字后面列出的父合约的顺序来确定的

// c 是在构造函数中传递参数
contract C is X, Y {
    // Pass the parameters here in the constructor,
    // similar to function modifiers.
    // 在构造函数中调用父合约的构造函数，传入 _name 和 _text
    constructor(string memory _name, string memory _text) X(_name) Y(_text) {}
}

// Parent constructors are always called in the order of inheritance
// regardless of the order of parent contracts listed in the
// constructor of the child contract.

// Order of constructors called:
// 1. X
// 2. Y
// 3. D
contract D is X, Y {
    // 在构造函数中调用父合约的构造函数，传入固定的字符串参数。
    constructor() X("X was called") Y("Y was called") {}
    // 构造函数调用顺序：父合约的构造函数总是按照继承顺序调用。在这个例子中，X 的构造函数会先被调用，然后是 Y 的构造函数
}

// Order of constructors called:
// 1. X
// 2. Y
// 3. E
contract E is X, Y {
    // 尽管在构造函数中 Y 的构造函数先被调用，但由于继承顺序，X 的构造函数仍然会在 Y 之前被调用
    constructor() Y("Y was called") X("X was called") {}
}