
这个文件主要分析了 core/vm 包中的 contract.go 和 evm.go。

contract.go 文件定义了 Contract 结构体，代表了以太坊状态数据库中的一个合约，包括其代码和调用参数等信息。
evm.go 文件则定义了 EVM 结构体，它是以太坊虚拟机的基础对象，提供了执行合约所需的工具。


## **contract.go**

contract 代表了以太坊 state database 里面的一个合约。包含了合约代码，调用参数。

结构

```go
// ContractRef 是合约背后对象的引用接口。
// ContractRef is a reference to the contract's backing object
type ContractRef interface {
        Address() common.Address // 返回合约地址
}

// AccountRef implements ContractRef.
//
// Account references are used during EVM initialisation and
// it's primary use is to fetch addresses. Removing this object
// proves difficult because of the cached jump destinations which
// are fetched from the parent contract (i.e. the caller), which
// is a ContractRef.
// AccountRef 实现了 ContractRef 接口，主要用于 EVM 初始化和获取地址。
type AccountRef common.Address

// Address casts AccountRef to a Address
// 该方法是 AccountRef 类型的方法
// 返回一个 common.Address 类型的值
// 这个方法的主要用途是提供一种方便的方式，将 AccountRef 类型的实例转换为以太坊地址。这在需要使用地址进行交易、合约调用或其他操作时非常有用。
func (ar AccountRef) Address() common.Address { return (common.Address)(ar) } // 将 AccountRef 类型的 ar 转换为 common.Address类型

// Contract represents an ethereum contract in the state database. It contains
// the the contract code, calling arguments. Contract implements ContractRef
type Contract struct {
        // CallerAddress is the result of the caller which initialised this
        // contract. However when the "call method" is delegated this value
        // needs to be initialised to that of the caller's caller.
        CallerAddress common.Address // 调用者地址，如果是委托调用则为调用者的调用者
        caller        ContractRef // 保存调用者的引用
        self          ContractRef // 合约自身的引用

        jumpdests destinations // JUMPDEST 指令的分析结果

        Code     []byte  // 合约代码
        CodeHash common.Hash  // 合约代码的哈希
        CodeAddr *common.Address // 合约地址
        Input    []byte     // 调用参数

        Gas   uint64                  // 合约的剩余 Gas
        value *big.Int      // 合约收到的以太币

        Args []byte  // 似乎没有使用

        DelegateCall bool  // 标记是否为委托调用
}
```

构造

```go
//NewContract 函数 为EVM的执行 返回一个新的合约环境。
// NewContract returns a new contract environment for the execution of EVM.
// 定义了一个名为 NewContract 的构造函数，用于创建新的合约实例
/*参数：
        caller ContractRef： 调用合约的引用，表示发起调用的合约或账户。
        object ContractRef： 目标合约的引用，表示被调用的合约。
        value *big.Int： 传递给合约的以太币数量，使用 big.Int 类型表示，以支持大数值。
        gas uint64： 执行合约所需的燃气量。
返回值：返回一个指向新创建的 Contract 实例的指针。
*/
func NewContract(caller ContractRef, object ContractRef, value *big.Int, gas uint64) *Contract {
        // 创建合约实例 
        c := &Contract{CallerAddress: caller.Address(), caller: caller, self: object, Args: nil} //  self：保存目标合约的引用
        
        //这行代码检查 caller 是否是一个合约。如果是，则可以重用父合约的跳转目标分析
        // 这段代码是 Go 语言中的类型断言，用于检查一个接口类型的变量是否可以被转换为特定的类型。
        // 在这个例子中，caller 是一个接口类型的变量，代码试图将其转换为 *Contract 类型
        // 表示我们希望将 caller 转换为指向 Contract 类型的指针
        if parent, ok := caller.(*Contract); ok {
                // Reuse JUMPDEST analysis from parent context if available.
                // 如果 caller 是一个合约，说明是合约调用了我们。 jumpdests设置为caller的jumpdests
                c.jumpdests = parent.jumpdests  // 重用调用者的 JUMPDEST 分析结果
                // JUMPDEST 指示一个有效的跳转目的地，确保在执行 JUMP 或 JUMPI 操作码时，跳转的目标位置是合法的
                // JUMPDEST 可以提高代码的安全性和可读性，确保跳转操作不会导致意外的执行流错误。它是 EVM 中控制流管理的关键部分。
        } else {
                c.jumpdests = make(destinations) // 否则创建一个新的 JUMPDEST 映射
        }

        // Gas should be a pointer so it can safely be reduced through the run
        // This pointer will be off the state transition
        c.Gas = gas // 设置合约的 Gas
        // ensures a value is set
        c.value = value  // 设置转入合约的以太币值

        return c
}
```

