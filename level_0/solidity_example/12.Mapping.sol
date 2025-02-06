// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
在 Solidity 中，mapping 是一种非常重要的数据结构，用于存储键值对（key-value pairs）。
它类似于其他编程语言中的哈希表或字典。
mapping 允许你将一个唯一的键映射到一个值，使得查找和存储数据变得高效。

基本语法
mapping 的基本语法如下：

mapping(keyType => valueType) public mappingName;

keyType  ：键的类型，可以是任何基本数据类型（如 uint, address, bytes32 等），但不能是引用类型（如数组或结构体）。The keyType can be any built-in value type, bytes, string, or any contract.
valueType：值的类型，可以是任何类型，包括基本数据类型、结构体、数组或其他 mapping。 valueType can be any type including another mapping or an array.
mappingName：你为这个 mapping 选择的名称。
*/

contract Mapping {
    // Mapping from address to uint
    mapping(address => uint256) public mymap;

    function get(address _addr) public view returns (uint256) {
        return mymap[_addr];
    }

    function set(address _addr, uint256 _i) public {
        mymap[_addr] = _i;
    }

    function remove(address _addr) public  {
        delete mymap[_addr];
    }

}


contract NestedMapping {
    // 是一个嵌套(nested)的 mapping,
    /* 外层 mapping：
    address 是外层 mapping 的键类型，表示每个地址（例如用户的以太坊地址）将映射到一个内部的 mapping
    内层 mapping：
    mapping(uint256 => bool) 是内层 mapping，它的键类型是 uint256，值类型是 bool。这意味着对于每个地址，可以存储多个 uint256 键，每个键对应一个布尔值。
    */
    mapping(address => mapping(uint256 => bool)) public nested;

    function set(address _addr1, uint256 _i, bool _boo) public {
        nested[_addr1][_i] = _boo;
    }

    function get(address _addr1, uint256 _i) public view returns (bool) {
        // You can get values from a nested mapping, even when it is not initialized
        // 当你访问一个未初始化的嵌套 mapping 的值时，Solidity 会返回该值类型的默认值。对于布尔值（bool），默认值是 false
        return nested[_addr1][_i];
    }

    function remove(address _addr1, uint256 _i) public {
        delete nested[_addr1][_i];
    }

}