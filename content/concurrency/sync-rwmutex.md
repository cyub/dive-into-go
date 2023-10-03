---
title: "读写锁 - sync.RWMutex"
---

# 读写锁 - sync.RWMutex

RWMutex是Go语言中内置的一个reader/writer锁，用来解决读者-写者问题（Readers–writers problem）。在任意一时刻，一个RWMutex只能由任意数量的reader持有，或者只能由一个writer持有。

## 读者-写者问题

读者-写者问题（Readers–writers problem）描述了计算机并发处理读写数据遇到的问题，如何保证数据完整性、一致性。解决读者-写者问题需保证对于一份资源操作满足以下下条件：

- 读写互斥
- 写写互斥
- 允许多个读者同时读取

解决读者-写者问题，可以采用`读者优先（readers-preference）`方案或者`写者优先（writers-preference）`方案。

- **读者优先（readers-preference）**：读者优先是读操作优先于写操作，即使写操作提出申请资源，但只要还有读者在读取操作，就还允许其他读者继续读取操作，直到所有读者结束读取，才开始写。读优先可以提供很高的并发处理性能，但是在频繁读取的系统中，会长时间写阻塞，导致写饥饿。

- **写者优先（writers-preference）**：写者优先是写操作优先于读操作，如果有写者提出申请资源，在申请之前已经开始读取操作的可以继续执行读取，但是如果再有读者申请读取操作，则不能够读取，只有在所有的写者写完之后才可以读取。写者优先解决了读者优先造成写饥饿的问题。但是若在频繁写入的系统中，会长时间读阻塞，导致读饥饿。

RWMutex设计采用写者优先方法，保证写操作优先处理。

## 源码分析

下面分析的源码进行精简处理，去掉了race检查功能的代码。

### RWMutex的定义

```go
type RWMutex struct {
	w           Mutex  // 互斥锁
	writerSem   uint32 // writers信号量
	readerSem   uint32 // readers信号量
	readerCount int32  // reader数量
	readerWait  int32  // writer申请锁时候，已经申请到锁的reader的数量
}


const rwmutexMaxReaders = 1 << 30 // 最大reader数，用于反转readerCount
```
### RLock/RUnlock的实现

```go
func (rw *RWMutex) RLock() {
	if atomic.AddInt32(&rw.readerCount, 1) < 0 { // 如果rw.readerCount为负数，说明此时已有一个writer持有锁或者正在申请锁。
		runtime_SemacquireMutex(&rw.readerSem, false, 0) // 此时reader休眠阻塞在readerSem信号上，等待唤醒
	}
}

func (rw *RWMutex) RUnlock() {
	if r := atomic.AddInt32(&rw.readerCount, -1); r < 0 { // r小于0说明此时有等待请求锁的writer
		rw.rUnlockSlow(r)
	}
}

func (rw *RWMutex) rUnlockSlow(r int32) {
	if r+1 == 0 || r+1 == -rwmutexMaxReaders { // RLock之前已经进行了RUnlock操作
		throw("sync: RUnlock of unlocked RWMutex")
	}

	if atomic.AddInt32(&rw.readerWait, -1) == 0 { // 此时是最后一个获取到锁的reader进行RUnlock操作，那么释放writerSem信号，唤醒等待的writer来获取锁。
		runtime_Semrelease(&rw.writerSem, false, 1)
	}
}
```

### Lock/Unlock的实现

```go
func (rw *RWMutex) Lock() {
	rw.w.Lock() // 加互斥锁，阻塞其他writer进行Lock操作，保证写-写互斥。

	// 将rw.readerCount 更改为rw.readerCount - rwmutexMaxReaders，
	// 此时rw.readerCount由一个正数转变成一个负数，这种方式既能保持记录reader数量，又能表明有writer正在请求锁
	r := atomic.AddInt32(&rw.readerCount, -rwmutexMaxReaders) + rwmutexMaxReaders

	if r != 0 && atomic.AddInt32(&rw.readerWait, r) != 0 { // r!=0表明此时有reader持有锁，则当前writer只能阻塞等待，但为了保证写优先，需要readerWait记录当前已获取到锁的读者数量
		runtime_SemacquireMutex(&rw.writerSem, false, 0)
	}
}

func (rw *RWMutex) Unlock() {
	r := atomic.AddInt32(&rw.readerCount, rwmutexMaxReaders)
	if r >= rwmutexMaxReaders { // Lock之前先进行了Unlock操作
		throw("sync: Unlock of unlocked RWMutex")
	}

	for i := 0; i < int(r); i++ { // 释放信号，唤醒阻塞的reader们
		runtime_Semrelease(&rw.readerSem, false, 0)
	}
	rw.w.Unlock() // 是否互锁锁，允许其他writer进行获取锁操作了
}
```

对于`读者优先（readers-preference）`的读写锁，只需要一个`readerCount`记录所有读者，就可以轻易实现。Go中的RWMutex实现的是`写者优先（writers-preference）`的读写锁，那就需要用到`readerWait`来记录写者申请锁时候，已经获取到锁的读者数量。

