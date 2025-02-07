// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
/*数据位置 - 存储、内存和 Calldata

变量声明为存储、内存或调用数据，以显式指定数据的位置。
存储变量storage 是一个状态变量 (存储在区块链上)
内存变量memory 位于内存中，并且在调用函数时存在
calldata包含函数参数的特殊数据位置
*/
contract DataLocations {
    uint256[] public arr; // 状态变量，存储一个动态数组
    mapping(uint256 => address) map;  // 状态变量，存储一个映射
    
    struct MyStruct {
        uint256 foo;  // 结构体，包含一个 uint256 类型的字段
    }
    mapping(uint256 => MyStruct) myStructs; // 状态变量，存储一个映射，映射到 MyStruct 结构体

    
    function f() public {
        // call _f with state variables  // 在 Solidity 中，函数的调用顺序与它们的定义顺序无关。你可以根据自己的需要选择先定义哪个函数，编译器会正确处理所有函数的调用.
        _f(arr, map, myStructs[1]);

        // get a struct from a mapping
        MyStruct storage myStruct = myStructs[1];
        // create a struct in memory  
            // MyStruct.foo = 0 和 MyStruct[0] 这样的写法是无效的, 因为 MyStruct 是一个结构体类型，而不是一个具体的结构体实例。要使用这种语法，你需要先创建一个 MyStruct 的实例，然后才能访问和修改其字段。
            /*正确的用法
                创建结构体实例：
                首先，你需要创建一个 MyStruct 的实例。可以在 memory 或 storage 中创建它。
                访问和修改字段：
                一旦你有了结构体的实例，就可以使用点（.）运算符来访问和修改其字段。*/      
        MyStruct memory myMemStruct = MyStruct(0);
        /* 使用构造函数的方式初始化 MyStruct(0) = 使用键值对的方式初始化 MyStruct({foo=0})// 
            MyStruct memory myMemStruct
            myMemStruct.foo = 0;
        */

    function _f(
        uint256[] storage _arr,
        mapping(uint256 => address) storage _map,
        MyStruct storage _myStruct
    ) internal {
        // do something with storage variables
    }

    // You can return memory variables
    function g(uint256[] memory _arr) public returns (uint256[] memory) {
        // do something with memory array
    }

    function h(uint256[] calldata _arr) external {
        // do something with calldata array
    }
    
}
 