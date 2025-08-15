table.go 主要实现了 p2p 的 Kademlia 协议。

### **Kademlia 协议简介(建议阅读 references 里面的 pdf 文档)**

Kademlia 协议（以下简称 Kad） 是美国纽约大学的 PetarP. Maymounkov 和 David Mazieres. 在 2002 年发布的一项研究结果《Kademlia: A peerto -peer information system based on the XOR metric》。 简单的说， Kad 是一种分布式哈希表（ DHT） 技术， 不过和其他 DHT 实现技术比较，如 Chord、 CAN、 Pastry 等， Kad 通过独特的以异或算法（ XOR）为距离度量基础，建立了一种 全新的 DHT 拓扑结构，相比于其他算法，大大提高了路由查询速度。

### **table 的结构和字段**

```go
使用 const() 块可以将相关的常量组织在一起，使代码更具可读性和结构性。一次性声明多个常量，而不需要为每个常量单独写 const 关键字
在 const() 块中定义的常量可以根据其值自动推导类型
const (
        //帮助管理节点的并发处理、存储、连接稳定性和网络的健康状态。通过合理设置这些常量，可以优化网络的性能和可靠性
        alpha      = 3  // Kademlia concurrency factor Kademlia 协议中的并发因子，表示在处理节点请求时可以并行的最大节点数。这有助于提高网络的效率和响应速度。
        bucketSize = 16 // Kademlia bucket size Kademlia 中每个桶的大小。桶用于存储节点信息，限制桶的大小可以帮助管理节点的数量和维护网络的稳定性。
        hashBits   = len(common.Hash{}) * 8 //字节求位数 1 字节 (byte) = 8 位 (bit)
        //哈希值的位数，通常用于表示节点 ID 的大小。这里的 common.Hash{} 是一个哈希结构体，len 返回其字节长度，乘以 8 转换为位数。
        //乘以 8: 在计算机科学中，1 字节等于 8 位。因此，为了将字节长度转换为位数，需要将字节长度乘以 8。
        //示例: 如果 common.Hash 的字节长度为 32，那么乘以 8 后得到的位数为 256。这表示该哈希值是 256 位长。
        nBuckets   = hashBits + 1 // Number of buckets
        //桶的数量，通常是哈希位数加一。这个常量用于确定 Kademlia 网络中可以使用的桶的总数
        maxBondingPingPongs = 16
        //在节点连接过程中，允许的最大 ping-pong 次数。这是为了确保节点之间的连接稳定性，避免过多的无效请求。
        maxFindnodeFailures = 5
        //在查找节点时允许的最大失败次数。如果在查找过程中失败次数超过这个值，可能会触发错误处理或重试机制。
        autoRefreshInterval = 1 * time.Hour
        //自动刷新节点信息的时间间隔。这个常量用于定期更新节点的状态，以确保网络中的节点信息是最新的。
        seedCount           = 30
        //在引导过程中使用的种子节点数量。这个常量指定了在网络启动时需要连接的初始节点数量。
        seedMaxAge          = 5 * 24 * time.Hour
        //种子节点的最大年龄，超过这个时间的种子节点将被视为过期。这有助于确保网络中使用的种子节点是活跃的。
)

 Table 的结构体，通常用于实现 Kademlia 协议中的节点管理和路由表。以下是对 Table 结构体中每个字段的详细解释
type Table struct {
        mutex   sync.Mutex        // protects buckets, their content, and nursery 互斥锁，用于保护 buckets、它们的内容和 nursery 的并发访问
        buckets [nBuckets]*bucket // index of known nodes by distance 
        //一个数组，存储已知节点的桶，按距离索引。每个桶包含一组节点，便于管理和查找。
        nursery []*Node           // bootstrap nodes
        //存储引导节点（bootstrap nodes）的切片。这些节点用于网络启动时的连接
        db      *nodeDB           // database of known nodes 
        //指向已知节点数据库的指针

        refreshReq chan chan struct{}
        //通道，用于请求节点信息的刷新。可以通过发送信号来触发刷新操作。
        closeReq   chan struct{}
        //通道，用于请求关闭 Table。可以通过发送信号来安全地关闭相关操作。
        closed     chan struct{}
        //通道，用于通知 Table 已关闭。其他部分可以通过监听这个通道来确认关闭状态。

        bondmu    sync.Mutex
        //另一个互斥锁，用于保护与节点连接相关的操作，确保在并发环境中安全地管理连接过程。
        bonding   map[NodeID]*bondproc
        //存储正在进行的连接过程的映射。NodeID 是节点的唯一标识符，bondproc 是处理连接的结构体
        bondslots chan struct{} // limits total number of active bonding processes
        // 通道，用于限制活动连接过程的总数。可以防止同时进行过多的连接请求，避免资源耗尽
        nodeAddedHook func(*Node) // for testing
        //一个函数类型的字段，用于在节点添加时执行特定操作，主要用于测试目的。
        net  transport
        //表示网络传输的接口或结构体，负责节点之间的通信。
        self *Node // metadata of the local node
        //指向本地节点的指针，包含本地节点的元数据（如 ID、IP 地址等）。
}
```

