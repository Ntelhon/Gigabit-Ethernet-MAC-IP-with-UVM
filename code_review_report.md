# Gigabit Ethernet MAC + DMA IP — Deep-Dive Design & Verification Review

**Repository:** `Ntelhon/Gigabit-Ethernet-MAC-IP-with-UVM` (branch `dev`)
**Scope:** `rtl/` (mac_core, dma, phy_if, controller top) and `verif/` (agents, envs, sequences, tests, tb top)
**Method:** Manual line-level review of all live RTL/UVM sources, cross-checked with Verilator 5.x lint + elaboration of the integrated `eth_controller_top`. Findings marked **[tool-verified]** were reproduced mechanically.

> **Executive summary:** The codebase has a clean, well-commented structure and several genuinely good ideas (Gray-coded async FIFOs, toggle-based store-and-forward CDC handshake, transaction-locked AXI arbiter, layered UVM with sub-environments). However, it is **not currently synthesizable** (multiply-driven registers in three modules, blocking/non-blocking mixing that even Verilator refuses to compile), **not functionally correct as integrated** (a FIFO parameter-semantics mismatch destroys both MAC CDC FIFOs; the DMA RX engine writes back descriptors before packets complete; descriptor writeback corrupts the ring), and **not self-checking in verification** (the system scoreboard is disconnected, the MAC scoreboard compares mismatched byte ranges, and the AXI4 slave BFM silently drops all write data into a zero-length array). The prioritized fix list is in Section 4.

---

## 1. ASIC RTL & Synthesizability Review

### 1.1 Synthesizability blockers

**S-1. Multiply-driven registers (synthesis error, simulation race) — `mac_rx.v`, `dma_desc.v`, `dma_top.v`**
Three modules drive the same `reg` from two separate `always` blocks:

- `mac_rx.v` — `rx_data`, `rx_data_valid`, `rx_sof` are assigned "defaults" inside the *RX Data Output Generation* block **and** are the primary outputs of the *Latch Outputs* block. In simulation the winner depends on process scheduling order; in DC/Genus/Vivado-synth this is a multi-driven-register error. The frame-aligned EOF scheme only "works" today because most simulators happen to execute the second block last.
- `dma_desc.v` — `tx_desc_valid` / `rx_desc_valid` are driven by the main FSM **and** by the trailing *Descriptor consumed acknowledgment* block.
- `dma_top.v` — `write_locked` is cleared in one `always` block (on `bvalid && bready`) and set in a second one (on arbiter grant). As written, the transaction lock that the comment calls *CRITICAL* does not exist as coherent logic.

**S-2. Blocking + non-blocking assignments to the same variables — `dma_rx.v` [tool-verified]**
`boundary_limit`, `buffer_limit`, `fifo_limit`, `min_bytes`, `calculated_len`, `assembled_data`, `assembled_strb`, `rd_idx`, `valid_bytes` are reset with `<=` and computed with `=` inside the same clocked process. Verilator hard-errors (`BLKANDNBLK`) and cannot even elaborate the design; synthesis tools that accept it will infer registers whose reset value fights the combinational use. Convert these to pure combinational temporaries in an `always @(*)` block (or SystemVerilog `always_comb` functions), and register only the true state.

**S-3. FIFO depth parameter semantics mismatch destroys the MAC CDC FIFOs — `eth_controller_top.v` vs `mac_top.v`/`mac_cdc_fifo.v` [tool-verified]**
`mac_top.TX_FIFO_DEPTH` is documented and used as an **address width** (`2^N` entries), but `eth_controller_top` passes `MAC_TX_FIFO_DEPTH = 2048` (and the testbench passes `16`) as an **entry count**. With `ADDR_WIDTH = 2048`, `localparam FIFO_DEPTH = 1 << ADDR_WIDTH` overflows 32-bit integer arithmetic to 0, producing a degenerate memory (`mem[1:-1]` per Verilator elaboration) with **2049-bit** Gray-coded pointers and synchronizers. Elaboration output:

```
%Warning-WIDTHTRUNC: mac_cdc_fifo.v:148: Bit extraction of array[1:-1] requires 1 bit index, not 2048 bits.
%Warning-WIDTHEXPAND: mac_cdc_fifo.v:131: Operator AND expects 2049 bits ...
```

The integrated design therefore has effectively no MAC-side elasticity buffers, and the full/empty flags are computed on garbage. The same mismatch appears in the TB (`MAC_TX_FIFO_DEPTH(16)` → a 65,536-entry FIFO of flip-flops), which is why simulation accidentally hides the store-and-forward deadlock described in Section 2. Fix: make the parameter meaning uniform (`FIFO_ADDR_W` everywhere, or `$clog2(DEPTH)` conversion at the boundary) and add an `initial`/generate elaboration assertion on legal ranges.

**S-4. RGMII behavioral DDR is not implementable — `rgmii_phy_if.v`**
`assign rgmii_txd = gtx_clk ? rgmii_txd_rising : rgmii_txd_falling;` uses the clock as a combinational mux select. This is glitch-prone, untimable, and will be rejected or mangled by ASIC synthesis (clock net feeding logic). The header acknowledges this, but as delivered the RGMII path is simulation-only. Replace with technology DDR output cells (and IDDR-equivalents on RX) behind a thin wrapper, and give the negedge-domain flops a properly synchronized reset. Note also that no RGMII TX clock skew (~2 ns) provision exists — clock and data are edge-aligned, which only works for PHYs with internal delay enabled.

