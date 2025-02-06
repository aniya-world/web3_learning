// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Array {

    uint256[] public arr;
    uint256[] public arr2 = [1,2,3];
    // Fixed sized array, all elements initialize to 0
    uint256[10] public myFixedSizeArr;

    function get(uint256 i) public view returns (uint256) {
        return arr2[i];
    }

    /*memory：
    memory 是一种数据存储位置，表示该数组将在内存中创建。与 storage（合约的持久存储）和 calldata（只读数据，通常用于函数参数）不同，memory 中的数据在函数执行结束后会被销毁。
    使用 memory 存储的数组是临时的，适用于函数内部的计算和处理。
    */
    function getArr() public view returns (uint256[] memory) {
        return arr2;
    }

    function push(uint256 i) public {
        // Append to array ; This will increase the array length by 1.
        arr2.push(i);
    }

    function pop() public {
        // Remove last element from array
        // `the array length` -= 1
        arr2.pop();
    }

    function getLength() public view returns (uint256) {
        return arr2.length;
    }

    function remove(uint256 index) public {
        // delete does not change the array length.
        // It resets the value at index to it's default value 0,
        delete arr2[index];
    }

    // 在 Solidity 中，external 是一种函数可见性修饰符，用于指定函数的访问权限。具体来说，external 修饰符表示该函数只能从合约外部调用，而不能从合约内部调用。
    function examples() external pure  {
        // create array in memory, only fixed size can be created 
        uint256[] memory a = new uint256[](5);
        // 是一种用于创建动态数组的语法
        //这部分代码创建了一个长度为 5 的 uint256 数组。new 关键字用于动态分配内存。
        // 数组的初始值将是默认值，对于 uint256 类型，默认值是 0。因此，创建的数组 a 将包含五个元素，所有元素的初始值都是 0。
    }

}
