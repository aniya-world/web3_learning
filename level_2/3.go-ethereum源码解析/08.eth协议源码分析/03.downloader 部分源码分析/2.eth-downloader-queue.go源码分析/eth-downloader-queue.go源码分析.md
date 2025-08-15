
queue 给 downloader 提供了·调度功能·和·限流的功能·。 

通过调用 Schedule/ScheduleSkeleton 来申请对任务进行调度，然后调用 ReserveXXX 方法来领取调度完成的任务，并在 downloader 里面的线程来执行，调用 DeliverXXX 方法把下载完的数据给 queue。 最后通过 WaitResults 来获取已经完成的任务。中间还有一些对任务的额外控制，ExpireXXX 用来控制任务是否超时， CancelXXX 用来取消任务。

## **Schedule 方法**

Schedule 调用申请对一些区块头进行下载调度。可以看到做了一些合法性检查之后，把任务插入了 blockTaskPool，receiptTaskPool，receiptTaskQueue，receiptTaskPool。 
blockTaskPool 是 Map，用来记录 header 的 hash 是否存在。 
TaskQueue 是优先级队列，优先级是区块的高度的负数， 这样区块高度越小的优先级越高，就实现了首先调度小的任务的功能。

Schedule 方法用于将一组区块头添加到下载队列中进行调度，并返回新遇到的区块头。
它首先会进行合法性检查，然后将任务插入到 blockTaskPool, blockTaskQueue, receiptTaskPool 和 receiptTaskQueue 中

```go
// Schedule adds a set of headers for the download queue for scheduling, returning
// the new headers encountered.
// from表示headers里面第一个元素的区块高度。 返回值返回了所有被接收的header
func (q *queue) Schedule(headers []*types.Header, from uint64) []*types.Header {
        q.lock.Lock()                  // 获取互斥锁，保护队列的并发访问
        defer q.lock.Unlock()          // 在函数返回时释放锁

        inserts := make([]*types.Header, 0, len(headers))  // 创建一个切片用于存储将被插入的新区块头
        for _, header := range headers {                   // 遍历所有待处理的区块头
                hash := header.Hash()                      // 计算当前区块头的哈希
                if header.Number == nil || header.Number.Uint64() != from { // 检查区块号是否与期望的from值匹配
                        log.Warn("Header broke chain ordering", "number", header.Number, "hash", hash, "expected", from)
                        break
                }
                if q.headerHead != (common.Hash{}) && q.headerHead != header.ParentHash { // 检查当前区块头的父哈希是否与上一个插入的区块头的哈希匹配
                        log.Warn("Header broke chain ancestry", "number", header.Number, "hash", hash)
                        break
                }
                if _, ok := q.blockTaskPool[hash]; ok {  // 检查区块头是否已经存在于`blockTaskPool`中，避免重复调度
                        log.Warn("Header  already scheduled for block fetch", "number", header.Number, "hash", hash)
                        continue
                }
                if _, ok := q.receiptTaskPool[hash]; ok { // 检查区块头是否已经存在于`receiptTaskPool`中，避免重复调度
                        log.Warn("Header already scheduled for receipt fetch", "number", header.Number, "hash", hash)
                        continue
                }
                q.blockTaskPool[hash] = header           // 将区块头添加到`blockTaskPool`中，以哈希为键
                q.blockTaskQueue.Push(header, -float32(header.Number.Uint64())) // 将区块头及其优先级（区块号的负值，数字越小优先级越高）推入`blockTaskQueue`

                if q.mode == FastSync && header.Number.Uint64() <= q.fastSyncPivot { // 如果是快速同步模式且区块号小于或等于快同步的枢轴点
                        q.receiptTaskPool[hash] = header // 将区块头添加到`receiptTaskPool`中
                        q.receiptTaskQueue.Push(header, -float32(header.Number.Uint64())) // 将区块头及其优先级推入`receiptTaskQueue`
                }
                inserts = append(inserts, header)        // 将有效的区块头添加到`inserts`切片中
                q.headerHead = hash                      // 更新`headerHead`为当前区块头的哈希
                from++                                   // 增加from值以期望下一个区块
        }
        return inserts                                   // 返回所有被接受的区块头
}
```