AsDelegate 将合约设置为委托调用并返回当前合约（用于链式调用）

```go
// AsDelegate sets the contract to be a delegate call and returns the current
// contract (for chaining calls)
func (c *Contract) AsDelegate() *Contract {
        c.DelegateCall = true // 将 DelegateCall 标志设置为 true
        parent := c.caller.(*Contract) // 获取父合约
        c.CallerAddress = parent.CallerAddress // 将调用者地址设置为父合约的调用者地址
        c.value = parent.value // 将值设置为父合约的值

        return c
}
```

GetOp 用来获取下一跳指令

GetOp 方法用于获取合约字节数组中指定位置的指令
```go
// GetOp returns the n'th element in the contract's byte array
func (c *Contract) GetOp(n uint64) OpCode {
        return OpCode(c.GetByte(n)) // 将指定位置的字节转换为操作码
}

// GetByte returns the n'th byte in the contract's byte array
func (c *Contract) GetByte(n uint64) byte {
        if n < uint64(len(c.Code)) {
                return c.Code[n] // 如果索引在代码范围内，返回对应的字节
        }

        return 0
}

// Caller returns the caller of the contract.
//
// Caller will recursively call caller when the contract is a delegate
// call, including that of caller's caller.
func (c *Contract) Caller() common.Address {
        return c.CallerAddress // 返回调用者地址
}
```

UseGas 使用 Gas。
方法用于尝试使用指定量的 Gas，并在成功时返回 true
```go
// UseGas attempts the use gas and subtracts it and returns true on success
func (c *Contract) UseGas(gas uint64) (ok bool) {
        if c.Gas < gas { // 如果剩余 Gas 小于需要使用的 Gas
                return false // 返回 false
        }
        c.Gas -= gas // 消耗 Gas
        return true // 返回 true
}

/*
总结
这两个方法提供了对 Contract 结构体的基本信息访问：

Address 方法返回合约的地址，方便在需要合约地址的上下文中使用。
Value 方法返回合约的价值，表示合约在执行时接收到的以太币数量。这些方法在与合约交互时非常有用，允许开发者轻松获取合约的地址和价值信息。
*/
// Address returns the contracts address 返回一个 common.Address 类型的值，表示合约的地址。
func (c *Contract) Address() common.Address {
        return c.self.Address()  //self 是一个 ContractRef 类型的引用，指向合约本身
}

// Value returns the contracts value (sent to it from it's caller) ；返回一个指向 big.Int 类型的指针，表示合约的价值。表示从调用者传递给合约的以太币数量
func (c *Contract) Value() *big.Int {
        return c.value
}
```

SetCode 和 SetCallCode
这些方法用于设置合约代码
```go
// SetCode sets the code to the contract
func (self *Contract) SetCode(hash common.Hash, code []byte) {
        self.Code = code // 设置合约代码
        self.CodeHash = hash // 设置代码哈希
}

// SetCallCode sets the code of the contract and address of the backing data
// object
func (self *Contract) SetCallCode(addr *common.Address, hash common.Hash, code []byte) {
        self.Code = code // 设置合约代码
        self.CodeHash = hash // 设置代码哈希
        self.CodeAddr = addr // 设置代码地址
}
```

## **evm.go**
EVM 结构体是 以太坊虚拟机 的核心对象。它提供了在给定状态下使用提供的上下文运行合约的必要工具


