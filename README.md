# 6.828 实验记录(文档更新中)

这篇实验记录是针对 2018 年版 6.828，选择 18 年版是因为 18 年版使用的是 x86 汇编，与如今常用的 PC 机架构一致，借此机会可以应用一下，由于课上学习过，也比较好上手。实验记录将包含两部分内容，一部分是把实验中用得到的比较关键的知识整理下来，另一部分是对自己写的代码的简要描述。

## lab1 Booting a PC

### 0. 环境搭建

只需要配置好 gcc 和 qemu 即可

#### 0.1 编译器

我使用的虚拟机是 ubuntu 18.04，是自带 gcc 的。

按照实验指导，首先应该检查发布版本是否是x86，执行以下命令，返回结果应有elf32-i386字样

```bash
$ objdump -i
```

接下来要检查是否有 32 位 libgcc 的链接库，需要有类似 `/usr/lib/gcc/i486-linuxgnu/*version*/libgcc.a` 或  `/usr/lib/gcc/x86_64-linux-gnu/*version*/32/libgcc.a` 这样的输出。

```bash
$ gcc -m32 -print-libgcc-file-name
```

最后，如果机器是 64 位的，应该安装 32 位的 `support library` ，否则的话可能出现 `__udivdi3 not found` 或 `__muldi3 not found` 等错误。我在实际使用的时候是出现过这个问题。（怀疑与64位除法有关）

```bash
$ sudo apt-get install gcc-multilib
```

#### 0.2 QEMU

为了方便 debug，课程提供了一个修改过的 QEMU 版本，QEMU 是一种模拟器。

首先把代码 clone 下来

```bash
$ git clone https://github.com/mit-pdos/6.828-qemu.git qemu
```

安装必要的库：`libsdl1.2-dev`, `libtool-bin`, `libglib2.0-dev`, `libz-dev`, 和 `libpixman-1-dev`

生成 configure 文件，Linux 中使用如下命令。其中 `prefix` 用来配置安装的路径，默认值是 `/usr/local`， `target-list` 用于指定 `QEMU` 支持哪些 CPU 架构，用于实验的只需要支持 `i386-softmmu` 和 `x86_64-softmmu` 即可，注意：这个参数一定要指定，不然的话编译时将各个架构分别编译一个。

```bash
./configure --disable-kvm --disable-werror [--prefix=PFX] [--target-list="i386-softmmu x86_64-softmmu"]
```

最后，编译。编译好之后，需要记得把生成的 QEMU 可执行文件加到 PATH 中

```bash
$ make && make install
```



### 1. PC Bootstrap

#### 1.1 关于 AT&T 汇编语言格式

在学校里学的 x86 汇编语言是 Intel 的 NASM 格式的汇编，而 gcc 支持的汇编格式是 AT&T 格式。两种本质上是一个指令集，原理上没有不同，仅语法上有所不同，而且 AT&T 格式汇编支持汇编嵌入到 C 代码中，并允许实现寄存器和 C 语言中变量之间的映射。

