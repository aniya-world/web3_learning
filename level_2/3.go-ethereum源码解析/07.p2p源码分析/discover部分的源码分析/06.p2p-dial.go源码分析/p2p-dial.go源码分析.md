dial.go 在 p2p 里面主要负责建立链接的部分工作。 比如发现建立链接的节点。 与节点建立链接。 通过 discover 来查找指定节点的地址。等功能。

dial.go 里面利用一个 dailstate 的数据结构来存储中间状态,是 dial 功能里面的核心数据结构。

```go
// dialstate schedules dials and discovery lookups.
// it get's a chance to compute new tasks on every iteration
// of the main loop in Server.run.
type dialstate struct {
        maxDynDials int                                                //最大的动态节点链接数量
        ntab        discoverTable                        //discoverTable 用来做节点查询的
        netrestrict *netutil.Netlist

        lookupRunning bool
        dialing       map[discover.NodeID]connFlag                //正在链接的节点
        lookupBuf     []*discover.Node // current discovery lookup results //当前的discovery查询结果
        randomNodes   []*discover.Node // filled from Table //从discoverTable随机查询的节点
        static        map[discover.NodeID]*dialTask  //静态的节点。 
        hist          *dialHistory

        start     time.Time        // time when the dialer was first used
        bootnodes []*discover.Node // default dials when there are no peers //这个是内置的节点。 如果没有找到其他节点。那么使用链接这些节点。
}
```

dailstate 的创建过程。

```go
func newDialState(static []*discover.Node, bootnodes []*discover.Node, ntab discoverTable, maxdyn int, netrestrict *netutil.Netlist) *dialstate {
    // 定义一个方法 newDialState，接收静态节点、引导节点、发现表、最大动态连接数和网络限制，返回一个新的 dialstate 实例
    s := &dialstate{
        //创建了一个新的 dialstate 结构体实例，并通过指针 s 引用它。结构体的各个字段被初始化为传入参数的值或通过其他方法生成的值。
        maxDynDials: maxdyn,
        // 设置最大动态拨号数
        ntab:        ntab,
        // 设置发现表
        netrestrict: netrestrict,
        // 设置网络限制
        static:      make(map[discover.NodeID]*dialTask),
        // 初始化静态拨号任务的映射
        dialing:     make(map[discover.NodeID]connFlag),
        // 初始化正在拨号的连接标志的映射
        bootnodes:   make([]*discover.Node, len(bootnodes)),
        // 创建一个与引导节点长度相同的切片
        randomNodes: make([]*discover.Node, maxdyn/2),
        // 创建一个用于存储随机节点的切片，长度为最大动态拨号数的一半
        hist:        new(dialHistory),
        // 创建一个新的拨号历史记录实例
    }
    copy(s.bootnodes, bootnodes)
    // 将引导节点复制到 dialstate 的 bootnodes 字段
    for _, n := range static {
        s.addStatic(n)
        // 遍历静态节点并将其添加到 dialstate 中
    }
    return s
    // 返回新创建的 dialstate 实例
}

```

dail 最重要的方法是 newTasks 方法。这个方法用来生成 task。 task 是一个接口。有一个 Do 的方法。