```go
// Context provides the EVM with auxiliary information. Once provided
// it shouldn't be modified.
// Context 结构体为 EVM 提供辅助信息，一旦提供就不应该被修改
type Context struct {
        CanTransfer CanTransferFunc // 函数，返回账户是否有足够的以太币进行转账
        Transfer TransferFunc // 函数，用于在账户间进行以太币转账
        GetHash GetHashFunc // 函数，用于返回给定区块号对应的哈希值

        // Message information
        Origin   common.Address // 提供 ORIGIN 指令所需的信息
        GasPrice *big.Int       // 提供 GASPRICE 指令所需的信息

        // Block information
        Coinbase    common.Address // 提供 COINBASE 指令所需的信息
        GasLimit    *big.Int       // 提供 GASLIMIT 指令所需的信息
        BlockNumber *big.Int       // 提供 NUMBER 指令所需的信息
        Time        *big.Int       // 提供 TIME 指令所需的信息
        Difficulty  *big.Int       // 提供 DIFFICULTY 指令所需的信息
}

type EVM struct {
        Context // 上下文，提供辅助的区块链信息
        StateDB StateDB // 状态数据库，提供对底层状态的访问
        depth int // 当前的调用堆栈深度

        chainConfig *params.ChainConfig // 包含当前链的信息
        chainRules params.Rules // 包含当前纪元的链规则
        vmConfig Config // 虚拟机配置选项
        interpreter *Interpreter // 全局的 EVM 解释器
        abort int32 // 用于中止 EVM 调用操作，必须原子地设置
}
```

构造函数

```go
// NewEVM retutrns a new EVM . The returned EVM is not thread safe and should
// only ever be used *once*.
NewEVM 函数返回一个 EVM 新实例，该实例不是线程安全的，只能使用一次。
func NewEVM(ctx Context, statedb StateDB, chainConfig *params.ChainConfig, vmConfig Config) *EVM {
        evm := &EVM{
                Context:     ctx,
                StateDB:     statedb,
                vmConfig:    vmConfig,
                chainConfig: chainConfig,
                chainRules:  chainConfig.Rules(ctx.BlockNumber),
        }

        evm.interpreter = NewInterpreter(evm, vmConfig)
        return evm
}

// Cancel cancels any running EVM operation. This may be called concurrently and
// it's safe to be called multiple times.
func (evm *EVM) Cancel() {
        atomic.StoreInt32(&evm.abort, 1)
}
```

 
Create 方法使用给定的代码作为部署代码创建一个新合约
```go
// Create creates a new contract using code as deployment code.
func (evm *EVM) Create(caller ContractRef, code []byte, gas uint64, value *big.Int) (ret []byte, contractAddr common.Address, leftOverGas uint64, err error) {
        if evm.depth > int(params.CallCreateDepth) { // 检查调用深度
                return nil, common.Address{}, gas, ErrDepth
        }
        if !evm.CanTransfer(evm.StateDB, caller.Address(), value) { // 检查账户余额是否足够
                return nil, common.Address{}, gas, ErrInsufficientBalance
        }
        nonce := evm.StateDB.GetNonce(caller.Address()) // 获取调用者的 nonce
        evm.StateDB.SetNonce(caller.Address(), nonce+1) // 增加调用者的 nonce

        contractAddr = crypto.CreateAddress(caller.Address(), nonce) // 创建合约地址
        contractHash := evm.StateDB.GetCodeHash(contractAddr)
        if evm.StateDB.GetNonce(contractAddr) != 0 || (contractHash != (common.Hash{}) && contractHash != emptyCodeHash) { // 检查地址是否已存在合约
                return nil, common.Address{}, 0, ErrContractAddressCollision
        }
        snapshot := evm.StateDB.Snapshot() // 创建状态数据库快照
        evm.StateDB.CreateAccount(contractAddr) // 创建新账户
        if evm.ChainConfig().IsEIP158(evm.BlockNumber) {
                evm.StateDB.SetNonce(contractAddr, 1) // 设置 nonce
        }
        evm.Transfer(evm.StateDB, caller.Address(), contractAddr, value) // 转账

        contract := NewContract(caller, AccountRef(contractAddr), value, gas) // 初始化新合约
        contract.SetCallCode(&contractAddr, crypto.Keccak256Hash(code), code)

        if evm.vmConfig.NoRecursion && evm.depth > 0 {
                return nil, contractAddr, gas, nil
        }
        ret, err = run(evm, snapshot, contract, nil) // 执行合约的初始化代码
        maxCodeSizeExceeded := evm.ChainConfig().IsEIP158(evm.BlockNumber) && len(ret) > params.MaxCodeSize // 检查代码大小是否超出限制
        if err == nil && !maxCodeSizeExceeded {
                createDataGas := uint64(len(ret)) * params.CreateDataGas
                if contract.UseGas(createDataGas) {
                        evm.StateDB.SetCode(contractAddr, ret) // 设置合约代码
                } else {
                        err = ErrCodeStoreOutOfGas // 如果 Gas 不足，返回错误
                }
        }

        if maxCodeSizeExceeded || (err != nil && (evm.ChainConfig().IsHomestead(evm.BlockNumber) || err != ErrCodeStoreOutOfGas)) { // 如果发生错误或代码大小超出限制，则回滚
                evm.StateDB.RevertToSnapshot(snapshot)
                if err != errExecutionReverted {
                        contract.UseGas(contract.Gas) // 消耗所有剩余的 Gas
                }
        }
        if maxCodeSizeExceeded && err == nil {
                err = errMaxCodeSizeExceeded
        }
        return ret, contractAddr, contract.Gas, err
}
```

