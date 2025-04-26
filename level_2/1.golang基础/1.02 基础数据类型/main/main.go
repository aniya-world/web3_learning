package main

import (
    "fmt"
)

 // go mod init  github.com/aniya-world/study1.02

func main() {
	// 1.2.1.1 整型
	// 十六进制
	var a uint8 = 0xF
	var b uint8 = 0xf

	// 八进制
	var c uint8 = 017
	var d uint8 = 0o17
	var e uint8 = 0O17 

	// 二进制
	var f uint8 = 0b1111
	var g uint8 = 0B1111

	// 十进制
	var h uint8 = 15

    fmt.Println(a==b)
	fmt.Println(b==c)
	fmt.Println(c==d)
	fmt.Println(d==e)
	fmt.Println(e==f)
	fmt.Println(f==g)
	fmt.Println(g==h)
	/*
	
	true
	true
	true
	true
	true
	true
	true
	
	*/
}