**S-5. Flip-flop RAM arrays with byte-granular combinational reads — `mac_cdc_fifo.v`, `dma_tx.v`, `dma_rx.v`**
- `mac_cdc_fifo` reads `mem` combinationally (`assign rd_data = mem[rd_ptr...]`) for FWFT behavior, which prevents mapping to a dual-port SRAM macro. At the depths a real frame buffer needs (≥2 KB), that is ~20 K flops per FIFO plus a 2048:1 × 10-bit read mux. (Aside: `rd_data_reg`/`rd_data_valid_reg` in this module are dead logic — remove them.)
- `dma_tx` (2048 B) and `dma_rx` (4096 B) implement byte arrays `reg [7:0] fifo_mem[0:DEPTH-1]` with per-byte indexed reads such as `fifo_mem[fifo_rd_ptr + i]` unrolled ×8 inside the clocked FSM. That is eight parallel 4096:1 byte muxes on the write-data path — a guaranteed timing-closure failure at 125–250 MHz and an enormous area penalty. These buffers must become SRAM/register-file macros with registered read data, 64-bit organization, and a small output alignment stage.

**S-6. Latch inference / FSM hygiene**
Good news: all `always @(*)` blocks assign defaults first, so no unintended latches were found. FSMs use `localparam` binary encoding with `default` arms — fine, though 4-state-capable `state` vectors with unused codes should get `unique case` (SV) or synthesis FSM pragmas for safe recovery.

**S-7. Lint-level correctness hazards [tool-verified]**
- `wr_ptr_bin + (wr_en & ~wr_full)` in `mac_cdc_fifo.v` relies on context-determined width expansion of `~wr_full`; it happens to evaluate correctly, but it is fragile and flagged by every lint tool. Write `(wr_en && !wr_full) ? 1'b1 : 1'b0` explicitly.
- `dma_tx.v:269`: `fifo_space[FIFO_ADDR_W-1:0]` truncates the (N+1)-bit space count. When `fifo_space == FIFO_DEPTH` (empty FIFO) the slice reads **0**; if `bytes_remaining ≥ fifo_space` the min-select then yields `max_bytes = 0`, and `calc_len = (0+7)/8 - 1 = 8'hFF`, i.e. an accidental **256-beat (2 KB) burst** that overruns both the FIFO and the descriptor. Reachable with descriptor lengths ≥ FIFO depth; a one-line width bug with protocol-level consequences.
- `$clog2()` assigned to 3-bit `arsize/awsize` without a cast (width-trunc warnings in `dma_desc/dma_tx/dma_rx`).
- `dma_desc.v:394` indexes `desc_buf[2]` in the `DATA_WIDTH==32` branch while the array has 2 entries for 64-bit builds — dead in the current configuration but not generate-guarded, so it elaborates and warns; guard the 32-bit descriptor parsing with `generate`.
- `mac_rx.MAX_FRAME_SIZE` and `FCS_LEN` are declared and **never used** — there is no oversize/jabber protection at all (see 2.2).

### 1.2 Clock Domain Crossing

**What's done well:** the async FIFO uses Gray-coded pointers with 2-stage synchronizers and pessimistic flags; `tx_enable`/`rx_enable` get 3-stage bit synchronizers; frame availability uses a toggle-and-edge-detect CDC into the gtx domain. These are the right idioms.

**CDC-1. Multi-bit status buses cross domains raw — `mac_top.v` → `mac_regs.v` (Critical)**
`tx_frame_cnt` (gtx domain), `rx_frame_cnt`, `rx_err_cnt`, `rx_active` (rx domain) feed the sys-clk AXI-Lite read mux with **no synchronization**. Software reads can capture torn, metastable counter values. Standard fixes: keep counters in their source domain and either (a) transfer with Gray-coded counters, (b) snapshot via a req/ack handshake on read, or (c) accept per-bit sync only for quasi-static level signals (which counters are not).

**CDC-2. Interrupt pulses cross domains raw — `mac_top.v` (Critical)**
`int_tx_complete = tx_done` (single gtx-clk pulse) and `int_rx_received/crc_err/runt` (single rx-clk pulses) are sampled directly by the sys-clk sticky-status logic in `mac_regs`. A pulse can be missed entirely when sys_clk is slower (the TB runs sys at 100 MHz vs 125 MHz MAC clocks — interrupt loss is *expected* in the shipped configuration) or sampled metastably. The code comments admit "Production should add proper pulse synchronizers" — this must be a toggle-based pulse synchronizer per event before tape-out consideration.

**CDC-3. Store-and-forward frame counter protocol — `mac_top.v` (Design note)**
The toggle CDC loses events if two `tlast` writes occur within the ~3-cycle sync latency. With byte-wide writes and ≥60-byte frames this cannot happen today, but it becomes a real hazard if the AXIS width is ever increased. Either document the invariant with an assertion or replace with a Gray-coded frame counter.

**CDC-4. FWFT combinational RAM read across the domain boundary — `mac_cdc_fifo.v` (Waiver-needed)**
Reading `mem[]` written in the other domain is safe *given* the pointer-synchronization guarantee (data is stable ≥2 rd_clk before `empty` deasserts), but a CDC tool (SpyGlass/Questa CDC) will flag every mem bit; plan the waiver or add the standard registered-read + `empty` pipeline.

### 1.3 Reset Strategy

**R-1. Mixed reset styles across the design.** The MAC core uses synchronous active-low resets throughout; the DMA subsystem and the enable synchronizers in `mac_top` use asynchronous resets (`always @(posedge clk or negedge rst_n)`). Pick one policy (async-assert/sync-deassert is the usual ASIC choice) and apply it uniformly — mixed styles complicate DFT, STA (recovery/removal), and reset-tree synthesis.

**R-2. No per-domain reset synchronizers — `eth_controller_top.v` (Critical).**
`gtx_rst_n` and `rx_rst_n` are tied straight to `sys_rst_n` ("Assume same reset"). Reset *release* is therefore asynchronous to gtx_clk and rx_clk; with the MAC's synchronous resets, different flops can exit reset on different edges (recovery/removal violations), and the async FIFO's two sides can come out of reset misaligned — pointer corruption at time zero. Add a reset synchronizer (2-FF deassert sync) per clock domain, and sequence the FIFO reset so both sides are held until both domains' resets have deasserted.

