
vm 使用了 stack.go 里面的对象 Stack 来作为虚拟机的堆栈。memory 代表了虚拟机里面使用的内存对象。

## **stack**

比较简单，就是用 1024 个 big.Int 的定长数组来作为堆栈的存储。

构造

```go
// stack is an object for basic stack operations. Items popped to the stack are
// expected to be changed and modified. stack does not take care of adding newly
// initialised objects.
type Stack struct {
        data []*big.Int // 存储 big.Int 指针的切片
}

func newstack() *Stack {
        return &Stack{data: make([]*big.Int, 0, 1024)} // 初始化一个容量为1024的空切片，作为堆栈的存储
}
```

push 操作

```go
func (st *Stack) push(d *big.Int) { // 追加到切片的最末尾，即堆栈顶部
        st.data = append(st.data, d)
}
func (st *Stack) pushN(ds ...*big.Int) {
        st.data = append(st.data, ds...) // 接受可变参数，将多个元素追加到堆栈顶部
}
```

pop 操作

```go
func (st *Stack) pop() (ret *big.Int) { // 从切片的最末尾取出元素，然后缩小切片
        ret = st.data[len(st.data)-1]
        st.data = st.data[:len(st.data)-1]
        return
}

```

交换元素的值操作，还有这种操作？

```go
func (st *Stack) swap(n int) { 交换堆栈顶的元素和离栈顶n距离的元素的值。// 交换切片中倒数第一个和倒数第 n 个元素
        st.data[st.len()-n], st.data[st.len()-1] = st.data[st.len()-1], st.data[st.len()-n]
}
```

dup 操作 像复制指定位置的值到堆顶

```go
func (st *Stack) dup(pool *intPool, n int) {
        st.push(pool.get().Set(st.data[st.len()-n])) // 从 intPool 获取一个 big.Int，设置其值为指定位置的元素，然后推入堆栈
}
```

peek 操作. 偷看栈顶元素

```go
func (st *Stack) peek() *big.Int {
        return st.data[st.len()-1] // 返回切片的最后一个元素
}
```

Back 看指定位置的元素

```go
// Back returns the n'th item in stack
func (st *Stack) Back(n int) *big.Int {
        return st.data[st.len()-n-1] // 返回切片中倒数第 n+1 个元素
}
```

require 保证堆栈元素的数量要大于等于 n.

```go
func (st *Stack) require(n int) error {
        if st.len() < n {
                return fmt.Errorf("stack underflow (%d <=> %d)", len(st.data), n) // 如果元素数量不足，返回错误
        }
        return nil
}
```

## **intpool**

非常简单. 就是 256 大小的 big.int 的池, 用来加速 bit.Int 的分配

```go
var checkVal = big.NewInt(-42) // 用于验证池完整性的默认值

const poolLimit = 256 // 池的最大容量

// intPool is a pool of big integers that
// can be reused for all big.Int operations.
type intPool struct {
        pool *Stack // 使用 Stack 作为底层存储
}

func newIntPool() *intPool {
        return &intPool{pool: newstack()} // 初始化一个 intPool，其底层是一个新的 Stack
}

func (p *intPool) get() *big.Int {
        if p.pool.len() > 0 {
                return p.pool.pop() // 如果池中有可用对象，则从池中弹出并返回
        }
        return new(big.Int) // 否则，创建一个新的 big.Int
}
func (p *intPool) put(is ...*big.Int) {  //将一个或多个指向 big.Int 类型的指针放回一个对象池中，以便后续重用  ... 表示可变参数（variadic parameters），这意味着函数可以接收零个或多个参数
        if len(p.pool.data) > poolLimit { // 如果池已满
                return // 直接返回，不将对象放回池中
        }

        for _, i := range is {
                if verifyPool {
                        i.Set(checkVal) // 如果开启了验证，则设置一个默认值以检查完整性
                }

                p.pool.push(i) // 将对象推入池中
        }
}
```

## **memory**

