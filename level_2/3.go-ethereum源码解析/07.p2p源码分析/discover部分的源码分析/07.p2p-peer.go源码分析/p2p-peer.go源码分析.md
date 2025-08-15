在 p2p 代码里面。 peer 代表了一条创建好的网络链路。在一条链路上可能运行着多个协议。比如以太坊的协议(eth)。 Swarm 的协议。 或者是 Whisper 的协议。

peer 的结构

```go
type protoRW struct {
    Protocol
    in     chan Msg        // 接收读取消息的通道
    closed <-chan struct{} // 当 peer 关闭时接收信号
    wstart <-chan struct{} // 控制何时可以开始写入的信号
    werr   chan<- error    // 写入结果的通道
    offset uint64
    w      MsgWriter
}

// Protocol represents a P2P subprotocol implementation.
type Protocol struct {
    Name     string // 协议名称
    Version  uint   // 协议版本
    Length   uint64 // 消息代码数量
    Run      func(peer *Peer, rw MsgReadWriter) error // 协议运行方法
    NodeInfo func() interface{} // 获取节点信息的可选方法
    PeerInfo func(id discover.NodeID) interface{} // 获取特定 peer 信息的可选方法
}


// Peer represents a connected remote node.
type Peer struct {
    rw      *conn // 连接对象
    running map[string]*protoRW // 运行的协议
    log     log.Logger // 日志记录器
    created mclock.AbsTime // 创建时间
    wg      sync.WaitGroup // 等待组，用于管理 goroutine
    protoErr chan error // 协议错误通道
    closed   chan struct{} // 关闭信号通道
    disc     chan DiscReason // 断开原因通道
    events   *event.Feed // 事件通道
}

```

peer 的创建，根据匹配找到当前 Peer 支持的 protomap

```go
func newPeer(conn *conn, protocols []Protocol) *Peer {
    protomap := matchProtocols(protocols, conn.caps, conn)
    p := &Peer{
        rw:       conn,
        running:  protomap,
        created:  mclock.Now(),
        disc:     make(chan DiscReason),
        protoErr: make(chan error, len(protomap)+1), // 协议数量 + pingLoop
        closed:   make(chan struct{}),
        log:      log.New("id", conn.id, "conn", conn.flags),
    }
    return p
}

```

peer 的启动， 启动了两个 goroutine 线程。 一个是读取。一个是执行 ping 操作。

```go
func (p *Peer) run() (remoteRequested bool, err error) {
    var (
        writeStart = make(chan struct{}, 1)  // 控制写入的管道
        writeErr   = make(chan error, 1)
        readErr    = make(chan error, 1)
        reason     DiscReason // 发送给 peer 的原因
    )
    p.wg.Add(2)
    go p.readLoop(readErr) // 启动读取循环
    go p.pingLoop() // 启动 ping 循环

    // 启动所有协议处理
    writeStart <- struct{}{}
    p.startProtocols(writeStart, writeErr)

    // 等待错误或断开连接
loop:
    for {
        select {
        case err = <-writeErr:
            if err != nil {
                reason = DiscNetworkError
                break loop
            }
            writeStart <- struct{}{}
        case err = <-readErr:
            if r, ok := err.(DiscReason); ok {
                remoteRequested = true
                reason = r
            } else {
                reason = DiscNetworkError
            }
            break loop
        case err = <-p.protoErr:
            reason = discReasonForError(err)
            break loop
        case err = <-p.disc:
            break loop
        }
    }

    close(p.closed) // 关闭 peer
    p.rw.close(reason) // 关闭连接
    p.wg.Wait() // 等待所有 goroutine 完成
    return remoteRequested, err
}

```

startProtocols 方法，这个方法遍历所有的协议。

