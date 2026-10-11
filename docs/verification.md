# 验证计划与实测结果

## 可复现的验收

```bash
make test            # 单元 + 44 组 Icarus 差分回归
make lint            # Verilator --Wall，警告按失败处理
make test-verilator  # 三组第二仿真器检查
make synth           # Yosys 结构综合检查和乘除法器通用逻辑映射
```

编译/仿真退出码、超时、RTL $fatal、缺少完成标记、差分失败均使流程失败。Python 回归每个子进程限制 180 秒，RTL 也有周期上限。工作流通过上传 reports、trace 和日志保留失败证据。

## 独立模型与观察点

`tools/reference.py` 使用字节寻址内存、Python 整数和独立解码逻辑计算期望值，不调用 RTL 的解码器。每条退休记录比较 PC、指令、下一 PC、目的寄存器及结果、trap/cause/tval，以及成功 store 的地址/数据/WSTRB。取指访问错误时只忽略无意义的故障指令数据，继续比较其他字段。

模型实现完整的被测指令集合，但未进行官方架构认证，不能取代认证套件。逐条退休比对对所运行的程序有效；这些结果不等价于全部输入空间证明、代码覆盖率或工业签核。

## 测试矩阵

| 层次 | 输入 | 关键检查 |
|---|---|---|
| 乘除法 | 8 操作 ×（64 边界对 + 256 随机对） | 2,560 组结果，固定 32 拍，无除零/溢出陷阱 |
| Cache | 4 行配置的定向模块测试 | 字节合并、失败写保留旧值、写不分配、tag 冲突、非目标拍错误、回填期间失效、reset |
| 汇编定向 | `tests/programs/directed.S` | ALU/前递、load-use、分支冲刷、CSR、9 类异常、MRET、自修改代码/FENCE.I |
| C 集成 | 插入排序 64 元素、求和、GCD | 编译器生成的循环/访存/函数调用/REM，算法签名及逐条结果 |
| 指令随机 | 8 个确定种子的 600 段随机程序 | ALU/M/字节访存/条件分支、相邻依赖、x0、循环和 Cache 冲突 |
| 随机总线 | 以上 10 个程序 × 4 个总线种子 | AR/AW/W/R/B 独立延迟 |
| 强制顺序 | 定向程序各 1 组 | W 必须先于 AW；AW 必须先于 W |
| 长反压 | 定向程序 1 组 | 每 128 拍中连续 65 拍关闭请求接受/响应生成 |
| 读错误注入 | 定向程序 1 组，地址 `0x4004` | 非目标拍 SLVERR，整行回填作废，精确 load 访问异常 |
| 第二仿真器 | 定向、C、长反压共 3 组 | Verilator 编译执行，再用同一独立模型逐条检查 |

系统 Icarus 共 44 组：40 个基础组合 + 4 个特殊总线场景。额外 Cache 模块测试专门覆盖写响应错误保留原数据。

## 协议检查

Testbench 的 AXI RAM 独立接收 AW/W，直到两者都到达才更新 RAM 并提供 B。随机 R 响应每拍可以间隔；R/B 产生后必须保持到握手。读 burst/写地址检查长度、大小、类型、对齐和 4KB 边界。AR/AW/W 的反压稳定性和 x0 不变性有运行时检查。

AXI 固定属性由桥接器常量驱动。检查不是完整的商用 AXI VIP；没有测试多 ID 乱序返回，因为该桥每类最多一个事务在途，也没有实现乱序。

## 本次记录

执行日期：2026-10-11。工具：Icarus 12.0，Verilator 5.020，RISC-V GCC 13.2.0，Yosys 0.33。

- Icarus：44/44 通过，83,620 条退休/异常记录逐条比对。
- 56 个实现内指令助记符均执行，额外触发取指故障。非法编码另外在定向测试检查。
- 异常原因 0、1、2、3、4、5、6、7、11 全部触发。
- Verilator 第二仿真器：3/3 通过，额外 13,615 条记录逐条比对。
- 乘除法：2,560/2,560，运算阶段固定 32 拍。
- Cache 模块测试通过；Verilator 顶层 `--Wall` 无警告。
- 全系统 Yosys `hierarchy/proc/opt/memory_collect/check -assert` 通过，保留存储器。
- 乘除法器完整通用映射后为 2,442 个 cells，其中 365 个触发器单元；这不是工艺标准单元面积。

| 程序/总线条件 | 比对记录 | 拍数 |
|---|---:|---:|
| directed，seed=1 | 239（含 13 次异常） | 2,195 |
| algorithm，seed=1 | 13,137 | 60,015 |
| directed，W 先到 | 239 | 2,200 |
| directed，AW 先到 | 239 | 2,203 |
| directed，长反压 | 239 | 3,553 |
| directed，读错误注入 | 303 | 2,648 |

C 程序的当前 CPI 为 `60015/13137 ≈ 4.57`。取指单请求、Cache 命中响应延迟、分支冲刷、阻塞 store 和随机总线等待都包含在此数值中。其他程序和种子数据见 `reports/regression.json`。

完整设计没有接入 Liberty、SDC、SRAM 宏或器件约束，尚未执行 STA / P&R / FPGA 板级验证。没有报告频率、物理面积、功耗、功能覆盖率或代码覆盖率百分比。

## 发现并修复的问题

算术右移差分在 PC `0x44` 检出：RTL 为 `0x00000004`，期望为 `0xFFFFFFFC`。原代码将 `$signed(a) >>> shamt` 和无符号逻辑右移放进同一条件表达式，混合有/无符号上下文影响结果。改成分别赋值的条件分支，并在定向和随机 SRA/SRAI 中复测通过。

设计中另有显式预防措施：EX 暂停时保存前递值、MEM trap 优先禁止年轻请求、Cache 回填失败不安装 valid、FENCE.I 对在途回填 poison。它们由上述场景验证，不将预防性设计描述成曾经发现的 bug。

## 调试命令

```bash
# 保留特定种子的 trace，并可生成波形
vvp build/soc.vvp +image=build/directed.hex +trace=build/debug.trace +seed=1 +vcd
python3 tools/reference.py build/directed.hex build/debug.trace

# 故障注入；模型必须采用相同的故障地址
vvp build/soc.vvp +image=build/directed.hex +trace=build/error.trace +error_addr=00004004
python3 tools/reference.py build/directed.hex build/error.trace --error-addr 0x4004

# 更大的随机回归（先执行 make test 生成依赖）
python3 tools/regress.py --random-programs 32 --seeds 8
```

Trace 12 列按十六进制输出：pc、insn、next_pc、rd、data、trap、cause、tval、store、mem_addr、mem_data、mem_strb。非 store 指令不检查最后 3 列；非写回/rd=x0 的 data 固定为 0。
