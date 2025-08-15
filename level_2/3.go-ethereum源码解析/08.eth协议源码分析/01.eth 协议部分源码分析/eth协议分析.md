node 中的服务的定义， eth 其实就是实现了一个服务。

```go
type Service interface {
        // Protocols retrieves the P2P protocols the service wishes to start.
        Protocols() []p2p.Protocol
        // 这是一个方法声明，返回一个包含 P2P 协议的切片，表示该服务希望启动的协议。

        // APIs retrieves the list of RPC descriptors the service provides
        APIs() []rpc.API
        // 这是另一个方法声明，返回一个包含 RPC 描述符的切片，表示该服务提供的 API 列表。

        // Start is called after all services have been constructed and the networking
        // layer was also initialized to spawn any goroutines required by the service.
        Start(server *p2p.Server) error
        // 这是一个方法声明，接受一个指向 p2p.Server 的指针作为参数，返回一个 error 类型的值。
        // 该方法在所有服务构造完成后被调用，用于启动服务所需的 goroutine。

        // Stop terminates all goroutines belonging to the service, blocking until they
        // are all terminated.
        Stop() error
        // 这是一个方法声明，返回一个 error 类型的值。
        // 该方法用于终止服务所属的所有 goroutine，并在所有 goroutine 终止之前阻塞。
}

```

go ethereum 的 eth 目录是以太坊服务的实现。 以太坊协议是通过 node 的 Register 方法注入的。

```go
// RegisterEthService adds an Ethereum client to the stack.
func RegisterEthService(stack *node.Node, cfg *eth.Config) {
        // 定义一个名为 RegisterEthService 的函数，接受两个参数：指向 node.Node 的指针 stack 和指向 eth.Config 的指针 cfg。

        var err error
        // 声明一个变量 err，用于存储可能发生的错误。
        if cfg.SyncMode == downloader.LightSync {
                // 检查配置中的 SyncMode 是否为 LightSync。
                err = stack.Register(func(ctx *node.ServiceContext) (node.Service, error) {
                        // 注册一个新的服务，传入一个匿名函数，该函数接受一个指向 ServiceContext 的指针 ctx，并返回一个 Service 和 error。
                        return les.New(ctx, cfg)
                        // 调用 les.New 函数创建一个新的轻节点服务，并返回。
                })
        } else {
                // 如果 SyncMode 不是 LightSync，则执行以下代码。
                err = stack.Register(func(ctx *node.ServiceContext) (node.Service, error) {
                        // 注册一个新的服务，传入一个匿名函数，该函数接受一个指向 ServiceContext 的指针 ctx，并返回一个 Service 和 error。
                        fullNode, err := eth.New(ctx, cfg)
                        // 调用 eth.New 函数创建一个新的完整节点服务，并将其赋值给 fullNode。
                        if fullNode != nil && cfg.LightServ > 0 {
                                // 检查 fullNode 是否不为 nil 且配置中的 LightServ 大于 0。
                                ls, _ := les.NewLesServer(fullNode, cfg)
                                // 创建一个新的轻节点服务器 ls。
                                fullNode.AddLesServer(ls)
                                // 将轻节点服务器添加到完整节点服务中。
                        }
                        return fullNode, err
                        // 返回完整节点服务和可能的错误。
                })
        }
        if err != nil {
                // 检查是否发生了错误。
                Fatalf("Failed to register the Ethereum service: %v", err)
                // 如果发生错误，调用 Fatalf 函数输出错误信息并终止程序。
        }
}
```

以太坊协议的数据结构

```go
// Ethereum implements the Ethereum full node service.
type Ethereum struct {
    config      *Config                                        // 配置
    chainConfig *params.ChainConfig                          // 链配置

    // Channel for shutting down the service
    shutdownChan  chan bool                                  // 用于关闭以太坊服务的通道
    stopDbUpgrade func() error                               // 停止链数据库的顺序密钥升级

    // Handlers
    txPool          *core.TxPool                             // 交易池
    blockchain      *core.BlockChain                         // 区块链
    protocolManager *ProtocolManager                         // 协议管理
    lesServer       LesServer                                 // 轻量级客户端服务器

    // DB interfaces
    chainDb ethdb.Database                                   // 区块链数据库

    eventMux       *event.TypeMux                            // 事件多路复用器
    engine         consensus.Engine                           // 一致性引擎，通常是工作量证明（PoW）部分
    accountManager *accounts.Manager                          // 账号管理

    bloomRequests chan chan *bloombits.Retrieval            // 接收 bloom 过滤器数据请求的通道
    bloomIndexer  *core.ChainIndexer                         // 在区块导入时执行的 Bloom 索引器

    ApiBackend *EthApiBackend                                // 提供给 RPC 服务使用的 API 后端

    miner     *miner.Miner                                   // 矿工
    gasPrice  *big.Int                                       // 节点接收的最小 gasPrice，低于此值的交易将被拒绝
    etherbase common.Address                                  // 矿工地址

    networkId     uint64                                     // 网络 ID，测试网为 0，主网为 1
    netRPCService *ethapi.PublicNetAPI                       // RPC 服务
    lock sync.RWMutex                                        // 保护可变字段（如 gas price 和 etherbase）
}

```

以太坊协议的创建 New. 暂时先不涉及 core 的内容。 只是大概介绍一下。 core 里面的内容后续会分析。

