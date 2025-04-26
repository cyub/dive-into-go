---
title: "Go编译流程"
---

# 编译流程

Go语言是一门静态编译型语言，源代码需要通过编译器转换成目标平台的机器码才能运行。本文将介绍编译器的编译流程，包括编译器的六个阶段、Go编译器的自举机制以及源码编译的相关知识，帮助读者理解Go语言的编译流程。

## 编译的六阶段

编译器的核心任务是**将高级语言（high-level language）转换为目标平台的机器码（machine code）**。编译器的整个编译流程可分为两部分：分析部分（Analysis part）以及合成部分（Synthesis part）。这两部分也称为**编译前端**和**编译后端**。每部分又可以细分为三个阶段，简单来说整个编译流程大致可细分为六个阶段：

- 词法分析（Lexical analysis）[^1]
- 语法分析（Syntax analysis）[^2]
- 语义分析（Semantic analysis）
- 中间码生成（Intermediate code generator）
- 代码优化（Code optimizer）
- 机器代码生成（Code generator）

### 词法分析

词法分析是编译的第一步，编译器扫描源代码，从左到右逐行将字符序列分组，生成**词法单元（Tokens）**。这些词法单元包括标识符（identifier）、关键字（reserved word）、运算符（operator）和常量（constant）等。例如，对于代码 `c = a + b * 5`，词法分析会生成以下Tokens：

Lexemes | Tokens
--- | ---
c | 标志符
= | 赋值符号
a | 标志符
\+ | 加法符号
b | 标志符
\* | 乘法符号
5 | 数字

### 语法分析

词法分析阶段接收词法分析阶段生成的Tokens序列，然后基于特定编程语言的规则生成抽象语法树。

#### 抽象语法树

抽象语法树（Abstract Syntax Tree），简称AST，是源代码语法结构的一种抽象表示。它以树状的形式表现编程语言的语法结构，树上的每个节点都表示源代码中的一种结构。以`(a+b)*c`为例，最终生成的抽象语法树如下：

