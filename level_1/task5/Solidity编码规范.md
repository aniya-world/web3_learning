
## **代码布局**

#### 缩进

- 每行使用 4 个空格进行缩进。

#### 使用空格还是 Tab

- 首选使用空格进行缩进。
- 禁止混合使用 Tab 和空格。

#### 回车（空行）

- 两个合约之间增加两行空行。

规范的方式：

```
contract A {
    ...}
contract B {
    ...}
contract C {
    ...}
```

不规范的方式：

```
contract A {
    ...}contract B {
    ...}
    
contract C {
    ...}
```

合约内部函数之间需要回车，如果是函数声明和函数实现一起则需要两个回车

规范的方式：

```
contract A {
    function spam();
    function ham();
}

contract B is A {
    function spam() {
        ...
    }
    function ham() {
        ...
    }
}
```

不规范的方式：

```
contract A {
    function spam() {
        ...
    }
    
    function ham() {
        ...
    }}
```

## **源文件编码方式**

首选 UTF-8 或者 ASCII 编码

## **引入**

一般在代码开始进行引入声明

规范的方式：

```
import "owned";
contract A {
    ...}
    
contract B is owned {
    ...}
```

不规范的方式：

```
contract A {
    ...}
    
import "owned";

contract B is owned {
    ...}
```

表达式中的空格使用方法

在以下场景中，避免使用空格：

#### 括号、中括号、花括号之后避免使用空格

- 规范的方式: `spam(ham[1], Coin({name: "ham"}));`
- 不规范的方式: `spam( ham[ 1 ], Coin( { name: "ham" } ) );`

#### 逗号和分号之前避免使用空格

- 规范的方式: `function spam(uint i, Coin coin);`
- 不规范的方式: `function spam(uint i , Coin coin) ;`

#### 赋值符前后避免多个空格

- 规范的方式: `x = 42;`

规范的方式：

```
x = 1;
y = 2;
long_variable = 3;
```

不规范的方式：

```
x             = 1;
y             = 2;
long_variable = 3;
```

控制结构

#### 合约、库、函数、结构体的花括号使用方法

- 左花括号 `{` 和声明在同一行。
- 右花括号 `}` 和左花括号 `{` 的声明保持相同的缩进位置。
- 左花括号 `{` 后应换行。

规范的方式：

```
contract Coin {
    struct Bank {
        address owner;
        uint balance;
    }
}
```

不规范的方式：

```
contract Coin
{
    struct Bank {
        address owner;
        uint balance;
    }
}
```

以上建议也同样适用于 if、else、while、for。

此外，if、while、for 条件语句之间必须空行

规范的方式：

```
if (...) {

    ...
    
}
for (...) {

    ...
    
}
```

不规范的方式：

```
if (...)
{
    ...
}
while(...)
{
}
for (...)
 {
    ...;
}
```

对于控制结构内部如果只有单条语句可以不需要使用括号。

规范的方式：

```
if (x < 10)
    x += 1;
```

不规范的方式：

```
if (x < 10)
    someArray.push(Coin({
        name: 'spam',
        value: 42
    }));
```

对于 if 语句如果包含 else 或者 else if 语句，则 else 语句要新起一行。else 和 else if 的内部规范和 if 相同。

规范的方式：

```
if (x < 3) {
    x += 1;
}
else {
    x -= 1;
}
if (x < 3)
    x += 1;
else
    x -= 1;
```

不规范的方式：

```
if (x < 3) {
    x += 1;} 
else {
    x -= 1;}
```

## **函数声明**

对于简短的函数声明，建议将函数体的左括号 `{` 和函数名放在同一行。右括号 `}` 和函数声明保持相同的缩进。左括号 `{` 和函数名之间应增加一个空格。

## **规范的方式：**

```
function increment(uint x) returns (uint) {
    return x + 1;
}
function increment(uint x) public onlyowner returns (uint) {
    return x + 1;
}
```

不规范的方式：

```
function increment(uint x) returns (uint)
{
    return x + 1;
}
function increment(uint x) returns (uint)
{
    return x + 1;
}
function increment(uint x) returns (uint)
 {
    return x + 1;
}
function increment(uint x) returns (uint) 
{
    return x + 1;
}
```

默认修饰符应该放在其他自定义修饰符之前。

规范的方式：

```建议将默认修饰符（如 public、external、internal、private 等）放在自定义修饰符onlyowner之前
function kill() public onlyowner {
    selfdestruct(owner);
}
```

不规范的方式：

```
function kill() onlyowner public {
    selfdestruct(owner);
}
```

对于参数较多的函数声明可将所有参数逐行显示，并保持相同的缩进。函数声明的右括号和函数体左括号放在同一行，并和函数声明保持相同的缩进。

规范的方式：

```
function thisFunctionHasLotsOfArguments(
    address a,
    address b,
    address c,
    address d,
    address e,
    address f,
) {
    do_something;
}
```

不规范的方式：

```
function thisFunctionHasLotsOfArguments(address a, address b, address c,
    address d, address e, address f) {
    do_something;
}
function thisFunctionHasLotsOfArguments(address a,
                                        address b,
                                        address c,
                                        address d,
                                        address e,
                                        address f) {
    do_something;
}
function thisFunctionHasLotsOfArguments(
    address a,
    address b,
    address c,
    address d,
    address e,
    address f) {
    do_something;
}
```

