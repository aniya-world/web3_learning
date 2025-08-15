fetcher 包含基于块通知的同步。当我们接收到 NewBlockHashesMsg 消息得时候，我们只收到了很多 Block 的 hash 值。 需要通过 hash 值来同步区块，然后更新本地区块链。 fetcher 就提供了这样的功能。


这段Go代码是一个Fetcher的实现，它负责在区块链网络中同步区块。

它的主要功能是处理传入的
        区块公告和请求、
        检索丢失的区块数据，以及
        管理待导入到本地区块链的区块队列


数据结构

```go
// announce is the hash notification of the availability of a new block in the
// network.
// announce 是一个hash通知，表示网络上有合适的新区块出现。announce 结构体表示一个区块公告 
type announce struct {
        hash   common.Hash   // Hash of the block being announced //新区块的hash值
        number uint64        // Number of the block being announced (0 = unknown | old protocol) 区块的高度值，
        header *types.Header // Header of the block partially reassembled (new protocol)        重新组装的区块头
        time   time.Time     // Timestamp of the announcement 记录收到此公告的时间戳

        origin string // Identifier of the peer originating the notification 用来识别发送此公告的对等节点（peer）

        fetchHeader headerRequesterFn // Fetcher function to retrieve the header of an announced block  获取区块头的函数指针， 里面包含了peer的信息。就是说找谁要这个区块头
        fetchBodies bodyRequesterFn   // Fetcher function to retrieve the body of an announced block 获取区块体的函数指针
}

// headerFilterTask 结构体表示一批需要由 Fetcher 过滤的区块头。
type headerFilterTask struct {
        peer    string          // The source peer of block headers 标识了发送这批区块头的对等节点。
        headers []*types.Header // Collection of headers to filter 是一个指向 types.Header 结构体的指针切片（slice），表示需要过滤的区块头集合。
        time    time.Time       // Arrival time of the headers
}

// headerFilterTask represents a batch of block bodies (transactions and uncles)
// needing fetcher filtering.
type bodyFilterTask struct {
        peer         string                 //发送区块主体的对等节点
        transactions [][]*types.Transaction //每个区块的交易集合
        uncles       [][]*types.Header      //每个区块的叔块集合
        time         time.Time              //区块内容的到达时间
}

// inject represents a schedules import operation. 
// 当节点收到NewBlockMsg的消息时候，会插入一个区块 ；  结构体代表一个待插入的区块
type inject struct {
        origin string
        block  *types.Block
}

// Fetcher is responsible for accumulating block announcements from various peers
// and scheduling them for retrieval.
这是 Fetcher 的主要结构体，负责收集区块公告并安排检索
type Fetcher struct {
        // ...
        notify chan *announce        //接收announce的通道
        inject chan *inject                //接收inject的通道
        blockFilter  chan chan []*types.Block         //用于过滤区块的通道的通道
        headerFilter chan chan *headerFilterTask
        bodyFilter   chan chan *bodyFilterTask
        done chan common.Hash //导入完成后发送区块哈希的通道
        quit chan struct{} //用于请求终止的通道
        // Announce states
        announces  map[string]int              //按对等节点统计的公告数，防止内存耗尽
        announced  map[common.Hash][]*announce //等待调度的公告
        fetching   map[common.Hash]*announce   //正在fetching的公告
        fetched    map[common.Hash][]*announce //已获取区块头，等待获取区块体
        completing map[common.Hash]*announce   //已获取头和体，正在完成组装
        // Block cache
        queue  *prque.Prque            //包含导入操作的优先级队列（按区块号排序）
        queues map[string]int          //按对等节点统计的区块数，防止内存耗尽
        queued map[common.Hash]*inject //已在队列中的区块集合，用于去重
        // Callbacks
        getBlock       blockRetrievalFn   //从本地链检索区块的回调函数
        verifyHeader   headerVerifierFn   //验证区块头工作量证明的回调函数
        broadcastBlock blockBroadcasterFn //广播区块给对等节点的回调函数
        chainHeight    chainHeightFn      //获取当前链高度的回调函数
        insertChain    chainInsertFn      //将一批区块插入链中的回调函数
        dropPeer       peerDropFn         //断开与行为不当的对等节点连接的回调函数
        // Testing hooks
        announceChangeHook func(common.Hash, bool) //添加或删除公告哈希时调用的测试钩子
        queueChangeHook    func(common.Hash, bool) //添加或删除队列中的区块时调用的测试钩子
        fetchingHook       func([]common.Hash)     //开始区块或区块头检索时调用的测试钩子
        completingHook     func([]common.Hash)     //开始区块体检索时调用的测试钩子
        importedHook       func(*types.Block)      //成功导入区块后调用的测试钩子
}
```

