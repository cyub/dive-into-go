---
title: "等待组 - sync.WaitGroup"
---

# 等待组 - sync.WaitGroup

## 源码分析

```go
type WaitGroup struct {
    noCopy noCopy // waitgroup是不能够拷贝复制的，是通过go vet来检测实现
    
	/* 
	waitgroup使用一个int64来计数：高32位，用来add计数，低32位用来记录waiter数量。
	若要原子性更新int64就必须保证该int64对齐系数是8，即64位对齐。
	对于64位系统，直接使用一个int64类型字段就能保证原子性要求，但对32位系统就不行了。

	所以实现的时候并没有直接一个int64， 而是使用[3]int32数组，若[0]int32地址恰好是8对齐的，那就waitgroup int64 = [0]int32 + [1]int32，
	否则一定是4对齐的， 故[0]int32不用，恰好错开了4字节，此时[1]int32一定是8对齐的。此时waitgroup int64 = [1]int32 + [2]int32
	通过这个技巧恰好满足32位和64位系统下int64都能原子性操作
	*/
	state1 [3]uint32 // waitgroup对齐系数是4
}

func (wg *WaitGroup) state() (statep *uint64, semap *uint32) {
	// 当state1是8对齐的，则返回低8字节(statep)用来计数，即state1[0]是add计数，state1[1]是waiter计数
	if uintptr(unsafe.Pointer(&wg.state1))%8 == 0 {
		return (*uint64)(unsafe.Pointer(&wg.state1)), &wg.state1[2]
	} else {
		// 反之，则返回高8字节用来计数，即state1[1]是add计数，state1[2]是waiter计数
		return (*uint64)(unsafe.Pointer(&wg.state1[1])), &wg.state1[0]
	}
}

// Add方法用来更新add计数器。即将原来计数值加上delta，delta可以为负值
// waitgroup的Done方法本质上就是Add(-1)
// Add更新之后的计数器值不能小于0。当计数器值等于0时候，会释放信号，所有调用Wait方法而阻塞的Goroutine不再阻塞（释放的信号量=waiter计数）
func (wg *WaitGroup) Add(delta int) {
	statep, semap := wg.state()
	if race.Enabled { // 竞态检查，忽略不看
		_ = *statep // trigger nil deref early
		if delta < 0 {
			// Synchronize decrements with Wait.
			race.ReleaseMerge(unsafe.Pointer(wg))
		}
		race.Disable()
		defer race.Enable()
	}
	state := atomic.AddUint64(statep, uint64(delta)<<32) // delta左移32位，然后原子性更新statep值并返回更新后的statep值
	v := int32(state >> 32) // state高位的4字节是add计数，赋值给v
	w := uint32(state) // state低位的4字节是waiter计数，赋值给w
	
	if v < 0 { // add计数不能为负值。
		panic("sync: negative WaitGroup counter")
    }
    
	// Add方法与Wait方法不能并发调用
	if w != 0 && delta > 0 && v == int32(delta) {
		panic("sync: WaitGroup misuse: Add called concurrently with Wait")
	}
	if v > 0 || w == 0 { // add计数大于0，或者waiter计数等于0，直接返回不执行后面逻辑。
		return
    }
    
	// statep指向state1字段，其指向的值和state进行比较，如果不一样，说明存在并发调用了Add和Wait方法
	// 此时v = 0, w > 0，这个时候waitgroup的add计数和waiter计数不能再更改了。
	// *statep != state情况举例：假定当前groutine是g1，执行到此处时, 
	// 恰好另外一个groutine g2并发调用了Wait方法，
	// 那么waitgroup的state1字段会更新，而g1中w的值还是g2调用Wait方法之前的waiter数，
	// 这会导致总有一个g永远得不到释放信号，从而造成g泄漏。所以此处要进行panic判断
	if *statep != state {
		panic("sync: WaitGroup misuse: Add called concurrently with Wait")
    }
    
	*statep = 0 // 重置计数器为0
	for ; w != 0; w-- { // 有w个waiter，则释放出w个信号
		runtime_Semrelease(semap, false, 0)
	}
}

// Done() == Add(-1)
func (wg *WaitGroup) Done() {
	wg.Add(-1)
}

// Wait会阻塞当前goroutine，直到add计数器值为0
func (wg *WaitGroup) Wait() {
	statep, semap := wg.state()
	for {
		state := atomic.LoadUint64(statep)
		v := int32(state >> 32)
		w := uint32(state)
		// 使用for + cas进制，原子性更新waiter计数
		if atomic.CompareAndSwapUint64(statep, state, state+1) {
			// 更新成功后，开始获取信号，未获取到信号的话则当前g一直阻塞
			runtime_Semacquire(semap)
			if *statep != 0 {
				panic("sync: WaitGroup is reused before previous Wait has returned")
			}
			return
		}
	}
}
```

### 总结

- waitgroup是不能值传递的
- Add方法的传值可以是负数，但加上该传值之后的waitgroup计数器值不能是负值
- Done方法实际上调用的是Add(-1)
- Add方法和Wait方法不能并发调用
- Wait方法可以多次调用，调用此方法的goroutine会阻塞，一直阻塞到waitgroup计数器值变为0。