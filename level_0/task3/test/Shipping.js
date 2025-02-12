/*
https://github.com/RemoteCodeCamp/openWeb3/blob/main/03.%E4%BD%BF%E7%94%A8Solidity%20%E7%BC%96%E5%86%99%20Ethereum%E6%99%BA%E8%83%BD%E5%90%88%E5%90%8C.md
使用了 Hardhat 和 Chai 来测试你的 Solidity 合约

*/

 const { expect } = require("chai"); 
 const hre = require("hardhat"); 
 describe("Shipping", function () { 
	 let shippingContract; 
	 before(async () => { 
		 // ⽣成合约实例并且复⽤ 
		 shippingContract = await hre.ethers.deployContract("Shipping", []); }); it("should return the status Pending", async function () { 
		 // assert that the value is correct 
		 expect(await shippingContract.Status()).to.equal("Pending"); }); it("should return the status Shipped", async () => { 
		 // Calling the Shipped() function 
		 await shippingContract.Shipped(); 
		 // Checking if the status is Shipped 
		 expect(await shippingContract.Status()).to.equal("Shipped"); 
	 }); 

	// 我们还要测试合约中发送的事件。添加⼀个测试，以确认事件会返回所需的说明。 将此测试放在最后⼀个测试之后
	it("should return correct event description", async () => { 
	// Calling the Delivered() function 
	// Check event description is correct 
	await expect(shippingContract.Delivered()) // 验证事件是否被触发 
	.to.emit(shippingContract, "LogNewAlert") // 验证事件的参数是否符合预期 
	.withArgs("Your package has arrived"); 
	}); 

	/*
在终端中键入以下内容： npx hardhat test test/Shipping.js 应该看到所有测试都成功通过
web3_learning\level_0\task3>npx hardhat test test/Shipping.js

  Shipping
    ✔ should return the status Pending
    ✔ should return the status Shipped
    ✔ should return correct event description

·--------------------------|----------------------------|-------------|-----------------------------·
|   Solc version: 0.8.28   ·  Optimizer enabled: false  ·  Runs: 200  ·  Block limit: 30000000 gas  │
···························|····························|·············|······························
|  Methods                                                                                          │
·············|·············|··············|·············|·············|···············|··············
|  Contract  ·  Method     ·  Min         ·  Max        ·  Avg        ·  # calls      ·  usd (avg)  │
·············|·············|··············|·············|·············|···············|··············
|  Shipping  ·  Delivered  ·           -  ·          -  ·      28097  ·            2  ·          -  │
·············|·············|··············|·············|·············|···············|··············
|  Shipping  ·  Shipped    ·           -  ·          -  ·      45219  ·            1  ·          -  │
·············|·············|··············|·············|·············|···············|··············
|  Deployments             ·                                          ·  % of limit   ·             │
···························|··············|·············|·············|···············|··············
|  Shipping                ·           -  ·          -  ·     307288  ·          1 %  ·          -  │
·--------------------------|--------------|-------------|-------------|---------------|-------------·

  3 passing (746ms)
	*/

 }); 