PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator
YOSYS ?= yosys
CROSS ?= riscv64-unknown-elf-
CC = $(CROSS)gcc
OBJCOPY = $(CROSS)objcopy
ARCH = -march=rv32im_zicsr_zifencei -mabi=ilp32
FLAGS = $(ARCH) -O2 -ffreestanding -fno-builtin -nostdlib -nostartfiles -mno-relax -Wl,--no-relax -Wl,-T,tests/link.ld
RTL = $(wildcard rtl/*.v)
.PHONY: all test unit regression lint synth clean
all: test
build:
	mkdir -p build
build/soc.vvp: $(RTL) tb/tb_soc.v tb/soc_signals.vh tb/soc_instance.vh | build
	$(IVERILOG) -g2012 -Wall -I tb -s tb_soc -o $@ $(RTL) tb/tb_soc.v
build/muldiv.vvp: rtl/rv32_muldiv.v tb/tb_muldiv.v | build
	$(IVERILOG) -g2012 -Wall -s tb_muldiv -o $@ $^
build/muldiv.hex: tools/gen_muldiv.py tools/reference.py | build
	$(PYTHON) tools/gen_muldiv.py $@
build/cache.vvp: rtl/rv32_cache.v tb/tb_cache.v | build
	$(IVERILOG) -g2012 -Wall -s tb_cache -o $@ $^
unit: build/muldiv.vvp build/muldiv.hex build/cache.vvp
	$(PYTHON) tools/run_unit.py --vvp $(VVP)
build/directed.elf: tests/programs/directed.S tests/link.ld | build
	$(CC) $(FLAGS) -o $@ $<
build/algorithm.elf: tests/start.S tests/programs/algorithm.c tests/link.ld | build
	$(CC) $(FLAGS) -o $@ tests/start.S tests/programs/algorithm.c
build/%.bin: build/%.elf
	$(OBJCOPY) -O binary $< $@
build/%.hex: build/%.bin tools/bin2hex.py
	$(PYTHON) tools/bin2hex.py $< $@
regression: build/soc.vvp build/directed.hex build/algorithm.hex
	$(PYTHON) tools/regress.py --cc $(CC) --objcopy $(OBJCOPY) --vvp $(VVP)
test: unit regression
lint:
	$(VERILATOR) --lint-only --Wall --top-module rv32_soc $(RTL)
synth: | build
	$(YOSYS) -Q -T -s tools/synth.ys > build/synthesis.log
	$(PYTHON) tools/synth_report.py build/synthesis.json reports/synthesis.json
clean:
	rm -rf build

.PHONY: test-verilator
build/obj_verilator/soc_verilator: $(RTL) tb/tb_soc.v tb/soc_signals.vh tb/soc_instance.vh | build
	$(VERILATOR) --binary --timing -Wno-WIDTH --top-module tb_soc -Itb --Mdir build/obj_verilator -o soc_verilator $(RTL) tb/tb_soc.v > build/verilator-build.log 2>&1
test-verilator: build/obj_verilator/soc_verilator build/directed.hex build/algorithm.hex
	$(PYTHON) tools/cross_sim.py
