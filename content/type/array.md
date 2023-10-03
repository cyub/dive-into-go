---
title: "数组"
---

# 数组

数组是Go语言中常见的数据结构，相比切片，数组我们使用的比较少。

## 初始化

Go语言数组有两个声明初始化方式，一个需要显示指明数组大小，另一个使用`...`由编译器在编译阶段推断出来：

```go
arr1 := [3]int{1, 2, 3} // 使用[n]T方式
arr2 := [...]int{1, 2, 3} // 使用[...]T方式
arr3 := [3]int{2: 3} // 使用[n]T方式
arr4 := [...]int{2: 3} // 使用[...]T方式
```

```eval_rst
.. hint:: 上面代码中arr3和arr4的初始化方式，是指定数组索引对应的值。这种方式并不常见。
```
## 可比较性

数组大小是数组类型的一部分，只有数组大小和数组元素类型一样的数组才能够进行比较。

```go

func main() {
	var a1  [3]int
	var a2  [3]int
	var a3  [5]int
	fmt.Println(a1 == a2) // 输出true
	fmt.Println(a1 == a3) // 不能够比较，会报编译错误： invalid operation: a1 == a3 (mismatched types [3]int and [5]int)
}
```

## 值类型

Go语言中数组是一个值类型，将一个数组作为函数参数传递是拷贝原数组形成一个新数组传递，在函数里面对数组做任何更改都不会影响原数组：

```go
func passArr(arr [3]int) {
	arr[0] = arr[0] * 100
}

func main() {
	myArr := [3]int{1, 3, 5}
	passArr(myArr)
	fmt.Println(myArr[0]) // 输出1
}
```

## 空间局部性与时间局部性

CPU访问数据时候，趋于访问同一片内存区域的数据，这个称为局部性原理（principle of locality）。局部性原理可以为分为空间局部性（Spatial Locality）和时间局部性（Temporal Locality）。

- 空间局部性

    指的是如果一个位置的数据被访问，那么它周围的数据也有可能被访问到。

- 时间局部性

    指的是如果一个位置的数据被访问到，那么它下一次还是很有可能被访问到。所以我们可以把最近访问的数据缓存起来，内存淘汰算法LRU就是基于这个原理。

我们知道数组内存空间是连续分配的，比如对于[3][5]int类型数组其内存空间分配使用如下图所示：

```eval_rst
.. image:: https://static.cyub.vip/images/202104/array_memory_alloc.png
    :alt: 二位数组访问
    :width: 400px
    :align: center
```

推而广之，对于[m][n]T类型的数组中某一个元素内存地址的计算公式是：

```go
// 数组元素的内存地址 = 第一个数组元素的内存地址 + 该元素跨过了多少行 * 元素类型大小 + 该元素在当前行的位置 * 元素类型大小
address(arr[x][y]) = address(arr[0][0]) + x * n * sizeof(T) + y * sizeof(T)
 = address(arr[0][0]) + (x * n + y) * sizeof(T)
```

下面我们根据上面公式来访问一个数组，下面代码中使用到了`uintptr`和`unsafe.Pointer`，如果不太了解的话可以看本书的[指针](pointer.md)那一章节：

```go
package main

import (
	"fmt"
	"unsafe"
)

func main() {
	arr := [2][3]int{{1, 2, 3}, {4, 5, 6}}
	for i := 0; i < 2; i++ {
		for j := 0; j < 3; j++ {
			addr := uintptr(unsafe.Pointer(&arr[0][0])) + uintptr(i*3*8) + uintptr(j*8) // 地址
			fmt.Printf("arr[%d][%d]: 地址 = 0x%x，值 = %d\n", i, j, addr, *(*int)(unsafe.Pointer(uintptr(unsafe.Pointer(&arr[0][0])) + uintptr(i*3*8) + uintptr(j*8))))
		}
	}
}
```

上面代码运行结果如下：

```
arr[0][0]: 地址 = 0xc000068ef0，值 = 1
arr[0][1]: 地址 = 0xc000068ef8，值 = 2
arr[0][2]: 地址 = 0xc000068f00，值 = 3
arr[1][0]: 地址 = 0xc000068f08，值 = 4
arr[1][1]: 地址 = 0xc000068f10，值 = 5
arr[1][2]: 地址 = 0xc000068f18，值 = 6
```

### 空间局部性示例

对于数组的访问，我们可以一行行访问，也可以一列列访问，根据上面分析我们可以得出**一行行访问可以有很好的空间局部性，有更好的执行效率**的结论。因为一行行访问时，下一次访问的就是当前元素挨着的元素，而一列列访问则是需要跨过数组列数个元素：

```eval_rst
.. image:: https://static.cyub.vip/images/202104/multi_dimen_array.png
    :alt: 二位数组访问
    :width: 400px
    :align: center
```

最后我们来进行下基准测试验证一下：