**R-3. `soft_reset` in `dma_tx`/`dma_rx` is a partial reset.** It clears the FSM and FIFO pointers but leaves `cur_addr`, `bytes_remaining`, `pkt_len` (in `dma_rx`, partially handled elsewhere), and in-flight AXI state (`m_axi_awvalid` already issued, outstanding R/B beats) inconsistent — soft-resetting mid-burst will violate AXI (orphaned W beats / unaccepted B). A channel reset must quiesce the AXI interface (finish or fence outstanding transactions) before clearing state.

---

## 2. DMA & Ethernet MAC Architecture

### 2.1 DMA subsystem

**D-1. Descriptor writeback corrupts the descriptor ring — `dma_desc.v` (Critical).**
The writeback path writes **both** 64-bit words with full byte strobes:

```verilog
wb_buf[0] <= {16'd0, 16'd0, tx_wb_status_pending}; // overwrites BUFFER ADDRESS word!
wb_buf[1] <= {32'd0, tx_wb_status_pending};
```

Word 0 of the descriptor is the buffer address; writing status there destroys it, and the status lands in `[95:64]` rather than the documented `[127:96]`. The RX path is worse: `wb_buf[0] <= {status, length, 16'd0}` scrambles address-low with status/length, and the *actual length* never reaches its defined `[95:80]` field. After one pass around the ring, software's descriptors are garbage. Fix: write **only** the status/length half-word using partial `wstrb` (single-beat write to `desc_addr + 8` with `wstrb = 8'hF0`-style lane selection), matching the `dma_pkg.v` layout — and note the byte-lane/address alignment requirement in D-6.

**D-2. RX DMA "streaming mode" completes packets early — `dma_rx.v` (Critical).**
In `ST_WAIT_PKT`, if `fifo_count >= AXI_BYTES` before `tlast` arrives, the engine latches `latched_packet_len = fifo_count` — i.e., it treats *whatever happens to be buffered* as the packet length. It then writes those bytes, sees `bytes_written >= latched_packet_len`, and goes to `ST_WRITEBACK`: the descriptor is completed with `DONE=1`, a bogus length, and no FIRST/LAST segmentation — **while the packet is still arriving**. Any packet longer than 8 bytes whose delivery isn't instantaneous gets split across descriptors with corrupt lengths. Additionally, `pkt_len` is a single accumulator with no per-packet length queue, so a second packet arriving during writeback corrupts the first packet's accounting. Fix: store-and-forward with a small side FIFO of `{length, error}` records pushed at `tlast`, popped per descriptor; only enter the write path when a complete record exists.

**D-3. Status bit encoding contradicts `dma_pkg.v` — `dma_rx.v`/`dma_tx.v` (Critical for SW).**
`dma_rx` writes `{pkt_error@bit3, EOP@bit2, DONE@bit1, OWN@bit0}` but the package (and the UVM `dma_reg_defines.svh`, and the docs) define `DONE=1, ERR=2, LAST=3`. A driver written to the spec will read "ERR" whenever EOP is set and never see the error flag. Align the writeback fields with `dma_pkg.v` (and add a compile-time crosscheck in the UVM RAL/defines).

**D-4. The no-descriptor drop path is unreachable — `dma_rx.v` (Major).**
Nothing ever transitions **into** `ST_DROP_PKT`; `rx_drop_cnt` is dead. When descriptors run out, `s_axis_tready` stays high until `fifo_afull`, then backpressure propagates to the MAC's (intended 16-byte) RX FIFO, which silently drops mid-frame bytes with no framing recovery (see M-5). Implement descriptor-exhaustion detection (`!desc_valid` at packet start) → enter DROP, sink until `tlast`, count it.

**D-5. Scatter-gather is advertised but not implemented (Major).**
`FIRST`/`LAST`/`CRC_EN` control bits are defined in `dma_pkg.v` and set up by the docs/UVM sequences, but `dma_tx` ignores `cur_ctrl` entirely: every descriptor is treated as a full packet (`tlast` at end of each buffer), and `dma_rx` never chains buffers when a packet exceeds `cur_max_len` — it silently truncates at the buffer limit and completes. Either implement multi-descriptor chaining (carry `is_first_byte`/suppress `tlast` across LAST=0 descriptors on TX; continue into the next descriptor on RX) or strip the claims from `dma_pkg.v`, the docs, and the register map.

**D-6. AXI data-lane alignment violation for unaligned buffers — `dma_tx.v`, `dma_rx.v` (Major).**
Both engines assume byte 0 of every beat is data lane 0 regardless of address: `dma_rx` always builds `assembled_strb` from lane 0 upward with `awaddr = cur_addr` possibly unaligned, and `dma_tx` unpacks `m_axi_rdata[i*8 +: 8]` from lane 0. Per AXI, byte lanes must correspond to `ADDR mod (bus bytes)`. This currently "works" only because the UVM slave BFM makes the *same* wrong assumption (see V-6), masking the bug. Fix by rotating strobes/data by `cur_addr[2:0]` on the first beat, or by requiring/enforcing 8-byte-aligned buffer addresses in the descriptor checker (and returning a descriptor error otherwise).

**D-7. Descriptor engine throughput & OWN-bit polling storm (Major).**
- Exactly one descriptor is in flight; fetch → engine handshake → writeback are fully serialized through a single shared FSM and a single AXI ID per client, so descriptor latency is added to *every* packet. The header's "Prefetch logic for improved throughput" does not exist. A 2–4 deep descriptor prefetch FIFO per direction is the standard fix.
- When a fetched descriptor has OWN=0 (CPU-owned), `*_desc_valid` stays low, pointers don't move, and `ST_IDLE` immediately re-fetches the same descriptor — an unthrottled AXI read spin that will saturate the memory port whenever the ring runs dry. Add a poll-backoff timer or make OWN=0 park the channel until the head/tail pointer register is written (doorbell semantics — the pointers already exist, so polling shouldn't be needed at all).

**D-8. Bandwidth ceiling: 8-bit AXIS at sys_clk cannot sustain line rate (Architectural).**
The MAC↔DMA streams are 1 byte/cycle in the sys_clk domain. Gigabit Ethernet needs a sustained 125 MB/s; with the TB's 100 MHz sys_clk the datapath tops out at 100 MB/s *before* any stall, and `dma_tx` additionally serializes memory-fetch and stream-out phases (no overlap), and `dma_rx` drops `wvalid` between every W beat (halving W-channel utilization). For a NIC-class design: widen the internal AXIS to 32/64 bits (convert width at the MAC FIFO boundary), pipeline fetch-vs-stream in `dma_tx`, and hold `wvalid` across beats in `dma_rx`.

**D-9. Arbiter details (`dma_top.v`).** Besides the `write_locked` multi-driver (S-1): the R-channel demux by RID is sound for AXI4 (no read-data interleaving between IDs from a compliant AXI4 slave is still *permitted* per-ID — here each client tolerates it, fine); `m_axi_rready`/`bready` default to `1'b1` for unknown IDs, silently sinking data — make unknown IDs an error flag. Only one outstanding transaction per channel design-wide; acceptable for a first pass, but note it compounds D-7's latency serialization.

