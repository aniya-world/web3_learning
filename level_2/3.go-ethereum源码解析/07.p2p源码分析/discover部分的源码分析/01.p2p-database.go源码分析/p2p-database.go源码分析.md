p2p 包实现了通用的 p2p 网络协议。包括节点的查找，节点状态的维护，节点连接的建立等 p2p 的功能。p2p 包实现的是通用的 p2p 协议。 某一种具体的协议(比如 eth 协议。 whisper 协议。 swarm 协议)被封装成特定的接口注入 p2p 包。所以 p2p 内部不包含具体协议的实现。 只完成了 p2p 网络应该做的事情。

## **discover / discv5 节点发现**

目前使用的包是 discover。 discv5 是最近才开发的功能，还是属于实验性质，基本上是 discover 包的一些优化。 这里我们暂时只分析 discover 的代码。 对其完成的功能做一个基本的介绍。

### **database.go**

顾名思义，这个文件内部主要实现了节点的持久化，因为 p2p 网络节点的节点发现和维护都是比较花时间的，为了反复启动的时候，能够把之前的工作继承下来，避免每次都重新发现。 所以持久化的工作是必须的。

之前我们分析了 ethdb 的代码和 trie 的代码，trie 的持久化工作使用了 leveldb。 这里同样也使用了 leveldb。 不过 p2p 的 leveldb 实例和主要的区块链的 leveldb 实例不是同一个。

newNodeDB,根据参数 path 来看打开基于内存的数据库，还是基于文件的数据库。

```go
// newNodeDB creates a new node database for storing and retrieving infos about
// known peers in the network. If no path is given, an in-memory, temporary
// database is constructed.

//功能：根据提供的路径创建一个新的节点数据库。
// version：数据库的版本号。
// self：当前节点的标识符
func newNodeDB(path string, version int, self NodeID) (*nodeDB, error) {
        // 如果路径为空，则创建一个内存数据库；否则，创建一个持久化数据库。
        if path == "" {
                return newMemoryNodeDB(self)
        }
        return newPersistentNodeDB(path, version, self) 
}
// newMemoryNodeDB creates a new in-memory node database without a persistent
// backend.
一个新的内存节点数据库  不用持久化后端

func newMemoryNodeDB(self NodeID) (*nodeDB, error) {
        db, err := leveldb.Open(storage.NewMemStorage(), nil)
        if err != nil {
                return nil, err
        }
        return &nodeDB{   // 返回一个指向 nodeDB 的指针和可能的错误信息
                lvl:  db,
                self: self,
                quit: make(chan struct{}),
        }, nil
}

// newPersistentNodeDB creates/opens a leveldb backed persistent node database,
// also flushing its contents in case of a version mismatch.
创建或打开一个基于 LevelDB 的持久化节点数据库，并在版本不匹配时刷新其内容
func newPersistentNodeDB(path string, version int, self NodeID) (*nodeDB, error) {
        设置 LevelDB 的选项，指定打开文件的缓存容量
        opts := &opt.Options{OpenFilesCacheCapacity: 5}
        db, err := leveldb.OpenFile(path, opts)
        尝试打开指定路径的数据库文件。如果数据库损坏，尝试恢复
        if _, iscorrupted := err.(*errors.ErrCorrupted); iscorrupted {
                db, err = leveldb.RecoverFile(path, nil)
        }
        if err != nil {
                return nil, err
        }
        // The nodes contained in the cache correspond to a certain protocol version.
        // Flush all nodes if the version doesn't match.
        currentVer := make([]byte, binary.MaxVarintLen64)
        currentVer = currentVer[:binary.PutVarint(currentVer, int64(version))]
        blob, err := db.Get(nodeDBVersionKey, nil)
        switch err {
        case leveldb.ErrNotFound:
                // Version not found (i.e. empty cache), insert it
                如果版本不存在（即数据库为空），则插入当前版本
                if err := db.Put(nodeDBVersionKey, currentVer, nil); err != nil {
                        db.Close()
                        return nil, err
                }
        case nil:
                // Version present, flush if different
                //版本不同，先删除所有的数据库文件，重新创建一个。
                如果版本存在且与当前版本不同，则关闭数据库，删除所有文件，并重新创建数据库
                if !bytes.Equal(blob, currentVer) {
                        db.Close()
                        if err = os.RemoveAll(path); err != nil {
                                return nil, err
                        }
                        return newPersistentNodeDB(path, version, self)
                }
        }
        return &nodeDB{
                lvl:  db,
                self: self,
                quit: make(chan struct{}),
        }, nil
}
```

