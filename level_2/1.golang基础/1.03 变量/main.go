package main

import (
    "fmt"
)

var s1 string = "abc"
var zero int 
var b1 = true

var m map[string]int  // 声明一个映射（map）变量的语法是 var m map[keyType]valueType
var arr [2]byte   // 数组的长度为 2，元素类型为 byte   byte 是 uint8 的别名，表示一个 8 位无符号整数
var slice []byte  // 声明了一个名为 slice 的切片，切片的元素类型为 byte。与数组不同，切片是动态大小的
var p *int    // 声明了一个名为 p 的指针，指向一个 int 类型的值

var (
	i int = 11
	b2 bool
	s2 = "aaa"
)

// 使用 var 关键字和括号 () 可以同时声明多个变量
var (
	group1 = 2   // group1 是一个 int 类型的变量，默认类型为 int
	group2 byte = 2  // group2 是一个 byte 类型的变量，显式指定类型为 byte
)

func main() {
	fmt.Println(s1)
	fmt.Println(zero)
	fmt.Println(b1)
	fmt.Println(m)  // map[]
	fmt.Println(arr) // [0 0]
	fmt.Println(slice) // []
	fmt.Println(p)  // nil
	fmt.Println(i)
	fmt.Println(b2)
	fmt.Println(group1) //2
	fmt.Println(group2) //2

	m = make(map[string]int, 0) // 这里的map还有指针类型，不能直接添加值，必须用make进行初始化；否则会报空指针错误。 此处初始化一个映射（map）的语句。这里的 make 函数用于创建一个新的映射，并将其赋值给变量 m 
	m["a"] = 1  // map[a:1]
	/*
	在 Go 语言中，单引号和双引号用于表示不同类型的字面量：
		单引号 (')：用于表示字符（rune），即单个 Unicode 字符。例如，'a' 表示字符 a，其类型为 rune（相当于 int32）。
		双引号 (")：用于表示字符串（string），即一系列字符的集合。例如，"a" 表示字符串 a，其类型为 string。
			
	*/
	fmt.Println(m) 

}



