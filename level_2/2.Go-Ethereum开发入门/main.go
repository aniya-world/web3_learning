package main

import (
    "log"

    "github.com/ethereum/go-ethereum/common"
    "github.com/ethereum/go-ethereum/ethclient"
    "github.com/learn/init_order/store"
)

const (
    contractAddr = "0x8D4141ec2b522dE5Cf42705C3010541B4B3EC24e"
)

func main() {
    client, err := ethclient.Dial("http://127.0.0.1:7545")
    if err != nil {
        log.Fatal(err)
    }
    storeContract, err := store.NewStore(common.HexToAddress(contractAddr), client)
    if err != nil {
        log.Fatal(err)
    }

    _ = storeContract
}