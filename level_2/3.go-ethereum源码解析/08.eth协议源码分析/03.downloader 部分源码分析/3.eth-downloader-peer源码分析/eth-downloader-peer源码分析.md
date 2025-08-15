# 转换文档
peer 模块封装了 downloader 所使用的对等节点，包括其吞吐量、空闲状态以及之前的失败记录。


peerConnection 结构体记录了节点的各种活动状态、吞吐量、请求往返时间（RTT）等信息。

## **peer**

```go
// peerConnection represents an active peer from which hashes and blocks are retrieved.
// peerConnection represents an active peer from which hashes and blocks are retrieved.
type peerConnection struct {
        id string // 节点的唯一标识符

        headerIdle  int32 // 当前获取区块头的工作状态，0 表示空闲，1 表示活跃
        blockIdle   int32 // 当前获取区块体的工作状态，0 表示空闲，1 表示活跃
        receiptIdle int32 // 当前获取收据的工作状态，0 表示空闲，1 表示活跃
        stateIdle   int32 // 当前获取节点状态数据的工作状态，0 表示空闲，1 表示活跃

        headerThroughput  float64 // 记录每秒能够接收的区块头数量的度量值
        blockThroughput   float64 // 记录每秒能够接收的区块体数量的度量值
        receiptThroughput float64 // 记录每秒能够接收的收据数量的度量值
        stateThroughput   float64 // 记录每秒能够接收的账户状态数量的度量值

        rtt time.Duration // 请求的往返时间，用于跟踪响应能力

        headerStarted  time.Time // 记录上次开始获取区块头请求的时间
        blockStarted   time.Time // 记录上次开始获取区块体请求的时间
        receiptStarted time.Time // 记录上次开始获取收据请求的时间
        stateStarted   time.Time // 记录上次开始获取节点状态数据请求的时间
        
        lacking map[common.Hash]struct{} // 记录不会去请求的哈希值集合，通常是因为之前的请求失败

        peer Peer                        // 封装的 eth 对等节点

        version int        // eth 协议版本号，用于切换策略
        log     log.Logger // 上下文日志，用于向对等节点日志添加额外信息
        lock    sync.RWMutex // 读写互斥锁，用于保护对等节点数据
}
```

FetchXXX FetchHeaders FetchBodies 等函数  
FetchHeaders 等函数主要调用了 eth.peer 的功能来发送数据请求。
```go
// FetchHeaders sends a header retrieval request to the remote peer.
func (p *peerConnection) FetchHeaders(from uint64, count int) error {
        if p.version < 62 {                                            // 检查协议版本
                panic(fmt.Sprintf("header fetch [eth/62+] requested on eth/%d", p.version)) // 如果协议版本过低，触发 panic
        }
        if !atomic.CompareAndSwapInt32(&p.headerIdle, 0, 1) {          // 使用原子操作检查并设置 headerIdle 状态为活跃
                return errAlreadyFetching                              // 如果对等节点已经在获取，则返回错误
        }
        p.headerStarted = time.Now()                                   // 记录请求开始时间

        go p.peer.RequestHeadersByNumber(from, count, 0, false)        // 在一个新的 goroutine 中向对等节点请求区块头

        return nil
}
```

SetXXXIdle 函数 SetHeadersIdle, SetBlocksIdle 等函数  
SetHeadersIdle 等函数将对等节点的状态设置为空闲，并根据本次传输的数据量重新评估吞吐量
```go
// SetHeadersIdle sets the peer to idle, allowing it to execute new header retrieval
// requests. Its estimated header retrieval throughput is updated with that measured
// just now.
func (p *peerConnection) SetHeadersIdle(delivered int) {
        p.setIdle(p.headerStarted, delivered, &p.headerThroughput, &p.headerIdle) // 调用 setIdle 方法更新状态和吞吐量
}
```