## **ReserveXXX**

ReserveXXX 方法用来从 queue 里面领取一些任务来执行。downloader 里面的 goroutine 会调用这个方法来领取一些任务来执行。 这个方法直接调用了 reserveHeaders 方法。 所有的 ReserveXXX 方法都会调用 reserveHeaders 方法，除了传入的参数有一些区别。

ReserveXXX 方法用于从队列中领取任务来执行，供 downloader 里面的 goroutine 调用。
所有的 ReserveXXX 方法，包括 ReserveBodies 和 ReserveReceipts ，都会调用 reserveHeaders 方法。

ReserveBodies 用于为指定的对等节点预留一批区块体下载任务。
```go
// ReserveBodies reserves a set of body fetches for the given peer, skipping any
// previously failed downloads. Beside the next batch of needed fetches, it also
// returns a flag whether empty blocks were queued requiring processing.
func (q *queue) ReserveBodies(p *peerConnection, count int) (*fetchRequest, bool, error) {
        isNoop := func(header *types.Header) bool { // 定义一个匿名函数，检查区块是否是空块
                return header.TxHash == types.EmptyRootHash && header.UncleHash == types.EmptyUncleHash
        }
        q.lock.Lock()                  // 获取互斥锁
        defer q.lock.Unlock()          // 在函数返回时释放锁

        return q.reserveHeaders(p, count, q.blockTaskPool, q.blockTaskQueue, q.blockPendPool, q.blockDonePool, isNoop) // 调用`reserveHeaders`方法
}
```

reserveHeaders
reserveHeaders 是一个通用的方法，用于为指定的对等节点预留下载操作。
```go
// reserveHeaders reserves a set of data download operations for a given peer,
// skipping any previously failed ones. This method is a generic version used
// by the individual special reservation functions.
// reserveHeaders为指定的peer保留一些下载操作，跳过之前的任意错误。 这个方法单独被指定的保留方法调用。
// Note, this method expects the queue lock to be already held for writing. The
// reason the lock is not obtained in here is because the parameters already need
// to access the queue, so they already need a lock anyway.
// 这个方法调用的时候，假设已经获取到锁，这个方法里面没有锁的原因是参数已经传入到函数里面了，所以调用的时候就需要获取锁。
func (q *queue) reserveHeaders(p *peerConnection, count int, taskPool map[common.Hash]*types.Header, taskQueue *prque.Prque,
        pendPool map[string]*fetchRequest, donePool map[common.Hash]struct{}, isNoop func(*types.Header) bool) (*fetchRequest, bool, error) {
        if taskQueue.Empty() {                         // 如果任务队列为空
                return nil, false, nil                 // 直接返回
        }
        if _, ok := pendPool[p.id]; ok {               // 检查对等节点是否已经有正在下载的任务
                return nil, false, nil                 // 如果有，返回nil，避免状态损坏
        }
        space := len(q.resultCache) - len(donePool)    // 计算可用的任务空间
        for _, request := range pendPool {             // 遍历所有正在进行的请求
                space -= len(request.Headers)          // 从可用空间中减去正在下载的任务数量
        }
        send := make([]*types.Header, 0, count)        // 创建一个切片，用于存放要发送给对等节点的区块头
        skip := make([]*types.Header, 0)               // 创建一个切片，用于存放需要跳过的区块头

        progress := false
        for proc := 0; proc < space && len(send) < count && !taskQueue.Empty(); proc++ { // 循环直到满足条件
                header := taskQueue.PopItem().(*types.Header) // 从任务队列中弹出一个区块头
                index := int(header.Number.Int64() - int64(q.resultOffset)) // 计算结果应该存储在`resultCache`中的索引
                if index >= len(q.resultCache) || index < 0 { // 检查索引是否有效
                        common.Report("index allocation went beyond available resultCache space")
                        return nil, false, errInvalidChain
                }
                if q.resultCache[index] == nil {       // 如果是第一次调度这个任务
                        components := 1
                        if q.mode == FastSync && header.Number.Uint64() <= q.fastSyncPivot {
                                components = 2         // 快速同步模式下，需要下载区块体和收据，所以组件数为2
                        }
                        q.resultCache[index] = &fetchResult{ // 初始化结果容器
                                Pending: components,
                                Header:  header,
                        }
                }
                if isNoop(header) {                    // 如果区块是空块，不需要下载内容
                        donePool[header.Hash()] = struct{}{} // 将该任务标记为已完成
                        delete(taskPool, header.Hash())      // 从任务池中删除
                        space, proc = space-1, proc-1        // 更新空间和计数器
                        q.resultCache[index].Pending--       // 减少待处理组件数
                        progress = true
                        continue                           // 继续下一个循环
                }
                if p.Lacks(header.Hash()) {            // 如果对等节点明确表示没有这个区块数据
                        skip = append(skip, header)      // 将该区块头添加到跳过列表中
                } else {
                        send = append(send, header)      // 否则，将其添加到发送列表中
                }
        }
        for _, header := range skip {                  // 遍历所有被跳过的区块头
                taskQueue.Push(header, -float32(header.Number.Uint64())) // 将它们重新推回任务队列
        }
        if progress {                                  // 如果有进度更新
                q.active.Signal()                      // 通知`WaitResults`有改变
        }
        if len(send) == 0 {                            // 如果没有任务需要发送
                return nil, progress, nil                // 返回nil
        }
        request := &fetchRequest{                      // 创建一个下载请求
                Peer:    p,
                Headers: send,
                Time:    time.Now(),
        }
        pendPool[p.id] = request                       // 将请求添加到待处理池

        return request, progress, nil
}
```

