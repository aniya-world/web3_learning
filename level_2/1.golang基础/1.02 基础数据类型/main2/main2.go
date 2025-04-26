package main2

import (
    "fmt"
)

 // go mod init  github.com/aniya-world/study1.02

func main() {

	//var float1 float32 = 10

	// := 是短变量声明的语法，用于在函数内部声明并初始化变量。
	// 由于没有显式指定类型，Go会根据右侧的值自动推断出变量的类型。在这个例子中，10.1 是一个浮点数，因此 float2 的类型将被推断为 float64，这是Go语言中默认的浮点数类型
	//float2 := 10.0

	// float32 != float64
	// invalid operation: float1 == float2 (mismatched types float32 and float64)
    // fmt.Println(float1 == float2)
	// float1 = float2
	//float1 = float32(float2)

	var c1 complex64
	c1 = 1.10 + 0.1i

	// c2 = c3 =default is complex128
	c2 := 1.10 + 0.1i
	c3 := complex(1.10, 0.1) // c2与c3是等价的
	fmt.Println(c2==c3)
	fmt.Println(c1== complex64(c2))
	fmt.Println(complex128(c1) == c2)  // != , 由于虚数位


	x := real(c2)
	y := imag(c2)
	fmt.Println(x)
	fmt.Println(y)
	
	/*
	
	
	*/
}