setIdle
setIdle 方法设置对等节点为空闲，并更新其吞吐量
```go
 
// setIdle sets the peer to idle, allowing it to execute new retrieval requests.
// Its estimated retrieval throughput is updated with that measured just now.
func (p *peerConnection) setIdle(started time.Time, delivered int, throughput *float64, idle *int32) {
        defer atomic.StoreInt32(idle, 0) // 在函数返回时，使用原子操作将 idle 状态设为 0 (空闲)

        p.lock.Lock()                  // 获取互斥锁
        defer p.lock.Unlock()          // 在函数返回时释放锁

        if delivered == 0 {            // 如果没有交付数据（超时或数据不可用）
                *throughput = 0          // 将吞吐量设置为0
                return
        }
        elapsed := time.Since(started) + 1 // 计算请求经过的时间，加1纳秒以避免除以0
        measured := float64(delivered) / (float64(elapsed) / float64(time.Second)) // 计算本次测量的吞吐量
        
        *throughput = (1-measurementImpact)*(*throughput) + measurementImpact*measured // 使用指数平滑法更新吞吐量
        p.rtt = time.Duration((1-measurementImpact)*float64(p.rtt) + measurementImpact*float64(elapsed)) // 使用指数平滑法更新 RTT

        p.log.Trace("Peer throughput measurements updated",
                "hps", p.headerThroughput, "bps", p.blockThroughput,
                "rps", p.receiptThroughput, "sps", p.stateThroughput,
                "miss", len(p.lacking), "rtt", p.rtt) // 记录更新后的吞吐量和 RTT
}
```

XXXCapacity 函数，用来返回当前的链接允许的吞吐量。
HeaderCapacity 函数返回当前连接允许的吞吐量
```go
// HeaderCapacity retrieves the peers header download allowance based on its
// previously discovered throughput.
func (p *peerConnection) HeaderCapacity(targetRTT time.Duration) int {
        p.lock.RLock()                 // 获取读锁
        defer p.lock.RUnlock()         // 在函数返回时释放锁
        return int(math.Min(1+math.Max(1, p.headerThroughput*float64(targetRTT)/float64(time.Second)), float64(MaxHeaderFetch))) // 根据吞吐量和目标 RTT 计算容量，并限制在 1 到 MaxHeaderFetch 之间
}
```

 
MarkLacking 和 Lacks 函数用于标记和检查对等节点上次是否失败。
```go
// MarkLacking appends a new entity to the set of items (blocks, receipts, states)
// that a peer is known not to have (i.e. have been requested before). If the
// set reaches its maximum allowed capacity, items are randomly dropped off.
func (p *peerConnection) MarkLacking(hash common.Hash) {
        p.lock.Lock()                  // 获取写锁
        defer p.lock.Unlock()          // 在函数返回时释放锁
        
        for len(p.lacking) >= maxLackingHashes { // 如果 lacking 集合达到最大容量
                for drop := range p.lacking {      // 随机删除一个元素
                        delete(p.lacking, drop)
                        break
                }
        }
        p.lacking[hash] = struct{}{}   // 将哈希添加到 lacking 集合中
}

// Lacks retrieves whether the hash of a blockchain item is on the peers lacking
// list (i.e. whether we know that the peer does not have it).
func (p *peerConnection) Lacks(hash common.Hash) bool {
        p.lock.RLock()                 // 获取读锁
        defer p.lock.RUnlock()         // 在函数返回时释放锁
        
        _, ok := p.lacking[hash]       // 检查哈希是否在 lacking 集合中
        return ok
}
```

## **peerSet**
peerSet 结构体代表了参与链下载过程的活跃对等节点集合。
```go
// peerSet represents the collection of active peer participating in the chain
// download procedure.
type peerSet struct {
        peers        map[string]*peerConnection
        newPeerFeed  event.Feed
        peerDropFeed event.Feed
        lock         sync.RWMutex
}
```

Register 和 UnRegister
Register 函数将一个新对等节点注入到工作集合中，如果节点已存在则返回错误。Unregister 函数从活跃集合中移除一个远程对等节点
```go
// Register injects a new peer into the working set, or returns an error if the
// peer is already known.
func (ps *peerSet) Register(p *peerConnection) error {
        p.rtt = ps.medianRTT()         // 获取当前对等节点集合的中位 RTT 作为新节点的默认 RTT

        ps.lock.Lock()                 // 获取写锁
        if _, ok := ps.peers[p.id]; ok { // 检查对等节点是否已注册
                ps.lock.Unlock()
                return errAlreadyRegistered
        }
        if len(ps.peers) > 0 {         // 如果存在其他对等节点
                p.headerThroughput, p.blockThroughput, p.receiptThroughput, p.stateThroughput = 0, 0, 0, 0 // 初始化新节点的吞吐量为0

                for _, peer := range ps.peers { // 遍历现有对等节点
                        peer.lock.RLock()
                        p.headerThroughput += peer.headerThroughput // 累加现有节点的吞吐量
                        p.blockThroughput += peer.blockThroughput
                        p.receiptThroughput += peer.receiptThroughput
                        p.stateThroughput += peer.stateThroughput
                        peer.lock.RUnlock()
                }
                p.headerThroughput /= float64(len(ps.peers)) // 计算平均吞吐量
                p.blockThroughput /= float64(len(ps.peers))
                p.receiptThroughput /= float64(len(ps.peers))
                p.stateThroughput /= float64(len(ps.peers))
        }
        ps.peers[p.id] = p             // 将新节点添加到 peerSet
        ps.lock.Unlock()               // 释放写锁

        ps.newPeerFeed.Send(p)         // 向 newPeerFeed 发送事件
        return nil
}

// Unregister removes a remote peer from the active set, disabling any further
// actions to/from that particular entity.
func (ps *peerSet) Unregister(id string) error {
        ps.lock.Lock()                 // 获取写锁
        p, ok := ps.peers[id]
        if !ok {
                defer ps.lock.Unlock()
                return errNotRegistered // 如果对等节点未注册，返回错误
        }
        delete(ps.peers, id)           // 从 peerSet 中删除对等节点
        ps.lock.Unlock()               // 释放写锁

        ps.peerDropFeed.Send(p)        // 向 peerDropFeed 发送事件
        return nil
}
```

