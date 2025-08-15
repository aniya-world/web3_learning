server 是 p2p 的最主要的部分。集合了所有之前的组件。

首先看看 Server 的结构

```go
// Server manages all peer connections.
type Server struct {
        // Config fields may not be modified while the server is running.
        Config

        // Hooks for testing. These are useful because we can inhibit
        // the whole protocol stack.
        newTransport func(net.Conn) transport
        newPeerHook  func(*Peer)

        lock    sync.Mutex // protects running
        running bool

        ntab         discoverTable
        listener     net.Listener
        ourHandshake *protoHandshake
        lastLookup   time.Time
        DiscV5       *discv5.Network

        // These are for Peers, PeerCount (and nothing else).
        peerOp     chan peerOpFunc
        peerOpDone chan struct{}

        quit          chan struct{}
        addstatic     chan *discover.Node
        removestatic  chan *discover.Node
        posthandshake chan *conn
        addpeer       chan *conn
        delpeer       chan peerDrop
        loopWG        sync.WaitGroup // loop, listenLoop
        peerFeed      event.Feed
}

// conn wraps a network connection with information gathered
// during the two handshakes.
type conn struct {
        fd net.Conn
        transport
        flags connFlag
        cont  chan error      // The run loop uses cont to signal errors to SetupConn.
        id    discover.NodeID // valid after the encryption handshake
        caps  []Cap           // valid after the protocol handshake
        name  string          // valid after the protocol handshake
}

type transport interface {
        // The two handshakes.
        doEncHandshake(prv *ecdsa.PrivateKey, dialDest *discover.Node) (discover.NodeID, error)
        doProtoHandshake(our *protoHandshake) (*protoHandshake, error)
        // The MsgReadWriter can only be used after the encryption
        // handshake has completed. The code uses conn.id to track this
        // by setting it to a non-nil value after the encryption handshake.
        MsgReadWriter
        // transports must provide Close because we use MsgPipe in some of
        // the tests. Closing the actual network connection doesn't do
        // anything in those tests because NsgPipe doesn't use it.
        close(err error)
}
```

并不存在一个 newServer 的方法。 初始化的工作放在 Start()方法中。

```go
// Start starts running the server.
// Servers can not be re-used after stopping.
func (srv *Server) Start() (err error) {
        srv.lock.Lock()
        defer srv.lock.Unlock()
        if srv.running { //避免多次启动。 srv.lock为了避免多线程重复启动
                return errors.New("server already running")
        }
        srv.running = true
        log.Info("Starting P2P networking")

        // static fields
        if srv.PrivateKey == nil {
                return fmt.Errorf("Server.PrivateKey must be set to a non-nil key")
        }
        if srv.newTransport == nil {                //这里注意的是Transport使用了newRLPX 使用了rlpx.go中的网络协议。
                srv.newTransport = newRLPX
        }
        if srv.Dialer == nil { //使用了TCLPDialer
                srv.Dialer = TCPDialer{&net.Dialer{Timeout: defaultDialTimeout}}
        }
        srv.quit = make(chan struct{})
        srv.addpeer = make(chan *conn)
        srv.delpeer = make(chan peerDrop)
        srv.posthandshake = make(chan *conn)
        srv.addstatic = make(chan *discover.Node)
        srv.removestatic = make(chan *discover.Node)
        srv.peerOp = make(chan peerOpFunc)
        srv.peerOpDone = make(chan struct{})

        // node table
        if !srv.NoDiscovery {  //启动discover网络。 开启UDP的监听。
                ntab, err := discover.ListenUDP(srv.PrivateKey, srv.ListenAddr, srv.NAT, srv.NodeDatabase, srv.NetRestrict)
                if err != nil {
                        return err
                }
                //设置最开始的启动节点。当找不到其他的节点的时候。 那么就连接这些启动节点。这些节点的信息是写死在配置文件里面的。
                if err := ntab.SetFallbackNodes(srv.BootstrapNodes); err != nil {
                        return err
                }
                srv.ntab = ntab
        }

        if srv.DiscoveryV5 {//这是新的节点发现协议。 暂时还没有使用。  这里暂时没有分析。
                ntab, err := discv5.ListenUDP(srv.PrivateKey, srv.DiscoveryV5Addr, srv.NAT, "", srv.NetRestrict) //srv.NodeDatabase)
                if err != nil {
                        return err
                }
                if err := ntab.SetFallbackNodes(srv.BootstrapNodesV5); err != nil {
                        return err
                }
                srv.DiscV5 = ntab
        }

        dynPeers := (srv.MaxPeers + 1) / 2
        if srv.NoDiscovery {
                dynPeers = 0
        }        
        //创建dialerstate。 
        dialer := newDialState(srv.StaticNodes, srv.BootstrapNodes, srv.ntab, dynPeers, srv.NetRestrict)

        // handshake
        //我们自己的协议的handShake 
        srv.ourHandshake = &protoHandshake{Version: baseProtocolVersion, Name: srv.Name, ID: discover.PubkeyID(&srv.PrivateKey.PublicKey)}
        for _, p := range srv.Protocols {//增加所有的协议的Caps
                srv.ourHandshake.Caps = append(srv.ourHandshake.Caps, p.cap())
        }
        // listen/dial
        if srv.ListenAddr != "" {
                //开始监听TCP端口
                if err := srv.startListening(); err != nil {
                        return err
                }
        }
        if srv.NoDial && srv.ListenAddr == "" {
                log.Warn("P2P server will be useless, neither dialing nor listening")
        }

        srv.loopWG.Add(1)
        //启动goroutine 来处理程序。
        go srv.run(dialer)
        srv.running = true
        return nil
}
```