如果函数包括多个修饰符，则需要将修饰符分行并逐行缩进显示。函数体左括号也要分行。

规范的方式：

```
function thisFunctionNameIsReallyLong(address x, address y, address z)
    public
    onlyowner
    priced
    returns (address)
{
    do_something;
}
function thisFunctionNameIsReallyLong(
    address x,
    address y,
    address z,)
    public
    onlyowner
    priced
    returns (address)
{
    do_something;
}
```

不规范的方式：

```
function thisFunctionNameIsReallyLong(address x, address y, address z)
                                      public
                                      onlyowner
                                      priced
                                      returns (address) {
    do_something;
}
function thisFunctionNameIsReallyLong(address x, address y, address z)
    public onlyowner priced returns (address){
    do_something;
}
function thisFunctionNameIsReallyLong(address x, address y, address z)
    public
    onlyowner
    priced
    returns (address) {
    do_something;
}
```

对于需要参数作为构造函数的派生合约，如果函数声明太长或者难于阅读，建议将其构造函数中涉及基类的构造函数分行独立显示。

规范的方式：

```
contract A is B, C, D {
    function A(uint param1, uint param2, uint param3, uint param4, uint param5)
        B(param1)
        C(param2, param3)
        D(param4)
    {
        // do something with param5
    }
}
```

不规范的方式：

```在这个例子中，基类构造函数的调用没有正确缩进，导致代码的可读性下降
contract A is B, C, D {
    function A(uint param1, uint param2, uint param3, uint param4, uint param5)
    B(param1)
    C(param2, param3)
    D(param4)
    {
        // do something with param5
    }
}
contract A is B, C, D {
    function A(uint param1, uint param2, uint param3, uint param4, uint param5)
        B(param1)
        C(param2, param3)
        D(param4) {
        // do something with param5
    }
}
```

对于函数声明的编程规范主要用于提升可读性，本指南不可能囊括所有编程规范，对于不涉及的地方，程序猿可发挥自己的主观能动性。

#### 函数声明规范

函数声明的编程规范主要用于提升代码的可读性。本指南无法囊括所有的编程规范，对于未涉及的部分，开发者可以根据实际情况发挥主观能动性。

### 变量声明

#### 数组变量声明

- 规范的方式: `uint[] x;`
- 不规范的方式: `uint [] x;`

### 其他建议

- 赋值运算符两边要有一个空格。

规范的方式：

```
x = 3;x = 100 / 10;x += 3 + 4;x |= y && z;
```

不规范的方式：

```
x=3;x = 100/10;x += 3+4;x |= y&&z;
```

- 为了显示优先级，优先级运算符和低优先级运算符之间要有空格，这也是为了提升复杂声明的可读性。对于运算符两侧的空格数目必须保持一致。

规范的方式：

```
x = 23 + 5;x = 2_y + 3_z;x = (a+b) * (a-**b);
```

不规范的方式：

```
x = 2** 3 + 5;x = y+z;x +=1;
```

### 命名规范

命名规范是强大且广泛使用的，使用不同的命名规范可以传递不同的信息。以下建议旨在提升代码的可读性，因此这些规范不是规则，而是帮助更好解释相关代码的指引。最后，编码风格的一致性是最重要的。

#### 命名方式

为了防止混淆，以下是不同的命名方式：

- b（单个小写字母）
- B（单个大写字母）
- 小写
- 有下划线的小写
- 大写
- 有下划线的大写
- CapWords 规范（首字母大写）
- 混合方式（与 CapitalizedWords 不同，首字母小写）
- 有下划线的首字母大写

#### 注意

当使用 CapWords 规范（首字母大写）的缩略语时，缩略语应全部大写，比如 HTTPServerError 比 HttpServerError 更易理解。

#### 避免的命名方式

- l（小写字母 el）
- O（大写字母 oh）
- I（大写字母 eye）

永远不要用‘l’（小写字母 el）、‘O’（大写字母 oh）或‘I’（大写字母 eye）作为单字符的变量名。在某些字体中，这些字符难以与数字 1 和 0 区分。尽量在使用‘l’时用‘L’代替。

#### 合约及库的命名

合约和库应该使用 CapWords 规范命名（首字母大写）。

#### 事件命名

事件应该使用 CapWords 规范命名（首字母大写）。

#### 函数命名

函数名使用大小写混合。

#### 函数参数命名

当定义一个在自定义结构体上的库函数时，结构体的名称必须具有自解释能力。

#### 局部变量命名

局部变量名使用大小写混合。

#### 常量命名

常量全部使用大写字母并用下划线分隔。
uint256 public constant MAX_SUPPLY = 1000000;
string public constant TOKEN_NAME = "MyToken";

#### 修饰符命名

功能修饰符使用小写字符并用下划线分隔。
modifier has_sufficient_balance(uint256 amount) {
    require(address(this).balance >= amount, "Insufficient balance");
    _;
}
#### 避免冲突

当与内置或者保留名称冲突时，建议在名称末尾加单个下划线，以避免冲突。