### **初始化**

```go
func newTable(t transport, ourID NodeID, ourAddr *net.UDPAddr, nodeDBPath string) (*Table, error) {
        // 创建一个新的表格，接受传输方式、节点ID、地址和数据库路径作为参数
        db, err := newNodeDB(nodeDBPath, Version, ourID)
        // 调用 newNodeDB 函数打开节点数据库，如果路径为空则使用内存数据库
        if err != nil {
                return nil, err
        }
        tab := &Table{
                net:        t,
                // 将传入的传输方式赋值给表格
                db:         db,
                // 将打开的数据库赋值给表格
                self:       NewNode(ourID, ourAddr.IP, uint16(ourAddr.Port), uint16(ourAddr.Port)),
                // 创建一个新的节点，使用传入的ID和地址信息
                bonding:    make(map[NodeID]*bondproc),
                // 初始化一个映射，用于存储节点ID和绑定处理程序的关系
                bondslots:  make(chan struct{}, maxBondingPingPongs),
                // 创建一个带缓冲的通道，用于管理绑定的槽位
                refreshReq: make(chan chan struct{}),
                // 创建一个通道，用于处理刷新请求
                closeReq:   make(chan struct{}),
                // 创建一个通道，用于处理关闭请求
                closed:     make(chan struct{}),
                // 创建一个通道，用于指示表格是否已关闭
        }
        for i := 0; i < cap(tab.bondslots); i++ {
                tab.bondslots <- struct{}{}  // 空结构体实例化传进去。
                // 填充 bondslots 通道，确保有足够的槽位可用
        }
        for i := range tab.buckets {
                tab.buckets[i] = new(bucket)
                // 初始化每个桶，创建新的 bucket 实例
        }
        go tab.refreshLoop()
        // 启动一个新的 goroutine 来处理刷新循环

        return tab, nil
        // 返回创建的表格和 nil 错误
}

```






上面的初始化启动了一个 goroutine refreshLoop()，这个函数主要完成以下的工作。

1. 每一个小时进行一次刷新工作(autoRefreshInterval)
2. 如果接收到 refreshReq 请求。那么进行刷新工作。
3. 如果接收到关闭消息。那么进行关闭。

所以函数主要的工作就是启动刷新工作。doRefresh


// 函数的类型声明
func (receiver receiverType) functionName(parameters) returnType {
   ...
}