启动监听。 可以看到是 TCP 协议。 这里的监听端口和 UDP 的端口是一样的。 默认都是 30303

```go
func (srv *Server) startListening() error {
        // Launch the TCP listener.
        listener, err := net.Listen("tcp", srv.ListenAddr)
        if err != nil {
                return err
        }
        laddr := listener.Addr().(*net.TCPAddr)
        srv.ListenAddr = laddr.String()
        srv.listener = listener
        srv.loopWG.Add(1)
        go srv.listenLoop()
        // Map the TCP listening port if NAT is configured.
        if !laddr.IP.IsLoopback() && srv.NAT != nil {
                srv.loopWG.Add(1)
                go func() {
                        nat.Map(srv.NAT, srv.quit, "tcp", laddr.Port, laddr.Port, "ethereum p2p")
                        srv.loopWG.Done()
                }()
        }
        return nil
}
```

listenLoop()。 这是一个死循环的 goroutine。 会监听端口并接收外部的请求。

```go
// listenLoop runs in its own goroutine and accepts
// inbound connections.
func (srv *Server) listenLoop() {
        defer srv.loopWG.Done()
        log.Info("RLPx listener up", "self", srv.makeSelf(srv.listener, srv.ntab))

        // This channel acts as a semaphore limiting
        // active inbound connections that are lingering pre-handshake.
        // If all slots are taken, no further connections are accepted.
        tokens := maxAcceptConns
        if srv.MaxPendingPeers > 0 {
                tokens = srv.MaxPendingPeers
        }
        //创建maxAcceptConns个槽位。 我们只同时处理这么多连接。 多了也不要。
        slots := make(chan struct{}, tokens)
        //把槽位填满。
        for i := 0; i < tokens; i++ {
                slots <- struct{}{}
        }

        for {
                // Wait for a handshake slot before accepting.
                <-slots

                var (
                        fd  net.Conn
                        err error
                )
                for {
                        fd, err = srv.listener.Accept()
                        if tempErr, ok := err.(tempError); ok && tempErr.Temporary() {
                                log.Debug("Temporary read error", "err", err)
                                continue
                        } else if err != nil {
                                log.Debug("Read error", "err", err)
                                return
                        }
                        break
                }

                // Reject connections that do not match NetRestrict.
                // 白名单。 如果不在白名单里面。那么关闭连接。
                if srv.NetRestrict != nil {
                        if tcp, ok := fd.RemoteAddr().(*net.TCPAddr); ok && !srv.NetRestrict.Contains(tcp.IP) {
                                log.Debug("Rejected conn (not whitelisted in NetRestrict)", "addr", fd.RemoteAddr())
                                fd.Close()
                                slots <- struct{}{}
                                continue
                        }
                }

                fd = newMeteredConn(fd, true)
                log.Trace("Accepted connection", "addr", fd.RemoteAddr())

                // Spawn the handler. It will give the slot back when the connection
                // has been established.
                go func() {
                        //看来只要连接建立完成之后。 槽位就会归还。 SetupConn这个函数我们记得再dialTask.Do里面也有调用， 这个函数主要是执行连接的几次握手。
                        srv.SetupConn(fd, inboundConn, nil)
                        slots <- struct{}{}
                }()
        }
}
```

