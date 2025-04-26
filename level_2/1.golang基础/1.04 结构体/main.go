package main

import (
    "fmt"
)

type A struct {
    a string
}

type B struct {
    A
    b string
}

type C struct {
    A
    B
    a string
    b string
    c string
}

type D struct {
	A    // A 被嵌入，因此 D 直接拥有 A 的字段和方法
    da A 
	db B

}

func main() {
	a := A{a: "a"}
	b := B{A:a, b: "b"}
	c := C{A:a, B: b, a:"ca", b:"cb", c:"cc"}
	d := D{A:a, da: a, db: b}
	fmt.Println(a)     // {a}
	fmt.Println(b)     // {{a} b}
	fmt.Println(c)    // { {a}  {{a} b} ca cb cc } 
	fmt.Println(d.da) // {a}
	fmt.Println(d.a)  // a   由于 A 的字段 a 是私有的（以小写字母开头），在结构体 D 中，d.a 代表的是嵌入的 A 结构体的字段 a
    

}