XXXIdlePeers
HeaderIdlePeers 函数检索活跃对等节点集合中所有当前空闲的对等节点，并按其信誉排序
```go
// HeaderIdlePeers retrieves a flat list of all the currently header-idle peers
// within the active peer set, ordered by their reputation.
func (ps *peerSet) HeaderIdlePeers() ([]*peerConnection, int) {
        idle := func(p *peerConnection) bool {         // 定义一个匿名函数，检查 headerIdle 状态是否为0
                return atomic.LoadInt32(&p.headerIdle) == 0
        }
        throughput := func(p *peerConnection) float64 { // 定义一个匿名函数，返回 headerThroughput
                p.lock.RLock()
                defer p.lock.RUnlock()
                return p.headerThroughput
        }
        return ps.idlePeers(62, 64, idle, throughput) // 调用 idlePeers 方法
}

// idlePeers retrieves a flat list of all currently idle peers satisfying the
// protocol version constraints, using the provided function to check idleness.
func (ps *peerSet) idlePeers(minProtocol, maxProtocol int, idleCheck func(*peerConnection) bool, throughput func(*peerConnection) float64) ([]*peerConnection, int) {
        ps.lock.RLock()                 // 获取读锁
        defer ps.lock.RUnlock()         // 释放读锁

        idle, total := make([]*peerConnection, 0, len(ps.peers)), 0 // 创建切片用于存储空闲对等节点
        for _, p := range ps.peers {    // 遍历所有对等节点
                if p.version >= minProtocol && p.version <= maxProtocol { // 检查协议版本
                        if idleCheck(p) {               // 如果对等节点空闲
                                idle = append(idle, p)  // 添加到空闲切片中
                        }
                        total++
                }
        }
        for i := 0; i < len(idle); i++ { // 冒泡排序，按吞吐量从大到小排序
                for j := i + 1; j < len(idle); j++ {
                        if throughput(idle[i]) < throughput(idle[j]) {
                                idle[i], idle[j] = idle[j], idle[i]
                        }
                }
        }
        return idle, total              // 返回空闲对等节点和总数
}
```

 
medianRTT 函数计算 peerSet 中所有对等节点 RTT 的中位数。
```go
// medianRTT returns the median RTT of te peerset, considering only the tuning
// peers if there are more peers available.
func (ps *peerSet) medianRTT() time.Duration {
        ps.lock.RLock()                 // 获取读锁
        defer ps.lock.RUnlock()         // 释放读锁

        rtts := make([]float64, 0, len(ps.peers)) // 创建切片用于存储 RTT
        for _, p := range ps.peers {    // 遍历所有对等节点
                p.lock.RLock()
                rtts = append(rtts, float64(p.rtt)) // 将 RTT 添加到切片
                p.lock.RUnlock()
        }
        sort.Float64s(rtts)             // 对 RTT 切片进行排序

        median := rttMaxEstimate
        if qosTuningPeers <= len(rtts) {
                median = time.Duration(rtts[qosTuningPeers/2]) // 如果对等节点数量足够，取调试对等节点的中位 RTT
        } else if len(rtts) > 0 {
                median = time.Duration(rtts[len(rtts)/2]) // 否则，取所有连接对等节点的中位 RTT
        }
        if median < rttMinEstimate {    // 将 RTT 限制在最小估算值和最大估算值之间
                median = rttMinEstimate
        }
        if median > rttMaxEstimate {
                median = rttMaxEstimate
        }
        return median
}
```