SetupConn,这个函数执行握手协议，并尝试把连接创建位一个 peer 对象。

```go
// SetupConn runs the handshakes and attempts to add the connection
// as a peer. It returns when the connection has been added as a peer
// or the handshakes have failed.
func (srv *Server) SetupConn(fd net.Conn, flags connFlag, dialDest *discover.Node) {
        // Prevent leftover pending conns from entering the handshake.
        srv.lock.Lock()
        running := srv.running
        srv.lock.Unlock()
        //创建了一个conn对象。 newTransport指针实际上指向的newRLPx方法。 实际上是把fd用rlpx协议包装了一下。
        c := &conn{fd: fd, transport: srv.newTransport(fd), flags: flags, cont: make(chan error)}
        if !running {
                c.close(errServerStopped)
                return
        }
        // Run the encryption handshake.
        var err error
        //这里实际上执行的是rlpx.go里面的doEncHandshake.因为transport是conn的一个匿名字段。 匿名字段的方法会直接作为conn的一个方法。
        if c.id, err = c.doEncHandshake(srv.PrivateKey, dialDest); err != nil {
                log.Trace("Failed RLPx handshake", "addr", c.fd.RemoteAddr(), "conn", c.flags, "err", err)
                c.close(err)
                return
        }
        clog := log.New("id", c.id, "addr", c.fd.RemoteAddr(), "conn", c.flags)
        // For dialed connections, check that the remote public key matches.
        // 如果连接握手的ID和对应的ID不匹配
        if dialDest != nil && c.id != dialDest.ID {
                c.close(DiscUnexpectedIdentity)
                clog.Trace("Dialed identity mismatch", "want", c, dialDest.ID)
                return
        }
        // 这个checkpoint其实就是把第一个参数发送给第二个参数指定的队列。然后从c.cout接收返回信息。 是一个同步的方法。
        //至于这里，后续的操作只是检查了一下连接是否合法就返回了。
        if err := srv.checkpoint(c, srv.posthandshake); err != nil {
                clog.Trace("Rejected peer before protocol handshake", "err", err)
                c.close(err)
                return
        }
        // Run the protocol handshake
        phs, err := c.doProtoHandshake(srv.ourHandshake)
        if err != nil {
                clog.Trace("Failed proto handshake", "err", err)
                c.close(err)
                return
        }
        if phs.ID != c.id {
                clog.Trace("Wrong devp2p handshake identity", "err", phs.ID)
                c.close(DiscUnexpectedIdentity)
                return
        }
        c.caps, c.name = phs.Caps, phs.Name
        // 这里两次握手都已经完成了。 把c发送给addpeer队列。 后台处理这个队列的时候，会处理这个连接
        if err := srv.checkpoint(c, srv.addpeer); err != nil {
                clog.Trace("Rejected peer", "err", err)
                c.close(err)
                return
        }
        // If the checks completed successfully, runPeer has now been
        // launched by run.
}
```

上面说到的流程是 listenLoop 的流程，listenLoop 主要是用来接收外部主动连接者的。 
还有部分情况是节点需要主动发起连接来连接外部节点的流程。 

以及处理刚才上面的 checkpoint 队列信息的流程。

这部分代码都在 server.run 这个 goroutine 里面。