Node 的存储，查询和删除

```go
// node retrieves a node with a given id from the database.
根据给定的节点 ID 从数据库中检索节点信息
func (db *nodeDB) node(id NodeID) *Node {
        blob, err := db.lvl.Get(makeKey(id, nodeDBDiscoverRoot), nil)
        使用 db.lvl.Get 方法从数据库中 获取 与节点 ID 相关的字节数据（blob）
        if err != nil {
                return nil
        }
        node := new(Node)
        创建一个新的 Node 实例，

        使用 rlp.DecodeBytes 方法将字节数据解码为节点对象 （返回结果是一个错误 正常不返回估计。）

                                        ；如果 err 不为 nil，表示解码过程中发生了错误
        if err := rlp.DecodeBytes(blob, node); err != nil {
                log.Error("Failed to decode node RLP", "err", err)
                return nil
        }
        node.sha = crypto.Keccak256Hash(node.ID[:])
        计算节点的 SHA 哈希值并赋值给 node.sha
        return node
        返回对应的 Node 对象
}

// updateNode inserts - potentially overwriting - a node into the peer database.
func (db *nodeDB) updateNode(node *Node) error {
        blob, err := rlp.EncodeToBytes(node)
        if err != nil {
                return err
        }

        makeKey 函数通常用于生成数据库中存储项的键
        将节点 ID 和其他参数（如 nodeDBDiscoverRoot）组合成一个唯一的键，以便在数据库中进行存储和检索
        nodeDBDiscoverRoot 是一个标识符，用于在数据库中组织和分类节点数据
        return db.lvl.Put(makeKey(node.ID, nodeDBDiscoverRoot), blob, nil)

功能：将节点信息插入到数据库中，可能会覆盖已有的节点信息。
实现：
使用 rlp.EncodeToBytes 方法将节点对象编码为字节数据（blob）。
如果编码失败，返回错误。
使用 db.lvl.Put 方法将 字节数据存储到数据库中，键由节点 ID 生成。
返回值：返回可能的错误信息。
}


// deleteNode deletes all information/keys associated with a node.
功能：删除与给定节点 ID 相关的所有信息和键。
func (db *nodeDB) deleteNode(id NodeID) error {
        实现：
        创建一个迭代器 deleter，用于遍历以节点 ID 为前缀的所有键。
        deleter := db.lvl.NewIterator(util.BytesPrefix(makeKey(id, "")), nil)

        使用 deleter.Next() 方法逐个遍历所有相关的键。
        for deleter.Next() {
                对于每个键，使用 db.lvl.Delete 方法将其从数据库中删除。如果删除失败，返回错误。
                if err := db.lvl.Delete(deleter.Key(), nil); err != nil {
                        return err
                }
        }
        return nil

}
```

Node 的结构


```go
type Node struct {
        IP       net.IP // len 4 for IPv4 or 16 for IPv6
        UDP, TCP uint16 // port numbers
        ID       NodeID // the node's public key 节点的公共密钥，通常用于身份验证和安全通信。NodeID 可能是一个自定义类型，表示节点的唯一标识符。
        // This is a cached copy of sha3(ID) which is used for node
        // distance calculations. This is part of Node in order to make it
        // possible to write tests that need a node at a certain distance.
        // In those tests, the content of sha will not actually correspond
        // with ID.

        sha common.Hash
        存储节点 ID 的 SHA3 哈希值。这个哈希值用于节点之间的距离计算，以便在网络中找到相似或相邻的节点。这个字段的存在使得在测试中可以创建特定距离的节点，而不需要实际对应的 ID。
        // whether this node is currently being pinged in order to replace
        // it in a bucket
        contested bool
}
```

