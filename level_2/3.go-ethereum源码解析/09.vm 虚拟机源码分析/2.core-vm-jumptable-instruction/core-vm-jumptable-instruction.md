
jumptable 是一个 [256]operation 类型的数据结构，每个索引对应一个指令。operation 结构体存储了指令的执行函数、gas 消耗函数、堆栈验证函数等信息。
## **jumptable**

数据结构 operation 存储了一条指令的所需要的函数.

```go
type operation struct {
        execute executionFunc // 执行指令的函数
        gasCost gasFunc // 计算 gas 消耗的函数
        validateStack stackValidationFunc // 验证堆栈大小的函数
        memorySize memorySizeFunc // 返回操作所需内存大小的函数

        halts   bool // 指示操作是否停止进一步执行  ；Trading Halts 停止交易
        jumps   bool // 指示程序计数器是否不自增
        writes  bool // 确定这是否是一个状态修改操作
        valid   bool // 指示检索到的操作是否有效且已知
        reverts bool // 确定操作是否恢复状态（隐式停止）
        returns bool // 确定操作是否设置了返回数据内容
}
```


不同的以太坊版本有不同的指令集。 下面定义了三种指令集,针对三种不同的以太坊版本,

NewByzantiumInstructionSet（拜占庭） 
        会在 NewHomesteadInstructionSet（霍姆斯特德指令集） 的基础上，
                增加 STATICCALL 、 RETURNDATASIZE 、 RETURNDATACOPY 和   等新指令。

```go
// NewByzantiumInstructionSet returns the frontier, homestead and
// byzantium instructions.
func NewByzantiumInstructionSet() [256]operation {
        instructionSet := NewHomesteadInstructionSet() // 基于 Homestead 指令集创建
        instructionSet[STATICCALL] = operation{ // 添加 STATIC`CALL 指令
                execute:       opStaticCall,
                gasCost:       gasStaticCall,
                validateStack: makeStackFunc(6, 1),
                memorySize:    memoryStaticCall,
                valid:         true,
                returns:       true,
        }
        instructionSet[RETURNDATASIZE] = operation{ // 添加 RETURN`DATA`SIZE 指令
                execute:       opReturnDataSize,
                gasCost:       constGasFunc(GasQuickStep),
                validateStack: makeStackFunc(0, 1),
                valid:         true,
        }
        instructionSet[RETURNDATACOPY] = operation{ // 添加 RETURN`DATA`COPY 指令
                execute:       opReturnDataCopy,
                gasCost:       gasReturnDataCopy,
                validateStack: makeStackFunc(3, 0),
                memorySize:    memoryReturnDataCopy,
                valid:         true,
        }
        instructionSet[REVERT] = operation{ // 添加 REVERT 指令
                execute:       opRevert,
                gasCost:       gasRevert,
                validateStack: makeStackFunc(2, 0),
                memorySize:    memoryRevert,
                valid:         true,
                reverts:       true,
                returns:       true,
        }
        return instructionSet
}
```

NewHomesteadInstructionSet

```go
// NewHomesteadInstructionSet returns the frontier and homestead
// instructions that can be executed during the homestead phase.
func NewHomesteadInstructionSet() [256]operation { 返回一个长度为 256 的 operation 数组，表示指令集
        instructionSet := NewFrontierInstructionSet() // 创建一个基础的 Frontier 指令集，并将其赋值给 instructionSet 变量
        instructionSet[DELEGATECALL] = operation{ // 添加 DELEGATE`CALL 指令  该指令的具体实现通过一个 operation 结构体来定义
                execute:       opDelegateCall,   指定执行该指令的函数为 opDelegateCall
                gasCost:       gasDelegateCall,
                validateStack: makeStackFunc(6, 1),  定义堆栈验证规则，表示该指令需要 6 个输入和 1 个输出
                memorySize:    memoryDelegateCall,   指定该指令在执行时所需的内存大小为 memoryDelegateCall
                valid:         true, 表示该指令是有效的
                returns:       true, 表示该指令会返回值
        }
        return instructionSet
}
```

## **instruction.go**

因为指令很多,所以不一一列出来, 只列举几个例子. 虽然组合起来的功能可以很复杂,但是单个指令来说,还是比较直观的.

```go
func opPc(pc *uint64, evm *EVM, contract *Contract, memory *Memory, stack *Stack) ([]byte, error) {
        stack.push(evm.interpreter.intPool.get().SetUint64(*pc)) // 将程序计数器的值推入堆栈
        return nil, nil
}