```go
// refreshLoop schedules doRefresh runs and coordinates shutdown.

func (tab *Table) refreshLoop() {
//定义了一个名为 refreshLoop 的方法，它属于 Table 类型，并且可以通过指向 Table 的指针来访问和修改该实例的状态
        var (
                timer   = time.NewTicker(autoRefreshInterval)
                // 创建一个定时器，每隔 autoRefreshInterval 时间触发一次
                waiting []chan struct{} // accumulates waiting callers while doRefresh runs
                // 用于存储在 doRefresh 运行期间等待的调用者通道
                done    chan struct{}   // where doRefresh reports completion
                // 用于接收 doRefresh 完成的信号
        )
loop:
        for {
                select {
                case <-timer.C:
                        // 当定时器触发时执行以下代码
                        if done == nil {
                                // 如果 done 通道尚未创建
                                done = make(chan struct{})
                                // 创建一个新的通道用于接收完成信号
                                go tab.doRefresh(done)
                                // 启动 doRefresh 函数，并将 done 通道传入
                        }
                case req := <-tab.refreshReq:
                        // 当接收到刷新请求时执行以下代码
                        waiting = append(waiting, req)
                        // 将请求通道添加到 waiting 列表中
                        if done == nil {
                                // 如果 done 通道尚未创建
                                done = make(chan struct{})
                                // 创建一个新的通道用于接收完成信号
                                go tab.doRefresh(done)
                                // 启动 doRefresh 函数，并将 done 通道传入
                        }
                case <-done:
                        // 当 doRefresh 完成时执行以下代码
                        for _, ch := range waiting {
                                close(ch)
                                // 关闭所有等待的通道，通知它们完成
                        }
                        waiting = nil
                        // 清空 waiting 列表
                        done = nil
                        // 重置 done 通道
                case <-tab.closeReq:
                        // 当接收到关闭请求时执行以下代码
                        break loop
                        // 退出循环
                }
        }

        if tab.net != nil {
                tab.net.close()
                // 如果网络连接存在，关闭网络连接
        }
        if done != nil {
                <-done
                // 等待 doRefresh 完成
        }
        for _, ch := range waiting {
                close(ch)
                // 关闭所有等待的通道
        }
        tab.db.close()
        // 关闭数据库连接
        close(tab.closed)
        // 关闭表格的关闭通道，表示所有操作已完成
}

```

doRefresh 函数

```go
// doRefresh performs a lookup for a random target to keep buckets
// full. seed nodes are inserted if the table is empty (initial
// bootstrap or discarded faulty peers).
// doRefresh 随机查找一个目标，以便保持buckets是满的。如果table是空的，那么种子节点会插入。 （比如最开始的启动或者是删除错误的节点之后）
func (tab *Table) doRefresh(done chan struct{}) {
        defer close(done)

        // The Kademlia paper specifies that the bucket refresh should
        // perform a lookup in the least recently used bucket. We cannot
        // adhere to this because the findnode target is a 512bit value
        // (not hash-sized) and it is not easily possible to generate a
        // sha3 preimage that falls into a chosen bucket.
        // We perform a lookup with a random target instead.
        //这里暂时没看懂
        var target NodeID
        rand.Read(target[:])
        result := tab.lookup(target, false) //lookup是查找距离target最近的k个节点
        if len(result) > 0 {  //如果结果不为0 说明表不是空的，那么直接返回。
                return
        }

        // The table is empty. Load nodes from the database and insert
        // them. This should yield a few previously seen nodes that are
        // (hopefully) still alive.
        //querySeeds函数在database.go章节有介绍，从数据库里面随机的查找可用的种子节点。
        //在最开始启动的时候数据库是空白的。也就是最开始的时候这个seeds返回的是空的。
        seeds := tab.db.querySeeds(seedCount, seedMaxAge)
        //调用bondall函数。会尝试联系这些节点，并插入到表中。
        //tab.nursery是在命令行中指定的种子节点。
        //最开始启动的时候。 tab.nursery的值是内置在代码里面的。 这里是有值的。
        //C:\GOPATH\src\github.com\ethereum\go-ethereum\mobile\params.go
        //这里面写死了值。 这个值是通过SetFallbackNodes方法写入的。 这个方法后续会分析。
        //这里会进行双向的pingpong交流。 然后把结果存储在数据库。
        seeds = tab.bondall(append(seeds, tab.nursery...))

        if len(seeds) == 0 { //没有种子节点被发现， 可能需要等待下一次刷新。
                log.Debug("No discv4 seed nodes found")
        }
        for _, n := range seeds {
                age := log.Lazy{Fn: func() time.Duration { return time.Since(tab.db.lastPong(n.ID)) }}
                log.Trace("Found seed node in database", "id", n.ID, "addr", n.addr(), "age", age)
        }
        tab.mutex.Lock()
        //这个方法把所有经过bond的seed加入到bucket(前提是bucket未满)
        tab.stuff(seeds) 
        tab.mutex.Unlock()

        // Finally, do a self lookup to fill up the buckets.
        tab.lookup(tab.self.ID, false) // 有了种子节点。那么查找自己来填充buckets。
}
```