**D-10. `dma_regs.v` W1C race.** `int_status <= int_status & ~wdata` on a W1C write drops any interrupt edge arriving in the same cycle. Use `(int_status | new_edges) & ~wdata` as `mac_regs.v` correctly does. Also: the register map defines `DMA_TX_TAIL_PTR` as HW-written/RO, but nothing prevents ring-size = 0 operation — the wrap comparison `ptr == ring_size - 1` with `ring_size = 0` compares against `16'hFFFF` and the pending-count modulo math breaks; add a `ring_size != 0` enable qualifier (the UVM sequences never program ring size at all — V-8).

### 2.2 Ethernet MAC protocol compliance

**M-1. TX padding off-by-one for exactly-60-byte payloads — `mac_tx.v` (Bug).**
`need_padding = (frame_byte_cnt < 60)` is evaluated on the EOF beat *before* that byte is counted. For a payload of exactly 60 bytes, `frame_byte_cnt` is 59 on the EOF beat → the FSM enters `ST_PAD` and emits one spurious pad byte (65-byte frame incl. FCS, and the pad byte is CRC'd, so the frame is "valid" but one byte longer than the client's data — corrupting length-sensitive payloads). Fix: `need_padding = (frame_byte_cnt + 1'b1) < (MIN_FRAME_SIZE - FCS_LEN)`. Payloads of 59 and 61 bytes were checked and are handled correctly; only the ==60 case is broken.

**M-2. Store-and-forward deadlock with the intended FIFO depth — `mac_top.v` (Critical).**
`tx_data_valid` requires a *complete* frame in the FIFO (`tx_frames_in_fifo > 0`) before the MAC starts, but with the documented 16-entry FIFO, `tready` deasserts after 16 bytes, the producer stalls, `tlast` never enters the FIFO, and the toggle never fires: **every frame ≥ 17 bytes hangs the TX path permanently** (minimum Ethernet frame is 60 bytes, so *all* traffic). This is masked in simulation only because of the S-3 parameter mismatch/huge TB FIFO. The FIFO must be ≥ MAX_FRAME_SIZE (2 KB) for store-and-forward — which, combined with S-5, means an SRAM-based packet FIFO, not this register FIFO.

**M-3. TX underrun handling — `mac_tx.v` (Major).**
On mid-frame `!tx_data_valid`, the FSM transmits `0x00` with `tx_er=1` (reasonable), but those bytes are **not** fed to the CRC and `frame_byte_cnt` doesn't advance, so the frame is stretched with un-CRC'd filler; worse, if valid never returns, the FSM waits in `ST_DATA` forever (no abort/timeout), wedging the MAC. Store-and-forward makes underrun "impossible," but a defensive abort (force `tx_er`, jump to IFG, raise an underflow interrupt) is mandatory for a robust MAC. Also, `new_frame` requires `tx_sof && tx_data_valid` in IDLE while `tx_ready=0` — legal against this FIFO, but it means a strict "valid-after-ready" AXIS source can never start a frame; document or decouple.

**M-4. No oversize/jabber filtering, no address filtering — `mac_rx.v` (Major).**
`MAX_FRAME_SIZE` is a dead parameter: a jabbering link partner streams up to 65,535 bytes (16-bit counter, then silent wrap) into the RX path unchecked. And `mac_addr` from `mac_regs` is wired nowhere — the MAC is permanently promiscuous, so every frame on the wire consumes an RX descriptor. Add: oversize discard at `frame_byte_cnt > MAX_FRAME_SIZE` (with a jabber interrupt), and DA compare (unicast match / broadcast / promiscuous-mode bit — a control bit the UVM `mac_reg_config_seq` already writes at CONTROL[2], where the RTL ignores it).

**M-5. RX FIFO overflow silently corrupts framing — `mac_top.v` (Critical).**
`rx_fifo_wr_en = rx_data_valid && !rx_fifo_full` drops arbitrary mid-frame bytes on backpressure — including, potentially, the **EOF/tlast beat**, after which the downstream DMA never sees a frame boundary again and concatenates packets forever. A packet FIFO must either be sized for a full frame + drop *whole* frames on overflow (rewind write pointer to frame start), or at minimum guarantee the tlast beat is always written (reserve one slot) and mark the frame bad. The `fifo_overflow` sticky flag in the (unused) `mac_rx_axi_stream.v` shows the intent, but `mac_top` implements neither.

