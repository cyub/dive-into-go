---
title: "通道选择器-select"
---

# 通道选择器-select

Go 语言中`select`关键字结构跟`switch`结构类似，但是`select`结构的case语句都是跟通道操作相关的。Go 语言会从`select`结构中已经可读取或可以写入通道对应的case语句中随机选择一个执行，如果所有case语句中的通道都不能可读取或可写入且存在default语句的话，那么会执行default语句。

根据Go 官方语法指南指出select语句执行分为以下几个步骤：

1. For all the cases in the statement, the channel operands of receive operations and the channel and right-hand-side expressions of send statements are evaluated exactly once, in source order, upon entering the "select" statement. The result is a set of channels to receive from or send to, and the corresponding values to send. Any side effects in that evaluation will occur irrespective of which (if any) communication operation is selected to proceed. Expressions on the left-hand side of a RecvStmt with a short variable declaration or assignment are not yet evaluated.

    对于case分支语句中写入通道的右侧表达式都会先执行，执行顺序是按照代码中case分支顺序，由上到下执行。case分支语句中读取通道的左右表达式不会先执行的。

2.  If one or more of the communications can proceed, a single one that can proceed is chosen via a uniform pseudo-random selection. Otherwise, if there is a default case, that case is chosen. If there is no default case, the "select" statement blocks until at least one of the communications can proceed.

    如果有一个或者多个case分支的通道可以通信（读取或写入），那么会随机选择一个case分支执行。否则如果存在default分支，那么执行default分支，若没有default分支，那么select语句会阻塞，直到某一个case分支的通道可以通信。

3. Unless the selected case is the default case, the respective communication operation is executed.

    除非选择的case分支是default分支，否则将执行相应case分支的通道读写操作。
4. If the selected case is a RecvStmt with a short variable declaration or an assignment, the left-hand side expressions are evaluated and the received value (or values) are assigned.
5. The statement list of the selected case is executed.

    执行所选case中的语句。

上面介绍的执行顺序第一步骤，我们可以从下面代码输出结果可以看出来：

```go
func main() {
	ch := make(chan int, 1)
	select {
	case ch <- getVal(1):
		println("recv: ", <-ch)
	case ch <- getVal(2):
		println("recv: ", <-ch)
	}
}

func getVal(n int) int {
	println("getVal: ", n)
	return n
}
```

上面代码输出结果可能如下：

```
getVal:  1
getVal:  2
recv:  2
```

可以看到通道写入的右侧表达式`getVal(1)`和`getVal(2)`都会立马执行，执行顺序跟case语句顺序一样。

接下来我们来看看第二步骤：

```go
func main() {
	ch := make(chan int, 1)
	ch <- 100

	select {
	case i := <-ch:
		println("case1 recv: ", i)
	case i := <-ch:
		println("case2 recv: ", i)
	}
}
```

上面代码中case1 和case2分支的通道都是可以通信状态，那么Go会随机选择一个分支执行，我们执行代码后打印出来的结果可以证明这一点。

我们接下来再看看下面的代码：

```go
func main() {
	ch := make(chan int, 1)
	go func() {
		time.Sleep(time.Second)
		ch <- 100
	}()

	select {
	case i := <-ch:
		println("case1 recv: ", i)
	case i := <-ch:
		println("case2 recv: ", i)
	default:
		println("default case")
	}
}
```

上面代码中case1 和case2语句中的ch是未可以通信状态，由于存在default分支，那么Go会执行default分支，进而打印出`default case`。

如果我们注释掉default分支，我们可以发现select会阻塞，直到1秒之后ch通道是可以通信状态，此时case1或case2中某个分支会执行。