---
title: "Go编译流程"
---

# 编译流程

Go语言是一门编译型语言，程序运行时需要先编译成相应平台的可执行文件。在介绍Go语言编译流程之前，我们来了解下编译器编译整个流程。

## 编译六阶段

编译器工作目的是完成从高级语言（high-level langue）到机器码（machine code）的输出。整个编译流程可分为两大部分，每个部分可以细分为3个阶段。两大部分别是分析部分（Analysis part）以及合成部分（Synthesis part），这两大部分也称为编译前端和编译后端。编译六阶段如下：

- 词法分析（Lexical analysis）
- 语法分析（Syntax analysis）
- 语义分析（Semantic analysis）
- 中间码生成（Intermediate code generator）
- 代码优化（Code optimizer）
- 机器代码生成（Code generator）

### 词法分析

词法分析最终生成的是Tokens。词法分析时编译器扫描源代码，从当前行最左端开始到最右端，然后将扫描到的字符进行分组标记。编译器会将扫描到的词法单位（Lexemes）归类到常量、保留字、运算符等标记（Tokens）中。我们以`c = a+b*5`为例:

Lexemes | Tokens
--- | ---
c | identifier
= | assignment symbol
a | identifier
\+ | + (addition symbol)
b | identifier
\* | * (multiplication symbol)
5 | 5 (number)

### 语法分析

词法分析阶段接收上一阶段生成的Tokens序列，基于特定编程语言的规则生成抽象语法树（Abstract Syntax Tree）。

#### 抽象语法树

抽象语法树（Abstract Syntax Tree），简称AST，是源代码语法结构的一种抽象表示。它以树状的形式表现编程语言的语法结构，树上的每个节点都表示源代码中的一种结构。

以`(a+b)*c`为例，最终生成的抽象语法树如下：

