package main

import (
	"context"
	"fmt"
	"log"
	"math"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
)

func main() {
	client, err := ethclient.Dial("https://sepolia.infura.io/v3/7b17119e325545f9b000356999f07ac4")
	if err != nil {
		log.Fatal(err)
	}
	// hex str to account addr;  定义要查询的账户地址  将一个十六进制字符串表示的以太坊地址转换为 common.Address 类型，这是 go-ethereum 库中用来表示以太坊地址的官方类型
	account := common.HexToAddress("0x25836239F7b632635F815689389C537133248edb")
	balance, err := client.BalanceAt(context.Background(), account, nil)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(balance)
	blockNumber := big.NewInt(5532993)
	balanceAt, err := client.BalanceAt(context.Background(), account, blockNumber)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(balanceAt) // 25729324269165216042
	fbalance := new(big.Float)
	fbalance.SetString(balanceAt.String())
	ethValue := new(big.Float).Quo(fbalance, big.NewFloat(math.Pow10(18))) // 除以10^18 转换为标准的eth单位下的余额
	fmt.Println(ethValue)                                                  // 25.729324269165216041
	pendingBalance, err := client.PendingBalanceAt(context.Background(), account)
	fmt.Println(pendingBalance) // 25729324269165216042
}

/*
329220112897913554
0
0
329220112897913554
*/
