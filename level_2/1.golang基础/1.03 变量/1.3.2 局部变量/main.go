package main

import (
    "fmt"
)

func main() {
    method1()
    a,b := method2()
    method3()
    method4()
}
func method1() {
    // 方式1，类型推导，用得最多
    a := 1
    // 方式2，完整的变量声明写法
    var b int = 2
    // 方式3，仅声明变量，但是不赋值，
    var c int
    fmt.Println(a, b, c)
}

// 方式4，直接在返回值中声明
func method2() (a int, b string) {
    // 这种方式必须声明return关键字
    // 并且同样不需要使用，并且也不用必须给这种变量赋值
    return 1, "test"
}

func method3() (a int, b string) {
    a = 1
    b = "test"
    return
}

func method4() (a int, b string) {
    return
}