节点超时处理

定义了一些方法，用于管理节点数据库中的数据过期机制

```go
// ensureExpirer is a small helper method ensuring that the data expiration
// mechanism is running. If the expiration goroutine is already running, this
// method simply returns.
// ensureExpirer方法用来确保expirer方法在运行。 如果expirer已经运行，那么这个方法就直接返回。
// 这个方法设置的目的是为了在网络成功启动后在开始进行数据超时丢弃的工作(以防一些潜在的有用的种子节点被丢弃)。
// The goal is to start the data evacuation only after the network successfully
// bootstrapped itself (to prevent dumping potentially useful seed nodes). Since
// it would require significant overhead to exactly trace the first successful
// convergence, it's simpler to "ensure" the correct state when an appropriate
// condition occurs (i.e. a successful bonding), and discard further events.
func (db *nodeDB) ensureExpirer() {
        // ensureExpirer（） 是一个辅助方法，确保数据过期机制正在运行。
        db.runner.Do(func() { go db.expirer() })
        //使用 db.runner.Do 方法启动 expirer 方法，确保它在一个新的 goroutine 中运行。
}

// expirer should be started in a go routine, and is responsible for looping ad
// infinitum and dropping stale data from the database.
expirer 方法在一个 goroutine 中循环运行，负责定期从数据库中删除过期的数据。
func (db *nodeDB) expirer() {
        定时器: 使用 time.Tick 创建一个定时器，按照 nodeDBCleanupCycle 的周期触发。
        tick := time.Tick(nodeDBCleanupCycle)
        for {
                select {
                case <-tick:
                        // 数据过期处理: 每当定时器触发时，调用 expireNodes 方法来删除过期节点。
                        if err := db.expireNodes(); err != nil {
                                log.Error("Failed to expire nodedb items", "err", err)
                        }
                退出条件: 如果接收到 db.quit 的信号，则退出循环
                case <-db.quit:
                        return
                }
        }
}

// expireNodes iterates over the database and deletes all nodes that have not
// been seen (i.e. received a pong from) for some allotted time.
//这个方法遍历所有的节点，如果某个节点最后接收消息超过指定值，那么就删除这个节点。
expireNodes 方法遍历数据库，删除所有在指定时间内未被看到（即未收到 pong 响应）的节点。
func (db *nodeDB) expireNodes() error {
        时间阈值: 计算一个时间阈值，表示节点的过期时间。
        threshold := time.Now().Add(-nodeDBNodeExpiration)

        // Find discovered nodes that are older than the allowance 迭代器: 使用迭代器遍历数据库中的节点。
        it := db.lvl.NewIterator(nil, nil)
        defer it.Release()

        使用迭代器遍历数据库中的节点
        for it.Next() {
                // Skip the item if not a discovery node 跳过非发现节点
                id, field := splitKey(it.Key())
                if field != nodeDBDiscoverRoot {
                        continue
                }
                // Skip the node if not expired yet (and not self) 检查节点是否过期，如果未过期则继续。
                if !bytes.Equal(id[:], db.self[:]) {
                        if seen := db.lastPong(id); seen.After(threshold) {
                                continue
                        }
                }
                // Otherwise delete all associated information 如果节点过期，则调用 deleteNode 方法删除该节点及其相关信息。
                db.deleteNode(id)
        }
        return nil
}

这段代码实现了一个有效的节点过期管理机制，确保在网络成功启动后，定期清理未活跃的节点。
通过 ensureExpirer、expirer 和 expireNodes 方法的协作，系统能够保持节点数据库的健康，避免存储过时或无用的节点信息。
```

一些状态更新函数

