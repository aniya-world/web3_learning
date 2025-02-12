require("@nomicfoundation/hardhat-toolbox");
// 这里可以配置测试网测试账号啊
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
solidity: { 
   compilers: [ 
     { 
      version: "0.8.28",
     }, 
    ], 
   }, 
}; 
// 保存文件。执行 npx hardhat compile 编译成功后会在artifacts 文件夹生成相应的文件

/*
web3_learning\level_0\task3>npx hardhat compile
Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> contracts/Shipping.sol


Compiled 7 Solidity files successfully (evm target: paris).

执行 npx hardhat compile 编译成功后会在artifacts 文件夹生成相应的文件

请注意，除了合约文件夹中定义的合约外，@openzeppelin/contracts 中的合约也进行了编译。 在继续之前，请确保已成功完成生成。

总结
这个例⼦是 ERC20 代币的⼀个基本而直接的实现。 
你可以看到编写自己的代币合约是多么轻松，这些合约会继承已定义的 ERC 代币标准中的函数和事件。 
请记住，“代币”这个词只是⼀个隐喻。 它是指由计算机网络或区块链网络共同管理的资产或访问权限。 
代币是并入区块链网络的⼀个重要项目。 若要更熟悉代币，请探索 OpenZeppelin 提供的其他代币合约。 尝试创建你自己的代币合约！
*/