这样当后续有其他读者继续申请锁时候，可以读取`readerWait`是否大于0，大于0则说明有写者已经申请锁了，按照`写者优先（writers-preference）`原则，该读者需要排到写者之后，但是我们还需要记录这些排在写者后面读者的数量呀，毕竟写着将来释放锁的时候，还得唤醒一个个这些读者。这种情况下既要读取`readerWait`，又要更新排队的读者数量，这是两个操作，无法原子化。RWMutex在实现时候，通过将readerCount转换成负数，一方面表明有写者申请了锁，另一方面readerCount还可以继续记录排队的读者数量，解决刚描述的无法原子化的问题，真是巧妙！


对于`读者优先（readers-preference）`的读写锁，我们可以借助Mutex实现。示例代码如下：

```go
type rwlock struct {
	reader_cnt  int
	reader_lock sync.Mutex
	writer_lock sync.Mutex
}

func NewRWLock() *rwlock {
	return &rwlock{}
}

func (l *rwlock) RLock() {
	l.reader_lock.Lock()
	defer l.reader_lock.Unlock()
	l.reader_cnt++
	if l.reader_cnt == 1 { // first reader
		l.writer_lock.Lock()
	}
}

func (l *rwlock) RUnlock() {
	l.reader_lock.Lock()
	defer l.reader_lock.Unlock()
	l.reader_cnt--
	if l.reader_cnt == 0 { // latest reader
		l.writer_lock.Unlock()
	}
}

func (l *rwlock) Lock() {
	l.writer_lock.Lock()
}

func (l *rwlock) Unlock() {
	l.writer_lock.Unlock()
}
```

上面示例代码中，尽管读者操作的实现上用到互斥锁，但由于它是用完立马就是释放掉，性能不会差太多。

## 三大错误使用场景

### RLock/RUnlock、Lock/Unlock未成对出现

同互斥锁一样，sync.RWMutex的RLock/RUnlock，以及Lock/Unlock总是成对出现的。Lock或RLock多余调用会导致锁没有释放，可能出现死锁，Unlock或RUnlock多余的调用会大导致panic.

```go
func main() {
	var l sync.RWMutex
	l.Lock()
	l.Unlock()
	l.Unlock() // fatal error: sync: Unlock of unlocked RWMutex
}
```

对于Lock/Unlock未成对出现所有可能情况如下：

- 如果只有Lock情况

	如果有一个 goroutine 只执行 Lock 操作而不执行 Unlock 操作，那么其他的 goroutine 就会一直被阻塞（拿不到锁），随着越来越多的阻塞的 goroutine 越来越多，整个系统最终会崩溃。

- 如果只有Unlock情况

	- 如果其他 goroutine 持有锁，锁将被释放。
	- 如果锁处于空闲状态（unoccupied state），它会panic。


### 复制sync.RWMutex作为函数值传递

同Mutex一样，RWMutex也是不能复制使用的，考虑下面场景代码：

```go
func main() {
	var l sync.RWMutex
	l.Lock()
	foo(l)
	l.Lock()
	l.Unlock()
}

func foo(l sync.RWMutex) {
	l.Unlock()
}
```

上面场景代码中本意先使用l.Lock()进行上锁操作，然后调用foo(l)释放该锁，最后再次上锁和释放锁。但这种操作是错误的，会导致死锁。foo()函数接收的参数是变量l的一个副本，该副本把之前l变量的锁状态（锁状态指的是writerSem，readerCount等字段信息）也复制了一遍，此时副本的锁状态是上锁状态的，所以foo函数中是可以进行释放锁操作的，但释放的并不是最开始的那个锁。

我们可以使用`go vet`命令检测复制锁情况：

```bash
vagrant@vagrant:~$ go vet main.go
# command-line-arguments
./main.go:8:6: call of foo copies lock value: sync.RWMutex
./main.go:13:12: foo passes lock by value: sync.RWMutex
```

解决上面问题可以使用指针传递:

```go
func foo(l *sync.RWMutex) {
	l.Unlock()
}
```

### 不可重入导致死锁

可重入锁(ReentrantLock)指的一个线程中可以多次获取同一把锁，换到Go语言场景就是一个Goroutine中，Mutex和RWMutex可以连续Lock操作，而不会导致死锁。同互斥体Mutex一样，RWMutex也是不可重入锁，不支持重入。

```go
func main() {
	var l sync.RWMutex
	l.Lock()
	foo(&l) // foo中尝试重入锁，会导致死锁
	l.Unlock()
}

func foo(l *sync.RWMutex) {
	l.Lock()
	l.Unlock()
}
```

下面是读锁和写锁重入时候导致的死锁：

```go
func main() {
	var l sync.RWMutex
	l.RLock()
	foo(&l)
	l.RUnlock()
}

func foo(l *sync.RWMutex) {
	l.Lock()
	l.Unlock()
}
```
上面代码中写锁重入时候，需要读锁先释放，而读锁释放又依赖写锁，这样就形成了死循环，导致死锁。

## 进一步阅读

- [Readers–writers problem](https://en.wikipedia.org/wiki/Readers%E2%80%93writers_problem)
- [sync.RWMutex: Solving readers-writers problems](https://medium.com/golangspec/sync-rwmutex-ca6c6c3208a0)
- [Use sync.Mutex, sync.RWMutex to lock share data for race condition](https://cloudolife.com/2020/04/18/Programming-Language/Golang-Go/Synchronization/Use-sync-Mutex-sync-RWMutex-to-lock-share-data-for-race-condition/)
