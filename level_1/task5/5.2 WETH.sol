WETH 是包装 ETH 主币，作为 ERC20 的合约。
标准的 ERC20 合约包括如下几个
- 3 个查询
  - balanceOf: 查询指定地址的 Token 数量
  - allowance: 查询指定地址对另外一个地址的剩余授权额度
  - totalSupply: 查询当前合约的 Token 总量
- 2 个交易
  - transfer: 从当前调用者地址发送指定数量的 Token 到指定地址。
    - 这是一个写入方法，所以还会抛出一个 Transfer 事件。
  - transferFrom: 当向另外一个合约地址存款时，对方合约必须调用 transferFrom 才可以把 Token 拿到它自己的合约中。
- 2 个事件
  - Transfer
  - Approval
- 1 个授权
  - approve: 授权指定地址可以操作调用者的最大 Token 数量。

该合约允许用户存入以太币（Ether），并获得相应的 WETH 代币，同时也可以通过销毁 WETH 代币来提取以太币。
```
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
contract WETH {
	//状态变量
    string public name = "Wrapped Ether"; // 代币名
    string public symbol = "WETH";  // 代币的符号（"WETH"）
    uint8 public decimals = 18;     // 代币的小数位数（18）

    // 事件
    event Approval(address indexed src, address indexed delegateAds, uint256 amount); //当用户批准某个地址可以支配其代币时触发
    event Transfer(address indexed src, address indexed toAds, uint256 amount);// 当代币转移时触发
    event Deposit(address indexed toAds, uint256 amount); // 用户存入以太币时触发
    event Withdraw(address indexed src, uint256 amount); // 当用户提取以太币时触发

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;// 外层映射将代币持有者的地址 映射到内层映射 是被授权者的地址 映射到一个无符号整数（uint256），表示该被授权者可以从外层映射的地址中支配的代币数量

    // 函数 
    function deposit() public payable { 
    	// 允许用户存入以太币，并更新其余额，同时触发 Deposit 事件
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }
    // 允许用户提取指定数量的以太币，前提是其余额足够，并触发 Withdraw 事件
    function withdraw(uint256 amount) public {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit Withdraw(msg.sender, amount);
    }
    //  返回合约当前持有的以太币总量
    function totalSupply() public view returns (uint256) {
        return address(this).balance;
    }
    // 允许某个地址支配用户的代币，并触发 Approval 事件。
    function approve(address delegateAds, uint256 amount) public returns (bool) {
    	// delegateAds: 这是函数参数，表示被授权的地址。这个地址将被允许在授权额度内转移调用者的代币
    	// amount: 这是函数参数，表示授权的代币数量
    	// allowance 允许用户授权其他地址在一定额度内转移其代币
    	// 作用是设置一个地址（delegateAds）可以从调用者（msg.sender）的账户中支配的代币数量
        allowance[msg.sender][delegateAds] = amount; // 设置授权额度
        // 在此函数中，msg.sender 是发起授权操作的用户
        emit Approval(msg.sender, delegateAds, amount); // 触发 Approval 事件
        return true; 
    }
    //  从调用者的账户转移代币到指定地址
    function transfer(address toAds, uint256 amount) public returns (bool) {
        return transferFrom(msg.sender, toAds, amount);
    }
    // 从src地址转移代币到toAds目标地址，支持授权转账
    function transferFrom(
        address src, // 代币的源地址
        address toAds, // 这是目标地址 代币将被转移到的地址
        uint256 amount // 要转移的代币数量
    ) public returns (bool) {
        require(balanceOf[src] >= amount); // 确保源地址 src 的余额足够进行此次转移
        if (src != msg.sender) { // 首先检查 src 是否与调用者（msg.sender）相同。如果不同，说明调用者是一个被授权的地址。
            require(allowance[src][msg.sender] >= amount); // 然后，它检查调用者是否有足够的授权额度
            allowance[src][msg.sender] -= amount;  //调用者的授权额度将减少相应的 amount
        }
        balanceOf[src] -= amount;  //  更新余额
        balanceOf[toAds] += amount;//  更新余额
        emit Transfer(src, toAds, amount); //这行代码触发 Transfer 事件，记录此次转移的详细信息，包括源地址、目标地址和转移的数量。
        return true;
    }
    fallback() external payable {
        deposit(); //当合约接收到以太币但没有数据时调用，自动调用 deposit() 函数
    }
    receive() external payable {
        deposit(); // 当合约接收到以太币时调用，自动调用 deposit() 函数
    }
}
```