package main

import (
	"context"
	"fmt"
	"log"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
)

func main() {
	client, err := ethclient.Dial("https://sepolia.infura.io/v3/7b17119e325545f9b000356999f07ac4")
	if err != nil {
		log.Fatal(err)
	}
	////// Method 1 : 当使用 `BlockByNumber` 方法获取到完整的区块信息之后，可以调用区块实例的 `Transactions` 方法来读取块中的交易，该方法返回一个 `Transaction` 类型的列表。 循环遍历集合并获取交易的信息。

	// show the chain called id;  restore sender addr needs it
	// 使用 context.Background() 通常表示你没有特定的上下文需求，适用于根级别的请求或在没有其他上下文可用的情况下使用
	chainID, err := client.ChainID(context.Background())
	if err != nil {
		log.Fatal(err)
	}

	// get the block 5671744
	blockNumber := big.NewInt(5671744)
	block, err := client.BlockByNumber(context.Background(), blockNumber)
	if err != nil {
		log.Fatal(err)
	}

	for _, tx := range block.Transactions() {
		fmt.Println(tx.Hash().Hex())        // 0x20294a03e8766e9aeab58327fc4112756017c6c28f6f99c7722f4a29075601c5
		fmt.Println(tx.Value().String())    // 100000000000000000
		fmt.Println(tx.Gas())               // 21000
		fmt.Println(tx.GasPrice().Uint64()) // 100000000000
		fmt.Println(tx.Nonce())             // 245132
		fmt.Println(tx.Data())              // []
		fmt.Println(tx.To().Hex())          // 0x8F9aFd209339088Ced7Bc0f57Fe08566ADda3587

		// restore sender addr
		if sender, err := types.Sender(types.NewEIP155Signer(chainID), tx); err == nil {
			fmt.Println("sender", sender.Hex()) // 0x2CdA41645F2dBffB852a605E92B185501801FC28
		} else {
			log.Fatal(err)
		}

		// query the receipt through tx hash
		receipt, err := client.TransactionReceipt(context.Background(), tx.Hash())
		if err != nil {
			log.Fatal(err)
		}

		fmt.Println(receipt.Status) // 1
		fmt.Println(receipt.Logs)   // []

		// only query the latest block
		break
	}

	//////  Method 2: query the latest block

	// 获取区块哈希  将一个十六进制字符串转换为以太坊的哈希值，表示一个特定的区块
	blockHash := common.HexToHash("0xae713dea1419ac72b928ebe6ba9915cd4fc1ef125a606f90f5e783c47cb1a4b5")
	// 获取区块中的交易数量
	count, err := client.TransactionCount(context.Background(), blockHash)
	if err != nil {
		log.Fatal(err) // 如果发生错误，则记录错误并终止程序
	}
	// 遍历区块中的交易
	for idx := uint(0); idx < count; idx++ {
		// 对于每个交易，调用 client.TransactionInBlock 方法获取交易信息，并打印交易的哈希值
		tx, err := client.TransactionInBlock(context.Background(), blockHash, idx)
		if err != nil {
			log.Fatal(err)
		}
		// 打印交易哈希
		fmt.Println(tx.Hash().Hex()) // 0x20294a03e8766e9aeab58327fc4112756017c6c28f6f99c7722f4a29075601c5
		break                        // 只处理第一个交易
	}
	// 获取特定交易的详细信息
	txHash := common.HexToHash("0x20294a03e8766e9aeab58327fc4112756017c6c28f6f99c7722f4a29075601c5") // 先将一个交易哈希转换为哈希值
	tx, isPending, err := client.TransactionByHash(context.Background(), txHash)                     //然后调用 client.TransactionByHash 方法获取该交易的详细信息; 该方法还返回一个布尔值 isPending
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(isPending)
	fmt.Println(tx.Hash().Hex()) // 0x20294a03e8766e9aeab58327fc4112756017c6c28f6f99c7722f4a29075601c5.Println(isPending)       // false
}

/*
go run main.go
0x20294a03e8766e9aeab58327fc4112756017c6c28f6f99c7722f4a29075601c5
100000000000000000
21000
100000000000
245132
[]
0x8F9aFd209339088Ced7Bc0f57Fe08566ADda3587
sender 0x2CdA41645F2dBffB852a605E92B185501801FC28
1
[]
0x20294a03e8766e9aeab58327fc4112756017c6c28f6f99c7722f4a29075601c5
false
0x20294a03e8766e9aeab58327fc4112756017c6c28f6f99c7722f4a29075601c5

总结
这段代码展示了如何使用 Go 语言与以太坊区块链进行交互，获取特定区块中的交易数量，遍历交易并获取特定交易的详细信息。通过这些操作，可以实现对以太坊区块链的基本查询和操作。
*/