```go
type task interface {
        Do(*Server)
}

func (s *dialstate) newTasks(nRunning int, peers map[discover.NodeID]*Peer, now time.Time) []task {
        if s.start == (time.Time{}) {
                s.start = now
        }

        var newtasks []task
        //addDial是一个内部方法， 首先通过checkDial检查节点。然后设置状态，最后把节点增加到newtasks队列里面。
        addDial := func(flag connFlag, n *discover.Node) bool {
                if err := s.checkDial(n, peers); err != nil {
                        log.Trace("Skipping dial candidate", "id", n.ID, "addr", &net.TCPAddr{IP: n.IP, Port: int(n.TCP)}, "err", err)
                        return false
                }
                s.dialing[n.ID] = flag
                newtasks = append(newtasks, &dialTask{flags: flag, dest: n})
                return true
        }

        // Compute number of dynamic dials necessary at this point.
        needDynDials := s.maxDynDials
        //首先判断已经建立的连接的类型。如果是动态类型。那么需要建立动态链接数量减少。
        for _, p := range peers {
                if p.rw.is(dynDialedConn) {
                        needDynDials--
                }
        }
        //然后再判断正在建立的链接。如果是动态类型。那么需要建立动态链接数量减少。
        for _, flag := range s.dialing {
                if flag&dynDialedConn != 0 {
                        needDynDials--
                }
        }

        // Expire the dial history on every invocation.
        s.hist.expire(now)

        // Create dials for static nodes if they are not connected.
        //查看所有的静态类型。如果可以那么也创建链接。
        for id, t := range s.static {
                err := s.checkDial(t.dest, peers)
                switch err {
                case errNotWhitelisted, errSelf:
                        log.Warn("Removing static dial candidate", "id", t.dest.ID, "addr", &net.TCPAddr{IP: t.dest.IP, Port: int(t.dest.TCP)}, "err", err)
                        delete(s.static, t.dest.ID)
                case nil:
                        s.dialing[id] = t.flags
                        newtasks = append(newtasks, t)
                }
        }
        // If we don't have any peers whatsoever, try to dial a random bootnode. This
        // scenario is useful for the testnet (and private networks) where the discovery
        // table might be full of mostly bad peers, making it hard to find good ones.
        //如果当前还没有任何链接。 而且20秒(fallbackInterval)内没有创建任何链接。 那么就使用bootnode创建链接。
        if len(peers) == 0 && len(s.bootnodes) > 0 && needDynDials > 0 && now.Sub(s.start) > fallbackInterval {
                bootnode := s.bootnodes[0]
                s.bootnodes = append(s.bootnodes[:0], s.bootnodes[1:]...)
                s.bootnodes = append(s.bootnodes, bootnode)

                if addDial(dynDialedConn, bootnode) {
                        needDynDials--
                }
        }
        // Use random nodes from the table for half of the necessary
        // dynamic dials.
        //否则使用1/2的随机节点创建链接。
        randomCandidates := needDynDials / 2
        if randomCandidates > 0 {
                n := s.ntab.ReadRandomNodes(s.randomNodes)
                for i := 0; i < randomCandidates && i < n; i++ {
                        if addDial(dynDialedConn, s.randomNodes[i]) {
                                needDynDials--
                        }
                }
        }
        // Create dynamic dials from random lookup results, removing tried
        // items from the result buffer.
        i := 0
        for ; i < len(s.lookupBuf) && needDynDials > 0; i++ {
                if addDial(dynDialedConn, s.lookupBuf[i]) {
                        needDynDials--
                }
        }
        s.lookupBuf = s.lookupBuf[:copy(s.lookupBuf, s.lookupBuf[i:])]
        // Launch a discovery lookup if more candidates are needed.
        // 如果就算这样也不能创建足够动态链接。 那么创建一个discoverTask用来再网络上查找其他的节点。放入lookupBuf
        if len(s.lookupBuf) < needDynDials && !s.lookupRunning {
                s.lookupRunning = true
                newtasks = append(newtasks, &discoverTask{})
        }

        // Launch a timer to wait for the next node to expire if all
        // candidates have been tried and no task is currently active.
        // This should prevent cases where the dialer logic is not ticked
        // because there are no pending events.
        // 如果当前没有任何任务需要做，那么创建一个睡眠的任务返回。
        if nRunning == 0 && len(newtasks) == 0 && s.hist.Len() > 0 {
                t := &waitExpireTask{s.hist.min().exp.Sub(now)}
                newtasks = append(newtasks, t)
        }
        return newtasks
}
```

checkDial 方法， 用来检查任务是否需要创建链接。

```go
func (s *dialstate) checkDial(n *discover.Node, peers map[discover.NodeID]*Peer) error {
        _, dialing := s.dialing[n.ID]
        switch {
        case dialing:                                        //正在创建
                return errAlreadyDialing
        case peers[n.ID] != nil:                //已经链接了
                return errAlreadyConnected
        case s.ntab != nil && n.ID == s.ntab.Self().ID:        //建立的对象不是自己
                return errSelf
        case s.netrestrict != nil && !s.netrestrict.Contains(n.IP): //网络限制。 对方的IP地址不在白名单里面。
                return errNotWhitelisted
        case s.hist.contains(n.ID):        // 这个ID曾经链接过。 
                return errRecentlyDialed
        }
        return nil
}
```

