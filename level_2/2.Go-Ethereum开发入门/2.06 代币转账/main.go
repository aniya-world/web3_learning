package main

import (
    "context"
    "crypto/ecdsa"
    "fmt"
    "log"
    "math/big"

    "golang.org/x/crypto/sha3"

    "github.com/ethereum/go-ethereum"
    "github.com/ethereum/go-ethereum/common"
    "github.com/ethereum/go-ethereum/common/hexutil"
    "github.com/ethereum/go-ethereum/core/types"
    "github.com/ethereum/go-ethereum/crypto"
    "github.com/ethereum/go-ethereum/ethclient"
)

func main() {
    client, err := ethclient.Dial("https://eth-sepolia.g.alchemy.com/v2/")
    if err != nil {
        log.Fatal(err)
    }

    privateKey, err := crypto.HexToECDSA("账户私钥") //将十六进制格式的私钥转换为 ECDSA 私钥对象。私钥用于签名交易
    if err != nil {
        log.Fatal(err)
    }

    publicKey := privateKey.Public() // 从私钥中获取对应的公钥
    publicKeyECDSA, ok := publicKey.(*ecdsa.PublicKey) // 将公钥断言为 *ecdsa.PublicKey 类型，以便后续使用。
    if !ok {
        log.Fatal("cannot assert type: publicKey is not of type *ecdsa.PublicKey")
    }

    fromAddress := crypto.PubkeyToAddress(*publicKeyECDSA) // 公钥计算出以太坊地址（即发送者地址）
    nonce, err := client.PendingNonceAt(context.Background(), fromAddress) // 获取发送者地址的当前 nonce 值
    if err != nil {
        log.Fatal(err)
    }

    value := big.NewInt(0) // 定义交易的金额，这里设置为 0 wei，因为我们要发送的是代币，而不是 ETH
    gasPrice, err := client.SuggestGasPrice(context.Background()) // 请求以太坊网络建议的 gas 价格
    if err != nil {
        log.Fatal(err)
    }
    // gasPrice = big.NewInt(0).Add(gasPrice, big.NewInt(10000000000))
    // 创建一个新的 big.Int 对象，初始值为 0。big.Int 是 Go 语言中用于处理大整数的类型，适用于以太坊中常用的 wei 单位。
    // Add 方法用于将两个 big.Int 对象相加。在这里，它将当前的 gasPrice（即从以太坊网络获取的建议 gas 价格）与一个新的 big.Int 对象（其值为 10 Gwei，即 10,000,000,000 wei）相加。
    // 10 Gwei 是一个常见的 gas 价格增量，通常用于确保交易在网络中更快地被处理。
    toAddress := common.HexToAddress("0x4592d8f8d7b001e72cb26a73e4fa1806a51ac79d") // 将目标地址（接收者地址）从十六进制字符串转换为以太坊地址
    tokenAddress := common.HexToAddress("0x28b149020d2152179873ec60bed6bf7cd705775d") // 将代币合约地址从十六进制字符串转换为以太坊地址

    transferFnSignature := []byte("transfer(address,uint256)") // 定义 ERC20 代币合约的 transfer 函数的签名，用于构造交易数据
    /*
    这行代码的目的是将 transfer 函数的签名转换为字节切片，以便在后续的交易数据构造中使用。
    具体来说，ERC20 代币的 transfer 函数在以太坊网络中调用时，需要将函数签名的哈希值作为交易数据的一部分。

    ## 使用场景
    在构造 ERC20 代币转账交易时，您需要将函数签名的哈希值（前 4 个字节）作为交易数据的开头，后面跟着接收者地址和转账金额。
    这样，矿工在处理交易时就能识别出这是一个调用 transfer 函数的请求。
    */
    hash := sha3.NewLegacyKeccak256() // 创建一个新的 Keccak256 哈希对象，用于计算函数签名的哈希值
    hash.Write(transferFnSignature) // 函数签名写入哈希对象
    methodID := hash.Sum(nil)[:4]   // 计算哈希值并取前 4 个字节，作为方法 ID
    fmt.Println(hexutil.Encode(methodID)) // 0xa9059cbb  打印方法 ID 的十六进制编码
    paddedAddress := common.LeftPadBytes(toAddress.Bytes(), 32) // 将接收者地址填充到 32 字节，以符合以太坊交易数据格式
    fmt.Println(hexutil.Encode(paddedAddress)) // 0x0000000000000000000000004592d8f8d7b001e72cb26a73e4fa1806a51ac79d 
    
    // 创建一个新的 big.Int 对象 amount，并将其设置为 1000 代币的数量（以 wei 为单位）。在 ERC20 代币中，通常代币的最小单位是 wei，因此这里的值是 1000 乘以 10 的 18 次方
    amount := new(big.Int)
    amount.SetString("1000000000000000000000", 10) // 1000 tokens

    // 将代币数量填充到 32 字节，以符合以太坊交易数据格式
    paddedAmount := common.LeftPadBytes(amount.Bytes(), 32)
    fmt.Println(hexutil.Encode(paddedAmount)) // 0x00000000000000000000000000000000000000000000003635c9adc5dea00000
    
    // 定义一个字节切片 data，用于存储构造的交易数据
    var data []byte
    data = append(data, methodID...)
    data = append(data, paddedAddress...) // 添加填充后的接收者地址
    data = append(data, paddedAmount...)  // 添加填充后的代币数量

    // 使用 EstimateGas 方法估算执行该交易所需的 gas 限制
    gasLimit, err := client.EstimateGas(context.Background(), ethereum.CallMsg{
        To:   &toAddress,
        Data: data,
    })
    if err != nil {
        log.Fatal(err)
    }

    // gasLimit := uint64(100000)
    fmt.Println(gasLimit) // 23256

    // 创建一个新的交易对象，包含 nonce、代币合约地址、转账金额（0 wei）、估算的 gas 限制、建议的 gas 价格和构造的交易数据
    tx := types.NewTransaction(nonce, tokenAddress, value, gasLimit, gasPrice, data)

    chainID, err := client.NetworkID(context.Background())
    if err != nil {
        log.Fatal(err)
    }

    signedTx, err := types.SignTx(tx, types.NewEIP155Signer(chainID), privateKey)
    if err != nil {
        log.Fatal(err)
    }

    err = client.SendTransaction(context.Background(), signedTx)
    if err != nil {
        log.Fatal(err)
    }

    fmt.Printf("tx sent: %s", signedTx.Hash().Hex()) // tx sent: 0xa56316b637a94c4cc0331c73ef26389d6c097506d581073f927275e7a6ece0bc
}