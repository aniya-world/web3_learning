// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;


contract Primitives {

    bool public boo = true;
    /*
    Uint 表示无符号整数，意思是非负整数
    uint8   ranges from 0 to 2 ^8 - 1
    在 Solidity 中，uint8 是一种无符号整数类型，它占用 1 个字节（8 位）。uint8 的取值范围是从 0 到 255。具体来说：
        最小值：0
        最大值：255
        这是因为 uint8 使用 8 位来表示数值，其中所有位都用于表示数值（没有符号位），因此可以表示的数值范围是 2^8=256 个不同的值，
        从 0 到 255。
    */
    uint8 public u8=1;
    uint256 public u256=456;
    uint256 public u=123;

    //对于 int 类型，允许使用负数。
    int8 public i8 = -1;
    int256 public i256 = 456;
    int256 public i = -123;

    // minimum and maximum of int
    int256 public minInt = type(int256).min;
    int256 public maxInt = type(int256).max;

    address public addr = 0xCA35b7d915458EF540aDe6068dFe2F44E8fa733c;

    /*
    数据类型 byte 表示一个字节序列。
    Solid 表示两种类型的字节：
        固定大小的字节数组
        动态大小的字节数组。
    Solidy 中的字节表示动态字节数组。
    是 byte [] 的简写
    */
    bytes1 a=0xbb;
    bytes1 v=0x55;

    /*
    Unassigned variables have a default value
    */
    bool public defaultBoo; // false
    uint256 public defaultUint; //0
    int256 public defaultInt; // 0
    address public defaultAddr; // 0x0000000000000000000000000000000000000000

}