```go
// New creates a new Ethereum object (including the
// initialisation of the common Ethereum object)
func New(ctx *node.ServiceContext, config *Config) (*Ethereum, error) {
        if config.SyncMode == downloader.LightSync {
                return nil, errors.New("can't run eth.Ethereum in light sync mode, use les.LightEthereum")
        }
        if !config.SyncMode.IsValid() {
                return nil, fmt.Errorf("invalid sync mode %d", config.SyncMode)
        }
        // 创建leveldb。 打开或者新建 chaindata目录
        chainDb, err := CreateDB(ctx, config, "chaindata")
        if err != nil {
                return nil, err
        }
        // 数据库格式升级
        stopDbUpgrade := upgradeDeduplicateData(chainDb)
        // 设置创世区块。 如果数据库里面已经有创世区块那么从数据库里面取出(私链)。或者是从代码里面获取默认值。
        chainConfig, genesisHash, genesisErr := core.SetupGenesisBlock(chainDb, config.Genesis)
        if _, ok := genesisErr.(*params.ConfigCompatError); genesisErr != nil && !ok {
                return nil, genesisErr
        }
        log.Info("Initialised chain configuration", "config", chainConfig)

        eth := &Ethereum{
                config:         config,
                chainDb:        chainDb,
                chainConfig:    chainConfig,
                eventMux:       ctx.EventMux,
                accountManager: ctx.AccountManager,
                engine:         CreateConsensusEngine(ctx, config, chainConfig, chainDb), // 一致性引擎。 这里我理解是Pow
                shutdownChan:   make(chan bool),
                stopDbUpgrade:  stopDbUpgrade,
                networkId:      config.NetworkId,  // 网络ID用来区别网路。 测试网络是0.主网是1
                gasPrice:       config.GasPrice,   // 可以通过配置 --gasprice 客户端接纳的交易的gasprice最小值。如果小于这个值那么会被节点丢弃。 
                etherbase:      config.Etherbase,  //挖矿的受益者
                bloomRequests:  make(chan chan *bloombits.Retrieval),  //bloom的请求
                bloomIndexer:   NewBloomIndexer(chainDb, params.BloomBitsBlocks),
        }

        log.Info("Initialising Ethereum protocol", "versions", ProtocolVersions, "network", config.NetworkId)

        if !config.SkipBcVersionCheck { // 检查数据库里面存储的BlockChainVersion和客户端的BlockChainVersion的版本是否一致
                bcVersion := core.GetBlockChainVersion(chainDb)
                if bcVersion != core.BlockChainVersion && bcVersion != 0 {
                        return nil, fmt.Errorf("Blockchain DB version mismatch (%d / %d). Run geth upgradedb.\n", bcVersion, core.BlockChainVersion)
                }
                core.WriteBlockChainVersion(chainDb, core.BlockChainVersion)
        }

        vmConfig := vm.Config{EnablePreimageRecording: config.EnablePreimageRecording}
        // 使用数据库创建了区块链
        eth.blockchain, err = core.NewBlockChain(chainDb, eth.chainConfig, eth.engine, vmConfig)
        if err != nil {
                return nil, err
        }
        // Rewind the chain in case of an incompatible config upgrade.
        if compat, ok := genesisErr.(*params.ConfigCompatError); ok {
                log.Warn("Rewinding chain to upgrade configuration", "err", compat)
                eth.blockchain.SetHead(compat.RewindTo)
                core.WriteChainConfig(chainDb, genesisHash, chainConfig)
        }
        // bloomIndexer 暂时不知道是什么东西 这里面涉及得也不是很多。 暂时先不管了
        eth.bloomIndexer.Start(eth.blockchain.CurrentHeader(), eth.blockchain.SubscribeChainEvent)

        if config.TxPool.Journal != "" {
                config.TxPool.Journal = ctx.ResolvePath(config.TxPool.Journal)
        }
        // 创建交易池。 用来存储本地或者在网络上接收到的交易。
        eth.txPool = core.NewTxPool(config.TxPool, eth.chainConfig, eth.blockchain)
        // 创建协议管理器
        if eth.protocolManager, err = NewProtocolManager(eth.chainConfig, config.SyncMode, config.NetworkId, eth.eventMux, eth.txPool, eth.engine, eth.blockchain, chainDb); err != nil {
                return nil, err
        }
        // 创建矿工
        eth.miner = miner.New(eth, eth.chainConfig, eth.EventMux(), eth.engine)
        eth.miner.SetExtra(makeExtraData(config.ExtraData))
        // ApiBackend 用于给RPC调用提供后端支持
        eth.ApiBackend = &EthApiBackend{eth, nil}
        // gpoParams GPO Gas Price Oracle 的缩写。 GasPrice预测。 通过最近的交易来预测当前的GasPrice的值。这个值可以作为之后发送交易的费用的参考。
        gpoParams := config.GPO
        if gpoParams.Default == nil {
                gpoParams.Default = config.GasPrice
        }
        eth.ApiBackend.gpo = gasprice.NewOracle(eth.ApiBackend, gpoParams)

        return eth, nil
}
```

ApiBackend 定义在 api_backend.go 文件中。 封装了一些函数。

```go
// EthApiBackend implements ethapi.Backend for full nodes
type EthApiBackend struct {
    eth *Ethereum                // 指向 Ethereum 结构体的指针，表示与以太坊节点的连接
    gpo *gasprice.Oracle         // 指向 gas price Oracle 的指针，  是用于获取当前的 gas 价格  Gas Price Oracle 是一个重要的组成部分，尤其是在高交易量的情况下。用户在发送交易时，可以查询 Gas Price Oracle 获取建议的 gas 价格，以确保他们的交易能够在合理的时间内被确认
}

func (b *EthApiBackend) SetHead(number uint64) {
    b.eth.protocolManager.downloader.Cancel() // 取消当前的下载操作
    b.eth.blockchain.SetHead(number)          // 设置区块链的头部为指定的区块号
}

```

New 方法中除了 core 中的一些方法， 有一个 ProtocolManager 的对象在以太坊协议中比较重要， 以太坊本来是一个协议。ProtocolManager 中又可以管理多个以太坊的子协议。

```go
//这段代码继续定义了 NewProtocolManager 函数的实现，主要负责创建和初始化一个新的 ProtocolManager 实例。
//它设置了不同的同步机制、验证器和区块插入器，并最终返回该实例。通过这些步骤，函数确保了以太坊协议的正确管理和操作
func NewProtocolManager(config *params.ChainConfig, mode downloader.SyncMode, networkId uint64, mux *event.TypeMux, txpool txPool, engine consensus.Engine, blockchain *core.BlockChain, chaindb ethdb.Database) (*ProtocolManager, error) {
        // 定义一个名为 NewProtocolManager 的函数，接受多个参数并返回一个指向 ProtocolManager 的指针和一个 error。
        
        manager := &ProtocolManager{
                // 创建一个新的 ProtocolManager 实例，并初始化其字段。
                networkId:   networkId,
                eventMux:    mux,
                txpool:      txpool,
                blockchain:  blockchain,
                chaindb:     chaindb,
                chainconfig: config,
                peers:       newPeerSet(),
                newPeerCh:   make(chan *peer),
                noMorePeers: make(chan struct{}),
                txsyncCh:    make(chan *txsync),
                quitSync:    make(chan struct{}),
        }

        if mode == downloader.FastSync && blockchain.CurrentBlock().NumberU64() > 0 {
                // 检查同步模式是否为 FastSync 且区块链当前区块编号大于 0。
                log.Warn("Blockchain not empty, fast sync disabled")
                // 如果条件满足，记录警告信息，表示快速同步被禁用。
                mode = downloader.FullSync
                // 将同步模式设置为 FullSync。
        }

        if mode == downloader.FastSync {
                manager.fastSync = uint32(1)
                // 如果同步模式为 FastSync，将 fastSync 字段设置为 1。
        }

        manager.SubProtocols = make([]p2p.Protocol, 0, len(ProtocolVersions))
        // 初始化 SubProtocols 字段为一个空的 p2p.Protocol 切片，容量为 ProtocolVersions 的长度。

        for i, version := range ProtocolVersions {
                // 遍历 ProtocolVersions 切片，获取每个版本及其索引。

                if mode == downloader.FastSync && version < eth63 {
                        continue
                        // 如果同步模式为 FastSync 且版本小于 eth63，跳过该版本。
                }

                version := version // Closure for the run
                // 创建一个局部变量 version，用于闭包。

                manager.SubProtocols = append(manager.SubProtocols, p2p.Protocol{
                        // 向 SubProtocols 切片中添加一个新的 p2p.Protocol 实例。
                        Name:    ProtocolName,
                        Version: version,
                        Length:  ProtocolLengths[i],
                        // 还记得p2p里面的Protocol么。 p2p的peer连接成功之后会调用Run方法
                        Run: func(p *p2p.Peer, rw p2p.MsgReadWriter) error {
                                // 定义一个 Run 方法，接受 p2p.Peer 和 p2p.MsgReadWriter 作为参数。
                                peer := manager.newPeer(int(version), p, rw)
                                // 创建一个新的 peer 实例。

                                select {
                                case manager.newPeerCh <- peer:
                                        // 将新创建的 peer 发送到 newPeerCh 通道。
                                        manager.wg.Add(1)
                                        // 增加 WaitGroup 的计数。
                                        defer manager.wg.Done()
                                        // 在函数结束时减少计数。
                                        return manager.handle(peer)
                                        // 调用 manager.handle 方法处理该 peer。
                                case <-manager.quitSync:
                                        return p2p.DiscQuitting
                                        // 如果 quitSync 通道被关闭，返回退出信号。
                                }
                        },
                        NodeInfo: func() interface{} {
                                //func() interface{} 表示定义了一个匿名函数，这个函数没有参数，并且返回一个 interface{} 类型的值。interface{} 是 Go 语言中的空接口，意味着这个函数可以返回任何类型的值。
                                return manager.NodeInfo()
                                // 定义 NodeInfo 方法，返回 manager 的节点信息。
                        },
                        PeerInfo: func(id discover.NodeID) interface{} {
                                // 定义 PeerInfo 方法，接受一个 NodeID 作为参数。
                                if p := manager.peers.Peer(fmt.Sprintf("%x", id[:8])); p != nil {
                                        return p.Info()
                                        // 如果找到对应的 peer，返回其信息。
                                }
                                return nil
                                // 如果没有找到，返回 nil。
                        },
                })
        }

        if len(manager.SubProtocols) == 0 {
                return nil, errIncompatibleConfig
                // 如果没有有效的 SubProtocols，返回 nil 和不兼容配置的错误。
        }

        manager.downloader = downloader.New(mode, chaindb, manager.eventMux, blockchain, nil, manager.removePeer)
        // 创建一个新的 downloader 实例，负责从其他 peer 同步数据。

        validator := func(header *types.Header) error {
                return engine.VerifyHeader(blockchain, header, true)
                // 定义一个 validator 函数，使用一致性引擎验证区块头。
        }

        heighter := func() uint64 {
                return blockchain.CurrentBlock().NumberU64()

                // 定义一个 heighter 函数，返回当前区块链的区块高度。
        }

        inserter := func(blocks types.Blocks) (int, error) {
                // 定义一个 inserter 函数，接受一个区块切片并返回插入的区块数量和可能的错误。

                if atomic.LoadUint32(&manager.fastSync) == 1 {
                        log.Warn("Discarded bad propagated block", "number", blocks[0].Number(), "hash", blocks[0].Hash())
                        // 如果 fastSync 为 1，记录警告信息，表示丢弃了不良传播的区块。
                        return 0, nil
                        // 返回 0 和 nil，表示没有插入任何区块。
                }

                atomic.StoreUint32(&manager.acceptTxs, 1) // Mark initial sync done on any fetcher import
                // 将 acceptTxs 设置为 1，标记初始同步完成。

                return manager.blockchain.InsertChain(blocks)
                // 调用 blockchain 的 InsertChain 方法插入区块，并返回插入的区块数量和可能的错误。
        }

        manager.fetcher = fetcher.New(blockchain.GetBlockByHash, validator, manager.BroadcastBlock, heighter, inserter, manager.removePeer)
        // 创建一个新的 fetcher 实例，负责从各个 peer 收集区块通知并安排检索。

        return manager, nil
        // 返回创建的 ProtocolManager 实例和 nil，表示没有错误。
}

```