```go
func (p *Peer) startProtocols(writeStart <-chan struct{}, writeErr chan<- error) {
    p.wg.Add(len(p.running)) // 为每个正在运行的协议增加等待组计数
    for _, proto := range p.running {
        proto := proto // 捕获当前协议
        proto.closed = p.closed // 设置关闭信号
        proto.wstart = writeStart // 设置写入开始信号
        proto.werr = writeErr // 设置写入错误信号
        var rw MsgReadWriter = proto // 将协议赋值给 rw
        if p.events != nil {
            rw = newMsgEventer(rw, p.events, p.ID(), proto.Name) // 如果有事件，创建事件处理器
        }
        p.log.Trace(fmt.Sprintf("Starting protocol %s/%d", proto.Name, proto.Version))
        // 为每个协议启动一个 goroutine，调用其 Run 方法
        go func() {
            err := proto.Run(p, rw) // 运行协议
            if err == nil {
                p.log.Trace(fmt.Sprintf("Protocol %s/%d returned", proto.Name, proto.Version))
                err = errProtocolReturned // 处理正常返回
            } else if err != io.EOF {
                p.log.Trace(fmt.Sprintf("Protocol %s/%d failed", proto.Name, proto.Version), "err", err)
            }
            p.protoErr <- err // 将错误发送到协议错误通道
            p.wg.Done() // 完成等待组计数
        }()
    }
}

```

回过头来再看看 readLoop 方法。 这个方法也是一个死循环。 调用 p.rw 来读取一个 Msg(这个 rw 实际是之前提到的 frameRLPx 的对象，也就是分帧之后的对象。然后根据 Msg 的类型进行对应的处理，如果 Msg 的类型是内部运行的协议的类型。那么发送到对应协议的 proto.in 队列上面。

```go 读取循环
func (p *Peer) readLoop(errc chan<- error) {  
    defer p.wg.Done() // 确保在函数结束时减少等待组计数
    for {
        msg, err := p.rw.ReadMsg() // 从 rw 读取消息
        if err != nil {
            errc <- err // 发送错误到错误通道
            return
        }
        msg.ReceivedAt = time.Now() // 记录消息接收时间
        if err = p.handle(msg); err != nil {
            errc <- err // 处理消息时发生错误，发送到错误通道
            return
        }
    }
}

处理消息
func (p *Peer) handle(msg Msg) error {
    switch {
    case msg.Code == pingMsg:
        msg.Discard() // 丢弃 ping 消息
        go SendItems(p.rw, pongMsg) // 发送 pong 消息
    case msg.Code == discMsg:
        var reason [1]DiscReason
        rlp.Decode(msg.Payload, &reason) // 解码断开消息
        return reason[0] // 返回断开原因
    case msg.Code < baseProtocolLength:
        return msg.Discard() // 忽略其他基础协议消息
    default:
        // 处理子协议消息
        proto, err := p.getProto(msg.Code) // 获取对应的协议
        if err != nil {
            return fmt.Errorf("msg code out of range: %v", msg.Code) // 消息代码超出范围
        }
        select {
        case proto.in <- msg: // 将消息发送到协议的输入通道
            return nil
        case <-p.closed:
            return io.EOF // 如果 peer 已关闭，返回 EOF
        }
    }
    return nil
}

```

在看看 pingLoop。这个方法很简单。就是定时的发送 pingMsg 消息到对端。

```go Ping循环
func (p *Peer) pingLoop() {
    ping := time.NewTimer(pingInterval) // 创建定时器
    defer p.wg.Done() // 确保在函数结束时减少等待组计数
    defer ping.Stop() // 停止定时器
    for {
        select {
        case <-ping.C: // 定时器到期
            if err := SendItems(p.rw, pingMsg); err != nil {
                p.protoErr <- err // 发送错误到协议错误通道
                return
            }
            ping.Reset(pingInterval) // 重置定时器
        case <-p.closed:
            return // 如果 peer 已关闭，退出循环
        }
    }
}

```

最后再看看 protoRW 的 read 和 write 方法。 可以看到读取和写入都是阻塞式的。

```go
func (rw *protoRW) WriteMsg(msg Msg) (err error) {
    if msg.Code >= rw.Length {
        return newPeerError(errInvalidMsgCode, "not handled")
        // 如果消息代码超出协议支持的范围，返回错误
    }
    msg.Code += rw.offset
    // 将消息代码加上偏移量，以适应协议的编码方式
    select {
    case <-rw.wstart:  // 等待可以写入的信号
        err = rw.w.WriteMsg(msg) // 调用底层的写入方法
        // 将写入状态报告回 Peer.run。如果错误非空，将启动关闭过程
        // 否则，解除下一个写入的阻塞。调用协议代码也应在错误时退出
        rw.werr <- err // 将写入结果发送到写入错误通道
    case <-rw.closed:
        err = fmt.Errorf("shutting down") // 如果关闭信号被接收，返回关闭错误
    }
    return err // 返回写入结果
}

```
