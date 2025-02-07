// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
/*
// Make sure EVM version and VM set to Cancun
// 确保EVM版本和VM设置为Cancun

// Storage - data is stored on the blockchain  Solidity 中的持久性存储，数据存储在区块链上
// Memory - data is cleared out after a function call  数据在函数调用期间有效，函数执行结束后，数据会被清除。
// Transient storage - data is cleared out after a transaction  数据在交易完成后被清除 Transient Storage 通常指的是 calldata，它用于外部函数的参数，数据在函数调用期间有效，不能被修改
*/

// 在 Solidity 中，interface 关键字用于定义接口。接口是一种特殊的合约类型，它只包含函数的声明，而不包含函数的实现。接口用于定义合约之间的交互规范，允许不同合约之间进行通信。
interface ITest  {
    function val() external view returns (uint256); // 一个外部可见的只读函数，返回一个 uint256 类型的值。
    function test() external; // 一个外部可见的函数，没有返回值。
}

// Callback合约 与一个接口 ITest 进行交互
contract Callback {
    uint256 public val;  // 公共状态变量

    /* fallback 函数定义
        外部可见性：fallback 函数必须是 external 的。
        无参数和返回值：fallback 函数不能有参数，也不能返回值。
    用途：它用于处理接收到的以太币或调用未定义的函数。
    */
    fallback() external {
        //msg.sender 是调用当前合约的地址。
        // ITest(msg.sender) 将 msg.sender 转换为 ITest 接口类型
        // 调用 val() 函数并将返回值赋给 val 变量
        val = ITest(msg.sender).val();
    }

    function test(address target) external {
        // 将参数target 地址转换为 ITest 接口类型
        //  ITest(msg.sender)  ITest(target) 这种方式类似于在其他编程语言中使用接口或抽象类的概念
        ITest(target).test();
    }
}


contract TestStorage {
    uint256 public val;

    function test() public {
        val = 123;
        bytes memory b = "";
        msg.sender.call(b);
    }
}


// 使用了汇编语言来存储和读取数据
contract TestTransientStorage {
    // constant 是不能更改的
    bytes32 constant SLOT = 0;

    function test() public {
        // 使用了 assembly 关键字来执行汇编代码
        assembly {
            // 试图将值 321 存储到指定的槽位 SLOT。然而，tstore 不是 Solidity 汇编语言中的有效指令。正确的指令应该是 sstore，用于存储数据到合约的存储中
            // 存储值
            tstore(SLOT, 321)
        }
        bytes memory b = "";
        // 会向调用者发送一个空的字节数组
        msg.sender.call(b);
    }

    function val() public view returns (uint256 v) {
        assembly {
            // SLOT 中读取值并返回
            v := tload(SLOT)
        }
    }
}


// 防止重入攻击  入攻击是一种常见的安全漏洞，攻击者可以在合约执行过程中重新进入合约并执行恶意操作
contract ReentrancyGuard {
    // 定义了一个私有的布尔变量 locked，用于指示合约是否处于锁定状态
    bool private locked;

    modifier lock() {
        // lock 修饰符首先检查 locked 是否为 false，如果为 true，则抛出异常，阻止重入。
        require(!locked);
        // 如果检查通过，locked 被设置为 true
        locked = true;
        // 然后执行修饰符下的函数体 ，忽略返回数据 ；在某些情况下，你可能只关心调用是否成功，而不关心返回的数据。在这种情况下，可以使用 _ 或空的变量名（如 ,）来忽略返回的数据
        _;
        // 函数执行完毕后，locked 被重置为 false
        locked = false;
    }

    // test 函数使用了 lock 修饰符，确保在执行过程中不会发生重入。
    function test() public lock {
        // Ignore call error
        bytes memory b = "";
        // msg.sender.call(b) 的返回值没有被检查。虽然你提到“忽略调用错误”，但在实际应用中，最好检查返回值，以确保调用成功
        (bool success, )  = msg.sender.call(b);
        //  (bool success, bytes memory returnData) = msg.sender.call(b);
        // 使用 (bool success, ) = 这种语法是为了处理低级调用（如 call、delegatecall 或 staticcall）的返回值。
        require(success, "Call failed"); // 检查调用是否成功
    }
}



// 实现重入保护
contract ReentrancyGuardTransient {
    // slot is like lock qwq
    bytes32 constant SLOT = 0;

    modifier lock() {
        assembly {
            // revert 与 require 有点相似，不同的是它不进行任何检查，直接就抛出异常。它可以被使用在任何你想要马上抛出异常，状态变量恢复原样的场景。
            // 使用汇编语言检查 SLOT 。如果 tload(SLOT) 返回非零值（表示已经锁定），则调用 revert(0, 0)，抛出异常，阻止重入
            if tload(SLOT) { revert(0, 0) }
            // 如果没有重入，使用 tstore(SLOT, 1) 将槽位的值设置为 1，表示当前合约正在执行
            tstore(SLOT, 1)
        }
        // _ 表示执行修饰符下的函数体。
        _;
        // 在函数体执行完毕后，使用 tstore(SLOT, 0) 将槽位的值重置为 0，表示合约执行完成
        assembly {
            tstore(SLOT, 0)
        }
    }


    function test() external lock {
        // Ignore call error
        bytes memory b = "";
        msg.sender.call(b);
        // (bool success, ) = msg.sender.call(b);
        // require(success, "Call failed");
    }
}