![](https://static.cyub.vip/images/202104/ast.png)

### 语义分析阶段

语义分析阶段用来检查代码的语义一致性。它使用前一阶段的语法树以及符号表来验证给定的源代码在语义上是一致的。它还检查代码是否传达了适当的含义。


### 中间码生成阶段

中间代码介是于高级语言和机器语言之间，具有跨平台特性。使用中间代码可以易于跨平台转换为特定类型目标机器代码。

### 代码优化阶段

代码优化阶段主要是改进中间代码，删除不必要的代码，以调整代码序列以生成速度更快和空间更少的中间代码。

### 机器码生成阶段

机器码生成阶段是编译器工作的最后阶段。此阶段会基于中间码生成汇编代码，汇编器根据汇编代码生成目标文件，目标文件经过链接器处理最终生成可执行文件。

## Go语言编译流程

上面介绍了编译器工作整个流程，Go语言编译器编译也符合上面流程：

```eval_rst
.. image:: https://static.cyub.vip/images/202104/go-compile.png
    :alt: Go语言编译流程
    :width: 500px
    :align: center
```

我们执行`go build`命令时候，带上`-n`选项可以观察编译流程所执行所有的命令：

```eval_rst
.. code-block::
   :emphasize-lines: 11,24

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
```

从上面命令输出的内容可以看到：

1. Go编译器首先会创建一个任务输出临时目录（mkdir -p $WORK/b001/）。每次构建都是由一系列task完成，它们构成[action graph](https://github.com/golang/go/blob/master/src/cmd/go/internal/work/action.go)，b001是root task的工作目录。

2. 接着将empty_string.go中依赖的包（packagefile runtime=/usr/lib/go/pkg/linux_amd64/runtime.a）写入到importcfg中

3. 接着会使用compile命令，并指定importcfg文件，将主程序empty_string.go编译成_pkg.a文件（/usr/lib/go/pkg/tool/linux_amd64/compile -o $WORK/b001/_pkg_.a -trimpath "$WORK/b001=>" -p main -complete -buildid aJhlsTb17ElgWQeF76b5/aJhlsTb17ElgWQeF76b5 -goversion go1.14.13 -D _/home/vagrant/dive-into-go -importcfg $WORK/b001/importcfg -pack ./empty_string.go）。

4. 程序依赖的包都写到importcfg.link这个文件中，Go编译器连接阶段中链接器会使用该文件，找到所有依赖的包文件，将其连接到程序中（/usr/lib/go/pkg/tool/linux_amd64/link -o $WORK/b001/exe/a.out -importcfg $WORK/b001/importcfg.link -buildmode=exe -buildid=FoylCipvV-SPkhyi2PJs/aJhlsTb17ElgWQeF76b5/aJhlsTb17ElgWQeF76b5/FoylCipvV-SPkhyi2PJs -extld=gcc $WORK/b001/_pkg_.a
 /usr/lib/go/pkg/tool/linux_amd64/buildid -w $WORK/b001/exe/a.out # internal）。

5. 将编译成功的二进制文件移动到输出目录中（mv $WORK/b001/exe/a.out empty_string）。

为了详细查看`go build`整个详细过程，我们可以使用`go build -work -a -p 1 -x empty_string.go`命令来观察整个过程，它比`go build -n`提供了更详细的信息:

- -work选项指示编译器编译完成后保留编译临时工作目录
- -a选项强制编译所有包。我们使用`go build -n`时候，只看到main包编译过程，这是因为其他包已经编译过了，不会再编译。我们可以使用这个选项强制编译所有包。
- -p选项用来指定编译过程中线程数，这里指定为1，是为观察编译的顺序性
- -x选项可以指定编译参数

输出内容摘要如下：

```
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

```
vagrant@vagrant:/tmp/go-build871888098$ ls
b001  b002  b003  b004  b006  b007  b008
```

其中`b001`目录用于main包编译，是任务图的root节点。`b001`目录下面的`importcfg.link`文件存放都是程序所有依赖的包地址，它们指向的都是b002,b003...这些目录下的`_pkg_.a`文件。

## Go 编译器

Go 编译器，英文名称是`Go compiler`，简称gc。gc是Go命令的一部分，包含在每次Go发行版本中。Go命令是由Go语言编写的，而Go 语言编写的程序需要Go命令来编译，也就是自己编译自己，这就出现了“先有鸡还是先有蛋”的问题。Go gc如何做到自己编译自己呢，要解答这个问题，我们先来了解下自举概念。

### 自举

自举，英文名称是Bootstrapping。自举指的是用要编译的程序的编程语言来编写其编译器。自举步骤一般如下，假定要编译的程序语言是A：

1. 先使用程序语言B实现A的编译器，假定为compiler0
2. 接着使用A语言实现A的编译器，之后使用步骤1中的compiler0编译器编译，得到编译器compiler1
3. 最后我们就可以使用compiler1来编译A语言写的程序，这样实现了自己编译自己

通过自举方式，解决了上面说的“先有鸡还是先有蛋”的问题，实现了自己编译自己。Go语言最开始是使用C语言实现的编译器，go1.4是最后一个C语言实现的编译器版本。自go1.5开始，Go实现了自举功能，go1.5的gc是由go语言实现的，它是由go1.4版本的C语言实现编译器编译出来的，详细内容可以参见Go 自举的设计文档：[Go 1.3+ Compiler Overhaul](https://docs.google.com/document/d/1P3BLR31VA8cvLJLfMibSuTdwTuF7WWLux71CYD0eeD8/edit)。

除了 Go 语言实现的 gc 外，Go 官方还维护了一个基于 gcc 实现的 Go 编译器 [gccgo](https://go.dev/doc/install/gccgo)。与 gc 相比，gccgo 编译代码较慢，但支持更强大的优化，因此由 gccgo 构建的 CPU 密集型(CPU-bound)程序通常会运行得更快。此外 gccgo 比 gc 支持更多的操作系统，如果交叉编译gc不支持的操作系统，可以考虑使用gccgo。

### 源码安装

Go 源码安装需要系统先有一个`bootstrap toolchain`，该toolchain可以从下面三种方式获取：

- 从官网下载Go二进制发行包
- 使用gccgo工具编译
- 基于Go1.4版本的工具链

#### 从官网下载发行包

第一种方式是从Go发行包中获取Go二进制应用，比如要源码编译go1.14.13，我们可以去[官网](https://golang.org/dl/)下载已经编译好的go1.13，设置好GOROOT_BOOTSTRAP环境变量，就可以源码编译了。

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