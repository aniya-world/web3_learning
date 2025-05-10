pragma solidity ^0.8.26;
// 主要功能是作为一个简单的键值存储系统，并记录一个版本号。
contract Store {
    //  声明了一个名为 ItemSet 的事件。事件是以太坊中一种重要的机制，用于在合约执行某些操作时通知外部监听者（如用户界面或其他合约）
    // 这个事件在被触发时会记录两个参数：一个 key (键) 和一个 value (值)，两者都是 bytes32 类型。
    // bytes32 是一种固定大小为32字节的数据类型，常用于存储哈希值或短的、固定长度的数据
  event ItemSet(bytes32 key, bytes32 value);

  string public version; // 状态变量，其类型为字符串。状态变量是永久存储在区块链上的数据
  mapping (bytes32 => bytes32) public items;    //  声明了一个名为 items 的状态变量，其类型为映射 (mapping)。映射类似于哈希表或字典，用于存储键值对

    // 构造函数是一个特殊的函数，只在合约首次部署到区块链上时执行一次
  constructor(string memory _version) {
    version = _version; // 在合约部署时，这行代码会将传入的 _version 参数的值赋给状态变量 version。这样，每个部署的 Store 合约实例都可以有一个特定的版本号
  }

  function setItem(bytes32 key, bytes32 value) external {
    items[key] = value;
    emit ItemSet(key, value); // 触发（发出）之前声明的 ItemSet 事件，并将刚刚设置的 key 和 value 作为事件的参数记录下来
  }
}