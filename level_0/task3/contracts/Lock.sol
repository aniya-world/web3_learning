// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// 是一个简单的锁定合约，允许合约的所有者在指定的时间后提取存入的以太币

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract Lock {
    uint public unlockTime; // 合约何时允许提取资金
    address payable public owner; // 所有者的地址 使用 payable 关键字表示该地址可以接收以太币

    event Withdrawal(uint amount, uint when); // 当资金被提取时触发的事件，记录提取的金额和时间戳

    //构造函数接受一个参数 _unlockTime，表示解锁时间
    constructor(uint _unlockTime) payable {
        require(  // 构造函数中使用 require 语句确保解锁时间在未来
            block.timestamp < _unlockTime,
            "Unlock time should be in the future"
        );

        unlockTime = _unlockTime;   // 将传入的解锁时间赋值给状态变量 unlockTime
        owner = payable(msg.sender); //将合约的创建者地址设置为所有者
    }

    // 合约所有者提取
    function withdraw() public {
        // Uncomment this line, and the import of "hardhat/console.sol", to print a log in your terminal
        // console.log("Unlock time is %o and block timestamp is %o", unlockTime, block.timestamp);
        // 确保当前时间已达到解锁时间
        require(block.timestamp >= unlockTime, "You can't withdraw yet");
        // 确保调用者是合约的所有者
        require(msg.sender == owner, "You aren't the owner");
        // 触发 Withdrawal 事件，记录提取的金额和时间戳
        emit Withdrawal(address(this).balance, block.timestamp);
        // 将合约中的所有以太币转移到所有者的地址
        owner.transfer(address(this).balance);
    }
}