ReserveReceipts 可以看到和 ReserveBodys 差不多。不过是队列换了而已。
ReserveReceipts 与 ReserveBodies 类似，用于为指定的对等节点预留一批收据下载任务
```go
// ReserveReceipts reserves a set of receipt fetches for the given peer, skipping
// any previously failed downloads. Beside the next batch of needed fetches, it
// also returns a flag whether empty receipts were queued requiring importing.
func (q *queue) ReserveReceipts(p *peerConnection, count int) (*fetchRequest, bool, error) {
        isNoop := func(header *types.Header) bool { // 定义一个匿名函数，检查区块是否包含收据
                return header.ReceiptHash == types.EmptyRootHash
        }
        q.lock.Lock()                  // 获取互斥锁
        defer q.lock.Unlock()          // 在函数返回时释放锁

        return q.reserveHeaders(p, count, q.receiptTaskPool, q.receiptTaskQueue, q.receiptPendPool, q.receiptDonePool, isNoop) // 调用`reserveHeaders`方法
}
```

## **DeliverXXX**

Deliver 方法在数据下载完之后会被调用。
DeliverBodies 将一个区块体检索响应注入到结果队列中
```go
// DeliverBodies injects a block body retrieval response into the results queue.
// The method returns the number of blocks bodies accepted from the delivery and
// also wakes any threads waiting for data delivery.
// DeliverBodies把一个 请求区块体的返回值插入到results队列
// 这个方法返回被delivery的区块体数量，同时会唤醒等待数据的线程
func (q *queue) DeliverBodies(id string, txLists [][]*types.Transaction, uncleLists [][]*types.Header) (int, error) {
        q.lock.Lock()                  // 获取互斥锁
        defer q.lock.Unlock()          // 在函数返回时释放锁

        reconstruct := func(header *types.Header, index int, result *fetchResult) error { // 定义一个匿名函数，用于重建区块体
                if types.DeriveSha(types.Transactions(txLists[index])) != header.TxHash || types.CalcUncleHash(uncleLists[index]) != header.UncleHash { // 检查交易哈希和叔块哈希是否匹配
                        return errInvalidBody
                }
                result.Transactions = txLists[index] // 将交易列表赋值给结果
                result.Uncles = uncleLists[index]    // 将叔块列表赋值给结果
                return nil
        }
        return q.deliver(id, q.blockTaskPool, q.blockTaskQueue, q.blockPendPool, q.blockDonePool, bodyReqTimer, len(txLists), reconstruct) // 调用`deliver`方法
}
```

