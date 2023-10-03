---
title: "内存模型 - memroy model"
---

# 内存模型

Go语言中的内存模型规定了多个goroutine读取变量时候，变量的可见性情况。注意本章节的内存模型并不是内存对象分配、管理、回收的模型，准确的说这里面的内存模型是内存一致性模型。

## Happens Before原则

Happens Before原则的定义是如果一个操作e1先于操作e2发生，那么我们就说e1 `happens before` e2，也可以描述成e2 `happens after` e2，此时e1操作的变量结果对e2都是可见的。如果e1操作既不先于e2发生又不晚于e2发生，我们说e1操作与e2操作并发发生。

Happens Before具有传导性：如果操作e1 `happens before` 操作e2，e3 `happends before` e1，那么e3一定也 `happends before` e2。

由于存在指令重排和多核CPU并发访问情况，我们代码中变量顺序和实际方法顺序并不总是一致的。考虑下面一种情况：

```go
a := 1
b := 2
c := a + 1
```

上面代码中是先给变量a赋值，然后给变量b赋值，最后给编程c赋值。但是在底层实现指令时候，可能发生指令重排：变量b赋值在前，变量a赋值在后，最后变量c赋值。对于依赖于a变量的c变量的赋值，不管怎样指令重排，Go语言都会保证变量a赋值操作 `happends before` c变量赋值操作。

上面代码运行是运行在同一goroutine中，Go语言时能够保证`happends before`原则的，实现正确的变量可见性。但对于多个goroutine共享数据时候，Go语言是无法保证`Happens Before`原则的，这时候就需要我们采用锁、通道等同步手段来保证数据一致性。考虑下面场景：

```go
 var a, b int 

 // goroutine A
 go func() {
     a = 1
     b = 2
 }()

 // goroutine B
 go func() {
     if b == 2 {
        print(a)
     }
 }()
```

当执行goroutine B打印变量a时并不一定打印出来1，有可能打印出来的是0。这是因为goroutine A中可能存在指令重排，先将b变量赋值2，若这时候接着执行goroutine B那么就会打印出来0

## Go语言中保证的 happens-before 场景

Go语言提供了某些场景下面的`happens-before`原则保证。详细内容可以阅读文章末尾进一步阅读中提供的Go官方资料。

### 初始化

当进行包初始化或程序初始化时候，会保证下面的`happens-before`:


- 如果包p导入了包q，则q的init函数的`happens before`在任何p的开始之前。
- 所有init函数happens before 入口函数main.main

### goroutine

与goroutine有关的`happens-before`保证场景有：

- goroutine的创建`happens before`其执行
- goroutine的完成不保证`happens-before`任何代码

对于第一条场景，考虑下面代码：

```go
var a string

func f() {
	print(a) // 3
}

func hello() {
	a = "hello, world" // 1
	go f() // 2
}
```

根据goroutine的创建`happens before`其执行，我们知道操作2 `happens before` 操作3。又因为在同一goroutine中，先书写的代码一定会`happens before`后面代码（注意：即使发生了执行重排，其并不会影响`happends before`），操作1 `happends before` 操作3，那么操作1 `happends before` 操作3，所以最终一定会打印出`hello, world`，不可能出现打印空字符串情况。

注意goroutine f()的执行完成，并不能保证hello()返回之前，其有可能是在hello返回之后执行完成。

对于第二条场景，考虑下面代码：

```go
var a string

func hello() {
	go func() { a = "hello" }() // 1
	print(a) // 2
}
```
由于goroutine的完成不保证`happens-before`任何代码，那么操作1和操作2无法确定谁先执行，谁后执行，那么最终可能打印出`hello`，也有可能打印出空字符串。


### 通道通信

- 对于缓冲通道，向通道发送数据`happens-before`从通道接收到数据

```go
var c = make(chan int, 10)
var a string

func f() {
	a = "hello, world" // 4
	c <- 0 // 5
}

func main() {
	go f() // 1
	<-c // 2
	print(a) // 3
}
```

c是一个缓存通道，操作5 `happens before` 操作2，所以最终会打印`hello, world`

- 对于无缓冲通道，从通道接收数据`happens-before`向通道发送数据

```go
var c = make(chan int)
var a string

func f() {
	a = "hello, world" // 4
	<-c // 5
}

func main() {
	go f() // 1
	c <- 0 // 2
	print(a) // 3
}
```

c是无缓存通道，操作5 `happens before` 操作2，所以最终会打印`hello, world`。


对于上面通道的两种`happens before`场景下打印数据结果，我们都可以通过通道特性得出相关结果。

### 锁

- 对于任意的`sync.Mutex`或者`sync.RWMutex`，n次Unlock()调用`happens before` m次Lock()调用，其中n<m

```go
var l sync.Mutex
var a string

func f() {
	a = "hello, world"
	l.Unlock() // 2
}

func main() {
	l.Lock() // 1
	go f()
	l.Lock() // 3
	print(a)
}
```

操作2 `happends before` 操作3，所以最终一定会打印出来hello,world。

对于这种情况，我们可以从锁的机制方面理解，操作3一定会阻塞到操作为2完成释放锁，那么最终一定会打印`hello, world`。

## 进一步阅读

- [The Go Memory Model](https://golang.org/ref/mem)