---
title: "空结构体"
---

# 空结构体

空结构体指的是没有任何字段的结构体。

## 大小与内存地址

空结构体占用的内存空间大小为零字节，并且它们的地址可能相等也可能不等。当发生内存逃逸时候，它们的地址是相等的，都指向`runtime.zerobase`。

```go
// empty_struct.go
type Empty struct{}

//go:linkname zerobase runtime.zerobase
var zerobase uintptr // 使用go:linkname编译指令，将zerobase变量指向runtime.zerobase

func main() {
	a := Empty{}
	b := struct{}{}

	fmt.Println(unsafe.Sizeof(a) == 0) // true
	fmt.Println(unsafe.Sizeof(b) == 0) // true
	fmt.Printf("%p\n", &a)             // 0x590d00
	fmt.Printf("%p\n", &b)             // 0x590d00
	fmt.Printf("%p\n", &zerobase)      // 0x590d00

	c := new(Empty)
	d := new(Empty)
	fmt.Sprint(c, d) // 目的是让变量c和d发生逃逸
	println(c) // 0x590d00
	println(d) // 0x590d00
	fmt.Println(c == d) // true

	e := new(Empty)
	f := new(Empty)
	println(e)          // 0xc00008ef47
	println(f)          // 0xc00008ef47
	fmt.Println(e == f) // flase
}
```

