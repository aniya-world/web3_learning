package main

import (
	"context"
	"crypto/ecdsa"
	"errors"
	"fmt"
	"log"
	"math/big"
	"time"

	"github.com/ethereum/go-ethereum" // pack.go里可以看到不同的编码方式， unpack.go里可以看到不太的解码方式
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

const (
	contractAddr = "0x1399E0Fa83fBc9d1f34E16fe8603CF1348aA943B"
)

func main() {
	client, err := ethclient.Dial("https://eth-sepolia.g.alchemy.com/v2/9LURSvm6osXr98M_7j_AfY4fdhs2J9WL")
	if err != nil {
		log.Fatal(err)
	}

	privateKey, err := crypto.HexToECDSA("38edd948f94c292109f1ab6a8315a6d1c2934ee0f514047d41cb7bb25087ff4c")
	if err != nil {
		log.Fatal(err)
	}

	// 获取公钥地址
	publicKey := privateKey.Public()
	publicKeyECDSA, ok := publicKey.(*ecdsa.PublicKey)
	if !ok {
		log.Fatal("error casting public key to ECDSA")
	}
	fromAddress := crypto.PubkeyToAddress(*publicKeyECDSA)

	// 获取 nonce
	nonce, err := client.PendingNonceAt(context.Background(), fromAddress)
	if err != nil {
		log.Fatal(err)
	}

	// 估算 gas 价格
	gasPrice, err := client.SuggestGasPrice(context.Background())
	if err != nil {
		log.Fatal(err)
	}

	// 准备交易数据 （用abi的方式）
	// contractABI, err := abi.JSON(strings.NewReader(`[{"inputs":[{"internalType":"string","name":"_version","type":"string"}],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"bytes32","name":"key","type":"bytes32"},{"indexed":false,"internalType":"bytes32","name":"value","type":"bytes32"}],"name":"ItemSet","type":"event"},{"inputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"name":"items","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32","name":"key","type":"bytes32"},{"internalType":"bytes32","name":"value","type":"bytes32"}],"name":"setItem","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"version","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"}]`))
	// if err != nil {
	// 	log.Fatal(err)
	// }
	// methodName := "setItem"
	// var key [32]byte
	// var value [32]byte
	// copy(key[:], []byte("demo_save_key_use_abi_12"))
	// copy(value[:], []byte("demo_save_value_use_abi_1222"))
	// input, err := contractABI.Pack(methodName, key, value)

	//////////////////////// （不用abi的方式）不同 1. 调用合约前的数据准备
	methodSignature := []byte("setItem(bytes32,bytes32)")   // 定义了智能合约函数的方法签名（method signature）  setItem 是这个函数的名称  两个参数的类型都是 bytes32
	methodSelector := crypto.Keccak256(methodSignature)[:4] // 这行代码计算了方法选择器（method selector）； [:4] 取哈希值的前四个字节。这4个字节的前缀是识别以太坊智能合约交易中要调用哪个函数的标准方式。当你向智能合约发送交易时，交易数据字段的前四个字节告诉合约应该执行哪个函数。

	var key [32]byte
	var value [32]byte
	// 将字符串数据复制到 key 和 value 字节数组中
	copy(key[:], []byte("demo_save_key_no_use_abi"))           //  key[:] 和 value[:] 表示获取 key 和 value 数组的切片，以便 copy 函数可以将字节复制到其中。
	copy(value[:], []byte("demo_save_value_no_use_abi_11111")) //  如果复制的字符串长度不足32字节，剩余的字节会自动用零填充；如果字符串长度超过32字节，则只会复制前32个字节，多余的部分会被截断。

	// 组合调用数据  形成最终的调用数据（call data）
	var input []byte                         // 空的字节切片，用于存储最终的调用数据。
	input = append(input, methodSelector...) // 首先，将4字节的方法选择器添加到 input 中。这是告诉智能合约要调用哪个函数的第一部分
	input = append(input, key[:]...)         // 接着，将 key 的32字节内容添加到 input 中。这是 setItem 函数的第一个参数。
	input = append(input, value[:]...)       // 最后，将 value 的32字节内容添加到 input 中。这是 setItem 函数的第二个参数。
	/// 最终生成的 input 字节切片就是一笔以太坊交易的 data 字段，当这笔交易发送到智能合约地址时，智能合约会解析这个 data 字段，找到 setItem 函数并用 key 和 value 作为参数来执行它。
	////////////////////////

	// 创建交易并签名交易
	chainID := big.NewInt(int64(11155111))
	tx := types.NewTransaction(nonce, common.HexToAddress(contractAddr), big.NewInt(0), 300000, gasPrice, input)
	signedTx, err := types.SignTx(tx, types.NewEIP155Signer(chainID), privateKey)
	if err != nil {
		log.Fatal(err)
	}

	// 发送交易
	err = client.SendTransaction(context.Background(), signedTx)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Transaction sent: %s\n", signedTx.Hash().Hex())
	_, err = waitForReceipt(client, signedTx.Hash())
	if err != nil {
		log.Fatal(err)
	}

	// 查询刚刚设置的值
	// callInput, err := contractABI.Pack("items", key)
	// if err != nil {
	// 	log.Fatal(err)
	// }
	// to := common.HexToAddress(contractAddr)
	// callMsg := ethereum.CallMsg{
	// 	To:   &to,
	// 	Data: callInput,
	// }

	//////////////////////// （不用abi的方式）不同 2. 查询部分，调用合约后的数据解析
	// 以执行一个**本地的、只读的查询（call）**操作，从智能合约中获取 key 对应的值。这种操作不会创建交易，不会消耗Gas，也不会改变区块链的状态，因此通常用于查询合约的公共状态。
	// 构建了一个以太坊调用消息（Ethereum Call Message），用于从智能合约中读取数据
	itemsSignature := []byte("items(bytes32)")            // 定义了智能合约中一个只读函数（view 或 pure function）的方法签名； items 是这个函数的名称，这个函数接受一个 bytes32 类型的参数
	itemsSelector := crypto.Keccak256(itemsSignature)[:4] // 计算了 items 函数的方法选择器  [:4] 取哈希值的前四个字节作为 items 函数的方法选择器
	// 组合了用于调用 items 函数的输入数据（call data）
	var callInput []byte                            // 声明了一个空的字节切片，用于存储最终的调用数据
	callInput = append(callInput, itemsSelector...) // 首先，将4字节的 items 函数的方法选择器添加到 callInput 中。
	callInput = append(callInput, key[:]...)        // 接着，将之前定义并复制了数据的 key （即 "demo_save_key_no_use_abi" 的32字节表示）添加到 callInput 中。这个 key 将作为 items 函数的参数，用于指定要查询的键。

	to := common.HexToAddress(contractAddr) // 将智能合约的地址0x...转换为以太坊 Go 客户端库所需的 common.Address 类型
	callMsg := ethereum.CallMsg{            // 构造了一个 ethereum.CallMsg 结构体，它是进行以太坊调用（call）操作所需的参数
		To:   &to,       // 传入的是 to 变量的地址
		Data: callInput, // 指定了调用 items 函数时要传递的输入数据。这包含了方法选择器和作为参数的 key。
	}

	// 解析返回值
	// result, err := client.CallContract(context.Background(), callMsg, nil)
	// if err != nil {
	// 	log.Fatal(err)
	// }
	// var unpacked [32]byte
	// contractABI.UnpackIntoInterface(&unpacked, "items", result)
	// if err != nil {
	// 	log.Fatal(err)
	// }
	// fmt.Println("is value saving in contract equals to origin value:", unpacked == value)

	result, err := client.CallContract(context.Background(), callMsg, nil) // CallContract：这是 ethclient.Client 提供的一个方法，用于执行一个以太坊的 eth_call RPC 请求。
	if err != nil {
		log.Fatal(err)
	}

	var unpacked [32]byte     // 声明了一个名为 unpacked 的变量，类型是一个固定大小为32字节的字节数组。这个变量将用于存储从智能合约调用结果中解析出来的32字节数据
	copy(unpacked[:], result) // 将从智能合约调用返回的 result 数据复制到 unpacked 数组中
	// result 是一个字节切片，其中包含了 items(bytes32) 函数的返回值。由于 items 函数很可能返回一个 bytes32 类型的值，所以我们期望 result 的长度为32字节。
	fmt.Println("is value saving in contract equals to origin value:", unpacked == value) // 获取 unpacked 数组的一个切片，以便 copy 函数可以将字节复制到这个数组中。

}

func waitForReceipt(client *ethclient.Client, txHash common.Hash) (*types.Receipt, error) {
	for {
		receipt, err := client.TransactionReceipt(context.Background(), txHash)
		if err == nil {
			return receipt, nil
		}
		if !errors.Is(err, ethereum.NotFound) {
			return nil, err
		}
		// 等待一段时间后再次查询
		time.Sleep(1 * time.Second)
	}
}

/*
Transaction sent: 0x0df0a37b1cc8b5192d2d0e602eb0a6312b183e5b254c3dcad1e1f6a16ea0dfa6
is value saving in contract equals to origin value: true

*/