deliver 方法
deliver 方法是通用的交付函数，用于处理下载完成的数据。
```go
func (q *queue) deliver(id string, taskPool map[common.Hash]*types.Header, taskQueue *prque.Prque,
        pendPool map[string]*fetchRequest, donePool map[common.Hash]struct{}, reqTimer metrics.Timer,
        results int, reconstruct func(header *types.Header, index int, result *fetchResult) error) (int, error) {

        request := pendPool[id]                        // 根据对等节点id获取请求
        if request == nil {                            // 如果请求不存在
                return 0, errNoFetchesPending            // 返回错误
        }
        reqTimer.UpdateSince(request.Time)             // 更新请求的计时器
        delete(pendPool, id)                           // 从待处理池中删除请求

        if results == 0 {                              // 如果结果为空
                for _, header := range request.Headers { // 遍历请求中的所有区块头
                        request.Peer.MarkLacking(header.Hash()) // 标记这个对等节点缺少这些数据
                }
        }
        var (
                accepted int
                failure  error
                useful   bool
        )
        for i, header := range request.Headers {       // 遍历请求中的区块头
                if i >= results {                      // 如果遍历索引超出结果数量
                        break                          // 停止遍历
                }
                index := int(header.Number.Int64() - int64(q.resultOffset)) // 计算结果在`resultCache`中的索引
                if index >= len(q.resultCache) || index < 0 || q.resultCache[index] == nil { // 检查索引是否有效
                        failure = errInvalidChain        // 标记为无效链
                        break
                }
                if err := reconstruct(header, i, q.resultCache[index]); err != nil { // 调用`reconstruct`函数重建数据
                        failure = err                    // 如果重建失败，标记错误
                        break
                }
                donePool[header.Hash()] = struct{}{}     // 将区块头哈希添加到已完成池中
                q.resultCache[index].Pending--           // 减少待处理组件数
                useful = true
                accepted++                               // 增加接受数量

                request.Headers[i] = nil                 // 清除已成功获取的区块头
                delete(taskPool, header.Hash())          // 从任务池中删除
        }
        for _, header := range request.Headers {       // 遍历所有未成功的请求
                if header != nil {
                        taskQueue.Push(header, -float32(header.Number.Uint64())) // 将它们重新推回任务队列
                }
        }
        if accepted > 0 {                              // 如果接受的数量大于0
                q.active.Signal()                      // 通知`WaitResults`线程
        }
        switch {
        case failure == nil || failure == errInvalidChain:
                return accepted, failure
        case useful:
                return accepted, fmt.Errorf("partial failure: %v", failure)
        default:
                return accepted, errStaleDelivery
        }
}
```

## **ExpireXXX and CancelXXX**

### **ExpireXXX**

ExpireBodies 函数获取了锁，然后直接调用了 expire 函数。
ExpireBodies 函数会检查超时的区块体请求，取消它们并将负责的对等节点返回以进行惩罚。
```go
// ExpireBodies checks for in flight block body requests that exceeded a timeout
// allowance, canceling them and returning the responsible peers for penalisation.
func (q *queue) ExpireBodies(timeout time.Duration) map[string]int {
        q.lock.Lock()                  // 获取互斥锁
        defer q.lock.Unlock()          // 释放互斥锁

        return q.expire(timeout, q.blockPendPool, q.blockTaskQueue, bodyTimeoutMeter) // 调用`expire`函数
}
```

