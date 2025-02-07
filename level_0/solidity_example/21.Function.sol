// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
/*
有几种方法可以从函数返回输出。
公共函数不能接受某些数据类型作为输入或输出
*/

contract Function {
    // Functions can return multiple values.
    function returnMany() public pure returns (uint256, bool, uint256) {
        return (1, true, 2);
    }

    // Return values can be named.
    function named() public pure returns (uint256 x, bool b, uint256 y) {
        return (1, true, 2);
    }

    // Return values can be assigned to their name.
    function assigned() public pure returns (uint256 x, bool b, uint256 y) {
        x = 1;
        b = true;
        y = 2;
        // // 这里可以省略 return 语句  In this case the return statement can be omitted.
    }

    // Use destructuring assignment when calling another
    // function that returns multiple values.
    function destructuringAssignments()
        public
        pure
        returns (uint256, bool, uint256, uint256, uint256)
    {
        (uint256 i, bool b, uint256 j) = returnMany();

        // Values can be left out. // 使用解构赋值，忽略第二个值  here is ,,
        (uint256 x,, uint256 y) = (4, 5, 6);

        return (i, b, j, x, y);
    }


    // Cannot use map for either input or output
    // Can use array for input
    // 在 Solidity 中，数组可以用作函数的输入和输出，而映射（mapping）则不能直接用作函数的输入或输出
    function arrayInput(uint256[] memory _arr) public {}

        // Can use array for output
        uint256[] public arr;

        function arrayOutput() public view returns (uint256[] memory) {
        return arr;
    }
}


// 命名参数的使用在 Solidity 中是一个相对较新的特性，确保你的 Solidity 版本支持此功能（从 0.8.0 版本开始支持
// Call function with key-value inputs  
// XYZ 合约展示了如何使用命名参数来调用一个具有多个输入的函数
contract XYZ {
    // 定义一个接受多个参数的函数
    function someFuncWithManyInputs(
        uint256 x,
        uint256 y,
        uint256 z,
        address a,
        bool b,
        string memory c
    ) public pure returns (uint256) {
        // 这里可以实现一些逻辑
        return x + y + z; // 示例：返回 x, y, z 的和
    }

    //  普通调用函数
    function callFunc() external pure returns (uint256) {
        return someFuncWithManyInputs(1, 2, 3, address(0), true, "c");
    }

    // 使用命名参数调用函数
    function callFuncWithKeyValue() external pure returns (uint256) {
        return someFuncWithManyInputs({
            a: address(0),
            b: true,
            c: "c",
            x: 1,
            y: 2,
            z: 3
        });
    }
}