**M-6. Bad frames are delivered, not dropped (Design decision to revisit).**
RX is cut-through: data streams into the FIFO before CRC/runt evaluation; `frame_bad` rides `tuser` on the tlast beat. `dma_rx` then DMAs the bad frame to memory anyway (consuming a descriptor) and merely sets a status bit whose position contradicts the spec (D-3). NIC-standard behavior is to drop CRC-bad/runt frames in the MAC RX FIFO (store-and-forward rewind). At minimum, the delivery-of-bad-frames policy must be documented and the error bit fixed.

**M-7. Positive protocol observations (for balance).**
The CRC32 implementation is correct: reflected-polynomial byte-serial update, `~crc` output, LSB-first FCS byte order, and the RX residue check against `0x2144DF1C` (complement of `0xDEBB20E3`) is mathematically right (the header comment citing `0xC704DD7B` refers to the non-reflected register and should be fixed as a comment-only issue). IFG is ≥12 byte-times by construction (12 in `ST_IFG` plus ≥1 in IDLE). Preamble (7×0x55) + SFD generation and tolerant RX preamble handling (short preamble accepted) match 802.3 practice. `gmii_col/crs` are correctly ignored for full-duplex GMII — state this explicitly as a feature limitation.

**M-8. Dead/duplicated integration code (Major cleanup).**
- `mac_tx_axi_stream.v` / `mac_rx_axi_stream.v` are complete adapter modules that are **never instantiated** — `mac_top` re-implements their logic inline (differently: the inline version added store-and-forward; the file version has neither store-and-forward nor working tlast capture). Two divergent implementations of the same function is a maintenance trap; delete or adopt one.
- `mac_gmii_if` is instantiated but its **TX outputs are left unconnected** — `mac_top` routes `tx_gmii_*` straight to the pins, so the "signal registration for timing closure" on TX is dead logic and the output-boundary register the module was built for doesn't exist in the netlist.
- The entire `eth_dma_*` family (7 files, ~2,600 lines), `eth_regs.v`, and `rtl/dma/dma_pkg.v`'s register map vs `eth_controller_regs`' actual decode form a second, dead generation of the design that the Vivado TCL still globs into every compile. Quarantine or delete; stale near-duplicates are how the wrong file gets edited.

**M-9. AXI-Lite slave FSM issues — `mac_regs.v`, `eth_controller_regs.v` (Major).**
- `mac_regs`: `wr_en` ignores the ready handshake (`(awvalid || addr_valid) && (wvalid || data_valid)` in `WR_IDLE`). If a master holds AW/W valid across the cycle where `awready` is still low, the register write executes **twice** (harmful for W1C `INT_STATUS`); and because `wr_addr_eff` prefers the live `awaddr` over the latched one, a pipelined second address can steal a latched transaction's write. Qualify `wr_en` with the actual accept event and always use latched address/data.
- `eth_controller_regs`: in `W_IDLE`, `wr_addr_valid` is cleared by the `else` branch one cycle after capture. If W arrives ≥2 cycles after AW (perfectly legal — real interconnects do this), the latched address is forgotten, the FSM never advances, no `BRESP` is ever returned, and the bus **hangs** (the internal timeout counter only runs in `W_FORWARD`, so it never fires). Make `wr_addr_valid`/`wr_data_valid` sticky until the transaction launches.
- Neither block ever returns `SLVERR/DECERR` (unmapped reads return `0xDEADBEEF` with `OKAY`), despite declaring the codes.

---

## 3. UVM Verification Environment Review

### 3.1 Architecture

