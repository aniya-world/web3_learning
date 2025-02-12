// from https://github.com/RemoteCodeCamp/openWeb3/blob/main/03.%E4%BD%BF%E7%94%A8Solidity%20%E7%BC%96%E5%86%99%20Ethereum%E6%99%BA%E8%83%BD%E5%90%88%E5%90%8C.md
const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules"); 
module.exports = buildModule("ShippingModule", (m) => { 
	const shipping = m.contract("Shipping", []); 
	m.call(shipping, "Status", []);
	return { shipping }; 
}); 

// \web3_learning\level_0\task3>npx hardhat ignition deploy ignition/modules/Shipping.js --network localhos