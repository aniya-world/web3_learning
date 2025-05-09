/*
npm install -g solc
solcjs --version

go install github.com/ethereum/go-ethereum/cmd/abigen@latest
abigen --abi=IERC20Metadata_sol_IERC20Metadata.abi --pkg=token --out=erc20.go
*/
package main

import (
	"fmt"
	"log"
	"math"
	"math/big"

	token "erc20/erc20" // for demo  导入本地的 token 包，这通常是 abigen 工具根据 ERC20 ABI 生成的 Go 代码
	// 它导入了当前目录下 contracts_erc20 子目录中的一个名为 token 的包。这个包通常不是手动编写的，而是使用 go-ethereum 提供的 abigen 工具，根据 ERC20 代币的 ABI（描述了合约的接口和函数）自动生成的 Go 代码文件。这个生成的代码会包含一个与合约同名的结构体（例如 Token）以及合约中所有公共函数的 Go 方法。

	"github.com/ethereum/go-ethereum/accounts/abi/bind" // 用于与智能合约绑定的辅助库
	"github.com/ethereum/go-ethereum/common"            // 包含以太坊常用的工具和数据类型，如地址
	"github.com/ethereum/go-ethereum/ethclient"         // 以太坊客户端库
)

func main() {
	client, err := ethclient.Dial("https://eth-sepolia.g.alchemy.com/v2/9LURSvm6osXr98M_7j_AfY4fdhs2J9WL")
	if err != nil {
		log.Fatal(err)
	}
	// 2. Golem (GNT) 代币的合约地址
	tokenAddress := common.HexToAddress("0xfadea654ea83c00e5003d2ea15c59830b65471c0") // 将十六进制字符串表示的 Golem (GNT) 代币的智能合约地址转换为 common.Address 类型
	instance, err := token.NewToken(tokenAddress, client)                             // 3. 创建 ERC20 代币合约的实例  token.NewToken(...): 这是调用由 abigen 生成的 token 包中的构造函数
	if err != nil {
		log.Fatal(err)
	}
	address := common.HexToAddress("0x25836239F7b632635F815689389C537133248edb")
	bal, err := instance.BalanceOf(&bind.CallOpts{}, address)
	if err != nil {
		log.Fatal(err)
	}
	name, err := instance.Name(&bind.CallOpts{})
	if err != nil {
		log.Fatal(err)
	}
	symbol, err := instance.Symbol(&bind.CallOpts{})
	if err != nil {
		log.Fatal(err)
	}
	decimals, err := instance.Decimals(&bind.CallOpts{})
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("name: %s\n", name)         // "name: Golem Network"
	fmt.Printf("symbol: %s\n", symbol)     // "symbol: GNT"
	fmt.Printf("decimals: %v\n", decimals) // "decimals: 18"
	fmt.Printf("wei: %s\n", bal)           // "wei: 74605500647408739782407023"
	fbal := new(big.Float)
	fbal.SetString(bal.String())
	value := new(big.Float).Quo(fbal, big.NewFloat(math.Pow10(int(decimals))))
	fmt.Printf("balance: %f", value) // "balance: 74605500.647409"
}

/*

 */
