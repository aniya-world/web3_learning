
众筹合约是一个募集资金的合约，在区块链上，我们是募集以太币，类似互联网业务的水滴筹。区块链早起的 ICO 就是类似业务。
### 1.需求分析
众筹合约分为两种角色：一个是受益人，一个是资助者。
```
// 两种角色:
//      受益人   beneficiary => address         => address 类型
//      资助者   funders     => address:amount  => mapping 类型 或者 struct 类型
```
```
状态变量按照众筹的业务：
// 状态变量
//      筹资目标数量    fundingGoal
//      当前募集数量    fundingAmount
//      资助者列表      funders
//      资助者人数      fundersKey
```
```
需要部署时候传入的数据:
//      受益人
//      筹资目标数量
```
### 2.演示代码
```
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
contract CrowdFunding {
    //主要变量
    address public immutable beneficiary;   // 受益人 合约部署时指定
    uint256 public immutable fundingGoal;   // 筹资目标数量 
    uint256 public fundingAmount;       // 当前已筹集的金额
    mapping(address=>uint256) public funders; // 一个映射，记录每个捐赠者的捐款金额
    // 可迭代的映射
    mapping(address=>bool) private fundersInserted; // 一个映射，用于跟踪捐赠者是否已被插入到 fundersKey 数组中
    address[] public fundersKey; // length  一个数组，存储所有捐赠者的地址
    // 不用自销毁方法，使用变量来控制
    bool public AVAILABLED = true; // 状态  表示合约是否可用（是否可以接受捐款）
    // 部署的时候，写入受益人+筹资目标数量
    constructor(address beneficiary_,uint256 goal_){
        beneficiary = beneficiary_;
        fundingGoal = goal_;
    }
    // 资助函数
    //      可用的时候才可以捐
    //      合约关闭之后，就不能在操作了
 function contribute() external payable {
        // 首先检查合约是否可用（AVAILABLED）。 抛出错误提示“众筹已关闭”。
        require(AVAILABLED, "CrowdFunding is closed");

        // 检查潜在金额是否会超过目标金额   msg.value 是用户发送的金额。将两者相加，得到潜在的资金总额。
        uint256 potentialFundingAmount = fundingAmount + msg.value;
        uint256 refundAmount = 0; //初始化退款金额

        if (potentialFundingAmount > fundingGoal) {
            refundAmount = potentialFundingAmount - fundingGoal;
            // 计算超出目标金额的部分。如果潜在资金超过目标金额，计算需要退款的金额。
            funders[msg.sender] += (msg.value - refundAmount);
            // 更新捐赠者的捐赠金额。将用户实际捐赠的金额（扣除退款）加到该用户的捐赠记录中。
            fundingAmount += (msg.value - refundAmount);
        } else {
            funders[msg.sender] += msg.value;
            fundingAmount += msg.value;
        }

        // 更新捐赠者信息   fundersInserted 是一个布尔值映射，用于跟踪用户是否已经捐赠过。
        if (!fundersInserted[msg.sender]) {
            fundersInserted[msg.sender] = true; //标记该用户为已捐赠。
            fundersKey.push(msg.sender); // 标记该用户为已捐赠。
        }

        // 退还多余的金额
        if (refundAmount > 0) {
            payable(msg.sender).transfer(refundAmount); // 将多余的金额退还给用户。使用 transfer 方法将退款金额发送给用户。

        }
    }
    // 关闭  用于关闭众筹并将筹集的资金转移给受益人。
    function close() external returns(bool){
        // 1.检查
        if(fundingAmount<fundingGoal){
            return false;
        }
        uint256 amount = fundingAmount; // 当前筹集的金额
        // 2.修改
        fundingAmount = 0;  // 将筹集金额重置为0，表示众筹已关闭。
        AVAILABLED = false; // 众筹已关闭
        // 3. 操作
        payable(beneficiary).transfer(amount);  // 将筹集的金额转移给受益人
        return true; //表示众筹成功关闭并且资金已转移
    }
    //定义一个公共可调用的视图函数 fundersLenght，用于返回捐赠者的数量。
    function fundersLenght() public view returns(uint256){
        return fundersKey.length;
    }
}
```
上面的合约只是一个简化版的 众筹合约，但它已经足以让我们理解本节介绍的类型概念。