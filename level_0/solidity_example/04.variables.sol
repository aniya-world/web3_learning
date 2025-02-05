// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Variables {
    // State variables are stored on the blockchain  状态变量存在区块链上。
    string public text = "Hello";
    uint256 public num = 123;

    function doSomething() public view{
        // Local variables are not saved to the blockchain. 局部变量不会保存到区块链中。
        uint256 i = 456;

        // Here are some global variables  以下是一些全局变量
        uint256 timestamp = block.timestamp; // Current block timestamp 当前块时间戳
        address sender = msg.sender; // address of the caller 呼叫者的地址
    }
}