Call 方法, 无论我们转账或者是执行合约代码都会调用到这里， 同时合约里面的 call 指令也会执行到这里。

```go
// Call executes the contract associated with the addr with the given input as
// parameters. It also handles any necessary value transfer required and takes
// the necessary steps to create accounts and reverses the state in case of an
// execution error or failed value transfer.

// Call 执行与给定的input作为参数与addr相关联的合约。 
// 它还处理所需的任何必要的转账操作，并采取必要的步骤来创建帐户
// 并在任意错误的情况下回滚所做的操作。

// Call executes the contract associated with the addr with the given input as
// parameters.
func (evm *EVM) Call(caller ContractRef, addr common.Address, input []byte, gas uint64, value *big.Int) (ret []byte, leftOverGas uint64, err error) {
        if evm.vmConfig.NoRecursion && evm.depth > 0 {
                return nil, gas, nil
        }

        if evm.depth > int(params.CallCreateDepth) { // 检查调用深度
                return nil, gas, ErrDepth
        }
        if !evm.Context.CanTransfer(evm.StateDB, caller.Address(), value) { // 检查账户余额
                return nil, gas, ErrInsufficientBalance
        }

        var (
                to       = AccountRef(addr)
                snapshot = evm.StateDB.Snapshot()
        )
        if !evm.StateDB.Exist(addr) { // 检查地址是否存在
                precompiles := PrecompiledContractsHomestead
                if evm.ChainConfig().IsByzantium(evm.BlockNumber) {
                        precompiles = PrecompiledContractsByzantium
                }
                if precompiles[addr] == nil && evm.ChainConfig().IsEIP158(evm.BlockNumber) && value.Sign() == 0 {
                        return nil, gas, nil
                }
                evm.StateDB.CreateAccount(addr) // 如果地址不存在，创建账户
        }
        evm.Transfer(evm.StateDB, caller.Address(), to.Address(), value) // 执行转账

        contract := NewContract(caller, to, value, gas) // 初始化新合约
        contract.SetCallCode(&addr, evm.StateDB.GetCodeHash(addr), evm.StateDB.GetCode(addr))

        ret, err = run(evm, snapshot, contract, input)
        if err != nil {
                evm.StateDB.RevertToSnapshot(snapshot) // 如果出错，回滚状态
                if err != errExecutionReverted {
                        contract.UseGas(contract.Gas) // 消耗所有剩余 Gas
                }
        }
        return ret, contract.Gas, err
}
```

剩下的三个函数 CallCode, DelegateCall, 和 StaticCall，这三个函数不能由外部调用，只能由 Opcode 触发。

