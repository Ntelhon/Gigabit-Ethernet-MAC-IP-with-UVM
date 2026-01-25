# File: Makefile
SIM = vcs
SIMV = simv
VCS_OPTS = -full64 -sverilog -timescale=1ns/1ps
VCS_OPTS += +vcs+lic+wait
VCS_OPTS += -debug_access+all
VCS_OPTS += -fsdb
VCS_OPTS += -kdb
VCS_OPTS += -lca
VCS_OPTS += +define+UVM_NO_DPI
UVM_HOME = $(VERDI_HOME)/etc/uvm-1.2
VCS_OPTS += +incdir+$(UVM_HOME)/src
VCS_OPTS += -ntb_opts uvm-1.2
FLIST = compile.f
TEST ?= eth_sanity_test
SEED ?= 1
VERBOSITY ?= UVM_MEDIUM
compile:
	$(SIM) $(VCS_OPTS) -f $(FLIST) -l compile.log
run:
	./$(SIMV) +UVM_TESTNAME=$(TEST) \
	          +UVM_VERBOSITY=$(VERBOSITY) \
	          +ntb_random_seed=$(SEED) \
	          -l sim_$(TEST)_$(SEED).log
regression:
	@echo "Running regression suite..."
	@make run TEST=eth_sanity_test SEED=1
	@make run TEST=eth_rx_path_test SEED=2
	@make run TEST=eth_tx_path_test SEED=3
	@make run TEST=eth_bidir_test SEED=4
	@make run TEST=mac_sanity_test SEED=5
	@make run TEST=dma_descriptor_test SEED=6
clean:
	rm -rf $(SIMV)* csrc *.log *.fsdb *.key verdiLog simv.daidir
gui:
	./$(SIMV) +UVM_TESTNAME=$(TEST) \
	          +UVM_VERBOSITY=$(VERBOSITY) \
	          +ntb_random_seed=$(SEED) \
	          -gui -l sim_$(TEST)_$(SEED).log
.PHONY: compile run regression clean gui
