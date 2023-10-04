---
title: "nil类型"
---

# nil

在探究 `nil` 之前，我们先看看零值的概念。

## 零值

**零值(zero value)**[^1] 指的是当声明变量且未显示初始化时，Go语言会自动给变量赋予一个默认初始值。对于值类型变量来说不同值类型，有不同的零值，比如整数型零值是 `0`，字符串类型是 `""`，布尔类型是 `false`。对于引用类型变量其零值都是 `nil`。

类型 | 零值
--- | ---
数值类型 | 0
字符串 | ""
布尔类型| false
指针类型 | nil
通道 | nil
函数 | nil
接口 | nil
映射 | nil
切片 | nil
结构体 | 每个结构体字段对应类型的零值
自定义类型 | 其底层类型的对应的零值

从零值的定义，可以看出Go语言引入 `nil` 概念，是为了将其作为引用类型变量的零值而存在。

## nil

`nil` 是Go语言中的一个变量，是预先声明的标识符，用来作为引用类型变量的零值。

```go
// nil is a predeclared identifier representing the zero value for a
// pointer, channel, func, interface, map, or slice type.
var nil Type // Type must be a pointer, channel, func, interface, map, or slice type
```

`nil` 不能通过:=方式赋值给一个变量，下面代码是编译不通过的：

```go
a := nil
```

上面代码编译不通过是因为Go语言是无法通过 `nil` 自动推断出a的类型，而Go语言是强类型的，每个变量都必须明确其类型。将 `nil` 赋值一个变量是可以的：

```go
var a chan int
a = nil

b := make([]int, 5)
b = nil
```

### 与nil进行比较

#### nil 与 nil比较

`nil` 是不能和 `nil` 比较的：

```go
func main() {
	fmt.Println(nil == nil) // 报错：invalid operation: nil == nil (operator == not defined on nil)
}
```

#### nil 与 指针类型变量、通道、切片、函数、映射比较

`nil` 是可以和指针类型变量，通道、切片、函数、映射比较的。

1. 对于指针类型变量，只有其未指向任何对象时候，才能等于 `nil`：

```go
func main() {
	var p *int
	println(p == nil) // true
	a := 100
	p = &a
	println(p == nil) // false
}
```

2. 对于通道、切片、映射只有 `var t T` 或者手动赋值为nil时候(`t = nil`)，才能等于nil:

```go
func main() {
	// 通道
	var ch chan int
	println(ch == nil) // true
	ch = make(chan int, 0)
	println(ch == nil) // false

	ch1 := make(chan int, 0)
	println(ch1 == nil) // false
	ch1 = nil
	println(ch1 == nil) // true

	// 切片
	var s []int // 此时s是nil slice
	println(s == nil) // true
	s = make([]int, 0, 0) // 此时s是empty slice
	println(s == nil) // false

	// 映射
	var m map[int]int // 此时m是nil map
	println(m == nil) // true
	m = make(map[int]int, 0)
	println(m == nil) // false

	// 函数
	var fn func()
	println(fn == nil)
	fn = func() {
	}
	println(fn == nil)
}
```

从上面可以看到，通过make函数初始化的变量都不等于 `nil`。

#### nil 与 接口比较

接口类型变量包含两个基础属性：`Type` 和 `Value`，`Type` 指的是接口类型变量的底层类型，`Value` 指的是接口类型变量的底层值。**接口类型变量是可以比较的**。**当它们具有相同的底层类型，且相等的底层值时候，或者两者都为nil时候，这两个接口值是相等的**。

当 `nil` 与接口比较时候，需要接口的 `Type` 和 `Value`都是 `nil` 时候，两者才相等：

```go
func main() {
	var p *int
	var i interface{}                   // (T=nil, V=nil)
	println(p == nil)                   // true
	println(i == nil)                   // true
	var pi interface{} = interface{}(p) // (T=*int, V= nil)
	println(pi == nil)                  // false
	println(pi == i)                    // fasle
	println(p == i)                     // false。跟上面强制转换p一样。当变量和接口比较时候，会隐式将其转换成接口

	var a interface{} = nil // (T=nil, V=nil)
	println(a == nil) // true
	var a2 interface{} = (*interface{})(nil) // (T=*interface{}, V=nil)
	println(a2 == nil) // false
	var a3 interface{} = (interface{})(nil) // (T=nil, V=nil)
	println(a3 == nil) // true
}
```

`nil` 和接口比较最容易出错的场景是使用error接口时候。Go官方文档举了一个例子 **[Why is my nil error value not equal to nil?](https://golang.org/doc/faq#nil_error)**:

```go
type MyError int
func (e *MyError) Error() string {
    return "errCode " + string(int)
}

func returnError() error {
	var p *MyError = nil
	if bad() { // 出现错误时候，返回MyError
		p = &MyError(401)
	}
	// println(p == nil) // 输出true
	return p
}

func checkError(err error) {
	if err == nil {
		println("nil")
		return
	}
	println("not nil")
}

err := returnError() // 假定returnsError函数中bad()返回false
println(err == nil) // false
checkError(err) // 输出not nil
```

我们可以看到上面代码中 `checkError` 函数输出的并不是 `nil`，而是 `not nil`。这是因为接口类型变量 `err` 的底层类型是 `(T=*MyError, V=nil)`，不再是 `(T=nil, V=nil)`。解决办法是当需返回 `nil` 时候，直接返回 `nil`。

```go
func returnError() error {
	if bad() { // 出现错误时候，返回MyError
		return &MyError(401)
	}
	return p
}
```

### 几个值为nil的特别变量

#### nil通道

通道类型变量的零值是 `nil`，对于等于 `nil` 的通道称为 `nil通道`。当从 `nil通道` 读取或写入数据时候，会发生永久性阻塞，若关闭则会发生恐慌。`nil通道` 存在的意义可以参考 **[Why are there nil channels in Go?](https://medium.com/justforfunc/why-are-there-nil-channels-in-go-9877cc0b2308)**

#### nil切片

对 `nil切片` 进行读写操作时候会发生恐慌。但对 `nil切片` 进行 `append` 操作时候是可以的，这是因为Go语言对append操作做了特殊处理。

```go
var s []int
s[0] = 1 // panic: runtime error: index out of range [0] with length 0
println(s[0]) // panic: runtime error: index out of range [0] with length 0
s = append(s, 100) // ok
```

#### nil映射

我们可以对 `nil映射` 进行读取和删除操作，当进行读取操作时候会返回映射的零值。当进行写操作时候会发生恐慌。

```go
func main() {
	var m map[int]int
	println(m[100]) // print 0
	delete(m, 1)
	m[100] = 100 // panic: assignment to entry in nil map
}
```

#### nil接收者

值为 `nil` 的变量可以作为函数的接收者：

```go
const defaultPath = "/usr/bin/"

type Config struct {
	path string
}

func (c *Config) Path() string {
	if c == nil {
		return defaultPath
	}
	return c.path
}

func main() {
	var c1 *Config
	var c2 = &Config{
		path: "/usr/local/bin/",
	}
	fmt.Println(c1.Path(), c2.Path())
}
```

#### nil函数

`nil函数` 可以用来处理默认值情况：

```go
func NewServer(logger function) {
	if logger == nil {
		logger = log.Printf  // default
	}
	logger.DoSomething...
}
```

## 参考资料

- [Golang 零值、空值与空结构](https://juejin.cn/post/6895231755091968013)
- [Why are there nil channels in Go?](https://medium.com/justforfunc/why-are-there-nil-channels-in-go-9877cc0b2308)

[^1]:[Go官方语法指南：零值的定义](https://go.dev/ref/spec#The_zero_value)