func opMsize(pc *uint64, evm *EVM, contract *Contract, memory *Memory, stack *Stack) ([]byte, error) {
        stack.push(evm.interpreter.intPool.get().SetInt64(int64(memory.Len()))) // 将当前内存大小推入堆栈
        return nil, nil
}
```

## **gas_table.go**

gas_table 返回了各种指令消耗的 gas 的函数 这个函数的返回值基本上只有 errGasUintOverflow 整数溢出的错误.

```go
定义了一些函数，用于计算以太坊虚拟机（EVM）中不同指令的 gas 消耗。每个函数都接收一组参数，并返回相应指令的固定或动态 gas 消耗
func gasBalance(gt params.GasTable, evm *EVM, contract *Contract, stack *Stack, mem *Memory, memorySize uint64) (uint64, error) {
        return gt.Balance, nil // 返回 BALANCE 指令的固定 gas 消耗
}

func gasExtCodeSize(gt params.GasTable, evm *EVM, contract *Contract, stack *Stack, mem *Memory, memorySize uint64) (uint64, error) {
        return gt.ExtcodeSize, nil // 返回 EXTCODESIZE 指令的固定 gas 消耗
}

func gasSLoad(gt params.GasTable, evm *EVM, contract *Contract, stack *Stack, mem *Memory, memorySize uint64) (uint64, error) {
        return gt.SLoad, nil // 返回 SLOAD 指令的固定 gas 消耗
}

计算 EXP 指令的 gas 消耗
func gasExp(gt params.GasTable, evm *EVM, contract *Contract, stack *Stack, mem *Memory, memorySize uint64) (uint64, error) {
        expByteLen := uint64((stack.data[stack.len()-2].BitLen() + 7) / 8) // 计算指数的字节长度
        首先，计算指数的字节长度 expByteLen ，通过获取堆栈中倒数第二个元素的位长度并转换为字节。

        var (
                gas      = expByteLen * gt.ExpByte // 计算指数的 gas 消耗  然后，计算 gas 消耗，gas 是字节长度乘以每字节的 gas 消耗 gt.ExpByte。
                overflow bool
        )
        if gas, overflow = math.SafeAdd(gas, GasSlowStep); overflow { // 加上基础 gas，并检查是否溢出  
//使用 math.SafeAdd 将基础 gas GasSlowStep 加入到 gas 中，并检查是否发生溢出。
                return 0, errGasUintOverflow // 如果溢出，返回错误
        }
        return gas, nil
}
 
```

## **interpreter.go 解释器**
Interpreter 结构体用于运行基于以太坊的合约，并根据配置使用字节码 VM 或 JIT VM
数据结构

```go
// Config are the configuration options for the Interpreter
// Config are the configuration options for the Interpreter  通常用于存储与解释器相关的配置参数
type Config struct {
        Debug bool // 启用调试
        EnableJit bool // 启用 JIT VM
        ForceJit bool // 强制使用 JIT VM
        Tracer Tracer // 操作码日志记录器
        NoRecursion bool // 禁用递归调用
        DisableGasMetering bool // 禁用 gas 计量
        EnablePreimageRecording bool // 启用 SHA3/keccak 预映像记录
        JumpTable [256]operation // EVM 指令表
}