服务的 APIs()方法会返回服务暴露的 RPC 方法。

```go
// APIs returns the collection of RPC services the ethereum package offers.
// NOTE, some of these services probably need to be moved to somewhere else.
func (s *Ethereum) APIs() []rpc.API {
        // 定义一个名为 APIs 的方法，属于 Ethereum 结构体，返回一个 rpc.API 切片。

        apis := ethapi.GetAPIs(s.ApiBackend)
        // 调用 ethapi.GetAPIs 函数，获取与 ApiBackend 相关的 API 列表，并将其赋值给 apis 变量。

        // Append any APIs exposed explicitly by the consensus engine
        apis = append(apis, s.engine.APIs(s.BlockChain())...)
        // 调用共识引擎的 APIs 方法，获取与当前区块链相关的 API，并将其追加到 apis 列表中。

        // Append all the local APIs and return
        return append(apis, []rpc.API{
                // 返回一个新的切片，包含所有本地 API。
                {
                        Namespace: "eth",
                        Version:   "1.0",
                        Service:   NewPublicEthereumAPI(s),
                        Public:    true,
                        // 定义一个 API，命名空间为 "eth"，版本为 "1.0"，服务为 NewPublicEthereumAPI 的实例，公开可用。
                },
                ...
                , {
                        Namespace: "net",
                        Version:   "1.0",
                        Service:   s.netRPCService,
                        Public:    true,
                        // 定义另一个 API，命名空间为 "net"，版本为 "1.0"，服务为 s.netRPCService，公开可用。
                },
        }...)
        // 将本地 API 列表追加到 apis 列表中，并返回最终的 API 列表。
}

```

服务的 Protocols 方法会返回服务提供了那些 p2p 的 Protocol。 
返回协议管理器里面的所有 SubProtocols. 
如果有 lesServer 那么还提供 lesServer 的 Protocol。
可以看到。所有的网络功能都是通过 Protocol 的方式提供出来的。

```go
// Protocols implements node.Service, returning all the currently configured
// network protocols to start.
func (s *Ethereum) Protocols() []p2p.Protocol {
        if s.lesServer == nil {
                return s.protocolManager.SubProtocols
        }
        return append(s.protocolManager.SubProtocols, s.lesServer.Protocols()...)
}
```

Ethereum 服务在创建之后，会被调用服务的 Start 方法。下面我们来看看 Start 方法

```go
// Start implements node.Service, starting all internal goroutines needed by the
// Ethereum protocol implementation.
func (s *Ethereum) Start(srvr *p2p.Server) error {
        // Start the bloom bits servicing goroutines
        // 启动布隆过滤器请求处理的goroutine TODO
        s.startBloomHandlers() // 调用方法启动处理布隆过滤器的goroutine ；Bloom Filter 是一种空间效率高的概率数据结构，用于测试一个元素是否在一个集合中

        // Start the RPC service
        // 创建网络的API net
        s.netRPCService = ethapi.NewPublicNetAPI(srvr, s.NetVersion()) // 创建新的公共网络API服务

        // Figure out a max peers count based on the server limits
        maxPeers := srvr.MaxPeers // 获取服务器允许的最大连接数
        if s.config.LightServ > 0 {
                maxPeers -= s.config.LightPeers // 减去轻客户端的连接数
                if maxPeers < srvr.MaxPeers/2 {
                        maxPeers = srvr.MaxPeers / 2 // 确保最大连接数不低于服务器最大连接数的一半
                }
        }
        // Start the networking layer and the light server if requested
        // 启动协议管理器
        s.protocolManager.Start(maxPeers) // 启动协议管理器，传入计算后的最大连接数
        if s.lesServer != nil {
                // 如果lesServer不为nil 启动它。
                s.lesServer.Start(srvr) // 启动轻客户端服务器
        }
        return nil // 返回nil表示没有错误
}

```

协议管理器的数据结构

```go
type ProtocolManager struct {
        networkId uint64 // 网络ID，用于标识不同的网络

        fastSync  uint32 // 标志位，指示是否启用快速同步（如果已经有区块则禁用）
        acceptTxs uint32 // 标志位，指示是否认为已同步（启用交易处理）

        txpool      txPool // 交易池，用于存储待处理的交易
        blockchain  *core.BlockChain // 区块链实例，管理区块链数据
        chaindb     ethdb.Database // 区块链数据库，用于持久化存储
        chainconfig *params.ChainConfig // 链的配置参数

        maxPeers    int // 最大连接的对等节点数

        downloader *downloader.Downloader // 下载器，用于下载区块
        fetcher    *fetcher.Fetcher // 获取器，用于获取数据
        peers      *peerSet // 对等节点集合，管理连接的对等节点

        SubProtocols []p2p.Protocol // 子协议列表，支持多种协议

        eventMux      *event.TypeMux // 事件多路复用器，用于处理事件
        txCh          chan core.TxPreEvent // 交易事件通道
        txSub         event.Subscription // 交易事件订阅
        minedBlockSub *event.TypeMuxSubscription // 已挖掘区块的事件订阅

        // channels for fetcher, syncer, txsyncLoop
        newPeerCh   chan *peer // 新对等节点通道
        txsyncCh    chan *txsync // 交易同步通道
        quitSync    chan struct{} // 退出同步通道
        noMorePeers chan struct{} // 无更多对等节点通道

        // wait group is used for graceful shutdowns during downloading
        // and processing
        wg sync.WaitGroup // 等待组，用于在下载和处理期间优雅地关闭
}

```