taskDone 方法。 这个方法再 task 完成之后会被调用。 查看 task 的类型。如果是链接任务，那么增加到 hist 里面。 并从正在链接的队列删除。 如果是查询任务。 把查询的记过放在 lookupBuf 里面。

```go
func (s *dialstate) taskDone(t task, now time.Time) {
        switch t := t.(type) {
        case *dialTask:
                s.hist.add(t.dest.ID, now.Add(dialHistoryExpiration))
                delete(s.dialing, t.dest.ID)
        case *discoverTask:
                s.lookupRunning = false
                s.lookupBuf = append(s.lookupBuf, t.results...)
        }
}
```

dialTask.Do 方法，不同的 task 有不同的 Do 方法。 dailTask 主要负责建立链接。 如果 t.dest 是没有 ip 地址的。 那么尝试通过 resolve 查询 ip 地址。 然后调用 dial 方法创建链接。 对于静态的节点。如果第一次失败，那么会尝试再次 resolve 静态节点。然后再尝试 dial（因为静态节点的 ip 是配置的。 如果静态节点的 ip 地址变动。那么我们尝试 resolve 静态节点的新地址，然后调用链接。）

```go
func (t *dialTask) Do(srv *Server) {
        if t.dest.Incomplete() {
                if !t.resolve(srv) {
                        return
                }
        }
        success := t.dial(srv, t.dest)
        // Try resolving the ID of static nodes if dialing failed.
        if !success && t.flags&staticDialedConn != 0 {
                if t.resolve(srv) {
                        t.dial(srv, t.dest)
                }
        }
}
```

resolve 方法。这个方法主要调用了 discover 网络的 Resolve 方法。如果失败，那么超时再试

```go
// resolve attempts to find the current endpoint for the destination
// using discovery.
//
// Resolve operations are throttled with backoff to avoid flooding the
// discovery network with useless queries for nodes that don't exist.
// The backoff delay resets when the node is found.
func (t *dialTask) resolve(srv *Server) bool {
        if srv.ntab == nil {
                log.Debug("Can't resolve node", "id", t.dest.ID, "err", "discovery is disabled")
                return false
        }
        if t.resolveDelay == 0 {
                t.resolveDelay = initialResolveDelay
        }
        if time.Since(t.lastResolved) < t.resolveDelay {
                return false
        }
        resolved := srv.ntab.Resolve(t.dest.ID)
        t.lastResolved = time.Now()
        if resolved == nil {
                t.resolveDelay *= 2
                if t.resolveDelay > maxResolveDelay {
                        t.resolveDelay = maxResolveDelay
                }
                log.Debug("Resolving node failed", "id", t.dest.ID, "newdelay", t.resolveDelay)
                return false
        }
        // The node was found.
        t.resolveDelay = initialResolveDelay
        t.dest = resolved
        log.Debug("Resolved node", "id", t.dest.ID, "addr", &net.TCPAddr{IP: t.dest.IP, Port: int(t.dest.TCP)})
        return true
}
```

dial 方法,这个方法进行了实际的网络连接操作。 主要通过 srv.SetupConn 方法来完成， 后续再分析 Server.go 的时候再分析这个方法。

```go
// dial performs the actual connection attempt.
func (t *dialTask) dial(srv *Server, dest *discover.Node) bool {
        fd, err := srv.Dialer.Dial(dest)
        if err != nil {
                log.Trace("Dial error", "task", t, "err", err)
                return false
        }
        mfd := newMeteredConn(fd, false)
        srv.SetupConn(mfd, t.flags, dest)
        return true
}
```

discoverTask 和 waitExpireTask 的 Do 方法，

```go
func (t *discoverTask) Do(srv *Server) {
        // newTasks generates a lookup task whenever dynamic dials are
        // necessary. Lookups need to take some time, otherwise the
        // event loop spins too fast.
        next := srv.lastLookup.Add(lookupInterval)
        if now := time.Now(); now.Before(next) {
                time.Sleep(next.Sub(now))
        }
        srv.lastLookup = time.Now()
        var target discover.NodeID
        rand.Read(target[:])
        t.results = srv.ntab.Lookup(target)
}


func (t waitExpireTask) Do(*Server) {
        time.Sleep(t.Duration)
}
```