// Interpreter is used to run Ethereum based contracts and will utilise the
// passed evmironment to query external sources for state information.
type Interpreter struct {  用于运行基于以太坊的合约
        evm      *EVM   是一个指向 EVM（以太坊虚拟机）实例的指针。EVM 负责执行智能合约的逻辑和操作
        cfg      Config  通常用于存储与解释器相关的配置参数   
        gasTable params.GasTable // 这是一个 GasTable 类型的字段，用于存储 gas 价格表。 它包含了不同操作的 gas 消耗信息，帮助解释器在执行合约时计算所需的 gas
        intPool  *intPool  // 是一个指向 intPool 的指针，可能用于管理整数的池化，以提高性能和减少内存分配的开销

        readOnly   bool // 是否在只读模式下
        returnData []byte // 用于存储上一个 CALL 操作的返回数据。合约在执行过程中可能会调用其他合约，返回的数据会被存储在这里，以便后续使用
}
```

构造函数

```go
// 函数返回一个 Interpreter 的新实例
// evm *EVM：传入的 EVM 实例，表示以太坊虚拟机  
// cfg Config：传入的配置对象，包含解释器的配置信息。
func NewInterpreter(evm *EVM, cfg Config) *Interpreter {
        if !cfg.JumpTable[STOP].valid { // 检查 JumpTable 是否已初始化，通过检查 STOP 指令的 valid 字段来判断
                switch {
                // switch 语句根据当前区块号选择合适的指令集
                case evm.ChainConfig().IsByzantium(evm.BlockNumber): // 当前区块属于 Byzantium 升级，则使用
                        cfg.JumpTable = byzantiumInstructionSet
                case evm.ChainConfig().IsHomestead(evm.BlockNumber): // 当前区块属于 Homestead 升级，则使用
                        cfg.JumpTable = homesteadInstructionSet
                default:
                        cfg.JumpTable = frontierInstructionSet //不属于以上两者，则使用
                }
        }
        return &Interpreter{
                evm:      evm,
                cfg:      cfg,
                gasTable: evm.ChainConfig().GasTable(evm.BlockNumber),//根据当前区块号获取的燃气表
                intPool:  newIntPool(), // 调用 newIntPool() 创建的新整数池
                // 在以太坊虚拟机（EVM）的上下文中，intPool 通常指的是一个整数池（Integer Pool），用于管理和优化整数的使用
// intPool 主要用于优化内存管理。通过重用已经分配的整数对象，可以减少内存分配和释放的开销，从而提高性能
// 在执行智能合约时，EVM 需要频繁地进行整数运算。使用整数池可以减少内存分配的频率，降低垃圾回收的压力，从而提高整体执行效率。
// EVM 可以有效地管理内存，避免内存碎片的产生。内存碎片会导致可用内存的减少，从而影响性能。
// 整数池的实现通常涉及一个集合或列表，用于存储可重用的整数对象。当需要一个整数时，首先检查池中是否有可用的对象；如果有，则直接使用；如果没有，则创建一个新的整数并将其添加到池中
// 总结
//intPool 是以太坊虚拟机中的一个重要组件，旨在通过重用整数对象来优化内存管理和提高性能。它在执行智能合约时发挥着关键作用，帮助 EVM 更高效地处理大量的整数运算
}
}
// 主要功能是根据当前区块的状态选择合适的指令集，并创建一个新的解释器实例，以便在以太坊网络中执行智能合约。
```

解释器一共就两个方法 enforceRestrictions 方法和 Run 方法.
主要功能是检查在执行操作时是否违反了某些限制，特别是在只读模式下
```go
//接收者：in *Interpreter，表示该方法是 Interpreter 结构体的方法
/*
参数：
op OpCode：当前操作的操作码，表示要执行的指令。
operation operation：表示当前操作的详细信息，包括是否会修改状态。
stack *Stack：指向当前操作的栈，栈用于存储操作数和结果。

返回值：返回一个 error 类型的值，表示是否发生了错误
*/
func (in *Interpreter) enforceRestrictions(op OpCode, operation operation, stack *Stack) error {
        //检查是否为 Byzantium 升级
        if in.evm.chainRules.IsByzantium {
                //只读模式检查
                if in.readOnly {
                        // If the interpreter is operating in readonly mode, make sure no
                        // state-modifying operation is performed. The 3rd stack item
                        // for a call operation is the value. Transferring value from one
                        // account to the others means the state is modified and should also
                        // return with an error.
                        //状态修改检查
                        /*
                        operation.writes：检查当前操作是否会写入状态。如果是，则返回错误 errWriteProtection。
(op == CALL && stack.Back(2).BitLen() > 0)：检查当前操作是否为 CALL，并且栈中第三个元素（即调用的值）是否大于 0。如果是，表示将会转移价值，这也会修改状态，因此返回错误。
                        */
                        if operation.writes || (op == CALL && stack.Back(2).BitLen() > 0) {
                                return errWriteProtection
                        }
                }
        }
        return nil
}