协议管理器的 Start 方法。这个方法里面启动了大量的 goroutine 用来处理各种事务，可以推测，这个类应该是以太坊服务的主要实现类。

```go
func (pm *ProtocolManager) Start(maxPeers int) {
        pm.maxPeers = maxPeers // 设置最大连接的对等节点数
        
        // broadcast transactions
        // 广播交易的通道。 txCh会作为txpool的TxPreEvent订阅通道。txpool有了这种消息会通知给这个txCh。 广播交易的goroutine会把这个消息广播出去。
        pm.txCh = make(chan core.TxPreEvent, txChanSize) // 创建一个用于交易事件的通道
        // 订阅的回执
        pm.txSub = pm.txpool.SubscribeTxPreEvent(pm.txCh) // 订阅交易预处理事件，接收交易消息
        // 启动广播的goroutine
        go pm.txBroadcastLoop() // 启动一个goroutine来处理交易的广播

        // broadcast mined blocks
        // 订阅挖矿消息。当新的Block被挖出来的时候会产生消息。 这个订阅和上面的那个订阅采用了两种不同的模式，这种是标记为Deprecated的订阅方式。
        pm.minedBlockSub = pm.eventMux.Subscribe(core.NewMinedBlockEvent{}) // 订阅新挖掘区块的事件
        // 挖矿广播 goroutine 当挖出来的时候需要尽快的广播到网络上面去。
        go pm.minedBroadcastLoop() // 启动一个goroutine来处理挖掘区块的广播

        // start sync handlers
        // 同步器负责周期性地与网络同步，下载散列和块以及处理通知处理程序。
        go pm.syncer() // 启动一个goroutine来处理同步操作
        // txsyncLoop负责每个新连接的初始事务同步。 当新的peer出现时，我们转发所有当前待处理的事务。 为了最小化出口带宽使用，我们一次只发送一个小包。
        go pm.txsyncLoop() // 启动一个goroutine来处理交易同步
}

```

当 p2p 的 server 启动的时候，会主动的找节点去连接，或者被其他的节点连接。 连接的过程是首先进行加密信道的握手，然后进行协议的握手。 最后为每个协议启动 goroutine 执行 Run 方法来把控制交给最终的协议。 这个 run 方法首先创建了一个 peer 对象，然后调用了 handle 方法来处理这个 peer

```go
Run: func(p *p2p.Peer, rw p2p.MsgReadWriter) error {
                                        peer := manager.newPeer(int(version), p, rw) // 创建一个新的对等节点实例
                                        select {
                                        case manager.newPeerCh <- peer:  // 把peer发送到newPeerCh通道
                                                manager.wg.Add(1) // 增加等待组计数，表示有一个新的goroutine正在运行
                                                defer manager.wg.Done() // 确保在函数结束时减少计数
                                                return manager.handle(peer)  // 调用handle方法处理该peer
                                        case <-manager.quitSync: // 如果接收到退出信号
                                                return p2p.DiscQuitting // 返回退出状态
                                        }
                                },

```

handle 方法,

```go
// handle is the callback invoked to manage the life cycle of an eth peer. When
// this function terminates, the peer is disconnected.
// handle是一个回调方法，用来管理eth的peer的生命周期管理。 当这个方法退出的时候，peer的连接也会断开。
func (pm *ProtocolManager) handle(p *peer) error {
        if pm.peers.Len() >= pm.maxPeers {
                return p2p.DiscTooManyPeers // 如果当前连接的对等节点数达到最大限制，返回连接过多的错误
        }
        p.Log().Debug("Ethereum peer connected", "name", p.Name()) // 记录对等节点连接的调试信息

        // Execute the Ethereum handshake
        td, head, genesis := pm.blockchain.Status() // 获取区块链状态信息
        // td是total difficult, head是当前的区块头，genesis是创世区块的信息。 只有创世区块相同才能握手成功。
        if err := p.Handshake(pm.networkId, td, head, genesis); err != nil {
                p.Log().Debug("Ethereum handshake failed", "err", err) // 记录握手失败的调试信息
                return err // 返回握手错误
        }
        if rw, ok := p.rw.(*meteredMsgReadWriter); ok {
                rw.Init(p.version) // 初始化消息读写器
        }
        // Register the peer locally
        // 把peer注册到本地
        if err := pm.peers.Register(p); err != nil {
                p.Log().Error("Ethereum peer registration failed", "err", err) // 记录注册失败的错误信息
                return err // 返回注册错误
        }
        defer pm.removePeer(p.id) // 确保在函数结束时移除该peer

        // Register the peer in the downloader. If the downloader considers it banned, we disconnect
        // 把peer注册给downloader. 如果downloader认为这个peer被禁，那么断开连接。
        if err := pm.downloader.RegisterPeer(p.id, p.version, p); err != nil {
                return err // 返回注册到下载器的错误
        }
        // Propagate existing transactions. new transactions appearing
        // after this will be sent via broadcasts.
        // 把当前pending的交易发送给对方，这个只在连接刚建立的时候发生
        pm.syncTransactions(p) // 同步当前待处理的交易到对等节点

        // If we're DAO hard-fork aware, validate any remote peer with regard to the hard-fork
        // 验证peer的DAO硬分叉
        if daoBlock := pm.chainconfig.DAOForkBlock; daoBlock != nil {
                // Request the peer's DAO fork header for extra-data validation
                if err := p.RequestHeadersByNumber(daoBlock.Uint64(), 1, 0, false); err != nil {
                        return err // 请求DAO硬分叉头部信息失败，返回错误
                }
                // Start a timer to disconnect if the peer doesn't reply in time
                // 如果15秒内没有接收到回应。那么断开连接。
                p.forkDrop = time.AfterFunc(daoChallengeTimeout, func() {
                        p.Log().Debug("Timed out DAO fork-check, dropping") // 记录超时信息
                        pm.removePeer(p.id) // 移除该peer
                })
                // Make sure it's cleaned up if the peer dies off
                defer func() {
                        if p.forkDrop != nil {
                                p.forkDrop.Stop() // 停止定时器
                                p.forkDrop = nil // 清空定时器引用
                        }
                }()
        }
        // main loop. handle incoming messages.
        // 主循环。 处理进入的消息。
        for {
                if err := pm.handleMsg(p); err != nil {
                        p.Log().Debug("Ethereum message handling failed", "err", err) // 记录消息处理失败的调试信息
                        return err // 返回消息处理错误
                }
        }
}

```

Handshake

```go
// Handshake executes the eth protocol handshake, negotiating version number,
// network IDs, difficulties, head and genesis blocks.
func (p *peer) Handshake(network uint64, td *big.Int, head common.Hash, genesis common.Hash) error {
        // Send out own handshake in a new thread
        // error的channel的大小是2， 就是为了一次性处理下面的两个goroutine方法
        errc := make(chan error, 2) // 创建一个大小为2的错误通道，用于接收两个goroutine的错误
        var status statusData // safe to read after two values have been received from errc

        go func() {
                errc <- p2p.Send(p.rw, StatusMsg, &statusData{ // 启动一个goroutine发送握手消息
                        ProtocolVersion: uint32(p.version), // 协议版本
                        NetworkId:       network, // 网络ID
                        TD:              td, // 总难度
                        CurrentBlock:    head, // 当前区块头
                        GenesisBlock:    genesis, // 创世区块
                })
        }()
        go func() {
                errc <- p.readStatus(network, &status, genesis) // 启动另一个goroutine读取状态
        }()
        timeout := time.NewTimer(handshakeTimeout) // 创建一个超时定时器
        defer timeout.Stop() // 确保在函数结束时停止定时器
        // 如果接收到任何一个错误(发送，接收),或者是超时， 那么就断开连接。
        for i := 0; i < 2; i++ { // 等待两个goroutine的结果
                select {
                case err := <-errc: // 从错误通道接收错误
                        if err != nil {
                                return err // 如果有错误，返回错误
                        }
                case <-timeout.C: // 如果超时
                        return p2p.DiscReadTimeout // 返回超时错误
                }
        }
        p.td, p.head = status.TD, status.CurrentBlock // 更新对等节点的总难度和当前区块头
        return nil // 返回nil表示握手成功
}
timeout.C：
timeout.C 是 time.Timer 的一个字段，类型为 <-chan time.Time，表示一个只读的通道。
当定时器到期时，timeout.C 会接收到一个 time.Time 类型的值，表示定时器的到期时间。
使用场景：
在并发编程中，timeout.C 通常用于实现超时机制。例如，在等待某个操作完成时，可以使用 select 语句来同时等待操作的结果和定时器的到期。
如果操作在指定时间内完成，处理结果；如果超时，则执行超时处理逻辑
```

