package m3

import (
    "fmt"
)


func main() {

	// var c1 complex64
	// c1 = 1.10 + 0.1i

	// c2 = c3 =default is complex128
	c2 := 1.10 + 0.1i
	c3 := complex(1.10, 0.1) // c2与c3是等价的
	fmt.Println(c2==c3)
	// fmt.Println(c1== complex64(c2))
	//fmt.Println(complex128(c1) == c2)  // != , 由于虚数位

	// x := real(c2)
	// y := imag(c2)
	// fmt.Println(x)
	// fmt.Println(y)
	
	/*
	
	
	*/
}



