package main

import (
    "fmt"
    "time"
)

func main() {
    // 创建一个通道，用于传递信号
    signalChan := make(chan struct{})

    // 创建一个通道，用于传递另一个通道
    requestChan := make(chan chan struct{})

    go func() {
        // 模拟一些工作
        time.Sleep(2 * time.Second)
        fmt.Println("Work done, sending signal...")
        signalChan <- struct{}{} // 发送信号
    }()

    go func() {
        // 等待请求通道的接收
        req := <-requestChan
        fmt.Println("Received request, waiting for signal...")
        <-signalChan // 等待信号
        fmt.Println("Signal received!")
        req <- struct{}{} // 发送响应
    }()

    // 发送请求通道
    requestChan <- signalChan

    // 等待响应
    <-signalChan
    fmt.Println("Main function completed.")
}