启动 fetcher， 直接启动了一个 goroutine 来处理。 这个函数有点长。 后续再分析。
Start 方法启动一个 goroutine 来运行 loop
```go
// Start boots up the announcement based synchroniser, accepting and processing
// hash notifications and block fetches until termination requested.
func (f *Fetcher) Start() {
        go f.loop()
}
```

loop 函数函数太长。 我先帖一个省略版本的出来。fetcher 
通过四个 map(announced,fetching,fetched,completing )
记录了 announce 的状态(等待 fetch,正在 fetch,fetch 完头等待 fetch body, fetch 完成)。 

loop 其实通过定时器和各种消息来对各种 map 里面的 announce 进行状态转换。

```go
// Loop is the main fetcher loop, checking and processing various notification
// events.
func (f *Fetcher) loop() {
        fetchTimer := time.NewTimer(0) //用于调度区块头fetching的定时器
        completeTimer := time.NewTimer(0) //用于调度区块体fetching的定时器

        for {
                // 清理任何过期的区块检索
                for hash, announce := range f.fetching {
                        if time.Since(announce.time) > fetchTimeout {
                                f.forgetHash(hash)
                        }
                }
                // 导入任何可能适合的排队区块
                height := f.chainHeight()
                for !f.queue.Empty() {
                        op := f.queue.PopItem().(*inject) //从队列中弹出优先级最高的区块
                        if f.queueChangeHook != nil {
                                f.queueChangeHook(op.block.Hash(), false)
                        }
                        number := op.block.NumberU64()
                        if number > height+1 { //区块高度太高，暂时不能导入
                                f.queue.Push(op, -float32(op.block.NumberU64())) //重新放入队列
                                if f.queueChangeHook != nil {
                                        f.queueChangeHook(op.block.Hash(), true)
                                }
                                break
                        }
                        hash := op.block.Hash()
                        if number+maxUncleDist < height || f.getBlock(hash) != nil { //区块太旧或已被导入
                                f.forgetBlock(hash)
                                continue
                        }
                        f.insert(op.origin, op.block) //插入区块
                }
                // 等待外部事件
                select {
                case <-f.quit: //接收到退出信号
                        return
                case notification := <-f.notify: //接收到区块公告
                        // ...
                case op := <-f.inject: //接收到完整的区块
                        // ...
                        f.enqueue(op.origin, op.block)
                case hash := <-f.done: //区块导入完成
                        // ...
                case <-fetchTimer.C: //区块头检索定时器触发
                        // ...
                case <-completeTimer.C: //区块体检索定时器触发
                        // ...
                case filter := <-f.headerFilter: //接收到区块头进行过滤
                        // ...
                case filter := <-f.bodyFilter: //接收到区块体进行过滤
                        // ...
                }
        }
}
```

### **区块头的过滤流程**

#### **FilterHeaders 请求**

FilterHeaders 方法在接收到 BlockHeadersMsg 的时候被调用。这个方法首先投递了一个 channel filter 到 headerFilter。 然后往 filter 投递了一个 headerFilterTask 的任务。然后阻塞等待 filter 队列返回消息。

```go
// FilterHeaders extracts all the headers that were explicitly requested by the fetcher,
// returning those that should be handled differently.
func (f *Fetcher) FilterHeaders(peer string, headers []*types.Header, time time.Time) []*types.Header {
        filter := make(chan *headerFilterTask) //创建一个用于通信的通道
        select {
        case f.headerFilter <- filter: //将通道发送给主循环
        case <-f.quit:
                return nil
        }
        select {
        case filter <- &headerFilterTask{peer: peer, headers: headers, time: time}: //将过滤任务发送给主循环
        case <-f.quit:
                return nil
        }
        select {
        case task := <-filter: //等待并接收过滤后的结果
                return task.headers
        case <-f.quit:
                return nil
        }
}
```

