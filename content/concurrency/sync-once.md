---
title: "一次性操作 - sync.Once"
---

# 一次性操作 - sync.Once

sync.Once用来完成一次性操作，比如配置加载，单例对象初始化等。

## 源码分析

sync.Once定义如下：

```go
type Once struct {
	done uint32 // 用来标志操作是否操作
	m    Mutex // 锁，用来第一操作时候，加锁处理
}
```

接下来看剩下的全部代码：

```go
func (o *Once) Do(f func()) {
	if atomic.LoadUint32(&o.done) == 0 {// 原子性加载o.done，若值为1，说明已完成操作，若为0，说明未完成操作
		o.doSlow(f)
	}
}

func (o *Once) doSlow(f func()) {
	o.m.Lock() // 加锁
	defer o.m.Unlock()
	if o.done == 0 { // 再次进行o.done是否等于0判断，因为存在并发调用doSlow的情况
		defer atomic.StoreUint32(&o.done, 1) // 将o.done值设置为1，用来标志操作完成
		f() // 执行操作
	}
}
```