```go
func BenchmarkAccessArrayByRow(b *testing.B) {
	var myArr [3][5]int
	b.ReportAllocs()
	b.ResetTimer()
	for k := 0; k < b.N; k++ {
		for i := 0; i < 3; i++ {
			for j := 0; j < 5; j++ {
				myArr[i][j] = i*i + j*j
			}
		}
	}
}

func BenchmarkAccessArrayByCol(b *testing.B) {
	var myArr [3][5]int
	b.ReportAllocs()
	b.ResetTimer()
	for k := 0; k < b.N; k++ {
		for i := 0; i < 5; i++ {
			for j := 0; j < 3; j++ {
				myArr[j][i] = i*i + j*j
			}
		}
	}
}
```

本人电脑中基准测试结果如下：

```
goos: linux
goarch: amd64
BenchmarkAccessArrayByRow 	121336255	        10.3 ns/op	       0 B/op	       0 allocs/op
BenchmarkAccessArrayByCol 	82772149	        13.2 ns/op	       0 B/op	       0 allocs/op
PASS
```

从上面结果可以看出来，我们可以发现按行访问（10.3 ns/op）快于按列访问（13.2 ns/op）验证我们的结论。

## 如何实现随机访问数组的全部元素？

这里将介绍两种实现方法。这两种实现方法都是Go语言底层使用到的算法。

第一种方法用在Go调度器部分。GMP调度模型中，当M关联的P的本地队列中没有可以执行的G时候，M会从其他P的本地可运行G队列中偷取G，所有P存储一个全局切片中，为了随机性选择P来偷取，这就需要随机的访问数组。该算法具体叫什么，未找到相关文档。由于该算法实现上使用到素数和取模运算，姑且称之素数取模随机法。

第二种方法使用算法`Fisher–Yates shuffle`，Go语言用它来随机性处理通道选择器select中case语句。

### 素数取模随机法

该算法实现逻辑是：对于一个数组[n]T，随机的从小于n的素数集合中，选择一个素数，假定是p，接着从数组0到n-1位置中随机选择一个位置开始，假定是m，那么此时`(m + p)%n = i`位置处的数组元素就是我们要访问的第一个元素。第二次要访问的元素是`(上一次位置+p)%n`处元素，这里面就是`(i+p)%n`，以此类推，访问n次就可以访问完全部数组元素。

举个具体例子来说明，比如对于[8]int数组a，其素数集合是{1, 3, 5, 7}。假定选择的素数是5，从位置1开始。

- 第一次访问元素是 (1 + 5)%8 = 6处元素，即a[6]
- 第二次访问元素是 (6 + 5)%8 = 3处元素，即a[3]
- 第三次访问元素是 (3 + 5)%8 = 0处元素，即a[0]
- 第四次访问元素是 (0 + 5)%8 = 5处元素，即a[5]
- 第五次访问元素是 (5 + 5)%8 = 2处元素，即a[2]
- 第六次访问元素是 (2 + 5)%8 = 7处元素，即a[7]
- 第七次访问元素是 (7 + 5)%8 = 4处元素，即a[4]
- 第八次访问元素是 (4 + 5)%8 = 1处元素，即a[1]

从上面例子可以看出来访问8次即可遍历完所有数组元素，由于素数和开始位置是随机的，那么访问也能做到随机性。

该算法实现如下，代码来自Go源码[runtime/proc.go](https://github.com/golang/go/blob/go1.14.13/src/runtime/proc.go#L5403-L5451)：

```go
package main

import (
	"fmt"
	"math/rand"
)

type randomOrder struct {
	count    uint32
	coprimes []uint32
}

type randomEnum struct {
	i     uint32
	count uint32
	pos   uint32
	inc   uint32
}

func (ord *randomOrder) reset(count uint32) {
	ord.count = count
	ord.coprimes = ord.coprimes[:0]
	for i := uint32(1); i <= count; i++ { // 初始化素数集合
		if gcd(i, count) == 1 {
			ord.coprimes = append(ord.coprimes, i)
		}
	}
}

func (ord *randomOrder) start(i uint32) randomEnum {
	return randomEnum{
		count: ord.count,
		pos:   i % ord.count,
		inc:   ord.coprimes[i%uint32(len(ord.coprimes))],
	}
}

func (enum *randomEnum) done() bool {
	return enum.i == enum.count
}

func (enum *randomEnum) next() {
	enum.i++
	enum.pos = (enum.pos + enum.inc) % enum.count
}

func (enum *randomEnum) position() uint32 {
	return enum.pos
}

func gcd(a, b uint32) uint32 { // 辗转相除法取最大公约数
	for b != 0 {
		a, b = b, a%b
	}
	return a
}

func main() {
	arr := [8]int{1, 2, 3, 4, 5, 6, 7, 8}
	var order randomOrder
	order.reset(uint32(len(arr)))

	fmt.Println("====第一次随机遍历====")
	for enum := order.start(rand.Uint32()); !enum.done(); enum.next() {
		fmt.Println(arr[enum.position()])
	}

	fmt.Println("====第二次随机遍历====")
	for enum := order.start(rand.Uint32()); !enum.done(); enum.next() {
		fmt.Println(arr[enum.position()])
	}
}
```

### Fisher–Yates shuffle

## 进一步阅读

- [Locality of reference](https://en.wikipedia.org/wiki/Locality_of_reference)
- [Fisher–Yates_shuffle](https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle#The_modern_algorithm)