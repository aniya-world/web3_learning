// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
/*

事件的用途

    用户界面更新：
事件可以被前端应用程序监听，以便在合约状态发生变化时更新用户界面。例如，当用户调用 test 函数时，前端可以捕获 Log 事件并显示相应的消息。
    便宜的存储：
事件提供了一种相对便宜的方式来存储信息。虽然事件的存储成本低于合约的状态变量，但它们仍然是不可变的，适合用于记录历史操作。
    过滤和查询：
使用 indexed 参数，您可以在查询日志时根据特定条件进行过滤。例如，您可以查询所有由特定地址触发的 Log 事件。
*/

// 合约展示了如何在智能合约中使用事件（events）来记录信息并与外部世界进行交互
contract Event {
    
    // Up to 3 parameters can be indexed.
    // Indexed parameters helps you filter the logs by the indexed parameter 
    // 包含两个参数：发送者的地址，使用 indexed 关键字使其可被索引，从而可以在日志中进行过滤。  string message：要记录的消息
    event Log(address indexed sender, string message);  // Event declaration 事件声明， 
    event AnotherLog(); // 这是另一个没有参数的事件声明。

    function test() public {   // 该函数用于触发事件
        emit Log(msg.sender, "Hello World!"); //触发 Log 事件，记录调用者的地址和消息 "Hello World!"。
        emit Log(msg.sender, "Hello EVM!");
        emit AnotherLog(); // 触发 AnotherLog 事件，没有参数
    }
}