// Run loops and evaluates the contract's code with the given input data and returns
// the return byte-slice and an error if one occurred.
// 用给定的入参循环执行合约的代码，并返回返回的字节片段，如果发生错误则返回错误。
// It's important to note that any errors returned by the interpreter should be
// considered a revert-and-consume-all-gas operation. No error specific checks
// should be handled to reduce complexity and errors further down the in.
// 重要的是要注意，解释器返回的任何错误都会消耗全部gas。 为了减少复杂性,没有特别的错误处理流程。
/*
接收者：in *Interpreter，表示该方法是 Interpreter 结构体的方法。
参数：
        snapshot int：快照的标识符，可能用于状态恢复。
        contract *Contract：要执行的合约实例。
        input []byte：传递给合约的输入数据。
返回值：返回合约执行的结果和可能的错误。
*/
func (in *Interpreter) Run(snapshot int, contract *Contract, input []byte) (ret []byte, err error) {
        in.evm.depth++ // 在执行合约之前，增加当前调用深度，并在函数返回时减少深度
        defer func() { in.evm.depth-- }() // 函数返回时减少调用深度

        in.returnData = nil // 重置上一次调用的返回数据

        if len(contract.Code) == 0 { // 如果合约代码为空，直接返回
                return nil, nil
        }
        codehash := contract.CodeHash
        //如果合约的代码哈希为空，则计算并设置它
        if codehash == (common.Hash{}) {
                codehash = crypto.Keccak256Hash(contract.Code)
        }
        //初始化操作码、内存、栈、程序计数器、燃气成本等变量
        var (
                op    OpCode
                mem   = NewMemory()
                stack = newstack()
                pc   = uint64(0)
                cost uint64
                stackCopy = newstack()
                pcCopy uint64
                gasCopy uint64
                logged bool
        )
        //设置合约输入
        contract.Input = input  //（参数传递给合约的输入数据）

        //如果发生错误且未记录状态，则在调试模式下捕获当前状态。
        defer func() {
                if err != nil && !logged && in.cfg.Debug {
                        in.cfg.Tracer.CaptureState(in.evm, pcCopy, op, gasCopy, cost, mem, stackCopy, contract, in.evm.depth, err)
                }
        }()

        /* atomic.LoadInt32(&in.evm.abort) == 0 
使用场景
        在并发程序中，您可能会使用 atomic.LoadInt32 来检查某个条件，例如：
                检查是否需要中止当前的操作。
                确保在执行某个关键操作之前，状态变量的值是最新的

atomic：这是 Go 语言的 sync/atomic 包，提供了一组原子操作的函数，允许在并发环境中安全地操作变量。
LoadInt32：这个函数用于读取一个 int32 类型的值，并确保在读取过程中不会被其他 goroutine 修改。
&in.evm.abort：这是传递给 LoadInt32 的参数，表示要读取的变量的地址。in.evm.abort 是一个 int32 类型的字段，可能用于指示某种状态（例如，是否应该中止某个操作）        
        */
        for atomic.LoadInt32(&in.evm.abort) == 0 { // 主循环，直到遇到停止条件

                //如以太坊的EVM）中，操作码（Opcode）是指令集中的基本命令，用于执行特定的操作。每个操作码对应一个特定的操作，例如算术运算、数据存取、控制流等
                op = contract.GetOp(pc) // 获取当前程序计数器位置的操作码

                if in.cfg.Debug {
                        // ...（调试信息捕获）
                }

                operation := in.cfg.JumpTable[op] // 通过操作码从 JumpTable 中获取对应的 operation

                //检查限制 上一个函数
                if err := in.enforceRestrictions(op, operation, stack); err != nil { // 检查是否违反只读模式限制
                        return nil, err
                }

                if !operation.valid { // 验证操作有效性
                        return nil, fmt.Errorf("invalid opcode 0x%x", int(op))
                }

                if err := operation.validateStack(stack); err != nil { // 验证堆栈 是否满足操作要求
                        return nil, err
                }

                var memorySize uint64
                // 算内存大小
                if operation.memorySize != nil { // 如果操作需要内存
                        memSize, overflow := bigUint64(operation.memorySize(stack))
                        if overflow {
                                return nil, errGasUintOverflow
                        }
                        if memorySize, overflow = math.SafeMul(toWordSize(memSize), 32); overflow {
                                return nil, errGasUintOverflow
                        }
                }
                // 算 Gas 消耗
                if !in.cfg.DisableGasMetering {
                        cost, err = operation.gasCost(in.gasTable, in.evm, contract, stack, mem, memorySize) // 计算 gas 消耗
                        if err != nil || !contract.UseGas(cost) {
                                return nil, ErrOutOfGas // 如果 gas 不足，返回错误
                        }
                }
                if memorySize > 0 {
                        mem.Resize(memorySize) // 调整内存大小 以适应当前操作的需求
                }

                //在调试模式下，捕获当前状态并记录相关信息，包括程序计数器、操作码、燃气消耗、内存、栈等。设置 logged 为 true，表示已经记录了状态
                if in.cfg.Debug {
                        in.cfg.Tracer.CaptureState(in.evm, pc, op, gasCopy, cost, mem, stackCopy, contract, in.evm.depth, err)
                        logged = true
                }
                //调用当前操作的 execute 方法，传入程序计数器、EVM 实例、合约、内存和栈，执行该操作并获取结果和可能的错误
                res, err := operation.execute(&pc, in.evm, contract, mem, stack) // 执行操作

                if operation.returns { // 如果操作有返回值
                        in.returnData = res // 设置返回数据
                }

                switch {
                case err != nil:
                        return nil, err //如果发生错误，返回错误
                case operation.reverts:
                        return res, errExecutionReverted //如果操作导致回滚，返回结果和回滚错误
                case operation.halts:
                        return res, nil //如果操作正常结束，返回结果
                case !operation.jumps:
                        pc++ // 如果操作不是跳转指令，则程序计数器自增，准备执行下一个操作
                }
        }
        return nil, nil
}
```
总结
Run 方法是以太坊虚拟机中执行智能合约的核心逻辑。它通过以下步骤实现合约的执行：

        增加调用深度并管理状态。
        检查合约代码和输入。
        初始化内存和栈。
        在主循环中
                获取操作码，检查限制，验证堆栈，计算 Gas 消耗，执行操作，并处理返回值和错误。

这个方法确保了合约的执行`符合以太坊的规则`和`限制`，同时提供了调试支持，以便开发者能够跟踪合约的执行过程。