bondall 方法，这个方法就是多线程的调用 bond 方法。

```go
// bondall bonds with all given nodes concurrently and returns
// those nodes for which bonding has probably succeeded.
func (tab *Table) bondall(nodes []*Node) (result []*Node) {
        // 定义一个方法 bondall，接收一个节点指针切片作为参数，返回一个节点指针切片
        rc := make(chan *Node, len(nodes))
        // 创建一个带缓冲的通道 rc，用于接收绑定结果，缓冲区大小为节点数量
        for i := range nodes {
                go func(n *Node) {
                        // 启动一个新的 goroutine，处理每个节点
                        nn, _ := tab.bond(false, n.ID, n.addr(), uint16(n.TCP))
                        // 调用 tab.bond 方法进行绑定，传入节点的 ID 和地址信息
                        rc <- nn
                        // 将绑定结果发送到通道 rc
                }(nodes[i])
        }
        for range nodes {
                // 遍历节点数量，接收每个绑定结果
                if n := <-rc; n != nil {
                        // 从通道 rc 接收结果，如果结果不为 nil
                        result = append(result, n)
                        // 将成功绑定的节点添加到结果切片中
                }
        }
        return result
        // 返回成功绑定的节点切片
}

```

bond 方法。记得在 udp.go 中。当我们收到一个 ping 方法的时候，也有可能会调用这个方法

```go
// bond ensures the local node has a bond with the given remote node.
// It also attempts to insert the node into the table if bonding succeeds.
// The caller must not hold tab.mutex.
// bond确保本地节点与给定的远程节点具有绑定。(远端的ID和远端的IP)。
// 如果绑定成功，它也会尝试将节点插入表中。调用者必须持有tab.mutex锁
// A bond is must be established before sending findnode requests.
// Both sides must have completed a ping/pong exchange for a bond to
// exist. The total number of active bonding processes is limited in
// order to restrain network use.
// 发送findnode请求之前必须建立一个绑定。        双方为了完成一个bond必须完成双向的ping/pong过程。
// 为了节约网路资源。 同时存在的bonding处理流程的总数量是受限的。        
// bond is meant to operate idempotently in that bonding with a remote
// node which still remembers a previously established bond will work.
// The remote node will simply not send a ping back, causing waitping
// to time out.
// bond 是幂等的操作，跟一个任然记得之前的bond的远程节点进行bond也可以完成。 远程节点会简单的不会发送ping。 等待waitping超时。
// If pinged is true, the remote node has just pinged us and one half
// of the process can be skipped.
//        如果pinged是true。 那么远端节点已经给我们发送了ping消息。这样一半的流程可以跳过。
func (tab *Table) bond(pinged bool, id NodeID, addr *net.UDPAddr, tcpPort uint16) (*Node, error) {
        if id == tab.self.ID {
                return nil, errors.New("is self")
        }
        // Retrieve a previously known node and any recent findnode failures
        node, fails := tab.db.node(id), 0
        if node != nil {
                fails = tab.db.findFails(id)
        }
        // If the node is unknown (non-bonded) or failed (remotely unknown), bond from scratch
        var result error
        age := time.Since(tab.db.lastPong(id))
        if node == nil || fails > 0 || age > nodeDBNodeExpiration {
                //如果数据库没有这个节点。 或者错误数量大于0或者节点超时。
                log.Trace("Starting bonding ping/pong", "id", id, "known", node != nil, "failcount", fails, "age", age)

                tab.bondmu.Lock()
                w := tab.bonding[id]
                if w != nil {
                        // Wait for an existing bonding process to complete.
                        tab.bondmu.Unlock()
                        <-w.done
                } else {
                        // Register a new bonding process.
                        w = &bondproc{done: make(chan struct{})}
                        tab.bonding[id] = w
                        tab.bondmu.Unlock()
                        // Do the ping/pong. The result goes into w.
                        tab.pingpong(w, pinged, id, addr, tcpPort)
                        // Unregister the process after it's done.
                        tab.bondmu.Lock()
                        delete(tab.bonding, id)
                        tab.bondmu.Unlock()
                }
                // Retrieve the bonding results
                result = w.err
                if result == nil {
                        node = w.n
                }
        }
        if node != nil {
                // Add the node to the table even if the bonding ping/pong
                // fails. It will be relaced quickly if it continues to be
                // unresponsive.
                //这个方法比较重要。 如果对应的bucket有空间，会直接插入buckets。如果buckets满了。 会用ping操作来测试buckets中的节点试图腾出空间。
                tab.add(node)
                tab.db.updateFindFails(id, 0)
        }
        return node, result
}
```