expire 函数
expire 是一个通用的检查函数，将过期任务从待处理池移回任务池
```go
// expire is the generic check that move expired tasks from a pending pool back
// into a task pool, returning all entities caught with expired tasks.
// expire是通用检查，将过期任务从待处理池移回任务池，返回所有捕获已到期任务的实体。

func (q *queue) expire(timeout time.Duration, pendPool map[string]*fetchRequest, taskQueue *prque.Prque, timeoutMeter metrics.Meter) map[string]int {
        expiries := make(map[string]int)               // 创建一个map来存储过期的请求
        for id, request := range pendPool {            // 遍历待处理池中的请求
                if time.Since(request.Time) > timeout { // 如果请求时间超过了设定的超时时间
                        timeoutMeter.Mark(1)           // 记录超时指标

                        if request.From > 0 {          // 如果请求有`From`字段
                                taskQueue.Push(request.From, -float32(request.From)) // 将其推回任务队列
                        }
                        for hash, index := range request.Hashes { // 遍历哈希和索引
                                taskQueue.Push(hash, float32(index)) // 将其推回任务队列
                        }
                        for _, header := range request.Headers { // 遍历区块头
                                taskQueue.Push(header, -float32(header.Number.Uint64())) // 将其推回任务队列
                        }
                        expirations := len(request.Hashes) // 计算过期请求的数量
                        if expirations < len(request.Headers) {
                                expirations = len(request.Headers)
                        }
                        expiries[id] = expirations     // 记录对等节点id及其过期请求数量
                }
        }
        for id := range expiries {                     // 遍历所有过期请求的id
                delete(pendPool, id)                   // 从待处理池中删除它们
        }
        return expiries                                // 返回过期的请求列表
}
```

### **CancelXXX**

Cancle 函数取消已经分配的任务， 把任务重新加入到任务池。
CancelBodies 函数用于中止一个区块体获取请求，将所有待处理的区块头返回到任务队列。
```go
// CancelBodies aborts a body fetch request, returning all pending headers to the
// task queue.
func (q *queue) CancelBodies(request *fetchRequest) {
        q.cancel(request, q.blockTaskQueue, q.blockPendPool) // 调用`cancel`函数
}

func (q *queue) cancel(request *fetchRequest, taskQueue *prque.Prque, pendPool map[string]*fetchRequest) {
        q.lock.Lock()                  // 获取互斥锁
        defer q.lock.Unlock()          // 释放互斥锁

        if request.From > 0 {          // 如果请求有`From`字段
                taskQueue.Push(request.From, -float32(request.From)) // 将其推回任务队列
        }
        for hash, index := range request.Hashes { // 遍历哈希和索引
                taskQueue.Push(hash, float32(index)) // 将其推回任务队列
        }
        for _, header := range request.Headers { // 遍历区块头
                taskQueue.Push(header, -float32(header.Number.Uint64())) // 将其推回任务队列
        }
        delete(pendPool, request.Peer.id)              // 从待处理池中删除请求
}
```

## **ScheduleSkeleton**

Schedule 方法传入的是已经 fetch 好的 header。Schedule(headers []*types.Header, from uint64)。而 ScheduleSkeleton 函数的参数是一个骨架， 然后请求对骨架进行填充。所谓的骨架是指我首先每隔 192 个区块请求一个区块头，然后把返回的 header 传入 ScheduleSkeleton。 在 Schedule 函数中只需要 queue 调度区块体和回执的下载，而在 ScheduleSkeleton 函数中，还需要调度那些缺失的区块头的下载。
“
ScheduleSkeleton 函数用于为已获取的骨架（header skeleton）添加一批区块头检索任务，以填充骨架。
骨架是指每隔 MaxHeaderFetch 个区块才请求一个区块头
```go
// ScheduleSkeleton adds a batch of header retrieval tasks to the queue to fill
// up an already retrieved header skeleton.
func (q *queue) ScheduleSkeleton(from uint64, skeleton []*types.Header) {
        q.lock.Lock()                  // 获取互斥锁
        defer q.lock.Unlock()          // 释放互斥锁

        if q.headerResults != nil {    // 检查是否已经有骨架组装正在进行
                panic("skeleton assembly already in progress") // 如果是，触发panic，这是一个严重的实现bug
        }
        q.headerTaskPool = make(map[uint64]*types.Header) // 初始化`headerTaskPool`
        q.headerTaskQueue = prque.New()                // 初始化`headerTaskQueue`
        //Go 语言中用于创建优先队列（Priority Queue）的函数，通常在使用 container/heap 包时与 prque 相关的实现中使用。优先队列是一种数据结构，其中每个元素都有一个优先级，元素的处理顺序是根据其优先级来决定的。
        q.headerPeerMiss = make(map[string]map[uint64]struct{}) // 初始化`headerPeerMiss`
        q.headerResults = make([]*types.Header, len(skeleton)*MaxHeaderFetch) // 初始化`headerResults`切片
        q.headerProced = 0                             // 初始化`headerProced`为0
        q.headerOffset = from                          // 设置`headerOffset`为起始区块号
        q.headerContCh = make(chan bool, 1)            // 创建一个通道用于控制

        for i, header := range skeleton {              // 遍历骨架中的每个区块头
                index := from + uint64(i*MaxHeaderFetch) // 计算区块号
                q.headerTaskPool[index] = header       // 将区块头添加到`headerTaskPool`中
                q.headerTaskQueue.Push(index, -float32(index)) // 将区块号及其优先级推入`headerTaskQueue`
        }
}
```