readStatus，检查对端返回的各种情况，

```go
func (p *peer) readStatus(network uint64, status *statusData, genesis common.Hash) (err error) {
        msg, err := p.rw.ReadMsg() // 从对等节点的读写器中读取消息
        if err != nil {
                return err // 如果读取消息出错，返回错误
        }
        if msg.Code != StatusMsg {
                return errResp(ErrNoStatusMsg, "first msg has code %x (!= %x)", msg.Code, StatusMsg) // 如果消息代码不是状态消息，返回错误
        }
        if msg.Size > ProtocolMaxMsgSize {
                return errResp(ErrMsgTooLarge, "%v > %v", msg.Size, ProtocolMaxMsgSize) // 如果消息大小超过最大限制，返回错误
        }
        // Decode the handshake and make sure everything matches
        if err := msg.Decode(&status); err != nil {
                return errResp(ErrDecode, "msg %v: %v", msg, err) // 解码消息失败，返回错误
        }
        if status.GenesisBlock != genesis {
                return errResp(ErrGenesisBlockMismatch, "%x (!= %x)", status.GenesisBlock[:8], genesis[:8]) // 验证创世区块是否匹配
        }
        if status.NetworkId != network {
                return errResp(ErrNetworkIdMismatch, "%d (!= %d)", status.NetworkId, network) // 验证网络ID是否匹配
        }
        if int(status.ProtocolVersion) != p.version {
                return errResp(ErrProtocolVersionMismatch, "%d (!= %d)", status.ProtocolVersion, p.version) // 验证协议版本是否匹配
        }
        return nil // 返回nil表示成功
}

```

Register 简单的把 peer 加入到自己的 peers 的 map

```go
// Register injects a new peer into the working set, or returns an error if the
// peer is already known.
func (ps *peerSet) Register(p *peer) error {
        ps.lock.Lock() // 加锁以确保线程安全
        defer ps.lock.Unlock() // 确保在函数结束时解锁

        if ps.closed {
                return errClosed // 如果对等节点集合已关闭，返回错误
        }
        if _, ok := ps.peers[p.id]; ok {
                return errAlreadyRegistered // 如果该peer已经注册，返回错误
        }
        ps.peers[p.id] = p // 将peer注册到集合中
        return nil // 返回nil表示注册成功
}

```

经过一系列的检查和握手之后， 循环的调用了 handleMsg 方法来处理事件循环。 这个方法很长，主要是处理接收到各种消息之后的应对措施。

