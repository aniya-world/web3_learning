package main

import (
    "context"
    "fmt"
    "log"
    "math/big"
    "strings"

    "github.com/ethereum/go-ethereum"
    "github.com/ethereum/go-ethereum/accounts/abi"
    "github.com/ethereum/go-ethereum/common"
    "github.com/ethereum/go-ethereum/crypto"
    "github.com/ethereum/go-ethereum/ethclient"
)
// 合约 ABI
var StoreABI = `[{"inputs":[{"internalType":"string","name":"_version","type":"string"}],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"bytes32","name":"key","type":"bytes32"},{"indexed":false,"internalType":"bytes32","name":"value","type":"bytes32"}],"name":"ItemSet","type":"event"},{"inputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"name":"items","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32","name":"key","type":"bytes32"},{"internalType":"bytes32","name":"value","type":"bytes32"}],"name":"setItem","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"version","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"}]`

func main() {
	//连接到以太坊节点
    client, err := ethclient.Dial("https://eth-sepolia.g.alchemy.com/v2/API_KEY")
    if err != nil {
        log.Fatal(err)
    }

    contractAddress := common.HexToAddress("0x2958d15bc5b64b11Ec65e623Ac50C198519f8742")

    // 定义过滤器 (FilterQuery)   创建一个 FilterQuery 对象，用于定义过滤日志的规则。
    query := ethereum.FilterQuery{
        FromBlock: big.NewInt(6920583),
        // ToBlock:   big.NewInt(2394201),  
        Addresses: []common.Address{
            contractAddress,
        },
        // Topics: [][]common.Hash{
        //  {},
        //  {},
        // }, 被注释掉的 ToBlock 和 Topics 是其他可选的过滤条件。ToBlock 可以指定结束区块，Topics 可以用来更精确地过滤特定事件或带有特定索引参数的事件
    }

    // eth节点会返回所有匹配条件的日志（logs）
    logs, err := client.FilterLogs(context.Background(), query)
    if err != nil {
        log.Fatal(err)
    }

    // 解析 ABI 并遍历日志
    contractAbi, err := abi.JSON(strings.NewReader(StoreABI)) //abi.JSON: 将之前定义的 StoreABI 字符串解析成一个 abi.ABI 对象 (contractAbi)。这个对象包含了反序列化日志数据所需的方法和类型信息
    if err != nil {
        log.Fatal(err)
    }

    for _, vLog := range logs {  //vLog 包含了很多元数据，如区块哈希、区块号、交易哈希等。
    	// ... 日志处理 ...
        fmt.Println(vLog.BlockHash.Hex()) // 打印日志所在区块的哈希
        fmt.Println(vLog.BlockNumber)
        fmt.Println(vLog.TxHash.Hex())  // 打印产生此日志的交易哈希
        event := struct {
            Key   [32]byte
            Value [32]byte
        }{}

        // 解析的核心部分
        err := contractAbi.UnpackIntoInterface(&event, "ItemSet", vLog.Data)  // 告诉 Unpack 方法我们要解析的是名为 ItemSet 的事件
        	// vLog.Data: 这是日志中包含的未被索引 (non-indexed) 的参数数据。对于 ItemSet 事件，value 字段是未被索引的。
        	// &event: Unpack 方法会将解析出的数据填充到这个结构体中。
        if err != nil {
            log.Fatal(err)
        }

        fmt.Println(common.Bytes2Hex(event.Key[:]))     // 为什么 Key 在这里打印？见下方解释
        	// 上面的代码示例在 Unpack 后打印 event.Key 实际上是错误的，因为 Unpack 只处理 vLog.Data，所以 event.Key 会是零值。正确的做法是直接使用 topics[1]
        fmt.Println(common.Bytes2Hex(event.Value[:]))  // 打印解析出来的 Value
        
        var topics []string
        // vLog.Topics 是日志中一个非常重要的部分。它是一个哈希数组
        	// topics[0]: 事件签名 (Event Signature) 的 Keccak256 哈希。这是事件的唯一标识符。所有 ItemSet 事件的 topics[0] 都是相同的
        	// topics[1:]: 被 indexed 关键字修饰的事件参数。
	        	// 在 ItemSet 事件的定义中 ("indexed":true,"internalType":"bytes32","name":"key")，key 是一个索引参数。
	        	// 因此，key 的值会出现在 topics 数组中（通常是 topics[1]）。
        for i := range vLog.Topics {
            topics = append(topics, vLog.Topics[i].Hex())
        }
        // 注意: 被索引的参数 (key) 的值存储在 vLog.Topics 中，而不是 vLog.Data 中。这就是为什么代码中直接从 vLog.Topics[1] 读取 key 的值，而不是从 Unpack 后的 event 结构体中获取

        fmt.Println("topics[0]=", topics[0])
        if len(topics) > 1 {
            fmt.Println("indexed topics:", topics[1:])
        }
    }

    //  计算事件签名  这部分代码演示了 topics[0] 是如何计算出来的。
    eventSignature := []byte("ItemSet(bytes32,bytes32)") // "ItemSet(bytes32,bytes32)": 这是 ItemSet 事件的规范签名，由事件名称和参数类型列表（不含参数名）组成
    hash := crypto.Keccak256Hash(eventSignature) // 对签名进行 Keccak256 哈希计算
    fmt.Println("signature topics=", hash.Hex()) //计算出的 hash 应该与程序前面打印出的 topics[0] 的值完全相同。这验证了事件签名的生成方式。
}
/*

总而言之，这段 Go 代码通过 Alchemy 连接到 Sepolia 测试网，
精确地查询了指定合约地址在特定区块之后发出的所有日志。
然后，它利用合约的 ABI，区分并解析了日志中的 Topics（存放索引参数和事件签名）和 Data（存放非索引参数），
最终将 ItemSet 事件的相关信息（如交易哈希、key 和 value）提取并打印出来
*/