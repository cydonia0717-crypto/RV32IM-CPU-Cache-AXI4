# RV32IM CPU + Cache + AXI4

一个可编译、可仿真、可复现的数字 IC 设计练习工程。包含五级顺序流水线、独立 I/D Cache、32 位 AXI4 主接口、迭代乘除法器、精确同步异常，以及独立 Python 指令级模型。

## 已实现的设计

| 模块 | 配置与行为 |
|---|---|
| CPU | RV32I/M，IF / ID / EX / MEM / WB，顺序退休 |
| 冒险处理 | MEM/WB 前递、WB 到 ID 旁路、load-use 互锁、暂停期间操作数保持 |
| 控制流 | EX 分支解析，静态顺序取指；跳转/异常冲刷，丢弃已发出的旧取指响应 |
| 乘除法 | 32 拍移位累加乘法、恢复除法；覆盖 8 条 M 指令和符号边界 |
| I-Cache | 4KB，直接映射，256 行，16B/行，支持 FENCE.I 失效 |
| D-Cache | 4KB，直接映射，写直达、写缺失不分配；写响应成功后更新命中行 |
| AXI4 | 32 位地址/数据；4 拍 INCR 读、单拍写，I/D 读轮询仲裁，AW/W 独立握手 |
| 异常 | 非法指令、ECALL、EBREAK、访存/跳转非对齐、指令/数据访问错误 |
| CSR | 6 条 Zicsr 指令；mstatus、misa、mtvec、mepc、mcause、mtval、mhartid；MRET |
| 验证 | 模块测试、汇编定向、编译 C 程序、随机指令、逐条指令差分、双仿真器 |

接口、CSR 的具体实现范围和集成约束见 [设计说明](docs/architecture.md)。本工程采用阻塞 Cache 和单请求取指，适合作为可解释、可验证的设计基线。

## 一键运行

Ubuntu 24.04 / WSL2：

```bash
sudo apt-get update
sudo apt-get install -y iverilog verilator yosys gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
make test
make lint
make test-verilator
make synth
```

`make test` 会生成镜像、执行模块测试和 44 组系统回归，并在差分失败时返回非零状态。`make test-verilator` 额外使用 Verilator 执行定向程序、C 程序和长反压程序。GitHub Actions 执行同样的流程。

可覆盖工具名，例如 `make test CROSS=riscv32-unknown-elf-`。所有生成文件位于 `build/`，测试报告位于 `reports/`。

## 实测结果

| 检查 | 本次结果 |
|---|---|
| Icarus 系统回归 | 44/44 通过，83,620 条指令逐条核对 |
| 乘除法模块 | 2,560 组向量通过，运算阶段固定 32 拍 |
| Cache 模块 | 字节合并、写错误保留旧值、不分配、替换、回填错误、失效、复位通过 |
| 指令场景 | 56 个实现内助记符均执行，另含取指错误；9 类同步异常原因均触发 |
| Verilator 第二仿真器 | 3/3 通过，额外核对 13,615 条记录 |
| Verilator RTL lint | `--Wall` 通过，无警告 |
| Yosys | 全系统结构综合检查通过；乘除法器映射为 2,442 个通用逻辑单元 |

C 测试执行插入排序、求和和最大公约数：13,137 条退休指令，seed=1 时为 60,015 拍，CPI 约 4.57。该数据包含当前取指策略和随机总线延迟。工程尚未接入工艺库或 FPGA 器件，因此没有实测 MHz、芯片面积、功耗或 STA 结果。

[完整验证记录](docs/verification.md) · [机器可读回归报告](reports/regression.json) · [学习与面试讲解](docs/walkthrough.md)

## 目录

```text
rtl/       CPU、Cache、乘除法和 AXI4 桥
tb/       AXI RAM、协议检查、模块测试
tests/    定向汇编、裸机 C 程序、启动与链接脚本
tools/    镜像转换、随机程序、独立模型、差分回归、综合脚本
docs/     架构、验证和代码讲解
reports/  实际执行生成的报告
```

RTL 顶层为 `rtl/rv32_soc.v`，复位后从地址 0 开始执行。测试平台提供 64KB RAM；软件向 `0xFFF0` 写入 1 表示完成，其他值表示程序失败。

## 规范参考

- [RISC-V RV32I](https://docs.riscv.org/reference/isa/unpriv/rv32.html)
- [RISC-V M 扩展](https://docs.riscv.org/reference/isa/unpriv/m-st-ext.html)
- [RISC-V Zicsr](https://docs.riscv.org/reference/isa/unpriv/zicsr.html)
- [RISC-V Zifencei](https://docs.riscv.org/reference/isa/unpriv/zifencei.html)
- [RISC-V Machine-Level ISA](https://docs.riscv.org/reference/isa/priv/machine.html)
- [Arm AXI / ACE IHI 0022H](https://community.arm.com/cfs-file/__key/communityserver-discussions-components-files/476/IHI0022H_5F00_amba_5F00_axi_5F00_protocol_5F00_spec.pdf)