```go
// handleMsg is invoked whenever an inbound message is received from a remote
// peer. The remote connection is turn down upon returning any error.
func (pm *ProtocolManager) handleMsg(p *peer) error {
        // Read the next message from the remote peer, and ensure it's fully consumed
        msg, err := p.rw.ReadMsg()
        if err != nil {
                return err
        }
        if msg.Size > ProtocolMaxMsgSize {
                return errResp(ErrMsgTooLarge, "%v > %v", msg.Size, ProtocolMaxMsgSize)
        }
        defer msg.Discard()

        // Handle the message depending on its contents
        switch {
        case msg.Code == StatusMsg:
                // Status messages should never arrive after the handshake
                // StatusMsg应该在HandleShake阶段接收到。 经过了HandleShake之后是不应该接收到这种消息的。
                return errResp(ErrExtraStatusMsg, "uncontrolled status message")

        // Block header query, collect the requested headers and reply
        // 接收到请求区块头的消息， 会根据请求返回区块头信息。
        case msg.Code == GetBlockHeadersMsg:
                // Decode the complex header query
                var query getBlockHeadersData
                if err := msg.Decode(&query); err != nil {
                        return errResp(ErrDecode, "%v: %v", msg, err)
                }
                hashMode := query.Origin.Hash != (common.Hash{})

                // Gather headers until the fetch or network limits is reached
                var (
                        bytes   common.StorageSize
                        headers []*types.Header
                        unknown bool
                )
                for !unknown && len(headers) < int(query.Amount) && bytes < softResponseLimit && len(headers) < downloader.MaxHeaderFetch {
                        // Retrieve the next header satisfying the query
                        var origin *types.Header
                        if hashMode {
                                origin = pm.blockchain.GetHeaderByHash(query.Origin.Hash)
                        } else {
                                origin = pm.blockchain.GetHeaderByNumber(query.Origin.Number)
                        }
                        if origin == nil {
                                break
                        }
                        number := origin.Number.Uint64()
                        headers = append(headers, origin)
                        bytes += estHeaderRlpSize

                        // Advance to the next header of the query
                        switch {
                        case query.Origin.Hash != (common.Hash{}) && query.Reverse:
                                // Hash based traversal towards the genesis block
                                // 从Hash指定的开始朝创世区块移动。 也就是反向移动。  通过hash查找
                                for i := 0; i < int(query.Skip)+1; i++ {
                                        if header := pm.blockchain.GetHeader(query.Origin.Hash, number); header != nil {// 通过hash和number获取前一个区块头
                                        
                                                query.Origin.Hash = header.ParentHash
                                                number--
                                        } else {
                                                unknown = true
                                                break //break是跳出switch。 unknow用来跳出循环。
                                        }
                                }
                        case query.Origin.Hash != (common.Hash{}) && !query.Reverse:
                                // Hash based traversal towards the leaf block
                                // 通过hash来查找
                                var (
                                        current = origin.Number.Uint64()
                                        next    = current + query.Skip + 1
                                )
                                if next <= current { //正向， 但是next比当前还小，防备整数溢出攻击。
                                        infos, _ := json.MarshalIndent(p.Peer.Info(), "", "  ")
                                        p.Log().Warn("GetBlockHeaders skip overflow attack", "current", current, "skip", query.Skip, "next", next, "attacker", infos)
                                        unknown = true
                                } else {
                                        if header := pm.blockchain.GetHeaderByNumber(next); header != nil {
                                                if pm.blockchain.GetBlockHashesFromHash(header.Hash(), query.Skip+1)[query.Skip] == query.Origin.Hash {
                                                        // 如果可以找到这个header，而且这个header和origin在同一个链上。
                                                        query.Origin.Hash = header.Hash()
                                                } else {
                                                        unknown = true
                                                }
                                        } else {
                                                unknown = true
                                        }
                                }
                        case query.Reverse:                // 通过number查找
                                // Number based traversal towards the genesis block
                                //  query.Origin.Hash == (common.Hash{}) 
                                if query.Origin.Number >= query.Skip+1 {
                                        query.Origin.Number -= (query.Skip + 1)
                                } else {
                                        unknown = true
                                }

                        case !query.Reverse:         //通过number查找
                                // Number based traversal towards the leaf block
                                query.Origin.Number += (query.Skip + 1)
                        }
                }
                return p.SendBlockHeaders(headers)

        case msg.Code == BlockHeadersMsg: //接收到了GetBlockHeadersMsg的回答。
                // A batch of headers arrived to one of our previous requests
                var headers []*types.Header
                if err := msg.Decode(&headers); err != nil {
                        return errResp(ErrDecode, "msg %v: %v", msg, err)
                }
                // If no headers were received, but we're expending a DAO fork check, maybe it's that
                // 如果对端没有返回任何的headers,而且forkDrop不为空，那么应该是我们的DAO检查的请求，我们之前在HandShake发送了DAO header的请求。
                if len(headers) == 0 && p.forkDrop != nil {
                        // Possibly an empty reply to the fork header checks, sanity check TDs
                        verifyDAO := true

                        // If we already have a DAO header, we can check the peer's TD against it. If
                        // the peer's ahead of this, it too must have a reply to the DAO check
                        if daoHeader := pm.blockchain.GetHeaderByNumber(pm.chainconfig.DAOForkBlock.Uint64()); daoHeader != nil {
                                if _, td := p.Head(); td.Cmp(pm.blockchain.GetTd(daoHeader.Hash(), daoHeader.Number.Uint64())) >= 0 {
                                        //这个时候检查对端的total difficult 是否已经超过了DAO分叉区块的td值， 如果超过了，说明对端应该存在这个区块头， 但是返回的空白的，那么这里验证失败。 这里什么都没有做。 如果对端还不发送，那么会被超时退出。
                                        verifyDAO = false
                                }
                        }
                        // If we're seemingly on the same chain, disable the drop timer
                        if verifyDAO { // 如果验证成功，那么删除掉计时器，然后返回。
                                p.Log().Debug("Seems to be on the same side of the DAO fork")
                                p.forkDrop.Stop()
                                p.forkDrop = nil
                                return nil
                        }
                }
                // Filter out any explicitly requested headers, deliver the rest to the downloader
                // 过滤出任何非常明确的请求， 然后把剩下的投递给downloader
                // 如果长度是1 那么filter为true
                filter := len(headers) == 1
                if filter {
                        // If it's a potential DAO fork check, validate against the rules
                        if p.forkDrop != nil && pm.chainconfig.DAOForkBlock.Cmp(headers[0].Number) == 0 {  //DAO检查
                                // Disable the fork drop timer
                                p.forkDrop.Stop()
                                p.forkDrop = nil

                                // Validate the header and either drop the peer or continue
                                if err := misc.VerifyDAOHeaderExtraData(pm.chainconfig, headers[0]); err != nil {
                                        p.Log().Debug("Verified to be on the other side of the DAO fork, dropping")
                                        return err
                                }
                                p.Log().Debug("Verified to be on the same side of the DAO fork")
                                return nil
                        }
                        // Irrelevant of the fork checks, send the header to the fetcher just in case
                        // 如果不是DAO的请求，交给过滤器进行过滤。过滤器会返回需要继续处理的headers，这些headers会被交给downloader进行分发。
                        headers = pm.fetcher.FilterHeaders(p.id, headers, time.Now())
                }
                if len(headers) > 0 || !filter {
                        err := pm.downloader.DeliverHeaders(p.id, headers)
                        if err != nil {
                                log.Debug("Failed to deliver headers", "err", err)
                        }
                }

        case msg.Code == GetBlockBodiesMsg:
                //  Block Body的请求 这个比较简单。 从blockchain里面获取body返回就行。
                // Decode the retrieval message
                msgStream := rlp.NewStream(msg.Payload, uint64(msg.Size))
                if _, err := msgStream.List(); err != nil {
                        return err
                }
                // Gather blocks until the fetch or network limits is reached
                var (
                        hash   common.Hash
                        bytes  int
                        bodies []rlp.RawValue
                )
                for bytes < softResponseLimit && len(bodies) < downloader.MaxBlockFetch {
                        // Retrieve the hash of the next block
                        if err := msgStream.Decode(&hash); err == rlp.EOL {
                                break
                        } else if err != nil {
                                return errResp(ErrDecode, "msg %v: %v", msg, err)
                        }
                        // Retrieve the requested block body, stopping if enough was found
                        if data := pm.blockchain.GetBodyRLP(hash); len(data) != 0 {
                                bodies = append(bodies, data)
                                bytes += len(data)
                        }
                }
                return p.SendBlockBodiesRLP(bodies)

        case msg.Code == BlockBodiesMsg:
                // A batch of block bodies arrived to one of our previous requests
                var request blockBodiesData
                if err := msg.Decode(&request); err != nil {
                        return errResp(ErrDecode, "msg %v: %v", msg, err)
                }
                // Deliver them all to the downloader for queuing
                trasactions := make([][]*types.Transaction, len(request))
                uncles := make([][]*types.Header, len(request))

                for i, body := range request {
                        trasactions[i] = body.Transactions
                        uncles[i] = body.Uncles
                }
                // Filter out any explicitly requested bodies, deliver the rest to the downloader
                // 过滤掉任何显示的请求， 剩下的交给downloader
                filter := len(trasactions) > 0 || len(uncles) > 0
                if filter {
                        trasactions, uncles = pm.fetcher.FilterBodies(p.id, trasactions, uncles, time.Now())
                }
                if len(trasactions) > 0 || len(uncles) > 0 || !filter {
                        err := pm.downloader.DeliverBodies(p.id, trasactions, uncles)
                        if err != nil {
                                log.Debug("Failed to deliver bodies", "err", err)
                        }
                }

        case p.version >= eth63 && msg.Code == GetNodeDataMsg:
                // 对端的版本是eth63 而且是请求NodeData
                // Decode the retrieval message
                msgStream := rlp.NewStream(msg.Payload, uint64(msg.Size))
                if _, err := msgStream.List(); err != nil {
                        return err
                }
                // Gather state data until the fetch or network limits is reached
                var (
                        hash  common.Hash
                        bytes int
                        data  [][]byte
                )
                for bytes < softResponseLimit && len(data) < downloader.MaxStateFetch {
                        // Retrieve the hash of the next state entry
                        if err := msgStream.Decode(&hash); err == rlp.EOL {
                                break
                        } else if err != nil {
                                return errResp(ErrDecode, "msg %v: %v", msg, err)
                        }
                        // Retrieve the requested state entry, stopping if enough was found
                        // 请求的任何hash值都会返回给对方。 
                        if entry, err := pm.chaindb.Get(hash.Bytes()); err == nil {
                                data = append(data, entry)
                                bytes += len(entry)
                        }
                }
                return p.SendNodeData(data)

        case p.version >= eth63 && msg.Code == NodeDataMsg:
                // A batch of node state data arrived to one of our previous requests
                var data [][]byte
                if err := msg.Decode(&data); err != nil {
                        return errResp(ErrDecode, "msg %v: %v", msg, err)
                }
                // Deliver all to the downloader
                // 数据交给downloader
                if err := pm.downloader.DeliverNodeData(p.id, data); err != nil {
                        log.Debug("Failed to deliver node state data", "err", err)
                }

        case p.version >= eth63 && msg.Code == GetReceiptsMsg:
                // 请求收据
                // Decode the retrieval message
                msgStream := rlp.NewStream(msg.Payload, uint64(msg.Size))
                if _, err := msgStream.List(); err != nil {
                        return err
                }
                // Gather state data until the fetch or network limits is reached
                var (
                        hash     common.Hash
                        bytes    int
                        receipts []rlp.RawValue
                )
                for bytes < softResponseLimit && len(receipts) < downloader.MaxReceiptFetch {
                        // Retrieve the hash of the next block
                        if err := msgStream.Decode(&hash); err == rlp.EOL {
                                break
                        } else if err != nil {
                                return errResp(ErrDecode, "msg %v: %v", msg, err)
                        }
                        // Retrieve the requested block's receipts, skipping if unknown to us
                        results := core.GetBlockReceipts(pm.chaindb, hash, core.GetBlockNumber(pm.chaindb, hash))
                        if results == nil {
                                if header := pm.blockchain.GetHeaderByHash(hash); header == nil || header.ReceiptHash != types.EmptyRootHash {
                                        continue
                                }
                        }
                        // If known, encode and queue for response packet
                        if encoded, err := rlp.EncodeToBytes(results); err != nil {
                                log.Error("Failed to encode receipt", "err", err)
                        } else {
                                receipts = append(receipts, encoded)
                                bytes += len(encoded)
                        }
                }
                return p.SendReceiptsRLP(receipts)

        case p.version >= eth63 && msg.Code == ReceiptsMsg:
                // A batch of receipts arrived to one of our previous requests
                var receipts [][]*types.Receipt
                if err := msg.Decode(&receipts); err != nil {
                        return errResp(ErrDecode, "msg %v: %v", msg, err)
                }
                // Deliver all to the downloader
                if err := pm.downloader.DeliverReceipts(p.id, receipts); err != nil {
                        log.Debug("Failed to deliver receipts", "err", err)
                }

        case msg.Code == NewBlockHashesMsg:
                // 接收到BlockHashesMsg消息
                var announces newBlockHashesData
                if err := msg.Decode(&announces); err != nil {
                        return errResp(ErrDecode, "%v: %v", msg, err)
                }
                // Mark the hashes as present at the remote node
                for _, block := range announces {
                        p.MarkBlock(block.Hash)
                }
                // Schedule all the unknown hashes for retrieval
                unknown := make(newBlockHashesData, 0, len(announces))
                for _, block := range announces {
                        if !pm.blockchain.HasBlock(block.Hash, block.Number) {
                                unknown = append(unknown, block)
                        }
                }
                for _, block := range unknown {
                        // 通知fetcher有一个潜在的block需要下载
                        pm.fetcher.Notify(p.id, block.Hash, block.Number, time.Now(), p.RequestOneHeader, p.RequestBodies)
                }

        case msg.Code == NewBlockMsg:
                // Retrieve and decode the propagated block
                var request newBlockData
                if err := msg.Decode(&request); err != nil {
                        return errResp(ErrDecode, "%v: %v", msg, err)
                }
                request.Block.ReceivedAt = msg.ReceivedAt
                request.Block.ReceivedFrom = p

                // Mark the peer as owning the block and schedule it for import
                p.MarkBlock(request.Block.Hash())
                pm.fetcher.Enqueue(p.id, request.Block)

                // Assuming the block is importable by the peer, but possibly not yet done so,
                // calculate the head hash and TD that the peer truly must have.
                var (
                        trueHead = request.Block.ParentHash()
                        trueTD   = new(big.Int).Sub(request.TD, request.Block.Difficulty())
                )
                // Update the peers total difficulty if better than the previous
                if _, td := p.Head(); trueTD.Cmp(td) > 0 {
                        // 如果peer的真实的TD和head和我们这边记载的不同， 设置peer真实的head和td，
                        p.SetHead(trueHead, trueTD)

                        // Schedule a sync if above ours. Note, this will not fire a sync for a gap of
                        // a singe block (as the true TD is below the propagated block), however this
                        // scenario should easily be covered by the fetcher.
                        // 如果真实的TD比我们的TD大，那么请求和这个peer同步。
                        currentBlock := pm.blockchain.CurrentBlock()
                        if trueTD.Cmp(pm.blockchain.GetTd(currentBlock.Hash(), currentBlock.NumberU64())) > 0 {
                                go pm.synchronise(p)
                        }
                }

        case msg.Code == TxMsg:
                // Transactions arrived, make sure we have a valid and fresh chain to handle them
                // 交易信息返回。 在我们没用同步完成之前不会接收交易信息。
                if atomic.LoadUint32(&pm.acceptTxs) == 0 {
                        break
                }
                // Transactions can be processed, parse all of them and deliver to the pool
                var txs []*types.Transaction
                if err := msg.Decode(&txs); err != nil {
                        return errResp(ErrDecode, "msg %v: %v", msg, err)
                }
                for i, tx := range txs {
                        // Validate and mark the remote transaction
                        if tx == nil {
                                return errResp(ErrDecode, "transaction %d is nil", i)
                        }
                        p.MarkTransaction(tx.Hash())
                }
                // 添加到txpool
                pm.txpool.AddRemotes(txs)

        default:
                return errResp(ErrInvalidMsgCode, "%v", msg.Code)
        }
        return nil
}
```

