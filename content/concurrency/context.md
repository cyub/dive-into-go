---
title: "上下文 - context"
---

# 上下文 - context

Context是由Golang官方开发的并发控制包，一方面可以用于当请求超时或者取消时候，相关的goroutine马上退出释放资源，另一方面Context本身含义就是上下文，其可以在多个goroutine或者多个处理函数之间传递共享的信息。

创建一个新的context，必须基于一个父context，新的context又可以作为其他context的父context。所有context在一起构造成一个context树。

![context tree](https://static.cyub.vip/images/202008/context-tree.jpg)

<!--more-->

## Context使用示例

Context一大用处就是超时控制。我们先看一个简单用法。

```go
func main() {
	ctx, cancel := context.WithTimeout(context.Background(), 3 * time.Second)
	defer cancel()
	go SlowOperation(ctx)
	go func() {
		for {
			time.Sleep(300 * time.Millisecond)
			fmt.Println("goroutine:", runtime.NumGoroutine())
		}
	}()
	time.Sleep(4 * time.Second)

}

func SlowOperation(ctx context.Context) {
	done := make(chan int, 1)
	go func() { // 模拟慢操作
		dur := time.Duration(rand.Intn(5)+1) * time.Second
		time.Sleep(dur)
		done <- 1
	}()

	select {
	case <-ctx.Done():
		fmt.Println("SlowOperation timeout:", ctx.Err())
	case <-done:
		fmt.Println("Complete work")
	}
}
```

上面代码会不停打印当前groutine数量，可以观察到SlowOperation函数执行超时之后，goroutine数量由4个变成2个，相关goroutetine退出了。源码可以去[go playground](https://play.golang.org/p/fjGJgMwtIl3)查看。

再看一个关于超时处理的例子， 源码可以去[go playground](https://play.golang.org/p/DctV9268FTD)查看：

```go
// 
// 根据github仓库统计信息接口查询某个仓库信息
func QueryFrameworkStats(ctx context.Context, framework string) <-chan string {
	stats := make(chan string)
	go func() {
		repos := "https://api.github.com/repos/" + framework
		req, err := http.NewRequest("GET", repos, nil)
		if err != nil {
			return
		}
		req = req.WithContext(ctx)

		client := &http.Client{}
		resp, err := client.Do(req)
		if err != nil {
			return
		}

		data, err := ioutil.ReadAll(resp.Body)
		if err != nil {
			return
		}
		defer resp.Body.Close()
		stats <- string(data)
	}()

	return stats
}

func main() {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	framework := "gin-gonic/gin"
	select {
	case <-ctx.Done():
		fmt.Println(ctx.Err())
	case statsInfo := <-QueryFrameworkStats(ctx, framework):
		fmt.Println(framework, " fork and start info : ", statsInfo)
	}
}
```


Context另外一个用途就是传递上下文信息。从WithValue方法我们可以创建一个可以储存键值的context


## Context源码分析

### Context接口

首先我们来看下Context接口

```go
type Context interface {
	Deadline() (deadline time.Time, ok bool)
    Done() <-chan struct{}
    Err() error
    Value(key interface{}) interface{}
}
```

Context接口一共包含四个方法：
- Deadline：返回绑定该context任务的执行超时时间，若未设置，则ok等于false
- Done：返回一个只读通道，当绑定该context的任务执行完成并调用cancel方法或者任务执行超时时候，该通道会被关闭
- Err：返回一个错误，如果Done返回的通道未关闭则返回nil,如果context如果被取消，返回`Canceled`错误，如果超时则会返回`DeadlineExceeded`错误
- Value：根据key返回，存储在context中k-v数据

### 实现Context接口的类型

Context一共有4个类型实现了Context接口, 分别是emptyCtx, cancelCtx,timerCtx,valueCtx。每个类型都关联一个创建方法。

![](https://static.cyub.vip/images/202009/context_implement.jpg)



#### emptyCtx

emptyCtx是int类型，**emptyCtx实现了Context接口，是一个空context，只能作为根context**。

```go
type emptyCtx int // 

func (*emptyCtx) Deadline() (deadline time.Time, ok bool) {
	return
}

func (*emptyCtx) Done() <-chan struct{} {
	return nil
}

func (*emptyCtx) Err() error {
	return nil
}

func (*emptyCtx) Value(key interface{}) interface{} {
	return nil
}

func (e *emptyCtx) String() string {
	switch e {
	case background:
		return "context.Background"
	case todo:
		return "context.TODO"
	}
	return "unknown empty Context"
}
```

**Background/TODO**

context包还提供两个函数返回emptyCtx类型。

```go
var (
	background = new(emptyCtx)
	todo       = new(emptyCtx)
)

func Background() Context {
	return background
}

func TODO() Context {
	return todo
}
```

Background用于创建根context，一般用于主函数、初始化和测试中，**我们创建的context一般都是基于Bacground创建的**。**TODO用于当我们不确定使用什么样的context的时候使用**。

#### cancelCtx

`cancelCtx`支持取消操作，取消同时也会对实现了`canceler`接口的子代进行取消操作。我们来看下`cancelCtx`结构体和`cancelceler`接口：

```go
type cancelCtx struct {
	Context
	mu       sync.Mutex
	done     chan struct{}
	children map[canceler]struct{}
	err      error
}

type canceler interface {
	cancel(removeFromParent bool, err error)
	Done() <-chan struct{}
}
```

cancelCtx:

- `Context`变量存储其父context
- `done`变量定义了一个通道，并且只在第一次取消调用才关闭此通道。该通道是惰性创建的
- `children`是一个映射类型，用来存储其子代context中实现的`canceler`，当该context取消时候，会遍历该映射来让子代context进行取消操作
- `err`记录错误信息，默认是nil，仅当第一次cancel调用时候，才会设置。

我们分别来看下cancelCtx实现的Done,Err,cancel方法。

```go
func (c *cancelCtx) Done() <-chan struct{} {
	c.mu.Lock() // 加锁
	if c.done == nil {
    	// done通道惰性创建，只有调用Done方法时候才会创建
		c.done = make(chan struct{})
	}
	d := c.done
	c.mu.Unlock()
	return d
}

func (c *cancelCtx) Err() error {
	c.mu.Lock()
	err := c.err
	c.mu.Unlock()
	return err
}

func (c *cancelCtx) cancel(removeFromParent bool, err error) {
	if err == nil { 
    	// 取消操作时候一定要传递err信息
		panic("context: internal error: missing cancel error")
	}
	c.mu.Lock()
	if c.err != nil { 
    	// 只允许第一次cancel调用操作，下一次进来直接返回
		c.mu.Unlock()
		return
	}
	c.err = err
	if c.done == nil { 
    	// 未先进行Done调用，而先行调用Cancel, 此时done是nil，
    	// 这时候复用全局已关闭的通道
		c.done = closedchan 
	} else {
    	// 关闭Done返回的通道，发送关闭信号
		close(c.done)
	}
    // 子级context依次进行取消操作
	for child := range c.children {
		child.cancel(false, err)
	}
	c.children = nil
	c.mu.Unlock()

	if removeFromParent {
    	// 将当前context从其父级context中children map中移除掉，父级Context与该Context脱钩。
    	// 这样当父级Context进行Cancel操作时候，不会再改Context进行取消操作了。因为再取消也没有意义了，因为该Context已经取消过了
		removeChild(c.Context, c)
	}
}

func removeChild(parent Context, child canceler) {
	p, ok := parentCancelCtx(parent)
	if !ok {
		return
	}
	p.mu.Lock()
	if p.children != nil {
		delete(p.children, child)
	}
	p.mu.Unlock()
}

func parentCancelCtx(parent Context) (*cancelCtx, bool) {
	for {
		switch c := parent.(type) {
		case *cancelCtx:
			return c, true
		case *timerCtx:
			return &c.cancelCtx, true
		case *valueCtx: // 当父级context是不支持cancel操作的ValueCtx类型时候，向上一直查找
			parent = c.Context
		default:
			return nil, false
		}
	}
}
```

注意`parentCancelCtx`找到的节点不一定是就是父context，有可能是其父辈的context。可以参考下面这种图:

![](https://static.cyub.vip/images/202008/context-cancel.jpg)

**WithCancel**

接下来看cancelCtx类型Context的创建。WithCancel会创一个cancelCtx，以及它关联的取消函数。

```go
type CancelFunc func()

func WithCancel(parent Context) (ctx Context, cancel CancelFunc) {
	// 根据父context创建新的cancelCtx类型的context
	c := newCancelCtx(parent)
    // 向上递归找到父辈，并将新context的canceler添加到父辈的映射中
	propagateCancel(parent, &c)
	return &c, func() { c.cancel(true, Canceled) }
}

func newCancelCtx(parent Context) cancelCtx {
	return cancelCtx{Context: parent}
}

func propagateCancel(parent Context, child canceler) {
	if parent.Done() == nil {
    	// parent.Done()返回nil表明父Context不支持取消操作
        // 大部分情况下，该父context已是根context，
        // 该父context是通过context.Background()，或者context.ToDo()创建的
		return
	}
	if p, ok := parentCancelCtx(parent); ok {
		p.mu.Lock()
		if p.err != nil {
        	// 父conext已经取消操作过，
        	// 子context立即进行取消操作，并传递父级的错误信息
			child.cancel(false, p.err)
		} else {
			if p.children == nil {
				p.children = make(map[canceler]struct{})
			}
			p.children[child] = struct{}{} 
            // 将当前context的取消添加到父context中
		}
		p.mu.Unlock()
	} else {
    	// 如果parent是不可取消的，则监控parent和child的Done()通道
		go func() {
			select {
			case <-parent.Done():
				child.cancel(false, parent.Err())
			case <-child.Done():
			}
		}()
	}
}
```

#### timerCtx

timerCtx是基于cancelCtx的context类型，它支持过期取消。

```go
type timerCtx struct {
	cancelCtx
	timer *time.Timer
	deadline time.Time
}

func (c *timerCtx) Deadline() (deadline time.Time, ok bool) {
	return c.deadline, true
}

func (c *timerCtx) String() string {
	return contextName(c.cancelCtx.Context) + ".WithDeadline(" +
		c.deadline.String() + " [" +
		time.Until(c.deadline).String() + "])"
}

func (c *timerCtx) cancel(removeFromParent bool, err error) {
	c.cancelCtx.cancel(false, err)
	if removeFromParent {
    	// 删除与父辈context的关联
		removeChild(c.cancelCtx.Context, c)
	}
	c.mu.Lock()
	if c.timer != nil {
    	// 停止timer并回收
		c.timer.Stop()
		c.timer = nil
	}
	c.mu.Unlock()
}
```

**WithDeadline**

WithDeadline会创建一个timerCtx，以及它关联的取消函数

```go
func WithDeadline(parent Context, d time.Time) (Context, CancelFunc) {
	if cur, ok := parent.Deadline(); ok && cur.Before(d) {
    	// 如果父context过期时间早于当前context过期时间，则创建cancelCtx
		return WithCancel(parent)
	}
	c := &timerCtx{
		cancelCtx: newCancelCtx(parent),
		deadline:  d,
	}
	propagateCancel(parent, c)
	dur := time.Until(d)
	if dur <= 0 {
    	// 如果新创建的timerCtx正好过期了，则取消操作并传递DeadlineExceeded
		c.cancel(true, DeadlineExceeded)
		return c, func() { c.cancel(false, Canceled) }
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.err == nil {
    	// 创建定时器，时间一到执行context取消操作
		c.timer = time.AfterFunc(dur, func() {
			c.cancel(true, DeadlineExceeded)
		})
	}
	return c, func() { c.cancel(true, Canceled) }
}
```

**WithTimeout**

WithTimeout用来创建超时就会取消的context，内部实现就是WithDealine，传递给WithDealine的过期时间就是当前时间加上timeout时间

```go
func WithTimeout(parent Context, timeout time.Duration) (Context, CancelFunc) {
	return WithDeadline(parent, time.Now().Add(timeout))
}
```

#### valueCtx

valueCtx是可以传递共享信息的context。

```go
type valueCtx struct {
	Context
	key, val interface{}
}

func (c *valueCtx) Value(key interface{}) interface{} {
	if c.key == key {
    	// 当前context存在当前的key
		return c.val
	}
    
    // 当前context不存在，则会沿着context树，向上递归查找，直到根context，如果一直未找到，则会返回nil
	return c.Context.Value(key)
}
```

如果当前context不存在该key，则会沿着context树，向上递归查找，直到查找到根context，最后返回nil
![](https://static.cyub.vip/images/202008/context-value.jpg)

**WithValue**

WithValue用来创建valueCtx。如果key是不可以比较的时候，则会发生恐慌。可以比较类型，可以参考[Comparison_operators](https://golang.org/ref/spec#Comparison_operators)。**key应该是不导出变量，防止冲突**。

```go
func WithValue(parent Context, key, val interface{}) Context {
	if key == nil {
		panic("nil key")
	}
	if !reflectlite.TypeOf(key).Comparable() {
		panic("key is not comparable")
	}
	return &valueCtx{parent, key, val}
}
```


## 总结

### 实现Context接口的类型

Context一共有4个类型实现了Context接口, 分别是`emptyCtx`,	`cancelCtx`,`timerCtx`,`valueCtx`。

它们的功能与创建方法如下：

| 类型 | 创建方法 | 功能 |
| --- |----|--- |
| emptyCtx | Background()/TODO() | 用做context树的根节点 |
cancelCtx | WithCancel() | 可取消的context
timerCtx | WithDeadline()/WithTimeout() | 可取消的context，过期或超时会自动取消
valueCtx | WithValue() | 可存储共享信息的context

### Context实现两种递归

Context实现两种方向的递归操作。

递归方向 | 目的
---|---
向下递归 | 当对父Context进去手动取消操作，或超时取消时候，向下递归处理对实现了canceler接口的后代进行取消操作
向上队规 | 当对Context查询Key信息时候，若当前Context没有当前K-V信息时候，则向父辈递归查询，一直到查询到跟节点的emptyCtx，返回nil为止

### Context使用规范
使用Context的是应该准守以下原则来保证在不同包中使用时候的接口一致性，以及能让静态分析工具可以检查context的传播：

1. 不要将Context作为结构体的一个字段存储，相反而应该显示传递Context给每一个需要它的函数，Context应该作为函数的第一个参数，并命名为ctx
2. 不要传递一个nil Context给一个函数，即使该函数能够接受它。如果你不确定使用哪一个Context，那你就传递context.TODO
3. context是并发安全的，相同的Context能够传递给运行在不同goroutine的函数



## 参考资料

- [深入理解Golang之context](https://juejin.im/post/6844904070667321357)
- [Go Concurrency Patterns: Context](https://blog.golang.org/context)
- [Using Goroutines, Channels, Contexts, Timers, WaitGroups and Errgroups](https://medium.com/@ankur_a22/using-goroutines-channels-contexts-timers-waitgroups-and-errgroups-24b6062c1c93)