### **ReserveHeaders**

这个方法只 skeleton 的模式下才会被调用。 用来给 peer 保留 fetch 区块头的任务。
 用于为对等节点预留获取区块头的任务。
```go
// ReserveHeaders reserves a set of headers for the given peer, skipping any
// previously failed batches.
func (q *queue) ReserveHeaders(p *peerConnection, count int) *fetchRequest {
        q.lock.Lock()                  // 获取互斥锁
        defer q.lock.Unlock()          // 释放互斥锁

        if _, ok := q.headerPendPool[p.id]; ok { // 检查对等节点是否已经有正在下载的任务
                return nil
        }
        send, skip := uint64(0), []uint64{}        // 初始化发送和跳过的切片
        for send == 0 && !q.headerTaskQueue.Empty() { // 循环直到找到一个可以发送的任务或队列为空
                from, _ := q.headerTaskQueue.Pop() // 从任务队列中弹出一个任务
                if q.headerPeerMiss[p.id] != nil { // 如果对等节点有缺失的区块记录
                        if _, ok := q.headerPeerMiss[p.id][from.(uint64)]; ok { // 检查当前任务是否在该节点的缺失列表中
                                skip = append(skip, from.(uint64)) // 如果是，将其添加到跳过列表中
                                continue
                        }
                }
                send = from.(uint64)                   // 找到一个可以发送的任务
        }
        for _, from := range skip {                    // 遍历所有被跳过的任务
                q.headerTaskQueue.Push(from, -float32(from)) // 将它们重新推回任务队列
        }
        if send == 0 {                                 // 如果没有任务可以发送
                return nil
        }
        request := &fetchRequest{                      // 创建一个下载请求
                Peer: p,
                From: send,
                Time: time.Now(),
        }
        q.headerPendPool[p.id] = request               // 将请求添加到待处理池
        return request                                 // 返回请求
}
```