**Strengths:** parameterized, reusable agents with config objects and packages; sub-environment layering (`mac_env`, `dma_env` under `eth_controller_env`); a virtual sequencer with typed sub-sequencer handles and `` `uvm_declare_p_sequencer ``; register-config/base/derived sequence layering; per-simulator run scripts. The skeleton is genuinely industry-shaped.

**V-1. The system scoreboard is disconnected (Critical).**
Every `connect()` from monitors to `eth_scoreboard` in `eth_controller_env::connect_phase` is **commented out**, and even if connected, `eth_scoreboard` performs no comparison — it queues packets and prints; `end_to_end_*_matched`/`mismatches` are never updated. End-to-end (memory ↔ wire) checking does not exist. Implement the actual match: on GMII TX frames, look up the source buffer contents (via `memory_model` + descriptor decode); on RX, compare wire payload to the buffer written at the descriptor's address (and check the written-back length/status). Distinguish descriptor writebacks from data writes by address range or AXI ID (the RTL conveniently uses ID 0/1/2).

**V-2. `mac_scoreboard` compares mismatched byte ranges (Critical).**
`gmii_item.payload` is the L2 **payload only** (header and FCS stripped by `set_from_bytes`), while the AXIS monitor item is the **full frame** (DA+SA+Type+payload, plus FCS on the MAC→DMA RX stream). `compare_payloads()` therefore compares arrays of different lengths and will flag every packet as a mismatch (or the scoreboard is being run disabled, which is worse). Compare like-for-like: reconstruct full frame bytes from the gmii_item (`get_frame_bytes`), strip FCS from the RX AXIS item per the DUT's documented behavior, and compare.

**V-3. In-order pop matching with no drop model (Major).**
Both check paths do blind `pop_front` pairing. Any intentionally-errored frame (CRC-injected, runt) that the DUT correctly drops desynchronizes the queues and turns every subsequent good packet into a false mismatch. The scoreboard needs a predictor: consume the gmii_item's `crc_error_detected/runt_detected/inject_*` knowledge, predict *drop* vs *deliver(+tuser)*, and only enqueue expected deliveries. Add a `check_phase` that errors on non-empty residual queues (today leftovers are at best a warning in `eth_scoreboard` and silent in `mac_scoreboard`).

**V-4. Monitor bugs (Major).**
- `gmii_monitor`: `bit min_frame_size;` is a **1-bit** field assigned from `cfg.min_frame_size` (64 → truncates to 0), so runt detection is dead — every runt is reported valid. Declare `int unsigned`.
- `gmii_monitor` skips CRC checking for frames < 18 bytes and leaves `frame_valid` at its default — short corrupt frames sail through.
- `axi_stream_monitor` overwrites `item.user` on every beat; for the TX stream (`tuser` = SOF on beat 0) the SOF is lost, and for RX (`tuser` = error on tlast) it works only by accident of being the last write. Capture `user` per-beat (queue) or capture-at-tlast explicitly.
- `run_phase` `fork...join_any` around two `forever` loops should be `join_none` (cosmetic) — and neither monitor has any protocol checking (no `tvalid`-stability-until-`tready` check, no tx_en glitch check).

**V-5. Race-condition posture (Positive + gap).**
All BFMs use clocking blocks with input/output skews — the monitor→scoreboard path is function-based `analysis_imp`, so no UVM-level races. The remaining race risk is the *DUT's own* multiply-driven `mac_rx` outputs (S-1), which the TB cannot paper over, and the hierarchical `assign dut.mac_tx_axis_* ...` white-box taps in `eth_tb_top` — acceptable for bring-up, but move to `bind`-ed interfaces for reuse and to survive RTL renames.

**V-6. AXI4 slave BFM never stores write data (Critical).**
In `axi4_driver::handle_write`:

```systemverilog
byte unsigned tmp_data[];        // size 0
tmp_data[0] = req.data[...];     // out-of-bounds write to a dynamic array — silently discarded
mem.write_mem(byte_addr, tmp_data, 1);  // loops over data.size()==0 → writes nothing
```

Every DMA write to "memory" is dropped; the memory model only ever holds what sequences `init_mem`. Any future end-to-end RX check would pass/fail meaninglessly. (`tmp_data = new[1];` fixes it.) The BFM also mirrors the DUT's lane-0 alignment model (D-6), and its `awready/arready` toggle-per-transaction serialization plus single-outstanding handling is fine for now but should be noted as a throughput limiter for stress tests.

**V-7. Testbench-vs-DUT configuration masks RTL bugs (Critical insight).**
`eth_tb_top` passes `MAC_*_FIFO_DEPTH(16)` (→ 65,536-entry FIFOs via S-3), runs `rx_clk` and `gtx_clk` from the **same** clock source (zero phase/ppm offset — the CDC FIFOs are never actually exercised asynchronously), and releases `rst_n` asynchronously to all clocks. Recommended: derive rx_clk with a ppm offset and random phase (`#(4ns+jitter)`), sweep sys_clk vs 125 MHz ratios, and parameterize FIFO depths to the *intended* production values so M-2/M-5 reproduce in sim.

