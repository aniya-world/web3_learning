任务 4️⃣: 👉使用OpenZeppelin创建代币

📖 内容概览：利用OpenZeppelin安全库来创建属于自己的代币。
✅预期成果：了解并能够使用OpenZeppelin来创建和管理代币。
⌛ 预计时间：1小时



# 使用OpenZeppelin创建代币
了解代币的重要性以及它们在区块链中的使用方式。

## 学习目标

说明什么是代币
	表示价值的数字资产
识别不同类型的代币
	可互换代币
	不可互换代币
使用 OpenZeppelin 中的合同库
	了解 OpenZeppelin? 
		是一款开源工具 提供两个产品：合同库和 SDK
		OpenZeppelin 合约库为 Ethereum 网络提供了一组可靠的模块化和可重用的智能合同。 智能合同是在 Solidity 中编写的
		OpenZeppelin 是应用智能合同的行业中最受欢迎的库源，而且是开源的。 使用OpenZeppelin 合同时，你将了解开发智能合同的最佳做法
创建代币智能合同



# 练习 - 设置一个新项目并集成 OpenZeppelin

** 复用上⼀章节创建Hardhat项⽬，然后加入 OpenZeppelin 合约库 **

1. npm install @openzeppelin/contracts  安装包到项目中
	a. 包（"@openzeppelin/contracts": "^5.2.0"）会作为依赖项被添加到了 package.json 文件
	b. 出现文件夹 node_modules，opo 文件夹从 OpenZeppelin 导入了所有可用的合约

	level_0\task3\node_modules\@openzeppelin\contracts 的目录

		2025/02/12  22:34    <DIR>          .
		2025/02/12  22:34    <DIR>          ..
		2025/02/12  22:34    <DIR>          access
		2025/02/12  22:34    <DIR>          account
		2025/02/12  22:34    <DIR>          build
		2025/02/12  22:34    <DIR>          finance
		2025/02/12  22:34    <DIR>          governance
		2025/02/12  22:34    <DIR>          interfaces
		2025/02/12  22:34    <DIR>          metatx
		2025/02/12  22:34               786 package.json
		2025/02/12  22:34    <DIR>          proxy
		2025/02/12  22:34             7,852 README.md
		2025/02/12  22:34    <DIR>          token
		2025/02/12  22:34    <DIR>          utils
		2025/02/12  22:34    <DIR>          vendor
			花些时间查看现可用于你的项目的可用合约源文件。 请特别注意代币合约。 更好地了解每个合约的实 现以及通常提供的具体函数。




# 练习 - 编写⼀个 ERC20 代币合约	

现在我们设置了⼀个基本项⽬，接下来使⽤ OpenZeppelin 的 ERC20 代币标准创建⼀个新的代币合约。



## 为什么说npx hardhat compile编译完成就生成好了合约 合约生成好后是什么样?
当你运行 npx hardhat compile 命令时，Hardhat 会编译你的 Solidity 合约，并生成相应的输出文件。以下是关于编译过程和生成的合约文件的详细信息：

编译过程
源代码解析：Hardhat 会读取你项目中的 Solidity 源代码文件（通常位于 contracts 目录下），并解析这些文件。
语法检查：在编译过程中，Hardhat 会检查合约的语法和结构，确保没有错误。
生成字节码：编译器将 Solidity 源代码转换为字节码，这是以太坊虚拟机（EVM）可以理解和执行的格式。
生成 ABI：同时，编译器还会生成应用程序二进制接口（ABI），这是一个 JSON 格式的描述，定义了合约的函数和事件，使得外部应用程序能够与合约进行交互。
生成的文件
编译完成后，Hardhat 会在项目目录下生成一个 artifacts 文件夹，通常结构如下：

Code

复制代码
your-project/
├── artifacts/
│   └── contracts/
│       └── YourContract.sol/
│           ├── YourContract.json
│           └── YourContract.bytecode
├── contracts/
│   └── YourContract.sol
├── hardhat.config.js
└── ...
1. YourContract.json
这是合约的主要输出文件，包含以下信息：

合约名称：合约的名称。
ABI：合约的应用程序二进制接口，描述了合约的函数和事件。
字节码：合约的字节码，用于在以太坊网络上部署合约。
编译器版本：用于编译合约的 Solidity 编译器版本。
其他元数据：如合约的部署信息、优化设置等。

2. YourContract.bytecode
这个文件包含合约的字节码，通常是一个长字符串，表示合约在 EVM 中的机器代码。

3. 合约生成后的用途
部署合约：你可以使用生成的字节码在以太坊网络上部署合约。
与合约交互：使用 ABI，你可以通过 Web3.js、Ethers.js 等库与合约进行交互，调用合约的函数或监听事件。
测试合约：生成的合约信息可以用于编写测试，确保合约的功能按预期工作。

总结
运行 npx hardhat compile 后，Hardhat 会生成合约的字节码和 ABI，这些信息是与合约进行交互和部署的基础。生成的文件位于 artifacts 目录中，包含了合约的所有必要信息。