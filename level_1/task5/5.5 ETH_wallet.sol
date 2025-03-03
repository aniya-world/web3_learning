pragma solidity ^0.8.17;
contract EtherWallet {
	//声明了一个可支付的地址类型的公共不可变变量 owner，用于存储合约的拥有者地址
    address payable public immutable owner; 
    // 记录函数名称、发送者地址、发送的以太币数量和附加数据
    event Log(string funName, address from, uint256 value, bytes data);
    constructor() {
        owner = payable(msg.sender); //构造函数，在合约部署时执行。将合约的拥有者设置为部署合约的地址（msg.sender）。
    }
    // 存
    receive() external payable {
    	//当合约接收到以太币时，会触发此函数，并记录日志，包含发送者地址和发送的以太币数量。
        emit Log("receive", msg.sender, msg.value, "");
        /*
        在 Solidity 中，receive() 函数是一个特殊的函数，用于处理接收到的以太币。它的定义方式与普通函数不同，因此不需要使用 function 关键字。以下是一些关于 receive() 函数的关键点：
特殊性：receive() 是一个特殊的接收函数，用于处理直接发送到合约的以太币（例如，使用 send 或 transfer 方法时）。它在合约接收到以太币时自动调用。
无参数和返回值：receive() 函数不接受任何参数，也不返回任何值。这是它与普通函数的一个重要区别。
可支付：receive() 函数必须标记为 payable，以便能够接收以太币。
替代 fallback 函数：在 Solidity 0.6.0 及更高版本中，receive() 函数是处理以太币接收的推荐方式，而 fallback() 函数则用于处理其他类型的调用（例如，调用不存在的函数）。
因此，receive() 函数的定义方式是为了简化合约接收以太币的逻辑，使其更清晰和易于使用。
        */
    }
    // 取
    function withdraw1() external {
        require(msg.sender == owner, "Not owner");
        // owner.transfer 相比 msg.sender 更消耗Gas
        // owner.transfer(address(this).balance);  //将合约的全部余额转移给拥有者。
        payable(msg.sender).transfer(100); // 将 100 wei 转移给调用者（合约的拥有者）。
    }
    function withdraw2() external {
        require(msg.sender == owner, "Not owner");
        bool success = payable(msg.sender).send(200); // 将 200 wei 发送给调用者，并将发送结果存储在 success 变量中
        require(success, "Send Failed");
    }
    function withdraw3() external {
        require(msg.sender == owner, "Not owner");
        // 使用 call 方法将合约的全部余额发送给调用者，并将结果存储在 success 变量中。
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Call Failed");
    }
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}