
多签钱包的功能: 合约有多个 owner，一笔交易发出后，需要多个 owner 确认，确认数达到最低要求数之后，才可以真正的执行。
### 1.原理
- 部署时候传入地址参数和需要的签名数
  - 多个 owner 地址
  - 发起交易的最低签名数
- 有接受 ETH 主币的方法，
- 除了存款外，其他所有方法都需要 owner 地址才可以触发
- 发送前需要检测是否获得了足够的签名数
- 使用发出的交易数量值作为签名的凭据 ID（类似上么）
- 每次修改状态变量都需要抛出事件
- 允许批准的交易，在没有真正执行前取消。
- 足够数量的 approve 后，才允许真正执行。
### 2.代码
这个多签名钱包合约允许多个所有者共同管理合约中的以太币。合约的主要功能包括：

提交交易：任何所有者可以提交交易，指定接收地址、金额和数据。
批准交易：所有者可以批准尚未执行的交易，只有在达到所需的批准数量后，交易才能被执行。
执行交易：当交易获得足够的批准后，任何所有者都可以执行该交易。
撤销批准：所有者可以撤销对尚未执行的交易的批准。
合约通过事件记录重要操作，确保透明性和可追溯性。

```
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
contract MultiSigWallet {
    // 状态变量
    address[] public owners;
    // 映射 isOwner，用于检查某个地址是否为钱包的所有者
    mapping(address => bool) public isOwner;3
    // 公共状态变量 required，表示执行交易所需的批准数量
    uint256 public required;
    // 结构体 Transaction 用于表示交易的相关信息，包括接收地址、金额、数据和是否已执行的状态。
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool exected;
    }
    //公共状态变量 transactions，用于存储所有的交易。
    Transaction[] public transactions;
    // 映射 approved，用于记录每个交易的批准状态。
    mapping(uint256 => mapping(address => bool)) public approved;

    //事件 
    event Deposit(address indexed sender, uint256 amount); // 事件Deposit，在接收到以太币时触发，记录发送者地址,金额
    event Submit(uint256 indexed txId); //事件 Submit，在提交交易时触发，记录交易 ID
    event Approve(address indexed owner, uint256 indexed txId); //事件 Approve，在批准交易时触发，记录批准者地址和交易 ID
    event Revoke(address indexed owner, uint256 indexed txId); //事件 Revoke，在撤销批准时触发，记录撤销者地址和交易 ID。
    event Execute(uint256 indexed txId); //事件 Execute，在执行交易时触发，记录交易 ID
    // receive
    receive() external payable {
    	// 当合约接收到以太币时触发 Deposit 事件
        emit Deposit(msg.sender, msg.value);
    }
    // 函数修改器 : 用于限制只有所有者可以调用某些函数
    modifier onlyOwner() {
        require(isOwner[msg.sender], "not owner");
        _;
    }
    // 定义一个修改器 txExists，用于检查交易是否存在
    modifier txExists(uint256 _txId) {
        require(_txId < transactions.length, "tx doesn't exist");
        _;
    }
    // 定义一个修改器 notApproved，用于检查交易是否未被批准
    modifier notApproved(uint256 _txId) {
        require(!approved[_txId][msg.sender], "tx already approved");
        _;
    }
    //  定义一个修改器 notExecuted，用于检查交易是否未被执行
    modifier notExecuted(uint256 _txId) {
        require(!transactions[_txId].exected, "tx is exected");
        _;
    }
    // 构造函数 接受所有者地址数组和所需批准数量
    constructor(address[] memory _owners, uint256 _required) {
    	//检查所有者数组的长度是否大于 0。
        require(_owners.length > 0, "owner required");
        // 检查输入合理 ： 所需批准数量是否有效。
        require(
            _required > 0 && _required <= _owners.length,  
            "invalid required number of owners"
        );
        // 遍历所有者数组。
        for (uint256 index = 0; index < _owners.length; index++) {
        	//获取当前索引的所有者地址。
            address owner = _owners[index];
            // 非零检查 : 所有者地址是否有效 
            require(owner != address(0), "invalid owner");
            // 检查所有者地址是否唯一
            require(!isOwner[owner], "owner is not unique"); // 如果重复会抛出错误
            // 将当前所有者地址标记为有效所有者
            isOwner[owner] = true;
            // 将当前所有者地址添加到 owners 数组
            owners.push(owner);
        }
        // 将所需批准数量设置为构造函数参数 _required。
        required = _required;
    }
    // 函数 查
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
    // 公共函数 submit，用于提交交易，接受接收地址、金额和数据作为参数。该函数只能由所有者调用。
    function submit(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external onlyOwner returns(uint256){
    	//将新交易添加到 transactions 数组中，初始状态为未执行。
        transactions.push(
            Transaction({to: _to, value: _value, data: _data, exected: false})
        );
        // 触发 Submit 事件，记录新交易的 ID。
        emit Submit(transactions.length - 1);
        // 返回新交易的 ID。
        return transactions.length - 1;
    }
    // 公共函数 approv，用于批准交易，接受交易 ID 作为参数。该函数只能由所有者调用，并且必须满足交易存在、未被批准和未执行的条件
    function approv(uint256 _txId)
        external
        onlyOwner
        txExists(_txId)
        notApproved(_txId)
        notExecuted(_txId)
    {
    	// 将调用者的地址标记为已批准该交易。
        approved[_txId][msg.sender] = true;
        emit Approve(msg.sender, _txId); //触发 Approve 事件，记录批准者地址和交易 ID。
    }
    // 执行交易，接受交易 ID 作为参数。该函数只能由所有者调用，并且必须满足交易存在和未执行的条件。
    function execute(uint256 _txId)
        external
        onlyOwner
        txExists(_txId)
        notExecuted(_txId)
    {
    	//检查该交易的批准数量是否达到所需的数量。
        require(getApprovalCount(_txId) >= required, "approvals < required");
        // 获取要执行的交易。
        Transaction storage transaction = transactions[_txId];
        // 将交易状态标记为已执行。
        transaction.exected = true;
        // 调用交易的目标地址，发送指定金额和数据，并捕获调用结果。
        (bool sucess, ) = transaction.to.call{value: transaction.value}(
            transaction.data
        );
        // 检查交易调用是否成功，如果失败则抛出错误。
        require(sucess, "tx failed");
        emit Execute(_txId); // 触发 Execute 事件，记录执行的交易 ID。
    }
    // 公共函数 getApprovalCount，用于获取指定交易的批准数量。
    function getApprovalCount(uint256 _txId)
        public
        view
        returns (uint256 count)
    {	
    	//循环遍历所有者数组。
        for (uint256 index = 0; index < owners.length; index++) {
        	//检查当前所有者是否已批准该交易。
            if (approved[_txId][owners[index]]) {
                count += 1;
            }
        }
    }
    // 公共函数 revoke，用于撤销对交易的批准，接受交易 ID 作为参数。该函数只能由所有者调用，并且必须满足交易存在和未执行的条件
    function revoke(uint256 _txId)
        external
        onlyOwner
        txExists(_txId)
        notExecuted(_txId)
    {
    	// 检查调用者是否已批准该交易，如果没有批准则抛出错误
        require(approved[_txId][msg.sender], "tx not approved");
        // 将调用者的批准状态设置为未批准。
        approved[_txId][msg.sender] = false;
        // 触发 Revoke 事件，记录撤销者地址和交易 ID。
        emit Revoke(msg.sender, _txId);
    }
}
```