#### **headerFilter 的处理**

 
headerFilter 的处理 (在 loop 中)
主循环中处理 headerFilter 通道的部分
```go
case filter := <-f.headerFilter: //接收到过滤请求
        var task *headerFilterTask
        select {
        case task = <-filter: //接收过滤任务
        case <-f.quit:
                return
        }
        unknown, incomplete, complete := []*types.Header{}, []*announce{}, []*types.Block{} //声明并初始化三个切片来分类区块头
        for _, header := range task.headers {
                hash := header.Hash()
                if announce := f.fetching[hash]; announce != nil && announce.origin == task.peer && f.fetched[hash] == nil && f.completing[hash] == nil && f.queued[hash] == nil {
                        if header.Number.Uint64() != announce.number { //区块号不匹配，断开连接并放弃哈希
                                f.dropPeer(announce.origin)
                                f.forgetHash(hash)
                                continue
                        }
                        if f.getBlock(hash) == nil { //区块未被导入
                                announce.header = header
                                announce.time = task.time
                                if header.TxHash == types.DeriveSha(types.Transactions{}) && header.UncleHash == types.CalcUncleHash([]*types.Header{}) { //区块为空
                                        block := types.NewBlockWithHeader(header)
                                        block.ReceivedAt = task.time
                                        complete = append(complete, block)
                                        f.completing[hash] = announce
                                        continue
                                }
                                incomplete = append(incomplete, announce) //区块不为空，等待获取区块体
                        } else { //区块已导入
                                f.forgetHash(hash)
                        }
                } else { //Fetcher不知道这个header
                        unknown = append(unknown, header)
                }
        }
        select {
        case filter <- &headerFilterTask{headers: unknown, time: task.time}: //将未知区块头返回给调用者
        case <-f.quit:
                return
        }
        for _, announce := range incomplete { //处理等待获取区块体的区块
                hash := announce.header.Hash()
                if _, ok := f.completing[hash]; ok {
                        continue
                }
                f.fetched[hash] = append(f.fetched[hash], announce) //放入fetched map等待处理
                if len(f.fetched) == 1 {
                        f.rescheduleComplete(completeTimer) //如果这是第一个，重新安排定时器
                }
        }
        for _, block := range complete { //处理只有区块头的区块
                if announce := f.completing[block.Hash()]; announce != nil {
                        f.enqueue(announce.origin, block) //放入队列等待导入
                }
        }
```

#### **bodyFilter 的处理**

和上面的处理类似。
主循环中处理 bodyFilter 通道的部分
```go
case filter := <-f.bodyFilter: //接收到区块体进行过滤
        var task *bodyFilterTask
        select {
        case task = <-filter:
        case <-f.quit:
                return
        }
        blocks := []*types.Block{}
        for i := 0; i < len(task.transactions) && i < len(task.uncles); i++ {
                matched := false
                for hash, announce := range f.completing { //遍历completing map查找匹配的公告
                        if f.queued[hash] == nil {
                                txnHash := types.DeriveSha(types.Transactions(task.transactions[i]))
                                uncleHash := types.CalcUncleHash(task.uncles[i])
                                if txnHash == announce.header.TxHash && uncleHash == announce.header.UncleHash && announce.origin == task.peer { //找到匹配项
                                        matched = true
                                        if f.getBlock(hash) == nil {
                                                block := types.NewBlockWithHeader(announce.header).WithBody(task.transactions[i], task.uncles[i]) //组装完整的区块
                                                block.ReceivedAt = task.time
                                                blocks = append(blocks, block)
                                        } else {
                                                f.forgetHash(hash)
                                        }
                                }
                        }
                }
                if matched {
                        // ...
                        i--
                        continue
                }
        }
        select {
        case filter <- task: //将未匹配的区块体返回给调用者
        case <-f.quit:
                return
        }
        for _, block := range blocks { //处理已完成组装的区块
                if announce := f.completing[block.Hash()]; announce != nil {
                        f.enqueue(announce.origin, block) //放入队列等待导入
                }
        }
```

#### **notification 的处理**

在接收到 NewBlockHashesMsg 的时候，对于本地区块链还没有的区块的 hash 值会调用 fetcher 的 Notify 方法发送到 notify 通道。

