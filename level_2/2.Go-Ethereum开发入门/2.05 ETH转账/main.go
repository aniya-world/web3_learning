package main

import (
    "context"
    "crypto/ecdsa"
    "fmt"
    "log"
    "math/big"

    "github.com/ethereum/go-ethereum/common"
    "github.com/ethereum/go-ethereum/core/types"
    "github.com/ethereum/go-ethereum/crypto"
    "github.com/ethereum/go-ethereum/ethclient"
)

func main() {
    client, err := ethclient.Dial("https://eth-sepolia.g.alchemy.com/v2/2LsRSvm6osXr98M_1j_AfY4fdhs2J9WL") //这里连接的是 Rinkeby 测试网络，通过 Infura 提供的节点。client 是与以太坊节点的连接，err 用于捕获连接过程中可能出现的错误
    if err != nil {
        log.Fatal(err)
    }

    privateKey, err := crypto.HexToECDSA("fad9c8855b740a0b7ed4c221dbad0f33a83a49cad6b3fe8d5817ac83d38b6a19") //将十六进制格式的私钥转换为 ECDSA 私钥对象。私钥用于签名交易
    if err != nil {
        log.Fatal(err)
    }

    publicKey := privateKey.Public() //检查私钥转换是否成功
    publicKeyECDSA, ok := publicKey.(*ecdsa.PublicKey) //从私钥中获取对应的公钥  将公钥断言为 *ecdsa.PublicKey 类型，以便后续使用。
    if !ok {
        log.Fatal("cannot assert type: publicKey is not of type *ecdsa.PublicKey")
    }

    fromAddress := crypto.PubkeyToAddress(*publicKeyECDSA) //根据公钥计算出以太坊地址（即发送者地址）
    nonce, err := client.PendingNonceAt(context.Background(), fromAddress) //获取发送者地址的当前 nonce 值。nonce 是一个计数器，用于防止重放攻击，确保每笔交易都是唯一的
    if err != nil {
        log.Fatal(err)
    }

    value := big.NewInt(1000000000000000000) // 定义交易的金额，这里是 1 ETH，单位是 wei（以太坊的最小单位）。
    gasLimit := uint64(21000)                // 定义交易的 gas 限制，这里设置为 21000，这是发送 ETH 交易的标准 gas 限制
    gasPrice, err := client.SuggestGasPrice(context.Background()) //请求以太坊网络建议的 gas 价格，以便在交易中使用
    if err != nil {
        log.Fatal(err) //检查获取 gas 价格是否成功
    }

    toAddress := common.HexToAddress("0x4592d8f8d7b001e72cb26a73e4fa1806a51ac79d") //将目标地址（接收者地址）从十六进制字符串转换为以太坊地址。
    var data []byte //定义交易数据，这里为空，因为这是一个简单的 ETH 转账交易

    ///  创建一个新的交易对象，包含 nonce、接收者地址、转账金额、gas 限制、gas 价格和交易数据
    tx := types.NewTransaction(nonce, toAddress, value, gasLimit, gasPrice, data)
    ///

    chainID, err := client.NetworkID(context.Background())  //获取当前网络的链 ID，以便在签名交易时使用
    if err != nil {
        log.Fatal(err)
    }

    signedTx, err := types.SignTx(tx, types.NewEIP155Signer(chainID), privateKey) //使用私钥对交易进行签名，使用 EIP-155 签名器来确保交易的有效性
    if err != nil {
        log.Fatal(err)
    }

    err = client.SendTransaction(context.Background(), signedTx) //将签名后的交易发送到以太坊网络
    if err != nil {
        log.Fatal(err)
    }

    fmt.Printf("tx sent: %s", signedTx.Hash().Hex())
}