```go
// lastPing retrieves the time of the last ping packet send to a remote node,
// requesting binding.
func (db *nodeDB) lastPing(id NodeID) time.Time {
        return time.Unix(db.fetchInt64(makeKey(id, nodeDBDiscoverPing)), 0)
}

// updateLastPing updates the last time we tried contacting a remote node.
func (db *nodeDB) updateLastPing(id NodeID, instance time.Time) error {
        return db.storeInt64(makeKey(id, nodeDBDiscoverPing), instance.Unix())
}

// lastPong retrieves the time of the last successful contact from remote node.
func (db *nodeDB) lastPong(id NodeID) time.Time {
        return time.Unix(db.fetchInt64(makeKey(id, nodeDBDiscoverPong)), 0)
}

// updateLastPong updates the last time a remote node successfully contacted.
func (db *nodeDB) updateLastPong(id NodeID, instance time.Time) error {
        return db.storeInt64(makeKey(id, nodeDBDiscoverPong), instance.Unix())
}

// findFails retrieves the number of findnode failures since bonding.
func (db *nodeDB) findFails(id NodeID) int {
        return int(db.fetchInt64(makeKey(id, nodeDBDiscoverFindFails)))
}

// updateFindFails updates the number of findnode failures since bonding.
func (db *nodeDB) updateFindFails(id NodeID, fails int) error {
        return db.storeInt64(makeKey(id, nodeDBDiscoverFindFails), int64(fails))
}
```

从数据库里面随机挑选合适种子节点

这段代码实现了从节点数据库中检索随机节点的功能，主要用于引导（bootstrapping）过程中的种子节点选择。以下是对每个方法的详细介绍
```go
// querySeeds retrieves random nodes to be used as potential seed nodes
// for bootstrapping. 
// querySeeds 方法从数据库中随机检索节点，以用作潜在的种子节点
n int: 需要检索的节点数量 ； maxAge time.Duration: 节点的最大年龄，超过这个时间的节点将被排除
func (db *nodeDB) querySeeds(n int, maxAge time.Duration) []*Node {

        初始化: 创建一个空的节点切片 nodes，并初始化一个迭代器 it。
        var (
                now   = time.Now()
                nodes = make([]*Node, 0, n)
                it    = db.lvl.NewIterator(nil, nil)
                id    NodeID
        )
        defer it.Release()

seek:
        随机检索: 使用一个循环，最多尝试 n * 5 次来找到 n 个节点。
        for seeks := 0; len(nodes) < n && seeks < n*5; seeks++ {
                // Seek to a random entry. The first byte is incremented by a
                // random amount each time in order to increase the likelihood
                // of hitting all existing nodes in very small databases.
                ctr := id[0]
                rand.Read(id[:])
                id[0] = ctr + id[0]%16
                生成一个随机的 NodeID，并通过 it.Seek 定位到相应的节点。
                it.Seek(makeKey(id, nodeDBDiscoverRoot))

                调用 nextNode 方法读取下一个节点。
                n := nextNode(it)

                过滤条件:
                if n == nil {
                        id[0] = 0
                        continue seek // iterator exhausted
                }
                if n.ID == db.self {
                        continue seek 跳过自身节点（db.self）。
                }
                if now.Sub(db.lastPong(n.ID)) > maxAge { 检查节点的最后 pong 时间是否超过 maxAge。
                        continue seek
                }
                for i := range nodes {
                        if nodes[i].ID == n.ID {
                                continue seek // duplicate  确保没有重复节点。
                        }
                }
                nodes = append(nodes, n)  返回结果: 返回找到的节点切片。
        }
        return nodes
}

// reads the next node record from the iterator, skipping over other
// database entries.  从迭代器中读取下一个节点记录，跳过其他数据库条目。
func nextNode(it iterator.Iterator) *Node {
        使用循环遍历迭代器，直到没有更多条目。
        for end := false; !end; end = !it.Next() {
                id, field := splitKey(it.Key())
                通过 splitKey 方法检查当前条目的字段是否为 nodeDBDiscoverRoot，如果不是，则跳过
                if field != nodeDBDiscoverRoot {
                        continue
                }
                var n Node
                解码节点: 使用 RLP 解码当前条目的值为 Node 结构体。如果解码失败，记录警告并继续。
                if err := rlp.DecodeBytes(it.Value(), &n); err != nil {
                        log.Warn("Failed to decode node RLP", "id", id, "err", err)
                        continue
                }
                return &n 返回解码后的节点。
        } 
        return nil
}
```