几种同步 synchronise, 之前发现对方的节点 比自己节点要更新的时候会调用这个方法 synchronise，

```go
// synchronise tries to sync up our local block chain with a remote peer.
// synchronise 尝试 让本地区块链跟远端同步。
func (pm *ProtocolManager) synchronise(peer *peer) {
        // Short circuit if no peers are available
        if peer == nil {
                return // 如果没有可用的对等节点，直接返回
        }
        // Make sure the peer's TD is higher than our own
        currentBlock := pm.blockchain.CurrentBlock() // 获取当前区块
        td := pm.blockchain.GetTd(currentBlock.Hash(), currentBlock.NumberU64()) // 获取当前区块的总难度

        pHead, pTd := peer.Head() // 获取对等节点的区块头和总难度
        if pTd.Cmp(td) <= 0 {
                return // 如果对等节点的总难度不高于本地的，直接返回
        }
        // Otherwise try to sync with the downloader
        mode := downloader.FullSync // 默认同步模式为完整同步
        if atomic.LoadUint32(&pm.fastSync) == 1 { // 如果显式声明为快速同步
                // Fast sync was explicitly requested, and explicitly granted
                mode = downloader.FastSync // 设置为快速同步模式
        } else if currentBlock.NumberU64() == 0 && pm.blockchain.CurrentFastBlock().NumberU64() > 0 { // 如果数据库是空白的
                // 数据库似乎是空的，因为当前区块是创世区块。然而快速区块在前面，因此在某个时刻为该节点启用了快速同步。
                // 这种情况通常发生在用户手动（或通过坏区块）将快速同步节点回滚到同步点以下。在这种情况下，重新启用快速同步是安全的。
                atomic.StoreUint32(&pm.fastSync, 1) // 启用快速同步
                mode = downloader.FastSync // 设置为快速同步模式
        }
        // Run the sync cycle, and disable fast sync if we've went past the pivot block
        err := pm.downloader.Synchronise(peer.id, pHead, pTd, mode) // 执行同步过程

        if atomic.LoadUint32(&pm.fastSync) == 1 {
                // Disable fast sync if we indeed have something in our chain
                if pm.blockchain.CurrentBlock().NumberU64() > 0 {
                        log.Info("Fast sync complete, auto disabling") // 记录快速同步完成的信息
                        atomic.StoreUint32(&pm.fastSync, 0) // 禁用快速同步
                }
        }
        if err != nil {
                return // 如果同步过程中出现错误，直接返回
        }
        atomic.StoreUint32(&pm.acceptTxs, 1) // 标记初始同步完成
        // 同步完成 开始接收交易。
        if head := pm.blockchain.CurrentBlock(); head.NumberU64() > 0 {
                // 我们已完成同步周期，通知所有对等节点新的状态。这条路径在星型拓扑网络中至关重要，网关节点需要通知所有过时的对等节点新块的可用性。
                // 这种失败场景通常会出现在私有和黑客马拉松网络中，但对于主网来说，可靠地更新对等节点或本地总难度状态也是健康的。
                // 我们告诉所有的peer我们的状态。
                go pm.BroadcastBlock(head, false) // 启动一个goroutine广播当前区块
        }
}

```