构造, memory 的存储就是 byte[]. 还有一个 lastGasCost 的记录.
Memory 结构体代表了虚拟机的内存，其存储是一个字节切片
```go
type Memory struct {
        store       []byte // 内存的底层存储，一个字节切片
        lastGasCost uint64 // 记录上一次操作的 gas 消耗
}

func NewMemory() *Memory {
        return &Memory{} // 初始化一个空的 Memory 实例
}
```

使用首先需要使用 Resize 分配空间

```go
// Resize resizes the memory to size
func (m *Memory) Resize(size uint64) {
        if uint64(m.Len()) < size { // 如果当前内存大小<目标大小
                m.store = append(m.store, make([]byte, size-uint64(m.Len()))...) // 扩展内存切片以达到目标大小
                /// ... 创建的字节切片中的每个元素都将作为单独的参数传递给接收函数或方法
        }
}
```

然后使用 Set 来设置值

```go
// Set sets offset + size to value
func (m *Memory) Set(offset, size uint64, value []byte) {
        if size > uint64(len(m.store)) { // 检查大小是否超出内存限制
                panic("INVALID memory: store empty") // 当程序遇到无法恢复的错误时，触发 panic  
        }

        if size > 0 {
                copy(m.store[offset:offset+size], value) // 将值复制到内存的指定位置
        }
}
```

Get 来取值, 一个是获取拷贝, 一个是获取指针.
Get 和 GetPtr 方法用于从内存中读取数据
```go
// Get returns offset + size as a new slice
func (self *Memory) Get(offset, size int64) (cpy []byte) {
        if size == 0 { // 如果大小为0，返回nil
                return nil
        }

        if len(self.store) > int(offset) { // 如果内存大小大于偏移量
                cpy = make([]byte, size) // 创建一个新的切片
                copy(cpy, self.store[offset:offset+size]) // 将内存数据复制到新切片中

                return
        }

        return
}

// GetPtr returns the offset + size
func (self *Memory) GetPtr(offset, size int64) []byte {
        if size == 0 { // 如果大小为0，返回nil
                return nil
        }

        if len(self.store) > int(offset) { // 如果内存大小大于偏移量
                return self.store[offset : offset+size] // 返回内存切片的子切片（指针）
        }

        return nil
}
```

## **一些额外的帮助函数 在 stack_table.go 里面**
这些验证函数确保在执行这些操作时，堆栈的状态是有效的，避免了潜在的错误和不一致性。
```go
接受两个参数 pop 和 push，并返回一个 stackValidationFunc 类型的函数
func makeStackFunc(pop, push int) stackValidationFunc {
        return func(stack *Stack) error {
                if err := stack.require(pop); err != nil { // 检查弹出元素的数量  是否有足够的元素可以弹出
                        return err
                }

                if stack.len()+push-pop > int(params.StackLimit) { // 检查堆栈限制  检查堆栈在推入新元素后是否会超过限制
                        return fmt.Errorf("stack limit reached %d (%d)", stack.len(), params.StackLimit)
                }
                return nil
        }
}
用于创建堆栈操作的验证函数，主要用于确保在执行特定操作（如复制和交换）时，堆栈的状态是有效的。它们利用了 makeStackFunc 函数来实现这一点
用途：这个函数用于创建一个验证函数，专门用于 dup 操作（复制堆栈顶部的元素）
逻辑：当调用这个验证函数时，它会检查堆栈是否至少有 n 个元素（可以弹出），并且在复制后堆栈的大小不会超过限制
func makeDupStackFunc(n int) stackValidationFunc {
        return makeStackFunc(n, n+1) // 为 dup 操作创建一个验证函数  参数：n 表示要弹出的元素数量（即复制的元素数量），n+1 表示在复制后堆栈中将增加的元素数量。
}

func makeSwapStackFunc(n int) stackValidationFunc {
        n 表示要弹出的元素数量（即交换的元素数量），在交换操作中，堆栈的大小不会增加，因此 push 和 pop 都是 n
        return makeStackFunc(n, n) // 为 swap 操作创建一个验证函数  当调用这个验证函数时，它会检查堆栈是否至少有 n 个元素（可以弹出），并且在交换后堆栈的大小不会改变。

}
```