Notify 和 enqueue 方法
这两个方法将事件发送到 notify 和 inject 通道
```go
// Notify announces the fetcher of the potential availability of a new block in
// the network.
func (f *Fetcher) Notify(peer string, hash common.Hash, number uint64, time time.Time,
        headerFetcher headerRequesterFn, bodyFetcher bodyRequesterFn) error {
        block := &announce{ //创建一个announce对象
                hash:        hash,
                number:      number,
                time:        time,
                origin:      peer,
                fetchHeader: headerFetcher,
                fetchBodies: bodyFetcher,
        }
        select {
        case f.notify <- block: //将announce发送到notify通道
                return nil
        case <-f.quit:
                return errTerminated
        }
}
```

在 loop 中的处理，主要是检查一下然后加入了 announced 这个容器等待定时处理。

```go
case notification := <-f.notify:
                // A block was announced, make sure the peer isn't DOSing us
                propAnnounceInMeter.Mark(1)

                count := f.announces[notification.origin] + 1
                if count > hashLimit {  //hashLimit 256 一个远端最多只存在256个announces
                        log.Debug("Peer exceeded outstanding announces", "peer", notification.origin, "limit", hashLimit)
                        propAnnounceDOSMeter.Mark(1)
                        break
                }
                // If we have a valid block number, check that it's potentially useful
                // 查看是潜在是否有用。 根据这个区块号和本地区块链的距离， 太大和太小对于我们都没有意义。
                if notification.number > 0 {
                        if dist := int64(notification.number) - int64(f.chainHeight()); dist < -maxUncleDist || dist > maxQueueDist {
                                log.Debug("Peer discarded announcement", "peer", notification.origin, "number", notification.number, "hash", notification.hash, "distance", dist)
                                propAnnounceDropMeter.Mark(1)
                                break
                        }
                }
                // All is well, schedule the announce if block's not yet downloading
                // 检查我们是否已经存在了。
                if _, ok := f.fetching[notification.hash]; ok {
                        break
                }
                if _, ok := f.completing[notification.hash]; ok {
                        break
                }
                f.announces[notification.origin] = count
                f.announced[notification.hash] = append(f.announced[notification.hash], notification)
                if f.announceChangeHook != nil && len(f.announced[notification.hash]) == 1 {
                        f.announceChangeHook(notification.hash, true)
                }
                if len(f.announced) == 1 {
                        f.rescheduleFetch(fetchTimer)
                }
```

#### **Enqueue 处理**

在接收到 NewBlockMsg 的时候会调用 fetcher 的 Enqueue 方法，这个方法会把当前接收到的区块发送到 inject 通道。 可以看到这个方法生成了一个 inject 对象然后发送到 inject 通道

```go
func (f *Fetcher) enqueue(peer string, block *types.Block) {
        hash := block.Hash()
        count := f.queues[peer] + 1
        if count > blockLimit { //检查区块数是否超出限制
                f.forgetHash(hash)
                return
        }
        if dist := int64(block.NumberU64()) - int64(f.chainHeight()); dist < -maxUncleDist || dist > maxQueueDist { //检查区块是否太旧或太远
                f.forgetHash(hash)
                return
        }
        if _, ok := f.queued[hash]; !ok { //如果区块未在队列中
                op := &inject{
                        origin: peer,
                        block:  block,
                }
                f.queues[peer] = count
                f.queued[hash] = op
                f.queue.Push(op, -float32(block.NumberU64())) //将区块放入队列
                if f.queueChangeHook != nil {
                        f.queueChangeHook(op.block.Hash(), true)
                }
        }
}
```

inject 通道处理非常简单，直接加入到队列等待 import

```go
case op := <-f.inject:
                // A direct block insertion was requested, try and fill any pending gaps
                propBroadcastInMeter.Mark(1)
                f.enqueue(op.origin, op.block)
```

enqueue