```go
func (srv *Server) run(dialstate dialer) {
        // 这行代码定义了一个方法 run，它属于指向 Server 结构体的指针类型 srv。
        // 该方法接收一个名为 dialstate 的参数，其类型为 dialer 接口。
        defer srv.loopWG.Done()
        // defer 关键字用于确保 srv.loopWG.Done() 语句会在 run 方法返回前被执行。
        // 这保证了 WaitGroup 的计数器会减少，从而避免主程序死锁。
        // WaitGroup 是 Go 语言用于等待一组 goroutine 完成的同步机制。

        var (
                peers        = make(map[discover.NodeID]*Peer)
                // 声明并初始化一个名为 peers 的 map，其键是节点的 ID，值是指向 Peer 结构体的指针。
                // 功能作用：用于存储所有当前连接的对等节点，方便通过 ID 查找和管理。
                trusted      = make(map[discover.NodeID]bool, len(srv.TrustedNodes))
                // 声明并初始化一个名为 trusted 的 map，其键是节点的 ID，值是布尔类型。
                // 初始容量被设置为 srv.TrustedNodes 的长度，可以减少后续扩容的开销。
                // 功能作用：用于快速检查某个节点是否在信任列表中，键的存在即代表信任。
                taskdone     = make(chan task, maxActiveDialTasks)
                // 声明并初始化一个名为 taskdone 的带缓冲 channel，用于在任务完成时发送通知。
                // 缓冲区大小为 maxActiveDialTasks，意味着可以存储指定数量的完成任务，而不会阻塞发送 goroutine。
                // 功能作用：用于接收完成的拨号任务，主循环可以监听此 channel 来处理已完成的任务。
                runningTasks []task
                // 声明一个名为 runningTasks 的 task 类型切片。
                // 功能作用：用于跟踪当前正在执行中的拨号任务。
                queuedTasks  []task
                // 声明一个名为 queuedTasks 的 task 类型切片。
                // 功能作用：用于存储等待执行的拨号任务。
        )

        for _, n := range srv.TrustedNodes {
                // 这是一个 for 循环，使用 range 遍历 srv.TrustedNodes 切片。
                // `_` 表示忽略索引，`n` 是切片中的每个元素（一个节点）。
                trusted[n.ID] = true
                // 语法：将节点的 ID 作为键，true 作为值，存入 trusted map。
                // 功能作用：将所有被信任的节点 ID 预加载到 trusted map 中，以便后续能以 O(1) 的时间复杂度快速查找。
        }

        delTask := func(t task) {
                // 语法：定义一个匿名函数，并将其赋值给变量 delTask。
                // 这个函数接收一个 task 类型的参数 t，用于从 runningTasks 切片中删除任务。
                for i := range runningTasks {
                        // 语法：遍历 runningTasks 切片，i 是索引。
                        // 功能作用：查找要删除的任务 t 在切片中的位置。
                        if runningTasks[i] == t {
                                // 语法：如果找到匹配的任务。
                                // 功能作用：进行任务的匹配比较。
                                runningTasks = append(runningTasks[:i], runningTasks[i+1:]...)
                                // 语法：这是一个 Go 切片删除元素的惯用写法。
                                // 它将 `i` 之前的子切片与 `i` 之后的子切片拼接起来，从而从切片中删除了索引 `i` 处的元素。
                                // 功能作用：从正在运行的任务列表中移除已完成的任务。
                                //为什么 runningTasks[:i] 不需要展开
                //直接传递切片：runningTasks[:i] 是一个切片，作为第一个参数直接传递给 append 函数。append 函数会将这个切片视为要添加元素的基础切片。
                //展开操作符的用途：展开操作符 ... 主要用于将切片中的元素作为单独的参数传递给函数。在这个例子中，runningTasks[i+1:] 是一个切片，使用 ... 将其元素展开为单独的参数，以便将这些元素添加到 runningTasks[:i] 中
                                break
                                // 语法：跳出当前 for 循环。
                                // 功能作用：找到并删除任务后，立即退出循环，提高效率。
                        }
                }
        }

        startTasks := func(ts []task) (rest []task) {
                // 语法：定义另一个匿名函数 startTasks，接收一个任务切片 ts，并返回一个名为 rest 的任务切片。
                // 功能作用：用于从给定的任务切片中，尽可能多地启动任务，并返回未启动的任务。
                i := 0
                // 语法：声明并初始化一个局部变量 i。
                // 功能作用：作为任务切片的索引。
                for ; len(runningTasks) < maxActiveDialTasks && i < len(ts); i++ {
                        // 语法：一个 for 循环，没有初始化语句。
                        // 循环条件：当前正在运行的任务数量小于最大允许值（maxActiveDialTasks），且, 还有待处理的任务。
                        // 功能作用：按顺序遍历任务切片，直到达到最大并发任务数或所有任务都已启动。
                        t := ts[i]
                        // 语法：将当前任务赋值给变量 t。
                        // 功能作用：获取要启动的任务。
                        log.Trace("New dial task", "task", t)
                        // 语法：调用日志库的 Trace 方法，记录一条日志。
                        // 功能作用：输出一条调试日志，表明一个新的拨号任务即将开始。
                        go func() { t.Do(srv); taskdone <- t }()
                        // 语法：使用 go 关键字启动一个 goroutine，在后台执行一个匿名函数。
                        // 该匿名函数首先调用任务的 Do 方法来执行任务，然后将任务 t 发送到 taskdone channel。
                        // 功能作用：以非阻塞的方式并发执行拨号任务，并在任务完成后通知主循环。
                        runningTasks = append(runningTasks, t)
                        // 语法：将新启动的任务添加到 runningTasks 切片中。
                        // 功能作用：更新正在运行的任务列表。
                }
                return ts[i:]
                // 语法：返回从索引 i 开始到切片末尾的子切片。
                // 功能作用：返回所有由于达到并发限制而未能启动的任务，这些任务将用于后续的排队。
        }

        scheduleTasks := func() {
                // 语法：定义一个匿名函数 scheduleTasks。
                // 功能作用：负责调度和启动任务，确保并发任务数量在限制范围内。
                queuedTasks = append(queuedTasks[:0], startTasks(queuedTasks)...)
                // 语法：将 queuedTasks 切片重新切片到其开头（[:0]），然后使用 startTasks(匿名函数) 启动其中的任务。
                // `...` 操作符将切片中的所有元素作为单独的参数传递给 append。
                // 这里的 `append` 操作实际上是清空了 `queuedTasks` 并用 `startTasks` 返回的未启动任务重新填充它。
                // 功能作用：先尝试启动所有已排队的任务，并将那些因为并发限制而无法启动的重新放回 `queuedTasks` 中。
                if len(runningTasks) < maxActiveDialTasks {
                        // 语法：检查当前正在运行的任务数量是否小于最大限制。
                        // 功能作用：如果还有空闲的任务槽位，就继续生成新任务。
                        nt := dialstate.newTasks(len(runningTasks)+len(queuedTasks), peers, time.Now())
                        // 语法：调用 dialstate 接口的 newTasks 方法来生成一批新的任务。
                        // 参数包括当前任务总数、所有已连接的对等节点和当前时间。
                        // 功能作用：从拨号状态机中获取新的拨号任务。
                        queuedTasks = append(queuedTasks, startTasks(nt)...)
                        // 语法：将新生成的任务 nt 传递给 startTasks 尝试启动，
                        // 然后将 startTasks 返回的未启动任务追加到 queuedTasks 的末尾。
                        // 功能作用：启动新生成的任务，并将所有无法立即启动的任务放入排队队列中。
                }
        }

running:
        // 语法：这是一个 for 循环的标签。
        // 功能作用：为外部循环提供一个名称，以便可以使用 `break running` 语句直接退出此循环。
        for {
                // 语法：这是一个无限循环。
                // 功能作用：作为主事件循环，持续运行直到收到退出信号。
                scheduleTasks()
                // 语法：调用 scheduleTasks 函数。
                // 功能作用：在每次循环迭代开始时，检查并启动新的任务。

                select {
                        // 语法：Go 语言的 select 语句，用于在多个 channel 通信操作上进行选择。∏
                        // 功能作用：监听多个 channel 的事件，哪个 channel 准备好，就执行哪个 case 语句。
                case <-srv.quit:
                        // 语法：从 srv.quit channel 接收数据，`<-` 表示接收操作。
                        // 功能作用：这是程序的退出信号 channel。当程序需要关闭时，会向此 channel 发送数据。
                        break running
                        // 语法：跳出带有 running 标签的外部 for 循环。
                        // 功能作用：接收到退出信号后，立即退出主循环，开始清理工作。

                case n := <-srv.addstatic:
                        // 语法：从 srv.addstatic channel 接收数据，并将其赋值给变量 n。
                        // 功能作用：处理添加静态节点的请求。
                        log.Debug("Adding static node", "node", n)
                        // 语法：记录一条调试日志。
                        // 功能作用：记录正在添加的静态节点的信息。
                        dialstate.addStatic(n)
                        // 语法：调用 dialstate 的 addStatic 方法。
                        // 功能作用：将新节点添加到拨号状态机的静态节点列表中。

                case n := <-srv.removestatic:
                        // 语法：从 srv.removestatic channel 接收数据，并将其赋值给变量 n。
                        // 功能作用：处理移除静态节点的请求。
                        log.Debug("Removing static node", "node", n)
                        // 语法：记录一条调试日志。
                        // 功能作用：记录正在移除的静态节点的信息。
                        dialstate.removeStatic(n)
                        // 语法：调用 dialstate 的 removeStatic 方法。
                        // 功能作用：将节点从拨号状态机的静态节点列表中移除。
                        if p, ok := peers[n.ID]; ok {
                                // 语法：使用 `if ... ok` 惯用方式检查 n.ID 是否存在于 peers map 中。
                                // 如果存在，将对应的值赋给 p，ok 为 true。
                                // 功能作用：检查要移除的静态节点是否当前已连接。
                                p.Disconnect(DiscRequested)
                                // 语法：调用 Peer 对象的 Disconnect 方法。
                                // 功能作用：主动断开与该节点的连接，并说明断开原因为请求移除。
                        }

                case op := <-srv.peerOp:
                        // 语法：从 srv.peerOp channel 接收一个函数 op。
                        // 功能作用：接收一个操作函数，该函数将直接操作 peers map。
                        op(peers)
                        // 语法：执行接收到的函数 op，并传入 peers map 作为参数。
                        // 功能作用：执行一个对 peers 列表的原子操作，例如获取或设置某些信息。
                        srv.peerOpDone <- struct{}{}
                        // 语法：向 srv.peerOpDone channel 发送一个空结构体。
                        // 空结构体 `struct{}` 不占用内存，是 Go 中常用的信号机制。
                        // 功能作用：通知发起该操作的 goroutine，操作已完成。

                case t := <-taskdone:
                        // 语法：从 taskdone channel 接收一个完成的任务 t。
                        // 功能作用：处理一个已完成的拨号任务。
                        log.Trace("Dial task done", "task", t)
                        // 语法：记录任务完成的调试日志。
                        // 功能作用：记录任务完成事件。
                        dialstate.taskDone(t, time.Now())
                        // 语法：调用 dialstate 的 taskDone 方法。
                        // 功能作用：通知拨号状态机某个任务已完成，状态机可以据此更新其内部状态，例如记录成功或失败。
                        delTask(t)
                        // 语法：调用之前定义的 delTask 函数。
                        // 功能作用：从 runningTasks 列表中移除这个已完成的任务，释放一个并发槽位。

                case c := <-srv.posthandshake:
                        // 语法：从 srv.posthandshake channel 接收一个连接 c。
                        // 功能作用：处理已经完成加密握手的连接。
                        if trusted[c.id] {
                                // 语法：检查连接的 ID 是否在 trusted map 中。
                                // 功能作用：判断当前连接是否来自一个受信任的节点。
                                c.flags |= trustedConn
                                // 语法：使用位或操作符 `|=` 设置连接的标志位。
                                // 功能作用：如果连接受信任，则在连接标志中添加 trustedConn 标记。
                        }
                        select {
                                // 语法：内嵌的 select 语句。
                                // 功能作用：处理握手检查结果的发送，同时监听退出信号以防程序关闭。
                        case c.cont <- srv.encHandshakeChecks(peers, c):
                                // 语法：调用 srv.encHandshakeChecks 方法，并将其返回值发送到连接的 c.cont channel。
                                // 功能作用：进行额外的加密握手检查，并将检查结果（通常是错误）返回给发起连接的 goroutine。
                        case <-srv.quit:
                                // 语法：从 srv.quit channel 接收数据。
                                // 功能作用：如果在握手检查期间接收到退出信号，则立即退出。
                                break running
                                // 语法：跳出外层带有 running 标签的 for 循环。
                                // 功能作用：确保在程序关闭时，不会因等待发送握手结果而阻塞。
                        }

                case c := <-srv.addpeer:
                        // 语法：从 srv.addpeer channel 接收一个连接 c。
                        // 功能作用：处理准备好成为正式对等节点的连接。
                        err := srv.protoHandshakeChecks(peers, c)
                        // 语法：调用 srv.protoHandshakeChecks 方法，将结果赋值给 err。
                        // 功能作用：进行协议级别的握手检查。
                        if err == nil {
                                // 语法：检查协议握手检查是否成功。
                                // 功能作用：如果握手通过，则继续添加对等节点。
                                p := newPeer(c, srv.Protocols)
                                // 语法：调用 newPeer 函数创建一个新的 Peer 对象。
                                // 功能作用：基于连接信息和支持的协议，创建一个代表新对等节点的实例。
                                if srv.EnableMsgEvents {
                                        // 语法：检查 Server 的 EnableMsgEvents 配置。
                                        // 功能作用：判断是否启用了消息事件功能。
                                        p.events = &srv.peerFeed
                                        // 语法：将 Server 的 peerFeed 字段的地址赋值给 Peer 的 events 字段。
                                        // 功能作用：使新 Peer 能够将消息事件发送到 Server 的事件流中。
                                }
                                name := truncateName(c.name)
                                // 语法：调用 truncateName 函数，截断节点名称。
                                // 功能作用：将过长的节点名称截断，使其更适合日志输出。
                                log.Debug("Adding p2p peer", "id", c.id, "name", name, "addr", c.fd.RemoteAddr(), "peers", len(peers)+1)
                                // 语法：记录一条调试日志，包含新对等节点的详细信息。
                                // 功能作用：记录成功的对等节点添加事件，便于调试和监控。
                                peers[c.id] = p
                                // 语法：将新创建的 Peer 实例添加到 peers map 中。
                                // 功能作用：将新节点正式添加到已连接对等节点的集合中。
                                go srv.runPeer(p)
                                // 语法：启动一个新的 goroutine，调用 srv.runPeer 方法。
                                // 功能作用：为新连接的 Peer 启动一个独立的 goroutine 来处理其数据收发和状态管理。
                        }
                        select {
                        case c.cont <- err:
                                // 语法：将握手检查的结果 err 发送到连接的 c.cont channel。
                                // 功能作用：将最终的握手结果（成功或失败）返回给发起连接的 goroutine。
                        case <-srv.quit:
                                // 语法：监听 srv.quit channel。
                                // 功能作用：在等待发送握手结果时，如果收到退出信号，则立即退出。
                                break running
                                // 语法：跳出外层 for 循环。
                                // 功能作用：确保程序能够平稳关闭。
                        }

                case pd := <-srv.delpeer:
                        // 语法：从 srv.delpeer channel 接收一个 PeerDrop 类型的数据 pd。
                        // 功能作用：处理对等节点断开连接的请求。
                        d := common.PrettyDuration(mclock.Now() - pd.created)
                        // 语法：计算节点连接持续的时间。
                        // 功能作用：计算并格式化节点从创建到断开的时间。
                        pd.log.Debug("Removing p2p peer", "duration", d, "peers", len(peers)-1, "req", pd.requested, "err", pd.err)
                        // 语法：记录一条调试日志，包含断开连接的原因和持续时间。
                        // 功能作用：记录节点移除事件，便于诊断问题。
                        delete(peers, pd.ID())
                        // 语法：使用内置函数 delete，从 peers map 中删除指定的节点。
                        // 功能作用：将断开连接的节点从活动对等节点列表中移除。
                }
        }

        log.Trace("P2P networking is spinning down")
        // 语法：记录一条跟踪日志。
        // 功能作用：在主循环退出后，日志记录 P2P 网络即将关闭。

        if srv.ntab != nil {
                // 语法：检查 srv.ntab（节点表）是否不为空。
                // 功能作用：确保在关闭节点表之前，它已经被初始化。
                srv.ntab.Close()
                // 语法：调用 srv.ntab 的 Close 方法。
                // 功能作用：关闭节点发现表，释放相关资源。
        }
        if srv.DiscV5 != nil {
                // 语法：检查 srv.DiscV5（发现服务）是否不为空。
                // 功能作用：确保在关闭发现服务之前，它已经被初始化。
                srv.DiscV5.Close()
                // 语法：调用 srv.DiscV5 的 Close 方法。
                // 功能作用：关闭 P2P 网络中的发现服务。
        }

        for _, p := range peers {
                // 语法：遍历所有剩余的对等节点。
                // 功能作用：确保在程序退出前，主动断开所有仍然连接的对等节点。
                p.Disconnect(DiscQuitting)
                // 语法：调用 Peer 对象的 Disconnect 方法，并传入 DiscQuitting 作为断开原因。
                // 功能作用：向每个对等节点发送断开连接的信号，告知对方本节点正在退出。
        }

        for len(peers) > 0 {
                // 语法：一个 for 循环，只要 peers map 中还有节点，就一直执行。
                // 功能作用：等待所有对等节点完全断开并从 peers map 中移除，确保清理完成。
                p := <-srv.delpeer
                // 语法：从 srv.delpeer channel 接收数据。
                // 功能作用：等待每个正在断开连接的节点通过 srv.delpeer channel 发送其断开信息。
                p.log.Trace("<-delpeer (spindown)", "remainingTasks", len(runningTasks))
                // 语法：记录一条跟踪日志，说明这是在程序关闭阶段接收到的 delpeer 事件。
                // 功能作用：记录关闭过程中的对等节点移除事件，并显示剩余任务数。
                delete(peers, p.ID())
                // 语法：从 peers map 中删除这个已断开连接的节点。
                // 功能作用：更新 peers map，直到所有节点都被移除。
        }
}


```