### **DeliverHeaders**
DeliverHeaders 方法将区块头检索响应注入到区块头结果缓存中。如果区块头可以正确地映射到骨架上，它会全部接受；否则，全部拒绝。
```go
// DeliverHeaders injects a header retrieval response into the header results
// cache. This method either accepts all headers it received, or none of them
// if they do not map correctly to the skeleton.
// 这个方法对于所有的区块头，要么全部接收，要么全部拒绝(如果不能映射到一个skeleton上面)
// If the headers are accepted, the method makes an attempt to deliver the set
// of ready headers to the processor to keep the pipeline full. However it will
// not block to prevent stalling other pending deliveries.
// 如果区块头被接收，这个方法会试图把他们投递到headerProcCh管道上面。 不过这个方法不会阻塞式的投递。而是尝试投递，如果不能投递就返回。
func (q *queue) DeliverHeaders(id string, headers []*types.Header, headerProcCh chan []*types.Header) (int, error) {
        q.lock.Lock()                  // 获取互斥锁
        defer q.lock.Unlock()          // 释放互斥锁

        request := q.headerPendPool[id]                // 根据id获取请求
        if request == nil {
                return 0, errNoFetchesPending
        }
        headerReqTimer.UpdateSince(request.Time)       // 更新计时器
        delete(q.headerPendPool, id)                   // 从待处理池中删除请求

        target := q.headerTaskPool[request.From].Hash() // 获取骨架中对应区块的哈希

        accepted := len(headers) == MaxHeaderFetch     // 检查区块头数量是否与预期匹配
        if accepted {
                if headers[0].Number.Uint64() != request.From { // 检查第一个区块号是否匹配
                        log.Trace("First header broke chain ordering", "peer", id, "number", headers[0].Number, "hash", headers[0].Hash(), request.From)
                        accepted = false
                } else if headers[len(headers)-1].Hash() != target { // 检查最后一个区块的哈希是否匹配
                        log.Trace("Last header broke skeleton structure ", "peer", id, "number", headers[len(headers)-1].Number, "hash", headers[len(headers)-1].Hash(), "expected", target)
                        accepted = false
                }
        }
        if accepted {
                for i, header := range headers[1:] {   // 遍历区块头，从第二个开始
                        hash := header.Hash()
                        if want := request.From + 1 + uint64(i); header.Number.Uint64() != want { // 检查区块号是否按顺序递增
                                log.Warn("Header broke chain ordering", "peer", id, "number", header.Number, "hash", hash, "expected", want)
                                accepted = false
                                break
                        }
                        if headers[i].Hash() != header.ParentHash { // 检查区块的父哈希是否与前一个区块的哈希匹配
                                log.Warn("Header broke chain ancestry", "peer", id, "number", header.Number, "hash", hash)
                                accepted = false
                                break
                        }
                }
        }
        if !accepted {                                 // 如果不被接受
                log.Trace("Skeleton filling not accepted", "peer", id, "from", request.From)
                miss := q.headerPeerMiss[id]
                if miss == nil {
                        q.headerPeerMiss[id] = make(map[uint64]struct{})
                        miss = q.headerPeerMiss[id]
                }
                miss[request.From] = struct{}{}        // 标记该对等节点在该任务上失败

                q.headerTaskQueue.Push(request.From, -float32(request.From)) // 将任务推回任务队列
                return 0, errors.New("delivery not accepted")
        }
        copy(q.headerResults[request.From-q.headerOffset:], headers) // 将区块头复制到结果切片中
        delete(q.headerTaskPool, request.From)         // 从任务池中删除

        ready := 0
        for q.headerProced+ready < len(q.headerResults) && q.headerResults[q.headerProced+ready] != nil { // 计算有多少数据可以投递
                ready += MaxHeaderFetch
        }
        if ready > 0 {
                process := make([]*types.Header, ready)
                copy(process, q.headerResults[q.headerProced:q.headerProced+ready]) // 复制准备好的区块头
                select {
                case headerProcCh <- process:            // 尝试将区块头发送到处理通道，非阻塞
                        log.Trace("Pre-scheduled new headers", "peer", id, "count", len(process), "from", process[0].Number)
                        q.headerProced += len(process)
                default:
                }
        }
        if len(q.headerTaskPool) == 0 {                // 如果任务池为空
                q.headerContCh <- false                // 发送信号表示所有区块头任务已完成
        }
        return len(headers), nil
}
```

RetrieveHeaders，ScheduleSkeleton 函数在上次调度还没有做完的情况下是不会调用的。 所以上次调用完成之后，会使用这个方法来获取结果，重置状态。
RetrieveHeaders 方法用于在调度完成后获取组装好的区块头链
```go
// RetrieveHeaders retrieves the header chain assemble based on the scheduled
// skeleton.
func (q *queue) RetrieveHeaders() ([]*types.Header, int) {
        q.lock.Lock()                  // 获取互斥锁
        defer q.lock.Unlock()          // 释放互斥锁

        headers, proced := q.headerResults, q.headerProced // 获取结果和已处理数量
        q.headerResults, q.headerProced = nil, 0           // 重置结果和已处理数量

        return headers, proced                         // 返回结果
}
```