**V-8. Sequence/DUT contract breaks (Major).**
- `eth_tx_path_vseq::setup_tx_packet` builds **8-byte** descriptors (`desc_addr = base + idx*8`) with length at bytes 4–5 and OWN at byte 7 bit 7, against the RTL's **16-byte** format (length at bytes 8–9, OWN at byte 12 bit 0). The TX path test cannot function as written.
- Neither config sequence programs `TX/RX_DESC_SIZE` (ring size), leaving `ring_size = 0` → broken wrap math in `dma_desc` (D-10).
- `mac_reg_config_seq` writes a promiscuous bit the RTL doesn't implement, and reads back nothing.
- Fixed `#20us` / `#100us` waits instead of polling status/interrupts — flaky and slow; `assert(vseq.randomize() ...)` will be compiled out under `-assertions off`; use `if (!...) `uvm_fatal`.
- `eth_base_test` forces `set_report_verbosity_level_hier(UVM_MEDIUM)`, overriding `+UVM_VERBOSITY` from the command line.
- The `sim/xcelium/rtl.f`/`tb.f` file lists reference a directory tree (`verif/interfaces`, `gmii_agent`, `mac_env_pkg.sv`, `verif/tb/tb_top.sv`) that no longer exists — the Xcelium flow is dead; only the Vivado TCL flow matches the repo.

### 3.2 Coverage & Assertions — currently **zero of each**

There is not a single `covergroup`, `assert property`, or `bind` in the repository, despite RTL headers listing "Verification Hooks." Minimum viable plan:

**Functional coverage (per-agent covergroups + env cross):**
- Frame length bins: {runt <60, ==60 (the M-1 corner!), 61..63, 64, 65..511, 512..1517, 1518, oversize}, × {good CRC, bad CRC, rx_er-injected}.
- IFG bins: {<12, ==12, 13..24, large}; back-to-back frame count.
- FIFO occupancy bins incl. full/empty/almost-full hit; simultaneous rd+wr.
- Descriptor: OWN∈{0,1} × {TX,RX}, ring wrap event, ring-full/empty, writeback status values, buffer alignment ∈ {8B-aligned, unaligned}.
- AXI: burst len bins {1, 2..15, 16}, 4 KB-boundary-limited burst taken, RRESP/BRESP ≠ OKAY.
- Register: every address R & W, W1C-while-set-arriving cross, enable toggled mid-traffic.

**SVA (bind files on the RTL — dynamic now, formal-friendly later):**

```systemverilog
// GMII TX shape (bind to mac_top, gtx_clk)
a_ifg_min:      assert property ( $fell(gmii_tx_en) |-> !gmii_tx_en [*12] );
a_preamble_sfd: assert property ( $rose(gmii_tx_en) |->
                                  (gmii_txd==8'h55)[*7] ##1 gmii_txd==8'hD5 );
a_min_frame:    // count bytes while tx_en after SFD; assert >= 64 at $fell(tx_en)
a_no_txen_glitch: assert property ( gmii_tx_en |=> gmii_tx_en || $past(fcs_last_byte) );

// CDC FIFO (bind to mac_cdc_fifo)
a_no_write_full:  assert property (@(posedge wr_clk) wr_en |-> !wr_full);
a_no_read_empty:  assert property (@(posedge rd_clk) rd_en |-> !rd_empty);
a_gray_onehot_wr: assert property (@(posedge wr_clk)
                                   $countones(wr_ptr_gray ^ $past(wr_ptr_gray)) <= 1);

// AXIS (bind to both MAC-side streams)
a_tvalid_stable:  assert property (tvalid && !tready |=> tvalid && $stable(tdata) && $stable(tlast));
a_tlast_exists:   // frame byte counter bounded => tlast within MAX_FRAME_SIZE beats

// AXI4 master (bind to dma_top m_axi_*)
a_aw_stable:      assert property (m_axi_awvalid && !m_axi_awready |=> m_axi_awvalid && $stable(m_axi_awaddr) && $stable(m_axi_awlen));
a_wlast_count:    // wlast on exactly the (awlen+1)-th beat of the locked transaction
a_no_4k_cross:    assert property (m_axi_awvalid |-> (m_axi_awaddr[11:0] + ((m_axi_awlen+1)<<m_axi_awsize)) <= 13'h1000);

// Descriptor protocol (bind to dma_desc)
a_own_before_use: assert property (tx_desc_valid |-> $past(desc_buf_own_bit));
a_wb_clears_own:  // writeback data OWN==0
```

The FIFO gray-code and no-write-when-full properties plus the AXI handshake set are also ideal first formal targets (small cones, resettable).

---

## 4. Concrete Code Recommendations (Prioritized)

### CRITICAL — Must fix (blocks synthesis or basic function)

| # | File(s) | Issue | Fix |
|---|---------|-------|-----|
| C1 | `mac_rx.v`, `dma_desc.v`, `dma_top.v` | Multiply-driven regs (`rx_data*`, `*_desc_valid`, `write_locked`) — synth error, sim race **[tool-verified]** | Merge each signal into a single always block; fold the desc-consumed clear and lock set/clear into the owning FSM |
| C2 | `dma_rx.v` | Blocking+non-blocking on 9 variables — Verilator cannot compile **[tool-verified]** | Move burst-calc/assembly temporaries to `always @(*)`; register only state |
| C3 | `eth_controller_top.v`, `mac_top.v`, `mac_cdc_fifo.v`, `eth_tb_top.sv` | FIFO "depth" passed into an address-width parameter → `mem[1:-1]`, 2049-bit pointers **[tool-verified]** | Uniform `FIFO_ADDR_W` semantics (`$clog2` at boundaries) + elaboration-time range assertion |
| C4 | `mac_top.v` | Store-and-forward deadlock: FIFO smaller than one frame stalls producer before `tlast`; all TX traffic hangs at intended depth 16 | Size TX packet FIFO ≥ `MAX_FRAME_SIZE` (SRAM-based, see C10); assert FIFO ≥ frame at elaboration |
| C5 | `mac_top.v` | RX FIFO overflow drops mid-frame bytes incl. the tlast beat → permanent downstream framing loss | Whole-frame drop on overflow (write-pointer rewind) or guaranteed-tlast + frame-bad marking |
| C6 | `dma_desc.v` | Descriptor writeback overwrites the buffer-address word; status/length in wrong fields | Partial-strobe single-beat write of status(+length) at offset 8, per `dma_pkg.v` layout |
| C7 | `dma_rx.v` | "Streaming mode" latches `fifo_count` as packet length → premature DONE writeback, split packets, wrong lengths; single `pkt_len` accumulator corrupts across packets | Store-and-forward with a `{length,error}` record FIFO pushed at `tlast`; remove the `fifo_count`-as-length path |
| C8 | `eth_controller_top.v` | `gtx_rst_n`/`rx_rst_n` tied to raw `sys_rst_n` — async release into sync-reset domains; async-FIFO reset unsynchronized | Per-domain reset synchronizers (async assert / sync deassert), coordinated FIFO reset |
| C9 | `mac_top.v`, `mac_regs.v` | Raw multi-bit counter CDC + raw cross-domain interrupt pulses (misses/metastability) | Toggle-pulse synchronizers per interrupt; Gray/handshake snapshot for counters |
| C10 | `mac_cdc_fifo.v`, `dma_tx.v`, `dma_rx.v` | Flop arrays with giant combinational read muxes (2–4 KB byte arrays) — untimable/un-areable at 125 MHz+ | Dual-port SRAM macros with registered reads; 64-bit organization for DMA buffers |
| C11 | `eth_controller_regs.v` | Latched write address forgotten after 1 cycle → AXI-Lite hang when W trails AW by ≥2 cycles | Make `wr_addr_valid`/`wr_data_valid` sticky until transaction launch; extend timeout to all wait states |
| C12 | `mac_tx.v` | Padding off-by-one: exactly-60-byte payloads get a spurious pad byte | `need_padding = (frame_byte_cnt + 1) < (MIN_FRAME_SIZE - FCS_LEN)` |
| C13 | `verif/.../axi4_driver.sv` | `tmp_data[0]` on zero-length dynamic array — DMA writes never reach the memory model | `tmp_data = new[1];` (and add a regression check that mem is non-empty after RX tests) |
| C14 | `verif/env/...` | System scoreboard fully disconnected & compare-less; MAC scoreboard compares payload-only vs full-frame bytes | Reconnect analysis ports; implement predictor-based end-to-end compare; align byte ranges (V-1/V-2/V-3) |
| C15 | `eth_tx_path_vseq.sv` | TB TX descriptors use an 8-byte format incompatible with the RTL's 16-byte layout; ring size never programmed anywhere | Rewrite descriptor builder against `dma_pkg.v`; program `*_DESC_SIZE` in `dma_reg_config_seq` |

### MAJOR — Optimization / robustness

| # | Area | Recommendation |
|---|------|----------------|
| J1 | `dma_rx.v`/`dma_tx.v` AXI | Fix data-lane vs address alignment (or enforce 8B-aligned buffers with a descriptor error); hold `wvalid` across beats; keep AR/fetch overlapped with streaming in `dma_tx` |
| J2 | `dma_desc.v` | Add 2–4 deep descriptor prefetch per direction; replace OWN=0 refetch spin with doorbell-driven fetch (head/tail writes already exist); align writeback status bits with `dma_pkg.v` (D-3) |
| J3 | `dma_rx.v` | Implement the (currently unreachable) DROP path on descriptor exhaustion; wire `rx_drop_cnt` |
| J4 | Scatter-gather | Implement FIRST/LAST descriptor chaining on both engines, or remove SG from pkg/docs/registers |
| J5 | `mac_rx.v` | Implement `MAX_FRAME_SIZE` oversize/jabber discard + interrupt; implement DA filtering with the promiscuous control bit the UVM already writes |
| J6 | `mac_tx.v` | Underrun abort path (force `tx_er`, jump to IFG, underflow IRQ, watchdog on stuck `ST_DATA`) |
| J7 | Datapath bandwidth | Widen MAC↔DMA AXIS to ≥32 bits or require sys_clk ≥ 125 MHz; document the line-rate budget |
| J8 | `mac_regs.v` | Qualify `wr_en` with the accept event (fix double-write and W1C hazard); return `DECERR` for unmapped addresses; same for `eth_controller_regs`/`dma_regs` (`SLVERR` codes are declared but never used) |
| J9 | Dead code | Delete or quarantine `eth_dma_*` (7 files), `eth_regs.v`, un-instantiated `mac_tx/rx_axi_stream.v`, `mac_gmii_if` dead TX half, `rd_data_reg` in the FIFO, and the stale `sim/xcelium/*.f` lists (they reference a nonexistent tree) |
| J10 | TB realism | Independent rx_clk with ppm/phase offset; production FIFO depths; synchronized reset release; replace fixed `#Nus` waits with status/IRQ polling; stop forcing verbosity in `eth_base_test` |
| J11 | UVM agents | Fix `gmii_monitor` 1-bit `min_frame_size` (kills runt detection); per-beat `tuser` capture in `axi_stream_monitor`; add AXIS/AXI/GMII protocol checkers (or the SVA binds from §3.2) |
| J12 | Coverage/SVA | Add the covergroups and bound assertions listed in §3.2; run the FIFO + AXI-handshake properties formally |
| J13 | `dma_regs.v` | W1C-with-simultaneous-set fix; `ring_size != 0` qualifier; consider UVM RAL to keep TB defines and RTL map in lockstep |

### MINOR — Refactoring / hygiene

- Replace `wr_en & ~wr_full` width-context tricks with explicit boolean expressions; cast `$clog2()` results to port widths **[tool-verified lint]**.
- Generate-guard the `DATA_WIDTH==32` descriptor-parsing branch (`desc_buf[2]` out-of-range warning) **[tool-verified]**.
- Normalize line endings (mac_core files are CRLF, dma files are LF) and reset style; adopt `always_ff`/`always_comb`/`logic` (SystemVerilog) for the RTL to make C1/C2-class bugs compile errors.
- Fix the `mac_crc32.v` header comment (`0xC704DD7B` is the non-reflected residue; the code correctly uses `0x2144DF1C`).
- Remove unused `rx_dv_falling`, `FCS_LEN` in `mac_rx.v`; wire or remove `gmii_col/crs` and MDIO stubs in `gmii_if.sv`.
- `eth_tb_top`: declare `mac_irq`/`dma_irq` wires explicitly; the "Connected implicitly" comments on floating AXIS ports are wrong — tie inputs off explicitly; move hierarchical taps to `bind`.
- `assert(vseq.randomize())` → `if (!vseq.randomize()) `uvm_fatal`; `join_any` → `join_none` in `gmii_monitor::run_phase`; `eth_virtual_sequencer` should extend `uvm_sequencer#(uvm_sequence_item)` per convention.
- Vivado TCL globs compile the entire dead `eth_dma_*`/`eth_regs` tree — switch to explicit file lists so dead code can't shadow live modules.

---

## Appendix A — Tool evidence

```
$ verilator --lint-only rtl/dma/dma_rx.v -Irtl/dma
%Error-BLKANDNBLK: rtl/dma/dma_rx.v:172..182: Blocked and non-blocking assignments
                   to same variable: boundary_limit, buffer_limit, fifo_limit,
                   min_bytes, calculated_len, assembled_data, assembled_strb,
                   rd_idx, valid_bytes                      → 9 errors, aborts

$ verilator --lint-only ... --top-module eth_controller_top   (DMA_ENABLE=1, default params)
%Warning-WIDTHTRUNC: mac_cdc_fifo.v:148: Bit extraction of array[1:-1] requires
                     1 bit index, not 2048 bits             → MAC FIFOs degenerate
%Warning-WIDTHEXPAND: mac_cdc_fifo.v:131: Operator AND expects 2049 bits ...
%Warning-SELRANGE:   dma_desc.v:394: Selection index out of range: 2 outside 1:0
```

## Appendix B — What is done well (keep these)

- `mac_crc32`: correct reflected CRC-32 with unrolled bit contributions — clean and fast.
- `mac_cdc_fifo` pointer discipline (Gray code, 2-FF sync, pessimistic flags) is textbook; only the memory style and parameter plumbing need work.
- The toggle-CDC store-and-forward *concept* in `mac_top` is the right architecture for GMII TX; it just needs a frame-sized SRAM FIFO underneath it.
- 4 KB-boundary and burst-limit calculations exist in both DMA engines (rare in first-pass code); they need the width fix (S-7) but the structure is right.
- UVM layering (config objects, sub-envs, virtual sequencer, register-define headers, multi-simulator scripts) is a solid foundation once the checking layer is made real.
