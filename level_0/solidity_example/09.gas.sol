// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/* Gas
`gas` is a unit of computation
`gas spent` is the total amount of gas used in a transaction
`gas price` is how much ether you are willing to pay per gas -> `gas price` have higher priority
Unspent gas will be refunded.
*/

/* Gas Limit

你可以花费的汽油量有两个上限
`gas limit`      , gas限额 (由你自行设定，你愿意在交易中使用的最大汽油数量)
`block gas limit`, 区块gas限制 (一个区块允许的最大气体量，由网络设定)
*/

contract Gas {

    uint256 public i = 0;
    /*
    Using up all of the gas that you send causes your transaction to fail.
     用完您发送的所有gas会导致交易失败
     原因：以太坊网络使用 Gas 来限制计算资源的使用。如果交易消耗的 Gas 超过了你为其设置的 Gas 限制，交易将被视为失败。
    State changes are undone.
     状态更改会撤消。
     原因：以太坊的设计确保了状态的一致性和原子性。要么所有的操作都成功并被提交，要么没有任何操作被执行。
    Gas spent are not refunded.
     已消耗的gas不予退还。
     原因：Gas 费用是用来补偿矿工或验证者处理交易的成本。即使交易失败，矿工仍然花费了资源来处理该交易，因此 Gas 费用不会被退还。

     如果交易消耗了所有的 Gas，交易将失败，所有状态更改将被撤销，并且已经消耗的 Gas 费用不会被退还。
     这强调了在编写合约和发送交易时，合理设置 Gas 限制的重要性，以避免不必要的费用和交易失败。
    */
    function forever() public {
        while (true) {
            i+=1;
        }
    }

}