runPeer 方法

```go
// runPeer runs in its own goroutine for each peer.
// it waits until the Peer logic returns and removes
// the peer.
func (srv *Server) runPeer(p *Peer) {
        // 语法：定义一个属于 Server 结构体的 runPeer 方法，它接收一个 Peer 类型的指针 p。
        // 功能作用：这个函数是专门为每个新连接的 Peer 启动的独立 goroutine 的入口，负责管理该 Peer 的整个生命周期。
        if srv.newPeerHook != nil {
                // 语法：检查 srv.newPeerHook 字段是否不为空。
                // 功能作用：如果存在自定义的新 Peer 钩子函数，则执行它。
                srv.newPeerHook(p)
                // 语法：调用 newPeerHook 函数，并传入 Peer 对象 p。
                // 功能作用：允许外部代码在 Peer 连接后执行自定义逻辑，如添加日志、更新状态等。
        }

        // broadcast peer add
        // 语法：这是一个代码注释，描述了接下来的代码块功能。
        // 功能作用：表示即将广播一个 Peer 添加事件。
        srv.peerFeed.Send(&PeerEvent{
                // 语法：调用 srv.peerFeed 的 Send 方法，发送一个 PeerEvent 结构体的指针。
                // 功能作用：`peerFeed` 可能是一个事件订阅/发布系统，该行代码用于通知所有订阅者一个新的 Peer 已连接。
                Type: PeerEventTypeAdd,
                // 语法：设置 PeerEvent 的 Type 字段。
                // 功能作用：指定事件类型为 Peer 添加事件。
                Peer: p.ID(),
                // 语法：设置 PeerEvent 的 Peer 字段。
                // 功能作用：传入新 Peer 的 ID，以便订阅者知道是哪个 Peer 被添加了。
        })

        // run the protocol
        // 语法：注释，描述了接下来的代码功能。
        // 功能作用：表示即将运行 Peer 的通信协议。
        remoteRequested, err := p.run()
        // 语法：调用 Peer 对象的 `run()` 方法，并将其两个返回值分别赋给 `remoteRequested` 和 `err`。
        // 功能作用：`p.run()` 是核心逻辑，它阻塞在这里，直到 Peer 断开连接。它负责处理该 Peer 的所有入站和出站消息。
        // `remoteRequested` 表示断开是否由远端发起，`err` 则是断开连接时的错误信息。

        // broadcast peer drop
        // 语法：注释，描述了接下来的代码功能。
        // 功能作用：表示即将广播一个 Peer 断开事件。
        srv.peerFeed.Send(&PeerEvent{
                // 语法：再次调用 `srv.peerFeed.Send`，发送一个 PeerEvent 结构体的指针。
                // 功能作用：通知所有订阅者 Peer 已断开。
                Type:  PeerEventTypeDrop,
                // 语法：设置事件类型为 Peer 断开事件。
                // 功能作用：指定事件类型。
                Peer:  p.ID(),
                // 语法：设置 Peer 字段。
                // 功能作用：传入断开连接的 Peer ID。
                Error: err.Error(),
                // 语法：设置 Error 字段，将错误信息转换为字符串。
                // 功能作用：将断开连接的原因（如果存在）传递给订阅者。
        })

        // Note: run waits for existing peers to be sent on srv.delpeer
        // before returning, so this send should not select on srv.quit.
        // 语法：注释，提供了关于 `run` 和 `srv.delpeer` 交互的重要信息。
        // 功能作用：解释了为什么接下来的 `srv.delpeer <- ...` 操作是阻塞的，并且不需要监听退出通道。
        // 它强调了主 `run` 函数会等待所有 `delpeer` 事件发送完毕。
        srv.delpeer <- peerDrop{p, err, remoteRequested}
        // 语法：向 `srv.delpeer` channel 发送一个 `peerDrop` 结构体。
        // 功能作用：将 Peer 的断开信息（包括 Peer 对象本身、错误和断开原因）发送到主 `run` 函数的事件循环中。
        // 主 `run` 函数会接收这个信息，并从 `peers` map 中移除这个 Peer，完成清理工作。
}

```

总结：

server 对象主要完成的工作把之前介绍的所有组件组合在一起。 
使用 rlpx.go 来处理加密链路。 
使用 discover 来处理节点发现和查找。 
使用 dial 来生成和连接需要连接的节点。 
使用 peer 对象来处理每个连接。

server 启动了一个 listenLoop 来监听和接收新的连接。 
启动一个 run 的 goroutine 来调用 dialstate 生成新的 dial 任务并进行连接。 
goroutine 之间使用 channel 来进行通讯和配合。