pingpong 方法

```go
func (tab *Table) pingpong(w *bondproc, pinged bool, id NodeID, addr *net.UDPAddr, tcpPort uint16) {
        // Request a bonding slot to limit network usage
        <-tab.bondslots
        defer func() { tab.bondslots <- struct{}{} }()

        // Ping the remote side and wait for a pong.
        // Ping远程节点。并等待一个pong消息
        if w.err = tab.ping(id, addr); w.err != nil {
                close(w.done)
                return
        }
        //这个在udp收到一个ping消息的时候被设置为真。这个时候我们已经收到对方的ping消息了。
        //那么我们就不同等待ping消息了。 否则需要等待对方发送过来的ping消息(我们主动发起ping消息)。
        if !pinged {
                // Give the remote node a chance to ping us before we start
                // sending findnode requests. If they still remember us,
                // waitping will simply time out.
                tab.net.waitping(id)
        }
        // Bonding succeeded, update the node database.
        // 完成bond过程。 把节点插入数据库。 数据库操作在这里完成。 bucket的操作在tab.add里面完成。 buckets是内存的操作。 数据库是持久化的seeds节点。用来加速启动过程的。
        w.n = NewNode(id, addr.IP, uint16(addr.Port), tcpPort)
        tab.db.updateNode(w.n)
        close(w.done)
}
```

tab.add 方法

```go
// add attempts to add the given node its corresponding bucket. If the
// bucket has space available, adding the node succeeds immediately.
// Otherwise, the node is added if the least recently active node in
// the bucket does not respond to a ping packet.
// add试图把给定的节点插入对应的bucket。 如果bucket有空间，那么直接插入。 否则，如果bucket中最近活动的节点没有响应ping操作，那么我们就使用这个节点替换它。
// The caller must not hold tab.mutex.
func (tab *Table) add(new *Node) {
        b := tab.buckets[logdist(tab.self.sha, new.sha)]
        tab.mutex.Lock()
        defer tab.mutex.Unlock()
        if b.bump(new) { //如果节点存在。那么更新它的值。然后退出。
                return
        }
        var oldest *Node
        if len(b.entries) == bucketSize {
                oldest = b.entries[bucketSize-1]
                if oldest.contested {
                        // The node is already being replaced, don't attempt
                        // to replace it.
                        // 如果别的goroutine正在对这个节点进行测试。 那么取消替换， 直接退出。
                        // 因为ping的时间比较长。所以这段时间是没有加锁的。 用了contested这个状态来标识这种情况。 
                        return
                }
                oldest.contested = true
                // Let go of the mutex so other goroutines can access
                // the table while we ping the least recently active node.
                tab.mutex.Unlock()
                err := tab.ping(oldest.ID, oldest.addr())
                tab.mutex.Lock()
                oldest.contested = false
                if err == nil {
                        // The node responded, don't replace it.
                        return
                }
        }
        added := b.replace(new, oldest)
        if added && tab.nodeAddedHook != nil {
                tab.nodeAddedHook(new)
        }
}
```

stuff 方法比较简单。 找到对应节点应该插入的 bucket。 如果这个 bucket 没有满，那么就插入这个 bucket。否则什么也不做。 需要说一下的是 logdist()这个方法。这个方法对两个值进行按照位置异或，然后返回最高位的下标。 比如 logdist(101,010) = 3 logdist(100, 100) = 0 logdist(100,110) = 2