```go
// enqueue schedules a new future import operation, if the block to be imported
// has not yet been seen.
func (f *Fetcher) enqueue(peer string, block *types.Block) {
        hash := block.Hash()

        // Ensure the peer isn't DOSing us
        count := f.queues[peer] + 1
        if count > blockLimit { blockLimit 64 如果缓存的对方的block太多。
                log.Debug("Discarded propagated block, exceeded allowance", "peer", peer, "number", block.Number(), "hash", hash, "limit", blockLimit)
                propBroadcastDOSMeter.Mark(1)
                f.forgetHash(hash)
                return
        }
        // Discard any past or too distant blocks
        // 距离我们的区块链太远。
        if dist := int64(block.NumberU64()) - int64(f.chainHeight()); dist < -maxUncleDist || dist > maxQueueDist { 
                log.Debug("Discarded propagated block, too far away", "peer", peer, "number", block.Number(), "hash", hash, "distance", dist)
                propBroadcastDropMeter.Mark(1)
                f.forgetHash(hash)
                return
        }
        // Schedule the block for future importing
        // 插入到队列。
        if _, ok := f.queued[hash]; !ok {
                op := &inject{
                        origin: peer,
                        block:  block,
                }
                f.queues[peer] = count
                f.queued[hash] = op
                f.queue.Push(op, -float32(block.NumberU64()))
                if f.queueChangeHook != nil {
                        f.queueChangeHook(op.block.Hash(), true)
                }
                log.Debug("Queued propagated block", "peer", peer, "number", block.Number(), "hash", hash, "queued", f.queue.Size())
        }
}
```

#### **定时器的处理**

定时器处理 (在 loop 中)
主循环中处理定时器的部分


一共存在两个定时器。 fetchTimer 和 completeTimer ，分别负责获取区块头 和 获取区块 body。

状态转换 announced --fetchTimer(fetch header)---> fetching --(headerFilter)--> fetched --completeTimer(fetch body)-->completing --(bodyFilter)--> enqueue --task.done--> forgetHash

发现一个问题。 completing 的容器有可能泄露。如果发送了一个 hash 的 body 请求。 但是请求失败，对方并没有返回。 这个时候 completing 容器没有清理。 是否有可能导致问题。

```go
case <-fetchTimer.C: //区块头检索定时器触发
        request := make(map[string][]common.Hash)
        for hash, announces := range f.announced {
                if time.Since(announces[0].time) > arriveTimeout-gatherSlack {
                        announce := announces[rand.Intn(len(announces))] //从多个公告中随机选择一个
                        f.forgetHash(hash)
                        if f.getBlock(hash) == nil {
                                request[announce.origin] = append(request[announce.origin], hash)
                                f.fetching[hash] = announce //将区块移动到fetching map
                        }
                }
        }
        for peer, hashes := range request {
                fetchHeader, hashes := f.fetching[hashes[0]].fetchHeader, hashes
                go func() {
                        if f.fetchingHook != nil {
                                f.fetchingHook(hashes)
                        }
                        for _, hash := range hashes {
                                fetchHeader(hash) //在新的goroutine中发送区块头请求
                        }
                }()
        }
        f.rescheduleFetch(fetchTimer) //重新安排定时器

case <-completeTimer.C: //区块体检索定时器触发
        request := make(map[string][]common.Hash)
        for hash, announces := range f.fetched {
                announce := announces[rand.Intn(len(announces))]
                f.forgetHash(hash)
                if f.getBlock(hash) == nil {
                        request[announce.origin] = append(request[announce.origin], hash)
                        f.completing[hash] = announce //将区块移动到completing map
                }
        }
        for peer, hashes := range request {
                if f.completingHook != nil {
                        f.completingHook(hashes)
                }
                go f.completing[hashes[0]].fetchBodies(hashes) //在新的goroutine中发送区块体请求
        }
        f.rescheduleComplete(completeTimer) //重新安排定时器
```

#### **其他的一些方法**

fetcher insert 方法。 这个方法把给定的区块插入本地的区块链。

```go
// insert spawns a new goroutine to run a block insertion into the chain. If the
// block's number is at the same height as the current import phase, if updates
// the phase states accordingly.
func (f *Fetcher) insert(peer string, block *types.Block) {
        hash := block.Hash()
        go func() { //启动一个新的goroutine
                defer func() { f.done <- hash }() //函数返回前发送完成信号
                parent := f.getBlock(block.ParentHash())
                if parent == nil { //父区块不存在
                        return
                }
                switch err := f.verifyHeader(block.Header()); err { //验证区块头
                case nil:
                        go f.broadcastBlock(block, true) //验证通过，广播完整的区块
                case consensus.ErrFutureBlock:
                        // ...
                default:
                        f.dropPeer(peer) //验证失败，断开连接
                        return
                }
                if _, err := f.insertChain(types.Blocks{block}); err != nil { //将区块插入链中
                        return
                }
                go f.broadcastBlock(block, false) //插入成功，广播区块哈希
                if f.importedHook != nil {
                        f.importedHook(block) //调用测试钩子
                }
        }()
}
```
