package main

/*
这段代码是用 Go 语言编写的，主要用于生成以太坊的公钥和地址。以下是代码的详细介绍：

主要功能
生成私钥：使用 crypto.GenerateKey() 生成一个新的以太坊私钥。
导出私钥和公钥：将生成的私钥和公钥转换为字节数组，并以十六进制格式输出。
计算以太坊地址：根据公钥计算以太坊地址，并输出。
*/
import (
	"crypto/ecdsa" // 用于处理椭圆曲线数字签名算法（ECDSA）
	"fmt"
	"log"

	"github.com/ethereum/go-ethereum/common/hexutil" //以太坊 Go 客户端库
	"github.com/ethereum/go-ethereum/crypto"
	"golang.org/x/crypto/sha3"
)

func main() {
	privateKey, err := crypto.GenerateKey() // 生成一个新的 ECDSA 私钥。如果生成失败，记录错误并退出
	if err != nil {
		log.Fatal(err)
	}
	// 导出私钥
	privateKeyBytes := crypto.FromECDSA(privateKey)  // 将私钥转换为字节数组，
	fmt.Println(hexutil.Encode(privateKeyBytes)[2:]) // 并以十六进制格式输出，去掉前缀 0x

	// 导出公钥
	publicKey := privateKey.Public()                   //从私钥中获取公钥，
	publicKeyECDSA, ok := publicKey.(*ecdsa.PublicKey) // 并确保其类型为 *ecdsa.PublicKey
	if !ok {
		log.Fatal("cannot assert type: publicKey is not of type *ecdsa.PublicKey")
	}

	publicKeyBytes := crypto.FromECDSAPub(publicKeyECDSA)
	fmt.Println("from pubKey:", hexutil.Encode(publicKeyBytes)[4:]) // 去掉'0x04'

	// 计算以太坊地址
	address := crypto.PubkeyToAddress(*publicKeyECDSA).Hex() // 使用 PubkeyToAddress 函数将公钥转换为以太坊地址，并输出。
	fmt.Println(address)

	// 计算公钥的 SHA3 哈希
	hash := sha3.NewLegacyKeccak256()
	hash.Write(publicKeyBytes[1:])
	fmt.Println("full:", hexutil.Encode(hash.Sum(nil)[:]))
	fmt.Println(hexutil.Encode(hash.Sum(nil)[12:])) // 原长32位，截去12位，保留后20位
	// 使用 SHA3 哈希算法计算公钥的哈希值，并输出完整的哈希值和最终的以太坊地址（后 20 字节）
}

/*
7590010ff88b91735f61422ebdcff49a9a13462ac5f34980a0d41b01be529b8a
from pubKey: ddb2d68437ff4063ca8439011bf1101e75236019769b4254c455ecba886b7e28d011e4859636ee1ba0b1af780532f4eb25825ccf35380a360b90ab7df5ba062b
0xB4468e5d6E287270e777C5945facc348Dc6E82B5 哈希是一样的

full: 0x308ad0cff1916df182a80a4db4468e5d6e287270e777c5945facc348dc6e82b5
0xb4468e5d6e287270e777c5945facc348dc6e82b5  哈希是一样的
*/