```go
// stuff adds nodes the table to the end of their corresponding bucket
// if the bucket is not full. The caller must hold tab.mutex.
func (tab *Table) stuff(nodes []*Node) {
outer:
        for _, n := range nodes {
                if n.ID == tab.self.ID {
                        continue // don't add self
                }
                bucket := tab.buckets[logdist(tab.self.sha, n.sha)]
                for i := range bucket.entries {
                        if bucket.entries[i].ID == n.ID {
                                continue outer // already in bucket
                        }
                }
                if len(bucket.entries) < bucketSize {
                        bucket.entries = append(bucket.entries, n)
                        if tab.nodeAddedHook != nil {
                                tab.nodeAddedHook(n)
                        }
                }
        }
}
```

在看看之前的 Lookup 函数。 这个函数用来查询一个指定节点的信息。 这个函数首先从本地拿到距离这个节点最近的所有 16 个节点。 然后给所有的节点发送 findnode 的请求。 然后对返回的界定进行 bondall 处理。 然后返回所有的节点。

```go
func (tab *Table) lookup(targetID NodeID, refreshIfEmpty bool) []*Node {
        var (
                target         = crypto.Keccak256Hash(targetID[:])
                asked          = make(map[NodeID]bool)
                seen           = make(map[NodeID]bool)
                reply          = make(chan []*Node, alpha)
                pendingQueries = 0
                result         *nodesByDistance
        )
        // don't query further if we hit ourself.
        // unlikely to happen often in practice.
        asked[tab.self.ID] = true
        不会询问我们自己
        for {
                tab.mutex.Lock()
                // generate initial result set
                result = tab.closest(target, bucketSize)
                //求取和target最近的16个节点
                tab.mutex.Unlock()
                if len(result.entries) > 0 || !refreshIfEmpty {
                        break
                }
                // The result set is empty, all nodes were dropped, refresh.
                // We actually wait for the refresh to complete here. The very
                // first query will hit this case and run the bootstrapping
                // logic.
                <-tab.refresh()
                refreshIfEmpty = false
        }

        for {
                // ask the alpha closest nodes that we haven't asked yet
                // 这里会并发的查询，每次3个goroutine并发(通过pendingQueries参数进行控制)
                // 每次迭代会查询result中和target距离最近的三个节点。
                for i := 0; i < len(result.entries) && pendingQueries < alpha; i++ {
                        n := result.entries[i]
                        if !asked[n.ID] { //如果没有查询过 //因为这个result.entries会被重复循环很多次。 所以用这个变量控制那些已经处理过了。
                                asked[n.ID] = true
                                pendingQueries++
                                go func() {
                                        // Find potential neighbors to bond with
                                        r, err := tab.net.findnode(n.ID, n.addr(), targetID)
                                        if err != nil {
                                                // Bump the failure counter to detect and evacuate non-bonded entries
                                                fails := tab.db.findFails(n.ID) + 1
                                                tab.db.updateFindFails(n.ID, fails)
                                                log.Trace("Bumping findnode failure counter", "id", n.ID, "failcount", fails)

                                                if fails >= maxFindnodeFailures {
                                                        log.Trace("Too many findnode failures, dropping", "id", n.ID, "failcount", fails)
                                                        tab.delete(n)
                                                }
                                        }
                                        reply <- tab.bondall(r)
                                }()
                        }
                }
                if pendingQueries == 0 {
                        // we have asked all closest nodes, stop the search
                        break
                }
                // wait for the next reply
                for _, n := range <-reply {
                        if n != nil && !seen[n.ID] { //因为不同的远方节点可能返回相同的节点。所有用seen[]来做排重。
                                seen[n.ID] = true
                                //这个地方需要注意的是, 查找出来的结果又会加入result这个队列。也就是说这是一个循环查找的过程， 只要result里面不断加入新的节点。这个循环就不会终止。
                                result.push(n, bucketSize)
                        }
                }
                pendingQueries--
        }
        return result.entries
}

// closest returns the n nodes in the table that are closest to the
// given id. The caller must hold tab.mutex.
func (tab *Table) closest(target common.Hash, nresults int) *nodesByDistance {
        // This is a very wasteful way to find the closest nodes but
        // obviously correct. I believe that tree-based buckets would make
        // this easier to implement efficiently.
        close := &nodesByDistance{target: target}
        for _, b := range tab.buckets {
                for _, n := range b.entries {
                        close.push(n, nresults)
                }
        }
        return close
}
```

