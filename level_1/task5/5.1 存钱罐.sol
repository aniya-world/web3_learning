5.1 存钱罐合约.md


1. 所有人都可以存钱ETH
2. 只有合约 owner 才可以取钱
2. 只要取钱，合约就销毁掉 selfdestruct

扩展：支持主币以外的资产
ERC20
ERC721

pragma solidity ^0.8.17;
contract Bank {
	// 合约拥有者的地址
	address public immutable owner;

	// 定义Deposit事件  用于记录合约中的重要操作，以便在区块链上进行日志记录。
	event Deposit(address _ads, uint256 amount); // 当存款发生时，  会发出Deposit事件
	event Withdraw(uint256 amount);              // 当资金被提取时，会发出Withdraw事件

	// 所有人都可以存钱 通过此函数体现的； receive() 函数允许任何人向合约发送以太币
	// receive() 函数是一个特殊的函数 函数会在合约接收到以太币时被自动调用 这个函数没有参数，也没有返回值
	// 只有在合约接收到以太币时，且没有附带数据时，receive() 函数才会被触发。
	// external：表示这个函数只能被外部调用，不能在合约内部调用. 这意味着任何外部账户（即任何以太坊地址）都可以调用这个函数。
	// payable：表示这个函数可以接收以太币。 / receive() 函数允许任何人向合约发送以太币
	// receive() 函数是 Solidity 中处理接收以太币的专用函数，它会在合约接收到以太币时自动触发，并通过 msg.value 获取接收到的以太币数量。
	receive() external payable {  // 
		// 当合约接收到以太币时，会触发这个事件
		// 当用户通过 send、transfer 或 call 等方式向合约发送以太币时，合约会自动调用 receive() 函数。
		emit Deposit(msg.sender, msg.value); // 记录发送者的地址（msg.sender）和发送的金额（msg.value)
		// msg.value 表示发送到合约的以太币数量。这个值是以 wei 为单位的（1 ether = 10^18 wei）。
	}

	contructor() payable {
		// 构造函数将 owner 变量赋值为部署合约的地址，payable允许合约接受初始的以太币
		owner = msg.sender;  // 在构造函数中，msg.sender 是部署合约的地址。
	}

	// 取款函数
	function withdraw() external {
		require(msg.sender == owner, "Not Owner");
		emit Withdraw(address(this).balance); // 允许拥有者提取合约的全部余额  = 只有合约 owner 才可以取钱
		selfdestruct(payable(msg.sender));  // 销毁合约后，合约将无法再使用
		// selfdestruct 是 Solidity 中的一个特殊函数，用于销毁合约并将合约的以太币余额发送到指定的地址。它是一个非常强大的功能，通常用于合约的生命周期结束时，或者在某些条件下需要清理合约的情况  基本语法selfdestruct(address payable recipient);
	}

	//获取余额  允许任何人查看合约的当前余额
	function getBalance() external view returns (uint256) {
		return address(this).balance;
	}

}

/*
注意事项：
如果合约中定义了 fallback() 函数，且没有定义 receive() 函数，那么当合约接收到以太币时，fallback() 函数会被调用。
如果合约接收到以太币时附带了数据，receive() 函数不会被调用，而是会调用 fallback() 函数。
*/