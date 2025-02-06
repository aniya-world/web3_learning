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

    function forever() public {
        while (true) {
            i+=1;
        }
    }

}