result.push 方法，这个方法会根据 所有的节点对于 target 的距离进行排序。 按照从近到远的方式决定新节点的插入顺序。(队列中最大会包含 16 个元素)。 这样会导致队列里面的元素和 target 的距离越来越近。距离相对远的会被踢出队列。

```go
// nodesByDistance is a list of nodes, ordered by
// distance to target.
type nodesByDistance struct {
        entries []*Node
        target  common.Hash
}

// push adds the given node to the list, keeping the total size below maxElems.
func (h *nodesByDistance) push(n *Node, maxElems int) {
        ix := sort.Search(len(h.entries), func(i int) bool {
                return distcmp(h.target, h.entries[i].sha, n.sha) > 0
        })
        if len(h.entries) < maxElems {
                h.entries = append(h.entries, n)
        }
        if ix == len(h.entries) {
                // farther away than all nodes we already have.
                // if there was room for it, the node is now the last element.
        } else {
                // slide existing entries down to make room
                // this will overwrite the entry we just appended.
                copy(h.entries[ix+1:], h.entries[ix:])
                h.entries[ix] = n
        }
}
```

### **table.go 导出的一些方法**

Resolve 方法和 Lookup 方法

```go
// Resolve searches for a specific node with the given ID.
// It returns nil if the node could not be found.
//Resolve方法用来获取一个指定ID的节点。 如果节点在本地。那么返回本地节点。 否则执行
//Lookup在网络上查询一次。 如果查询到节点。那么返回。否则返回nil
func (tab *Table) Resolve(targetID NodeID) *Node {
        // If the node is present in the local table, no
        // network interaction is required.
        hash := crypto.Keccak256Hash(targetID[:])
        tab.mutex.Lock()
        cl := tab.closest(hash, 1)
        tab.mutex.Unlock()
        if len(cl.entries) > 0 && cl.entries[0].ID == targetID {
                return cl.entries[0]
        }
        // Otherwise, do a network lookup.
        result := tab.Lookup(targetID)
        for _, n := range result {
                if n.ID == targetID {
                        return n
                }
        }
        return nil
}

// Lookup performs a network search for nodes close
// to the given target. It approaches the target by querying
// nodes that are closer to it on each iteration.
// The given target does not need to be an actual node
// identifier.
func (tab *Table) Lookup(targetID NodeID) []*Node {
        return tab.lookup(targetID, true)
}
```

SetFallbackNodes 方法，这个方法设置初始化的联系节点。 在 table 是空而且数据库里面也没有已知的节点，这些节点可以帮助连接上网络，

```go
// SetFallbackNodes sets the initial points of contact. These nodes
// are used to connect to the network if the table is empty and there
// are no known nodes in the database.
func (tab *Table) SetFallbackNodes(nodes []*Node) error {
        for _, n := range nodes {
                if err := n.validateComplete(); err != nil {
                        return fmt.Errorf("bad bootstrap/fallback node %q (%v)", n, err)
                }
        }
        tab.mutex.Lock()
        tab.nursery = make([]*Node, 0, len(nodes))
        for _, n := range nodes {
                cpy := *n
                // Recompute cpy.sha because the node might not have been
                // created by NewNode or ParseNode.
                cpy.sha = crypto.Keccak256Hash(n.ID[:])
                tab.nursery = append(tab.nursery, &cpy)
        }
        tab.mutex.Unlock()
        tab.refresh()
        return nil
}
```

### **总结**

这样， p2p 网络的 Kademlia 协议就完结了。 基本上是按照论文进行实现。 udp 进行网络通信。数据库存储链接过的节点。 table 实现了 Kademlia 的核心。 根据异或距离来进行节点的查找。 节点的发现和更新等流程。
