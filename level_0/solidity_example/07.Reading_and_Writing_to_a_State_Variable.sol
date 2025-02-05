// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract SimpleStorage {
    uint256 public num;
    // u need to send a transaction to write to a state variable.
    function set(uint256 _num) public {
        num = _num;
    }

    // u can read from a state variable without sending a transaction.
    function get() public view returns (uint256) {
        return num;
    }


    /*
    写入函数的操作通常被称为“发送交易”（send a transaction）。在 Ethereum 和其他基于区块链的系统中，任何对合约状态的修改（例如调用写入函数）都需要通过交易来实现。

    交易的特点
    状态改变：发送交易会导致区块链状态的改变，例如更新状态变量的值、转移代币等。
    费用：发送交易通常需要支付一定的交易费用（Gas），这笔费用是用以补偿矿工或验证者处理交易的成本。
    确认：交易在被发送后，需要被矿工打包到区块中并确认。确认后，交易的结果（例如状态变量的更新）才会在区块链上生效。

        总结
    写入操作（如调用 set 函数）需要发送交易，并会导致状态改变。
    读取操作（如调用 get 函数）不会发送交易，不会改变状态，也不需要支付 Gas 费用。
    */

}
    
    