交易广播。txBroadcastLoop 在 start 的时候启动的 goroutine。 txCh 在 txpool 接收到一条合法的交易的时候会往这个上面写入事件。 然后把交易广播给所有的 peers

```go
func (self *ProtocolManager) txBroadcastLoop() {
        for {
                select {
                case event := <-self.txCh: // 从交易事件通道接收事件
                        self.BroadcastTx(event.Tx.Hash(), event.Tx) // 广播接收到的交易

                // Err() channel will be closed when unsubscribing.
                case <-self.txSub.Err(): // 监听订阅的错误通道
                        return // 如果错误通道关闭，退出循环
                }
        }
}

```

挖矿广播。当收到订阅的事件的时候把新挖到的矿广播出去。

```go
// Mined broadcast loop
func (self *ProtocolManager) minedBroadcastLoop() {
        // automatically stops if unsubscribe
        for obj := range self.minedBlockSub.Chan() { // 从已订阅的通道中接收新挖掘的区块事件
                switch ev := obj.Data.(type) {
                case core.NewMinedBlockEvent: // 检查接收到的事件类型
                        self.BroadcastBlock(ev.Block, true)  // 首先将区块广播给对等节点
                        self.BroadcastBlock(ev.Block, false) // 然后再向其他节点宣布
                }
        }
}

```

syncer 负责定期和网络同步

```go
// syncer is responsible for periodically synchronising with the network, both
// downloading hashes and blocks as well as handling the announcement handler.
//同步器负责周期性地与网络同步，下载散列和块以及处理通知处理程序。
func (pm *ProtocolManager) syncer() {
        // Start and ensure cleanup of sync mechanisms
        pm.fetcher.Start() // 启动数据获取器
        defer pm.fetcher.Stop() // 确保在函数结束时停止数据获取器
        defer pm.downloader.Terminate() // 确保在函数结束时终止下载器

        // Wait for different events to fire synchronisation operations
        forceSync := time.NewTicker(forceSyncCycle) // 创建一个定时器，周期性触发同步操作
        defer forceSync.Stop() // 确保在函数结束时停止定时器

        for {
                select {
                case <-pm.newPeerCh: // 当有新的Peer增加的时候，会同步
                        // Make sure we have peers to select from, then sync
                        if pm.peers.Len() < minDesiredPeerCount { // 检查当前对等节点数量是否达到最小要求
                                break // 如果对等节点数量不足，跳出当前循环
                        }
                        go pm.synchronise(pm.peers.BestPeer()) // 启动一个goroutine与最佳对等节点同步

                case <-forceSync.C: // 定时触发
                        // Force a sync even if not enough peers are present
                        // BestPeer() 选择总难度最大的节点。
                        go pm.synchronise(pm.peers.BestPeer()) // 启动一个goroutine与最佳对等节点同步

                case <-pm.noMorePeers: // 退出信号
                        return // 退出函数
                }
        }
}

```

txsyncLoop 负责把 pending 的交易发送给新建立的连接。

```go
// txsyncLoop takes care of the initial transaction sync for each new
// connection. When a new peer appears, we relay all currently pending
// transactions. In order to minimise egress bandwidth usage, we send
// the transactions in small packs to one peer at a time.

func (pm *ProtocolManager) txsyncLoop() {
        var (
                pending = make(map[discover.NodeID]*txsync) // 存储待处理的事务同步
                sending = false               // 是否正在发送事务
                pack    = new(txsync)         // 正在发送的事务包
                done    = make(chan error, 1) // 发送结果的通道
        )

        // send starts a sending a pack of transactions from the sync.
        send := func(s *txsync) {
                // Fill pack with transactions up to the target size.
                size := common.StorageSize(0) // 初始化包的大小
                pack.p = s.p // 设置包的对等节点
                pack.txs = pack.txs[:0] // 清空包中的事务
                for i := 0; i < len(s.txs) && size < txsyncPackSize; i++ {
                        pack.txs = append(pack.txs, s.txs[i]) // 将事务添加到包中
                        size += s.txs[i].Size() // 更新包的大小
                }
                // Remove the transactions that will be sent.
                s.txs = s.txs[:copy(s.txs, s.txs[len(pack.txs):])] // 从待处理事务中移除已发送的事务
                if len(s.txs) == 0 {
                        delete(pending, s.p.ID()) // 如果没有待处理事务，删除该对等节点
                }
                // Send the pack in the background.
                s.p.Log().Trace("Sending batch of transactions", "count", len(pack.txs), "bytes", size) // 记录发送的事务信息
                sending = true // 标记为正在发送
                go func() { done <- pack.p.SendTransactions(pack.txs) }() // 在后台发送事务
        }

        // pick chooses the next pending sync.
        // 随机挑选一个txsync来发送。
        pick := func() *txsync {
                if len(pending) == 0 {
                        return nil // 如果没有待处理事务，返回nil
                }
                n := rand.Intn(len(pending)) + 1 // 随机选择一个待处理事务
                for _, s := range pending {
                        if n--; n == 0 {
                                return s // 返回选中的事务
                        }
                }
                return nil
        }

        for {
                select {
                case s := <-pm.txsyncCh: // 从txsyncCh接收消息
                        pending[s.p.ID()] = s // 将接收到的事务添加到待处理列表
                        if !sending { // 如果当前没有正在发送的事务
                                send(s) // 发送该事务
                        }
                case err := <-done: // 接收发送结果
                        sending = false // 标记为未发送
                        // Stop tracking peers that cause send failures.
                        if err != nil {
                                pack.p.Log().Debug("Transaction send failed", "err", err) // 记录发送失败的错误信息
                                delete(pending, pack.p.ID()) // 删除发送失败的对等节点
                        }
                        // Schedule the next send.
                        if s := pick(); s != nil { // 随机选择下一个待处理事务
                                send(s) // 发送该事务
                        }
                case <-pm.quitSync: // 接收到退出信号
                        return // 退出函数
                }
        }
}

```

txsyncCh 队列的生产者，syncTransactions 是在 handle 方法里面调用的。 在新链接刚刚创建的时候会被调用一次。

```go
// syncTransactions starts sending all currently pending transactions to the given peer.
func (pm *ProtocolManager) syncTransactions(p *peer) {
        var txs types.Transactions      // 声明一个事务切片
        pending, _ := pm.txpool.Pending() // 获取当前待处理的事务

        for _, batch := range pending { // 遍历待处理的事务批次
                txs = append(txs, batch...) // 将每个批次的事务添加到txs切片中
        }
        if len(txs) == 0 { // 如果没有待处理的事务
                return // 直接返回
        }
        select {
        case pm.txsyncCh <- &txsync{p, txs}: // 将事务同步请求发送到txsyncCh通道
        case <-pm.quitSync: // 监听退出信号
        }
}

```

总结一下。 我们现在的一些大的流程。

区块同步

1. 如果是自己挖的矿。通过 goroutine minedBroadcastLoop()来进行广播。
2. 如果是接收到其他人的区块广播，(NewBlockHashesMsg/NewBlockMsg),是否 fetcher 会通知的 peer？ TODO
3. goroutine syncer()中会定时的同 BestPeer()来同步信息。

交易同步

1. 新建立连接。 把 pending 的交易发送给他。
2. 本地发送了一个交易，或者是接收到别人发来的交易信息。 txpool 会产生一条消息，消息被传递到 txCh 通道。 然后被 goroutine txBroadcastLoop()处理， 发送给其他不知道这个交易的 peer。