参考链接：[Brennan's Guide to Inline Assembly](http://www.delorie.com/djgpp/doc/brennan/brennan_att_inline_djgpp.html)

##### 基本 AT&T 语法

* 寄存器命名: 寄存器名字前需要加上 `%` ，例如 `%eax`

* 操作数顺序：源操作数在前(左)，目标操作数在后(右)，这与 Intex 汇编格式是恰好相反的

  ```
  AT&T:  mov %eax, %ebx  # 把 eax 中的内容存到 ebx 中
  ```

* 常量(立即数)的格式：常量或立即数值的前面必须加上 `$`，显示表示这是一个常量(立即数)

  ```
  movl $_booga, %eax  # 把 C 代码中变量 booga 的地址(常量),存入寄存器 eax 中
  movl $0xd00d, %ebx  # 把立即数 0xd00d 存入寄存器 ebx 中
  ```

* 指令要明确指定操作的长度：指令前必须要后缀  `b`，`w`，`l` 来表明目标寄存器是一个 `byte(1)`, `word(2)`，`longword(4)`。如果没有明确指定，GNU 汇编器将会进行猜测(也许会出错)。

* 引用内存：只列举了 386-protected 模式，实模式在 bootstrap 之后就用不到了
  32位寻址格式: `immed32(basepointer, indexpointer, indexscale)`
  寻址的地址为: `immed32 + basepointer + indexpointer * indexscale`
  注意：寻址时 32 位立即数和基指针至少要有一个；指令的后缀必须指定操作的长度；寄存器 `esp` 可用于寻址，但只可作为基地址。

  * 寻址 C 变量：`_booga` (当从汇编器获取全局(静态)变量时, 前面必须加上 `_`)
  * 寻址寄存器(作为指针)指向的变量: `(%eax)`
  * 寻址基地址为变量 `v` 偏移量存在寄存器的变量: `_v(%eax)`
  * 寻址类型为 `int` 的数组的某个元素: `_array(, %eax, 4)`
  * 立即数计算时可以相加(汇编器会帮助计算出来): `_struct_pointer + 8`
  * 例: 有二维数组 `char c[][8]`, 现想要寻址 `arr[i][j]`，其中 `eax = i`, `ebx = j`, 此时寻址应使用 `_array(%ebx, %eax, 8)` 

##### 基本行内汇编格式

基本行内汇编格式如下，若 `asm` 与代码中某些标识符冲突，则可以使用 `__asm__` 作为替代

```c
asm("cli")
```

可以把多条汇编指令写在一个 `asm` 括号内，但每条指令后需要加上 `\n\t`， 否则汇编器获得的 `.s` 文件格式不对；也可以直接分别把每一条指令写在一个 `asm` 括号内

```c
# 例 1
asm("push %eax\n\t movl $0, %eax\n\t popl %eax")
# 例 2
asm("movl %eax, %ebx")
asm("xorl %ebx, %edx")
asm("movl $0, _booga")
```

注意：上面例 2 中，改变了寄存器的值。如果在代码中这样写，则有可能导致问题，因为 GCC 没有被告知 asm 语句将会对 `ebx` 和 `eax` 做出改变，此时编译器可能正把某些重要的变量分配在这些寄存器中存储着，这将导致这些变量被破坏，导致程序的错误。若想对寄存器做出改变，则必须使用扩展行内汇编，告知 GCC 我们想如何改变寄存器的值，这样 GCC 将会在 asm 语句之前和之后帮我们妥善处理好。

##### 扩展行内汇编格式

格式如下

```c
asm("statements" : output_registers : input_registers : clobbered_registers)
```

例 1 

```c
asm("cld\n\t"   /* 清除方向标志，使 stosl 的方向是向后 */
    "rep\n\t"
    "stosl"     /* stosl 中的 l 表示每次将移动一个 longword(4) */
                /* stosl：将 EAX 中的值保存到 ES:EDI 指向的地址中，由于方向为清除，EDI+4 */
    : /* no output registers */
    : "c" (count), "a" (fill_value), "D" (dest) 
      /* ecx = count, eax = fill_value, edi = dest */
    : "%ecx", "%edi")  /* 上述指令执行过程中破坏了 ecx 和 edi 的值 */
```

字母与寄存器的映射关系

```
a        eax
b        ebx
c        ecx
d        edx
S        esi
D        edi
I        constant value (0 to 31)
q,r      dynamically allocated register (see below)
g        eax, ebx, ecx, edx or variable in memory
A        eax and edx combined into a 64-bit integer (use long longs)
```

`input registers` ：括号内可以是一个表达式，该表达式的求值将被存入对应的寄存器中

`clobber list` ：如果在汇编语句中修改了变量，则必须在 `clobber list` 中加入 `"memory"` 字段，这样做是防止 GCC 目前已经把将要被修改的变量的值存储在其他寄存器中，这种情况下会 GCC 不会重新从内存中 `load` 该值，导致不一致的情况。此外，若汇编语句修改了标志寄存器，则应在 `clobber list` 中加入 `"cc"` 字段。

例 2 （为了让编译器能高效地安排寄存器，可以让 GCC 自己来为我们挑选合适的寄存器，而不是显示地挑选）

```c
asm("leal (%0, %0, 4), %0" /* 该句汇编的含义是 %0 = %0 + %0 * 4, 即快速计算寄存器 %0 * 5 */
    : "=r" (x)         /* 这里 r 对应 %0 */
    : "0" (x) );       /* 由于寄存器 %0 已在上一行分配，此处仍想使用，因此是 "0" */
/* 注： 原文中写的是 leal (%1, %1, 4), %0"，但我觉得这里不对，应是 %0 */
```

```c
/* 这段汇编等价于 */
asm("leal (%1, %1, 4), %0"
    : "=r" (x_times_5)  /* 按照先后顺序， 这里的 r 映射 %0 */
    : "r" (x) );        /* r 映射 %1 */
```

```c
/* 也可以不让编译器自动分配 */
asm("leal (%%ebx, %%ebx, 4), %%ebx"
    : "=b" (x)
    : "b" (x) )
/* 这个示例中虽然 ebx 的值改变了，但没有写在 clobber list 中， 是因为 GCC 知道修改后的 ebx 是和变量 x 间绑定的。且同时，在这段汇编执行前，编译器已将 ebx 原有的值保存(写回内存)，因为在 input 中 ebx = x */
/* 在扩展的行内汇编中，如果在汇编语句中显示地写寄存器，必须使用 %% 而不能是 % (语法上规定)，这样是为了与 %0, %1 等代号做区分 */
```

`"q"` 表示允许 GCC 从 `eax`, `ebx`, `ecx`, `edx` 中为我们挑选合适的寄存器，`"r"` 表示允许 GCC 除了上面的寄存器，还可以从 `esi`, `edi` 中挑选。注意：如果那条指令中，不允许使用 `esi` 或 `edi`，则应该使用 `"q"` 。

`"%n"` 的分配规则: 按照后面几个 `list` 中从左到右的先后顺序，每遇到一个 `q` 或 `r` 就分别映射一个新的 `"%n"`。如果后面涉及到重用已分配的寄存器，则应使用标号 `"0"`, `"1"`, `"2"` 等表示此前已分配的寄存器。

`"output register"` 中，代表寄存器的字母前要加上 `"="`。

如果汇编语句必须在程序中放着的那个地址被运行(不希望被优化: 如循环展开等)，需要在语句前加上 volatile

```c
__asm__ __volatile__ (...);
```

例 3 （常用的例子）

```c
#define disable() __asm__ __volatile__ ("cli");  /* 禁用中断 */
#define enable() __asm__ __volatile__ ("sti");   /* 允许中断 */
```

```c
/* memcpy() */
#define rep_movsl(src, dest, numwords) \
__asm__ __volatile__ ( \
  "cld\n\t" \
  "rep\n\t" \
  "movsl" \
  : : "S"(src), "D"(dest), "c"(numwords) \
  : "%ecx", "%esi", "%edi")
```

```c
/* memset() */
#define rep_stosl(value, dest, numwords) \
__asm__ __volatile__ ( \
  "cld\n\t" \
  "rep\n\t" \
  "stosl" \
  : : "a"(value), "D"(dest), "c"(numwords) \
  : "%ecx", "%edi")
```

```c
 /* I/O: 读取 CPU 的 timeStampCounter, 并将结果保存到变量 llptr 中 */
#define RDTSC(LLPTR) ({ \
__asm__ __volatile__ ( \
  ".byte 0x0f; .byte 0x31" \
  : "=A" (llptr) \
  : : "%eax", "%edx"); })
```



#### 1.2 QEMU 与 GDB

##### 运行

选用 QEMU 的好处：可以作为 GDB 的一个远程调试目标，可以帮助后续的一些调试。

在 `lab/` 目录下执行 `make` 进行编译，将会生成  `obj/kern/kernel.img`，该文件中同时包含了 bootloader: `obj/boot/boot` 和 kernel: `obj/kernel` 

```bash
$ make qemu      # 使用图形界面的 qemu，以 kernel.img 作为模拟器的虚拟硬盘，使用VGA(虚拟)作为输出，从键盘接收输入
$ make qemu-nox  # 使用命令行界面的 qemu (方便 ssh 使用)，它设置了虚拟硬盘，并且把串口的输出重定向到了终端，从串口接收输入
```

退出 QEMU: `Ctrl+a x` 

QEMU 是一个模拟器，他是真实地模拟了一台 x86 架构的 PC。也就是说，如果我们把 `obj/kern/kernel.img` 文件的内容拷贝到真实 PC 的硬盘中的头部扇区中，其运行结果将与 QEMU 中显示的结果是相同的。

##### GDB 调试

打开两个终端，在其中一个终端上运行 `make qemu-gdb` 或 `make qemu-nox-gdb` 。运行之后，QEMU 将在第一条指令运行前暂停并等待 GDB 的调试请求。在另一个终端上执行 `make gdb` 命令，即可像其他可执行文件一样调试。

 

#### 1.3 PC 物理地址空间

x86 架构的 PC (32位)物理地址空间的分布大致如下

```
+------------------+  <- 0xFFFFFFFF (4GB)
|      32-bit      |
|  memory mapped   |
|     devices      |
|                  |
/\/\/\/\/\/\/\/\/\/\

/\/\/\/\/\/\/\/\/\/\
|                  |
|      Unused      |
|                  |
+------------------+  <- depends on amount of RAM
|                  |
|                  |
| Extended Memory  |
|                  |
|                  |
+------------------+  <- 0x00100000 (1MB)
|     BIOS ROM     |
+------------------+  <- 0x000F0000 (960KB)
|  16-bit devices, |
|  expansion ROMs  |
+------------------+  <- 0x000C0000 (768KB)
|   VGA Display    |
+------------------+  <- 0x000A0000 (640KB)
|                  |
|    Low Memory    |
|                  |
+------------------+  <- 0x00000000
```

最开始的 16 位 8088 Intel CPU，只能寻址 1MB 的物理内存，可寻址的地址为 0x0000 0000 - 0x000F FFFF。早期的 PC 在这 1MB 的内存中，只有被命名为 `"Low Memory"` 的 0 - 640KB 的空间是 RAM。

从 640KB - 1MB 为硬件保留的物理地址，例如：VGA Buffer, 其他被放在非易失性内存中的固件等。在保留区域中最重要的是 BIOS(Basic Input/Output System)，占用从 960KB - 1MB 中的 64KB。

**BIOS 的作用：**进行基本的系统初始化，例如启动显卡、检查插入的内存大小。在执行完这些初始化操作后，BIOS 从硬盘、CD-ROM、网络等地方把操作系统载入到内存中，并通过跳转把极其的控制权交给操作系统。

Intel 80386 开始可以寻址 4GB 的物理地址空间，但 1MB 以下的地址分布仍然被保留。因此当代的 32 位 x86 PC 的 RAM 被划分为两部分：`low memory`  0 - 640KB, `extended memory` 1MB - 4GB(稍小于4GB)。此外，在 32 位物理地址空间的顶端，被划分给 32 位 PCI 设备来使用。

在这门课程中，QEMU 对物理内存大小的默认设置是 256MB（我的机器上是 128MB）。



#### 1.4 从 BIOS 启动

通过 GDB 对 QEMU 进行调试，可以看到第一条运行的指令是

```
[f000:fff0]    0xffff0: ljmp   $0xf000,$0xe05b
```

可以推测出：PC 启动后执行的第一条指令的物理地址为 0x000f fff0，这个地址是在整个 BIOS 保留物理地址的最上面。也就是说，PC 开机后，寄存器的初始值 CS = 0xf000, IP = 0xfff0。第一条将要执行的指令是一个 `jmp`，跳转地址位 CS = 0xf000, IP = 0xe05b。

在 Intel CPU 中，这个启动地址的确定的。原因是 BIOS 映射在物理地址空间 0x000f 0000 - 0x000f ffff，这能确保 PC 在上电或重启后 BIOS 总能获得机器的控制权，在这个时刻，RAM 中没有任何可以运行的程序。

QEMU 模拟器有自己实现的 BIOS，放在模拟器的模拟出的物理地址空间内。在虚拟的处理器重启后，处理器首先进入**实模式 (real mode)**, CS = 0xf000, IP = 0xfff0。在实模式中，寻址方式为 `physical address = 16 * segment + offset`。

（关于单步跟踪 BIOS 源码，在 GDB 中单步跟踪汇编真的太艰苦了，以后有时间再做吧 ）

在 BIOS 运行时，它设置了中断向量表和 BIOS 知道的所有重要的设备。接下来，它将寻找一个可以启动的设备，如软盘、硬盘、光驱等。最终，它将找到一个可以从中启动的硬盘，BIOS 把硬盘的 bootloader 读入内存，并将控制权交给 bootloader。



### 2. Bootloader

硬盘的最小传输粒度是扇区 (1 扇区=512 字节)，即每次硬盘 I/O 操作必须是以扇区为单位进行读写的。如果一个硬盘是可引导 (bootable), 第一个扇区叫做引导扇区(boot sector), bootloader 的代码就放在引导扇区中。

当 BIOS 发现一个引导盘时，它将把引导扇区的 512 个字节载入内存中物理地址为 0x7c00 - 0x7dff 的地方，然后用一条 `jmp` 指令跳转到 CS:IP = 0000:7c00，即跳转到 bootloader。

Bootloader 代码长度限制在 512 字节内。在 JOS 中，其代码包括两部分: `boot/boot.S` 和 `boot/main.c`.