1. CallCode
CallCode 的特殊之处在于它使用调用者的上下文来执行给定地址的代码
```go
// CallCode differs from Call in the sense that it executes the given address'
// code with the caller as context.
// CallCode与Call不同的地方在于 它使用caller的context来执行给定地址的代码。

// Call executes the contract associated with the addr with the given input as
// parameters.
func (evm *EVM) Call(caller ContractRef, addr common.Address, input []byte, gas uint64, value *big.Int) (ret []byte, leftOverGas uint64, err error) {
        if evm.vmConfig.NoRecursion && evm.depth > 0 {
                return nil, gas, nil
        }

        if evm.depth > int(params.CallCreateDepth) { // 检查调用深度
                return nil, gas, ErrDepth
        }
        if !evm.Context.CanTransfer(evm.StateDB, caller.Address(), value) { // 检查账户余额
                return nil, gas, ErrInsufficientBalance
        }

        var (
                to       = AccountRef(addr)
                snapshot = evm.StateDB.Snapshot()
        )
        if !evm.StateDB.Exist(addr) { // 检查地址是否存在
                precompiles := PrecompiledContractsHomestead
                if evm.ChainConfig().IsByzantium(evm.BlockNumber) {
                        precompiles = PrecompiledContractsByzantium
                }
                if precompiles[addr] == nil && evm.ChainConfig().IsEIP158(evm.BlockNumber) && value.Sign() == 0 {
                        return nil, gas, nil
                }
                evm.StateDB.CreateAccount(addr) // 如果地址不存在，创建账户
        }
        evm.Transfer(evm.StateDB, caller.Address(), to.Address(), value) // 执行转账

        contract := NewContract(caller, to, value, gas) // 初始化新合约
        contract.SetCallCode(&addr, evm.StateDB.GetCodeHash(addr), evm.StateDB.GetCode(addr))

        ret, err = run(evm, snapshot, contract, input)
        if err != nil {
                evm.StateDB.RevertToSnapshot(snapshot) // 如果出错，回滚状态
                if err != errExecutionReverted {
                        contract.UseGas(contract.Gas) // 消耗所有剩余 Gas
                }
        }
        return ret, contract.Gas, err
}
```

2. DelegateCall
DelegateCall 的特殊之处在于它使用调用者的上下文，并将调用者设置为调用者的调用者。
```go
// DelegateCall differs from CallCode in the sense that it executes the given address'
// code with the caller as context and the caller is set to the caller of the caller.
// DelegateCall 和 CallCode不同的地方在于 caller被设置为 caller的caller
func (evm *EVM) DelegateCall(caller ContractRef, addr common.Address, input []byte, gas uint64) (ret []byte, leftOverGas uint64, err error) {
        if evm.vmConfig.NoRecursion && evm.depth > 0 {
                return nil, gas, nil
        }
        if evm.depth > int(params.CallCreateDepth) { // 检查调用深度
                return nil, gas, ErrDepth
        }

        var (
                snapshot = evm.StateDB.Snapshot()
                to       = AccountRef(caller.Address())
        )
        contract := NewContract(caller, to, nil, gas).AsDelegate() // 初始化新合约并标记为委托调用
        contract.SetCallCode(&addr, evm.StateDB.GetCodeHash(addr), evm.StateDB.GetCode(addr))

        ret, err = run(evm, snapshot, contract, input)
        if err != nil {
                evm.StateDB.RevertToSnapshot(snapshot)
                if err != errExecutionReverted {
                        contract.UseGas(contract.Gas)
                }
        }
        return ret, contract.Gas, err
}


// StaticCall executes the contract associated with the addr with the given input
// as parameters while disallowing any modifications to the state during the call.
// Opcodes that attempt to perform such modifications will result in exceptions
// instead of performing the modifications.
// StaticCall不允许执行任何修改状态的操作，
3. StaticCall 不允许在调用期间对状态进行任何修改
func (evm *EVM) StaticCall(caller ContractRef, addr common.Address, input []byte, gas uint64) (ret []byte, leftOverGas uint64, err error) {
        if evm.vmConfig.NoRecursion && evm.depth > 0 {
                return nil, gas, nil
        }
        if evm.depth > int(params.CallCreateDepth) { // 检查调用深度
                return nil, gas, ErrDepth
        }
        if !evm.interpreter.readOnly { // 如果解释器不是只读模式
                evm.interpreter.readOnly = true // 设置为只读模式
                defer func() { evm.interpreter.readOnly = false }() // 函数返回时恢复只读模式
        }

        var (
                to       = AccountRef(addr)
                snapshot = evm.StateDB.Snapshot()
        )
        contract := NewContract(caller, to, new(big.Int), gas) // 初始化新合约
        contract.SetCallCode(&addr, evm.StateDB.GetCodeHash(addr), evm.StateDB.GetCode(addr))

        ret, err = run(evm, snapshot, contract, input)
        if err != nil {
                evm.StateDB.RevertToSnapshot(snapshot)
                if err != errExecutionReverted {
                        contract.UseGas(contract.Gas)
                }
        }
        return ret, contract.Gas, err
}
```
