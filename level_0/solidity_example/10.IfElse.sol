// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract IfElse {

    function foo(uint256 x) public pure returns (uint256) {
        if (x<10 && x>=0) {
            return 0;
        } else if (x<20 && x>=10) {
            return 1;
        } else {
            return 2;
        }
    }

    function ternary(uint256 _x) public pure returns (uint256) {
        // 三元运算符（ternary operator）
        // condition ? value_if_true : value_if_false;
        // 如果 _x 小于 10，则返回 1。
        // 如果 _x 大于或等于 10，则返回 0。
        return _x < 10? 1 : 0;
    }

}