从上面代码输出可以看到`a`, `b`, `zerobase`这三个变量的地址都是一样的，最终指向的都是全局变量`runtime.zerobase`([runtime/malloc.go](https://github.com/golang/go/blob/go1.14.13/src/runtime/malloc.go#L827))。

```go
// base address for all 0-byte allocations
var zerobase uintptr
```

我们可以通过下面方法再次来验证一下`runtime.zerobase`变量的地址是不是也是`0x590d00`：

```bash
go build -o empty_struct empty_struct.go
go tool nm ./empty_struct | grep 590d00
# 或者
objdump -t empty_struct | grep 590d00
```

执行上面命令输出以下的内容：

```
590d00 D runtime.zerobase
# 或者
0000000000590d00 g     O .noptrbss	0000000000000008 runtime.zerobase
```

从上面输出的内容可以看到`runtime.zerobase`的地址也是`0x590d00`。


接下来我们看看变量逃逸的情况：

```
 go run -gcflags="-m -l" empty_struct.go
# command-line-arguments
./empty_struct.go:15:2: moved to heap: a
./empty_struct.go:16:2: moved to heap: b
./empty_struct.go:18:13: ... argument does not escape
./empty_struct.go:18:31: unsafe.Sizeof(a) == 0 escapes to heap
./empty_struct.go:19:13: ... argument does not escape
./empty_struct.go:19:31: unsafe.Sizeof(b) == 0 escapes to heap
./empty_struct.go:20:12: ... argument does not escape
./empty_struct.go:21:12: ... argument does not escape
./empty_struct.go:22:12: ... argument does not escape
./empty_struct.go:24:10: new(Empty) escapes to heap
./empty_struct.go:25:10: new(Empty) escapes to heap
./empty_struct.go:26:12: ... argument does not escape
./empty_struct.go:29:13: ... argument does not escape
./empty_struct.go:29:16: c == d escapes to heap
./empty_struct.go:31:10: new(Empty) does not escape
./empty_struct.go:32:10: new(Empty) does not escape
./empty_struct.go:35:13: ... argument does not escape
./empty_struct.go:35:16: e == f escapes to heap
```

可以看到变量`c`和`d`逃逸到堆上，它们打印出来的都是`0x591d00`，且两者进行相等比较时候返回`true`。而变量`e`和`f`打印出来的都是`0xc00008ef47`，但两者进行相等比较时候却返回`false`。这因为Go有意为之的，当空结构体变量未发生逃逸时候，指向该变量的指针是不等的，当空结构体变量发生逃逸之后，指向该变量是相等的。这也就是[Go官方语法指南](https://go.dev/ref/spec)所说的：

> Pointers to distinct zero-size variables may or may not be equal

```eval_rst
.. image:: http://static.cyub.vip/images/202201/go-compare-operators.png
    :alt: Go比较操作符
    :width: 800px
    :align: center
```

## 当一个结构体嵌入空结构体时，占用空间怎么计算？

空结构体本身不占用空间，但是作为某结构体内嵌字段时候，有可能是占用空间的：

- 当空结构体是该结构体唯一的字段时，该结构体是不占用空间的，空结构体自然也不占用空间
- 当空结构体作为第一个字段或者中间字段时候，是不占用空间的
- 当空结构体作为最后一个字段时候，是占用空间的，大小跟其前一个字段保持一致

```go
type s1 struct {
	a struct{}
}

type s2 struct {
	_ struct{}
}

type s3 struct {
	a struct{}
	b byte
}

type s4 struct {
	a struct{}
	b int64
}

type s5 struct {
	a byte
	b struct{}
	c int64
}

type s6 struct {
	a byte
	b struct{}
}

type s7 struct {
	a int64
	b struct{}
}

type s8 struct {
	a struct{}
	b struct{}
}

func main() {
	fmt.Println(unsafe.Sizeof(s1{})) // 0
	fmt.Println(unsafe.Sizeof(s2{})) // 0
	fmt.Println(unsafe.Sizeof(s3{})) // 1
	fmt.Println(unsafe.Sizeof(s4{})) // 8
	fmt.Println(unsafe.Sizeof(s5{})) // 16
	fmt.Println(unsafe.Sizeof(s6{})) // 2
	fmt.Println(unsafe.Sizeof(s7{})) // 16
	fmt.Println(unsafe.Sizeof(s8{})) // 0
}
```

当空结构体作为数组、切片的元素时候：

```go
var a [10]int
fmt.Println(unsafe.Sizeof(a)) // 80

var b [10]struct{}
fmt.Println(unsafe.Sizeof(b)) // 0

var c = make([]struct{}, 10)
fmt.Println(unsafe.Sizeof(c)) // 24，即slice header的大小
```

## 用途

由于空结构体占用的空间大小为零，我们可以利用这个特性，完成一些功能，却不需要占用额外空间。

### 阻止`unkeyed`方式初始化结构体

```go
type MustKeydStruct struct {
	Name string
	Age  int
	_    struct{}
}

func main() {
	persion := MustKeydStruct{Name: "hello", Age: 10}
	fmt.Println(persion)
	persion2 := MustKeydStruct{"hello", 10} //编译失败，提示： too few values in MustKeydStruct{...}
	fmt.Println(persion2)
}
```

### 实现集合数据结构

集合数据结构我们可以使用map来实现：只关心key，不必关心value，我们就可以值设置为空结构体类型变量（或者底层类型是空结构体的变量）。

```go
package main

import (
	"fmt"
)

type Set struct {
	items map[interface{}]emptyItem
}

type emptyItem struct{}

var itemExists = emptyItem{}

func NewSet() *Set {
	set := &Set{items: make(map[interface{}]emptyItem)}
	return set
}

// 添加元素到集合
func (set *Set) Add(item interface{}) {
	set.items[item] = itemExists
}

// 从集合中删除元素
func (set *Set) Remove(item interface{}) {
	delete(set.items, item)

}

// 判断元素是否存在集合中
func (set *Set) Contains(item interface{}) bool {
	_, contains := set.items[item]
	return contains
}

// 返回集合大小
func (set *Set) Size() int {
	return len(set.items)
}

func main() {
	set := NewSet()
	set.Add("hello")
	set.Add("world")
	fmt.Println(set.Contains("hello"))
	fmt.Println(set.Contains("Hello"))
	fmt.Println(set.Size())
}
```

### 作为通道的信号传输

使用通道时候，有时候我们只关心是否有数据从通道内传输出来，而不关心数据内容，这时候通道数据相当于一个信号，比如我们实现退出时候。下面例子是基于通道实现的信号量。

```go
// empty struct
var empty = struct{}{}

// Semaphore is empty type chan
type Semaphore chan struct{}

// P used to acquire n resources
func (s Semaphore) P(n int) {
	for i := 0; i < n; i++ {
		s <- empty
	}
}

// V used to release n resouces
func (s Semaphore) V(n int) {
	for i := 0; i < n; i++ {
		<-s
	}
}

// Lock used to lock resource
func (s Semaphore) Lock() {
	s.P(1)
}

// Unlock used to unlock resource
func (s Semaphore) Unlock() {
	s.V(1)
}

// NewSemaphore return semaphore
func NewSemaphore(N int) Semaphore {
	return make(Semaphore, N)
}
```

## 进一步阅读

- [The empty struct](https://dave.cheney.net/2014/03/25/the-empty-struct)