![](https://static.cyub.vip/images/202104/ast.png)

### 语义分析

语义分析阶段用来检查代码的语义一致性。它使用前一阶段的语法树以及符号表来验证给定的源代码在语义上是一致的。它还检查代码是否传达了适当的含义。例如语义分析会检查`a+b`中的`a`和`b`是否为可以进行`+`操作的类型。

在Go语言中，语义分析会检查接口实现、类型推导（如 := 短变量声明）以及包级作用域的符号解析。例如，Go编译器会确保 `var x int; x = "string" `这样的代码被标记为类型错误。

### 中间码生成

中间码是一种介于高级语言和机器码之间的表示形式，具有跨平台特性。。使用中间码易于跨平台转换为特定类型目标机器代码。

Go编译器会生成一种平台无关的中间表示（IR），便于后续优化和目标代码生成。Go编辑器使用的是一种名为SSA(Static Single Assignment)的中间表示形式。SSA的每个变量只被赋值一次，便于优化器进行常量传播，死代码消除等操作。

### 代码优化

代码优化阶段主要是改进中间代码，生成更高效的代码，优化包括但不限于：
- 删除冗余代码（死代码消除）
- 常量折叠
- -通过循环展开来进行循环优化
- 内联函数
- 边界检查消除（BCE, Bound Check Elimination）

Go编译器在优化阶段执行**逃逸分析（Escape Analysis）**，确定变量是否需要分配到堆上，从而减少内存分配开销。此外，Go还会进行内联优化，将短小的函数直接嵌入调用处，减少函数调用开销。

### 机器码生成

机器码生成是编译器工作的最后阶段。此阶段会基于中间码生成汇编代码，汇编器根据汇编代码生成目标文件，目标文件经过链接器处理最终生成可执行文件。

Go编译器使用 `Plan9` 汇编作为统一汇编语言，屏蔽了不同架构的细节，生成的汇编代码随后通过汇编器（如 `go tool asm`）和链接器（如 `go tool link`）转换为可执行文件。

## Go 编译流程

上面介绍了通用编译器工作的整个流程，Go语言编译器整体遵循这个流程：

{{< figure src="https://static.cyub.vip/images/202104/go-compile.png" width="500px" class="text-center" title="Go语言编译流程">}}

Go 编译器在编译的具体实现时候， 在六个阶段基础上进一步细化。根据Go官方博客介绍[^3]，Go编译具体实现包括下面八个阶段：

阶段名称 | 主要功能 | 相关包
--- | --- | ---
解析	| 词法分析和语法分析，构建语法树，包含位置信息用于错误和调试。| cmd/compile/internal/syntax
类型检查	| 使用语法树的AST进行类型检查，基于go/types的端口。| cmd/compile/internal/types2
IR构建（Noding）| 将语法和类型转换为IR和类型，使用统一IR支持导入/导出和内联。| cmd/compile/internal/types, cmd/compile/internal/ir, cmd/compile/internal/noder
中端优化	| 包括死代码消除、去虚拟化、内联和逃逸分析等优化。	| cmd/compile/internal/inline, cmd/compile/internal/devirtualize, cmd/compile/internal/escape
遍历（Walk）|	分解复杂语句，引入临时变量，简化构造（如将switch转换为跳转表）。| cmd/compile/internal/walk
通用SSA	 | 将IR转换为SSA形式，应用内建函数，执行机器无关的优化（如死代码消除）。	| cmd/compile/internal/ssa, cmd/compile/internal/ssagen
生成机器码	| 将SSA降低为机器特定代码，优化（如寄存器分配），生成包含反射和调试数据的目标文件。	| cmd/compile/internal/ssa, cmd/internal/obj
导出	| 写入导出数据文件，包括类型信息、IR和逃逸分析摘要。

我们执行`go build`命令时候，带上`-n`选项可以观察编译流程所执行所有的命令：


{{< highlight shell "linenos=table,hl_lines=5 11 24" >}}
#
# command-line-arguments
#

mkdir -p $WORK/b001/
cat >$WORK/b001/importcfg << 'EOF' # internal
# import config
packagefile runtime=/usr/lib/go/pkg/linux_amd64/runtime.a
EOF
cd /home/vagrant/dive-into-go
/usr/lib/go/pkg/tool/linux_amd64/compile -o $WORK/b001/_pkg_.a -trimpath "$WORK/b001=>" -p main -complete -buildid aJhlsTb17ElgWQeF76b5/aJhlsTb17ElgWQeF76b5 -goversion go1.14.13 -D _/home/vagrant/dive-into-go -importcfg $WORK/b001/importcfg -pack ./empty_string.go
/usr/lib/go/pkg/tool/linux_amd64/buildid -w $WORK/b001/_pkg_.a # internal
cat >$WORK/b001/importcfg.link << 'EOF' # internal
packagefile command-line-arguments=$WORK/b001/_pkg_.a
packagefile runtime=/usr/lib/go/pkg/linux_amd64/runtime.a
packagefile internal/bytealg=/usr/lib/go/pkg/linux_amd64/internal/bytealg.a
packagefile internal/cpu=/usr/lib/go/pkg/linux_amd64/internal/cpu.a
packagefile runtime/internal/atomic=/usr/lib/go/pkg/linux_amd64/runtime/internal/atomic.a
packagefile runtime/internal/math=/usr/lib/go/pkg/linux_amd64/runtime/internal/math.a
packagefile runtime/internal/sys=/usr/lib/go/pkg/linux_amd64/runtime/internal/sys.a
EOF
mkdir -p $WORK/b001/exe/
cd .
/usr/lib/go/pkg/tool/linux_amd64/link -o $WORK/b001/exe/a.out -importcfg $WORK/b001/importcfg.link -buildmode=exe -buildid=FoylCipvV-SPkhyi2PJs/aJhlsTb17ElgWQeF76b5/aJhlsTb17ElgWQeF76b5/FoylCipvV-SPkhyi2PJs -extld=gcc $WORK/b001/_pkg_.a
/usr/lib/go/pkg/tool/linux_amd64/buildid -w $WORK/b001/exe/a.out # internal
mv $WORK/b001/exe/a.out empty_string

{{< / highlight >}}

从上面命令输出的内容可以看到：

1. Go编译器首先会创建一个任务输出临时目录（`mkdir -p $WORK/b001/`）。b001是root task的工作目录，每次构建都是由一系列task完成，它们构成 **[action graph](https://github.com/golang/go/blob/master/src/cmd/go/internal/work/action.go)**

2. 接着将`empty_string.go`中依赖的包: `/usr/lib/go/pkg/linux_amd64/runtime.a` 写入到`importcfg`中

3. 接着会使用`compile`命令，并指定`importcfg`文件，将主程序`empty_string.go`编译成`_pkg.a`文件（`/usr/lib/go/pkg/tool/linux_amd64/compile -o $WORK/b001/_pkg_.a -trimpath "$WORK/b001=>" -p main -complete -buildid aJhlsTb17ElgWQeF76b5/aJhlsTb17ElgWQeF76b5 -goversion go1.14.13 -D _/home/vagrant/dive-into-go -importcfg $WORK/b001/importcfg -pack ./empty_string.go`）。

4. 程序依赖的包都写到`importcfg.link`这个文件中，Go编译器连接阶段中链接器会使用该文件，找到所有依赖的包文件，将其连接到程序中（`/usr/lib/go/pkg/tool/linux_amd64/link -o $WORK/b001/exe/a.out -importcfg $WORK/b001/importcfg.link -buildmode=exe -buildid=FoylCipvV-SPkhyi2PJs/aJhlsTb17ElgWQeF76b5/aJhlsTb17ElgWQeF76b5/FoylCipvV-SPkhyi2PJs -extld=gcc $WORK/b001/_pkg_.a`）。接着会将`buildid`写入二进制文件中（
 `/usr/lib/go/pkg/tool/linux_amd64/buildid -w $WORK/b001/exe/a.out`）。

5. 将编译成功的二进制文件移动到输出目录中（`mv $WORK/b001/exe/a.out empty_string`）。

上面4中我们可以看到`buildid`写入过程。在 Go 的构建过程中，`buildid` 用于缓存管理。Go 的构建系统会根据`buildid`来判断是否需要重新构建某个包或模块。如果缓存中已经存在具有相同`buildid`的构建结果，构建系统可以重用缓存，从而加快构建速度。`buildid`也可用于唯一标识每次构建的二进制文件。我们可以通过下面命令查看二进制文件的`buildid`：

```bash
go tool buildid ./example_binary
```


### 完整编译流程输出

为了详细查看`go build`整个详细过程，我们可以使用`go build -work -a -p 1 -x empty_string.go`命令来观察整个过程，它比`go build -n`提供了更详细的信息:

- -work选项指示编译器编译完成后保留编译临时工作目录
- -a选项强制编译所有包。我们使用`go build -n`时候，只看到main包编译过程，这是因为其他包已经编译过了，不会再编译。我们可以使用这个选项强制编译所有包。
- -p选项用来指定编译过程中线程数，这里指定为1，是为观察编译的顺序性
- -x选项可以指定编译参数

完整编译输出内容摘要如下：

```bash
vagrant@vagrant:~/dive-into-go$ go build -work -a -p 1 -x empty_string.go
WORK=/tmp/go-build871888098
mkdir -p $WORK/b004/
cat >$WORK/b004/go_asm.h << 'EOF' # internal
EOF
cd /usr/lib/go/src/internal/cpu
/usr/lib/go/pkg/tool/linux_amd64/asm -trimpath "$WORK/b004=>" -I $WORK/b004/ -I /usr/lib/go/pkg/include -D GOOS_linux -D GOARCH_amd64 -gensymabis -o $WORK/b004/symabis ./cpu_x86.s
cat >$WORK/b004/importcfg << 'EOF' # internal
# import config
EOF
/usr/lib/go/pkg/tool/linux_amd64/compile -o $WORK/b004/_pkg_.a -trimpath "$WORK/b004=>" -p internal/cpu -std -+ -buildid 8F_1bll3rU7d1mo74DFt/8F_1bll3rU7d1mo74DFt -goversion go1.14.13 -symabis $WORK/b004/symabis -D "" -importcfg $WORK/b004/importcfg -pack -asmhdr $WORK/b004/go_asm.h ./cpu.go ./cpu_amd64.go ./cpu_x86.go
/usr/lib/go/pkg/tool/linux_amd64/asm -trimpath "$WORK/b004=>" -I $WORK/b004/ -I /usr/lib/go/pkg/include -D GOOS_linux -D GOARCH_amd64 -o $WORK/b004/cpu_x86.o ./cpu_x86.s
/usr/lib/go/pkg/tool/linux_amd64/pack r $WORK/b004/_pkg_.a $WORK/b004/cpu_x86.o # internal
/usr/lib/go/pkg/tool/linux_amd64/buildid -w $WORK/b004/_pkg_.a # internal
cp $WORK/b004/_pkg_.a /home/vagrant/.cache/go-build/e2/e20b6a590621cff911735ea491492b992b429df9b0b579155aecbfdffdf7ec74-d # internal
mkdir -p $WORK/b003/
cat >$WORK/b003/go_asm.h << 'EOF' # internal
EOF
cd /usr/lib/go/src/internal/bytealg
/usr/lib/go/pkg/tool/linux_amd64/asm -trimpath "$WORK/b003=>" -I $WORK/b003/ -I /usr/lib/go/pkg/include -D GOOS_linux -D GOARCH_amd64 -gensymabis -o $WORK/b003/symabis ./compare_amd64.s ./count_amd64.s ./equal_amd64.s ./index_amd64.s ./indexbyte_amd64.s
cat >$WORK/b003/importcfg << 'EOF' # internal
# import config
packagefile internal/cpu=$WORK/b004/_pkg_.a
EOF
/usr/lib/go/pkg/tool/linux_amd64/compile -o $WORK/b003/_pkg_.a -trimpath "$WORK/b003=>" -p internal/bytealg -std -+ -buildid I0-Z7SEGCaTIz2BZXZCm/I0-Z7SEGCaTIz2BZXZCm -goversion go1.14.13 -symabis $WORK/b003/symabis -D "" -importcfg $WORK/b003/importcfg -pack -asmhdr $WORK/b003/go_asm.h ./bytealg.go ./compare_native.go ./count_native.go ./equal_generic.go ./equal_native.go ./index_amd64.go ./index_native.go ./indexbyte_native.go
/usr/lib/go/pkg/tool/linux_amd64/asm -trimpath "$WORK/b003=>" -I $WORK/b003/ -I /usr/lib/go/pkg/include -D GOOS_linux -D GOARCH_amd64 -o $WORK/b003/compare_amd64.o ./compare_amd64.s
/usr/lib/go/pkg/tool/linux_amd64/asm -trimpath "$WORK/b003=>" -I $WORK/b003/ -I /usr/lib/go/pkg/include -D GOOS_linux -D GOARCH_amd64 -o $WORK/b003/count_amd64.o ./count_amd64.s
/usr/lib/go/pkg/tool/linux_amd64/asm -trimpath "$WORK/b003=>" -I $WORK/b003/ -I /usr/lib/go/pkg/include -D GOOS_linux -D GOARCH_amd64 -o $WORK/b003/equal_amd64.o ./equal_amd64.s
/usr/lib/go/pkg/tool/linux_amd64/asm -trimpath "$WORK/b003=>" -I $WORK/b003/ -I /usr/lib/go/pkg/include -D GOOS_linux -D GOARCH_amd64 -o $WORK/b003/index_amd64.o ./index_amd64.s
/usr/lib/go/pkg/tool/linux_amd64/asm -trimpath "$WORK/b003=>" -I $WORK/b003/ -I /usr/lib/go/pkg/include -D GOOS_linux -D GOARCH_amd64 -o $WORK/b003/indexbyte_amd64.o ./indexbyte_amd64.s
/usr/lib/go/pkg/tool/linux_amd64/pack r $WORK/b003/_pkg_.a $WORK/b003/compare_amd64.o $WORK/b003/count_amd64.o $WORK/b003/equal_amd64.o $WORK/b003/index_amd64.o $WORK/b003/indexbyte_amd64.o # internal
/usr/lib/go/pkg/tool/linux_amd64/buildid -w $WORK/b003/_pkg_.a # internal
cp $WORK/b003/_pkg_.a /home/vagrant/.cache/go-build/42/42c362e050cb454a893b15620b72fbb75879ac0a1fdd13762323eec247798a43-d # internal
mkdir -p $WORK/b006/
cat >$WORK/b006/go_asm.h << 'EOF' # internal
EOF
cd /usr/lib/go/src/runtime/internal/atomic
/usr/lib/go/pkg/tool/linux_amd64/asm -trimpath "$WORK/b006=>" -I $WORK/b006/ -I /usr/lib/go/pkg/include -D GOOS_linux -D GOARCH_amd64 -gensymabis -o $WORK/b006/symabis ./asm_amd64.s
cat >$WORK/b006/importcfg << 'EOF' # internal
# import config
EOF
/usr/lib/go/pkg/tool/linux_amd64/compile -o $WORK/b006/_pkg_.a -trimpath "$WORK/b006=>" -p runtime/internal/atomic -std -+ -buildid uI0THQvFtr7yRsGPOXDw/uI0THQvFtr7yRsGPOXDw -goversion go1.14.13 -symabis $WORK/b006/symabis -D "" -importcfg $WORK/b006/importcfg -pack -asmhdr $WORK/b006/go_asm.h ./atomic_amd64.go ./stubs.go
/usr/lib/go/pkg/tool/linux_amd64/asm -trimpath "$WORK/b006=>" -I $WORK/b006/ -I /usr/lib/go/pkg/include -D GOOS_linux -D GOARCH_amd64 -o $WORK/b006/asm_amd64.o ./asm_amd64.s
/usr/lib/go/pkg/tool/linux_amd64/pack r $WORK/b006/_pkg_.a $WORK/b006/asm_amd64.o # internal
/usr/lib/go/pkg/tool/linux_amd64/buildid -w $WORK/b006/_pkg_.a # internal
cp $WORK/b006/_pkg_.a /home/vagrant/.cache/go-build/6b/6b2c5449e17d9b0e34bfe37a77dc16b9675ffb657fbe9277a1067fa8ca5179ab-d # internal
mkdir -p $WORK/b008/
cat >$WORK/b008/importcfg << 'EOF' # internal
# import config
EOF
cd /usr/lib/go/src/runtime/internal/sys
/usr/lib/go/pkg/tool/linux_amd64/compile -o $WORK/b008/_pkg_.a -trimpath "$WORK/b008=>" -p runtime/internal/sys -std -+ -complete -buildid AZJ761JYi_ToDiYI_5UA/AZJ761JYi_ToDiYI_5UA -goversion go1.14.13 -D "" -importcfg $WORK/b008/importcfg -pack ./arch.go ./arch_amd64.go ./intrinsics.go ./intrinsics_common.go ./stubs.go ./sys.go ./zgoarch_amd64.go ./zgoos_linux.go ./zversion.go
/usr/lib/go/pkg/tool/linux_amd64/buildid -w $WORK/b008/_pkg_.a # internal
cp $WORK/b008/_pkg_.a /home/vagrant/.cache/go-build/f7/f706a1321f01a45857a441e80fd50709a700a9d304543d534a953827021222c1-d # internal
mkdir -p $WORK/b007/
cat >$WORK/b007/importcfg << 'EOF' # internal
# import config
packagefile runtime/internal/sys=$WORK/b008/_pkg_.a
EOF
cd /usr/lib/go/src/runtime/internal/math
/usr/lib/go/pkg/tool/linux_amd64/compile -o $WORK/b007/_pkg_.a -trimpath "$WORK/b007=>" -p runtime/internal/math -std -+ -complete -buildid NxqylyDav-hCzDju1Kr1/NxqylyDav-hCzDju1Kr1 -goversion go1.14.13 -D "" -importcfg $WORK/b007/importcfg -pack ./math.go
/usr/lib/go/pkg/tool/linux_amd64/buildid -w $WORK/b007/_pkg_.a # internal
cp $WORK/b007/_pkg_.a /home/vagrant/.cache/go-build/f6/f6dcba7ea64d64182a26bcda498c1888786213b0b5560d9bde92cfff323be7df-d # internal
...
```

从上面可以看到编译器工作目录是`/tmp/go-build871888098`，cd进去之后，我们可以看到多个子目录，每个子目录都是用编译子task使用，存放的都是编译后的包：

```bash
vagrant@vagrant:/tmp/go-build871888098$ ls
b001  b002  b003  b004  b006  b007  b008
```

其中`b001`目录用于main包编译，是任务图的root节点。`b001`目录下面的`importcfg.link`文件存放都是程序所有依赖的包地址，它们指向的都是b002,b003...这些目录下的`_pkg_.a`文件。

## Go 编译器

Go 编译器，英文名称是`Go compiler`，简称gc。gc是Go命令的一部分，包含在每次Go发行版本中。Go命令是由Go语言编写的，而Go语言编写的程序需要Go命令来编译，也就是自己编译自己，这就出现了“先有鸡还是先有蛋”的问题。Go gc如何做到自己编译自己呢，要解答这个问题，我们先来了解下自举概念。

### 自举

自举，英文名称是Bootstrapping，这个词来自自西方的一句谚语：“pull oneself up by one's bootstraps”，字面意思就是“拽着鞋带把自己拉起来”。自举一词在编译器领域指的是用待编译的程序的编程语言来编写其编译器。自举步骤一般如下，假定要编译的程序语言是A：

1. 先使用程序语言B实现A的编译器，假定为compiler0
2. 接着使用A语言实现A的编译器，之后使用步骤1中的compiler0编译器编译，得到编译器compiler1
3. 最后我们就可以使用compiler1来编译A语言写的程序，这样实现了自己编译自己

通过自举方式，解决了上面说的“先有鸡还是先有蛋”的问题，实现了自己编译自己。

Go语言最开始是使用C语言实现的编译器，go1.4是最后一个C语言实现的编译器版本。自go1.5开始，Go实现了自举功能，go1.5的gc是由go语言实现的，它是由go1.4版本的C语言实现编译器编译出来的，详细内容可以参见Go 自举的设计文档：[Go 1.3+ Compiler Overhaul](https://docs.google.com/document/d/1P3BLR31VA8cvLJLfMibSuTdwTuF7WWLux71CYD0eeD8/edit)。

除了 Go 语言实现的 gc 外，Go 官方还维护了一个基于 gcc 实现的 Go 编译器 [gccgo](https://go.dev/doc/install/gccgo)。与 gc 相比，gccgo 编译速度较慢，但支持更强大的优化，因此由 gccgo 构建的 CPU 密集型(CPU-bound)程序通常会运行得更快。此外 gccgo 比 gc 支持更多的操作系统，如果交叉编译gc不支持的操作系统，可以考虑使用gccgo。

### 源码安装

Go 源码安装需要系统先有一个`bootstrap toolchain`，该toolchain可以从下面三种方式获取：

- 从官网下载Go二进制发行包
- 使用gccgo工具编译
- 基于Go1.4版本的工具链

#### 从官网下载发行包

第一种方式是从Go发行包中获取Go二进制应用，比如要源码编译go1.14.13，我们可以去[官网](https://golang.org/dl/)下载已经编译好的go1.13，设置好`GOROOT_BOOTSTRAP`环境变量，就可以源码编译了。

```bash
wget https://golang.org/dl/go1.13.15.linux-amd64.tar.gz
tar xzvf go1.13.15.linux-amd64.tar.gz
mv go go1.13.15
export GOROOT_BOOTSTRAP=/tmp/go1.13.15 # 设置GOROOT_BOOTSTRAP环境变量指向bootstrap toolchain的目录

cd /tmp
git clone -b go1.14.13 https://go.googlesource.com/go go1.14.13
cd go1.14.13/src
./make.bash
```

#### 使用gccgo工具编译

第二种方式是使用gccgo来编译：

```bash
sudo apt-get install gccgo-5
sudo update-alternatives --set go /usr/bin/go-5
export GOROOT_BOOTSTRAP=/usr

cd /tmp
git clone -b go1.14.13 https://go.googlesource.com/go go1.14.13
cd go1.14.13/src
./make.bash
```

### 基于go1.14版本工具链编译

第三种方式是先编译出go1.4版本，然后使用go1.4版本去编译其他版本。

```bash
cd /tmp
git clone -b go1.4.3 https://go.googlesource.com/go go1.4
cd go1.4/src
./all.bash # go1.4版本是c语言实现的编译器
export GOROOT_BOOTSTRAP=/tmp/go1.4


git clone -b go1.14.13 https://go.googlesource.com/go go1.14.13
cd go1.14.13/src
./all.bash
```

## 进一步阅读

- [Go官方博客：Introduction to the Go compiler](https://go.dev/src/cmd/compile/README)
- [Go: Overview of the Compiler](https://medium.com/a-journey-with-go/go-overview-of-the-compiler-4e5a153ca889)
- [How a Go Program Compiles down to Machine Code](https://getstream.io/blog/how-a-go-program-compiles-down-to-machine-code/)
- [编译原理](https://draveness.me/golang/docs/part1-prerequisite/ch02-compile/golang-compile-intro/)
- [Compiler appearance - Phases of Compiler](http://www.en.w3ki.com/compiler_design/compiler_design_phases_of_compiler.html)
- [Introduction to the Go compiler](https://github.com/golang/go/tree/master/src/cmd/compile)
- [How “go build” Works](https://maori.geek.nz/how-go-build-works-750bb2ba6d8e)
- [Go 1.3+ Compiler Overhaul](https://docs.google.com/document/d/1P3BLR31VA8cvLJLfMibSuTdwTuF7WWLux71CYD0eeD8/edit)
- [Installing Go from source](https://golang.org/doc/install/source)
- [GcToolchainTricks](https://github.com/golang/go/wiki/GcToolchainTricks)
- [Bootstrapping Go](https://weeraman.com/bootstrapping-go-ee5633ce3329)
- [Gccgo in GCC 4.7.1](https://go.dev/blog/gccgo-in-gcc-471)

[^1]: [Lexical analysis](https://en.wikipedia.org/wiki/Lexical_analysis)
[^2]: [Syntax analysis](https://en.wikipedia.org/wiki/Parsing)
[^3]: https://go.dev/src/cmd/compile/README