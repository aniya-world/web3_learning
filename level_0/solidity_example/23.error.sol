// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
/*
你可以使用 require、revert 和 assert 来处理错误，每种机制都有其特定的用途。以下是对这三种机制的详细说明，以及使用自定义错误以节省 gas 的方法
1. require  
    目的：require 用于在执行函数之前验证输入和条件。如果条件不满足，它会回滚交易并可以提供错误信息。
    使用场景：通常用于输入验证、检查条件以及确保在继续执行之前满足某些要求。

2. revert
    目的：revert 与 require 类似，用于回滚交易。它可以在任何地方使用，并且可以提供自定义错误消息。
    使用场景：当你需要在函数中根据某些条件手动回滚时，可以使用 revert。

3. assert
    目的：assert 用于检查代码中应该永远为假的条件。如果断言失败，通常意味着代码中存在错误或漏洞。
    使用场景：用于检查不应该发生的情况，例如内部错误或不一致的状态。

4. Use custom error to save gas. 
    用自定义错误来节省gas。

*/

contract Error {

        function testRequire(uint256 _i) public pure {
        // Require should be used to validate conditions such as:
        // - inputs
        // - conditions before execution
        // - return values from calls to other functions
        require(_i > 10, "Input must be greater than 10");
        }

       function testRevert(uint256 _i) public pure {
        // Revert is useful when the condition to check is complex.
        // This code does the exact same thing as the example above
            if (_i <= 10) {
                revert("Input must be greater than 10");
            }
        }

        uint256 public num;

        function testAssert() public view {
            // Assert should only be used to test for internal errors,
            // and to check invariants.

            // Here we assert that num is always equal to 0
            // since it is impossible to update the value of num
            // 断言 num 始终等于 0，因为合约没有更新 num 的值  ; 如果 num 不等于 0，表示合约内部存在错误，交易将被回滚
            assert(num == 0);
        }

        // custom error 回滚交易，并提供当前余额和请求的提款金额 
        // 它接受两个参数：balance：表示当前合约的余额。 withdrawAmount：表示尝试提取的金额
        error InsufficientBalance(uint256 balance, uint256 withdrawAmount);

       
        function testCustomError(uint256 _withdrawAmount) public view {
            // 获取当前合约的以太币余额
            uint256 bal = address(this).balance;
            //  检查合约的余额 bal 是否小于请求提取的金额 _withdrawAmount。
            if (bal < _withdrawAmount) {
                // 如果余额不足，触发自定义错误 ; 自定义错误的好处在于，它们可以提供更具体的错误信息，而不需要使用字符串，这样可以节省 gas
                revert InsufficientBalance({
                    balance: bal,
                    withdrawAmount: _withdrawAmount
                });
            }
        }

}