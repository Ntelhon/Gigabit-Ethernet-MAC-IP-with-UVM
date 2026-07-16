# Gigabit Ethernet Controller — Scatter-Gather DMA Subsystem
# Design & Implementation Instructions (v2.0)

This document is the complete implementation specification for a production-grade,
descriptor-ring (scatter-gather) DMA subsystem for a Gigabit Ethernet MAC.
The architecture follows the model used by industry NIC DMA engines
(Intel e1000/igb, Synopsys DesignWare EQoS, Xilinx AXI Ethernet DMA):
software owns descriptor rings in system memory, hardware fetches descriptors,
moves packet data between memory and the MAC AXI-Stream interfaces, and writes
completion status back into the descriptors.

---

## 1. System Context

```
                 ┌────────────────────────────────────────────┐
                 │              eth_controller_top            │
                 │                                            │
  AXI4-Lite ────►│  eth_controller_regs ──► dma_regs (CSR)    │
  (CPU config)   │                                            │
                 │  ┌──────────┐  AXIS TX   ┌──────────────┐  │
  AXI4 Master ◄──┼──┤ dma_top  ├───────────►│   mac_top    ├──┼──► GMII/RGMII PHY
  (DDR memory)   │  │          │◄───────────┤              │  │
                 │  └──────────┘  AXIS RX   └──────────────┘  │
                 │        │                                   │
                 │        └──► dma_irq ──► CPU interrupt      │
                 └────────────────────────────────────────────┘
```

- **RX path:** PHY → MAC → AXI-Stream (8-bit, `tvalid/tready/tdata/tlast/tuser`)
  → DMA writes packet into an RX buffer described by an RX descriptor → writeback
  status/length → interrupt.
- **TX path:** software fills a buffer, writes a TX descriptor, bumps the tail
  pointer → DMA fetches descriptor → reads buffer over AXI → streams packet to
  MAC over AXI-Stream → writeback → interrupt.
- Everything runs in a **single clock domain** (`clk`, the system/AXI clock).
  Clock-domain crossing to the PHY clocks is the MAC's job (mac_cdc_fifo).

---

## 2. Global Coding Rules (apply to EVERY file)

1. **Language:** Verilog-2001. No SystemVerilog constructs.
2. **One module per file.** File name **must equal** module name
   (`dma_tx_fetch.v` contains only `module dma_tx_fetch`).
3. **Reset:** asynchronous, active-low `rst_n` everywhere:
   ```verilog
   always @(posedge clk or negedge rst_n) begin
       if (!rst_n) begin
           ...
       end else begin
           ...
       end
   end
   ```
   No synchronous resets. No active-high resets. Every flip-flop must have a
   defined reset value.
4. **State machines:** all states declared as named `localparam` constants,
   never raw numbers in `case`:
   ```verilog
   localparam [2:0] ST_IDLE     = 3'd0,
                    ST_FETCH_AR = 3'd1,
                    ST_FETCH_R  = 3'd2,
                    ST_CHECK    = 3'd3,
                    ST_WB_AW    = 3'd4;
   reg [2:0] state;
   ```
   Use one-process or two-process FSM style consistently (recommended:
   single sequential process for state + datapath; combinational `assign`
   only for simple decodes). Always include a `default:` branch that
   returns to `ST_IDLE`.
5. **Parameterization:** every width, depth, burst length, ring size limit and
   ID value is a module `parameter` with a sane default. Derived values use
   `localparam` and `$clog2`. Never hard-code `64`, `8`, `16` etc. in the body.
6. **Headers:** every file starts with a comment block: file name, module
   purpose, parameter description, clocking/reset notes, author, license.
7. **Naming:** lowercase `snake_case` for signals/modules; `UPPER_CASE` for
   parameters/localparams; AXI ports use standard names
   (`m_axi_aw*`, `m_axi_w*`, `m_axi_b*`, `m_axi_ar*`, `m_axi_r*`,
   `s_axis_t*`, `m_axis_t*`, `s_axil_*`).
8. **AXI compliance:**
   - `valid` must never depend combinationally on the same channel's `ready`.
   - Once `valid` is asserted, payload is held stable until `valid && ready`.
   - Bursts are INCR, never cross a 4 KB boundary, `awlen/arlen ≤ MAX_BURST_LEN-1`.
   - Register all AXI master outputs (no combinational paths onto the bus).
9. **Memories:** all RAM storage lives ONLY in `dma_ram_sdp.v`. No `reg [..] mem [..]`
   arrays anywhere else. This is the single swap point for ASIC memory compilers.
10. **No latches, no `initial` blocks in synthesizable code, no `#` delays.**
11. **Full/empty and pointer logic** in FIFOs uses the extra-MSB (Gray-free,
    single clock) pointer scheme: pointers are `ADDR_W+1` bits wide.
12. **Lint-clean:** no width mismatch warnings; use explicit part-selects and
    `{}` concatenations when resizing.

---

## 3. Top-Level Parameter Set (propagated everywhere)

| Parameter        | Default | Legal range        | Meaning                                        |
|------------------|---------|--------------------|------------------------------------------------|
| `ADDR_WIDTH`     | 64      | 32 or 64           | AXI4 master address width                      |
| `AXI_DATA_W`     | 64      | 32/64/128/256      | AXI4-MM data width                             |
| `AXI_ID_W`       | 4       | 1–8                | AXI ID width                                   |
| `AXIS_DATA_W`    | 8       | 8 (GMII MAC)       | AXI-Stream data width toward MAC               |
| `MAX_BURST_LEN`  | 16      | 1–256, power of 2  | Max beats per AXI burst                        |
| `TX_FIFO_DEPTH`  | 2048    | ≥ 2×MTU, pow. of 2 | TX data FIFO depth in **bytes**                |
| `RX_FIFO_DEPTH`  | 4096    | ≥ 2×MTU, pow. of 2 | RX data FIFO depth in **bytes**                |
| `PKT_FIFO_DEPTH` | 16      | ≥ 2, power of 2    | Packet-metadata FIFO depth (packets in flight) |
| `RING_PTR_W`     | 16      | fixed 16           | Descriptor ring index width                    |
| `DESC_SIZE_B`    | 16      | fixed 16           | Descriptor size in bytes                       |
| `LEN_W`          | 16      | fixed 16           | Packet/buffer length width (max 64 KB)         |
| `TX_AXI_ID`      | 1       | unique per master  | AXI ID used by TX fetch engine                 |
| `RX_AXI_ID`      | 2       | unique per master  | AXI ID used by RX write engine                 |
| `DESC_AXI_ID`    | 0       | unique per master  | AXI ID used by descriptor engines              |

Derived (localparams, computed with `$clog2`): `AXI_BYTES = AXI_DATA_W/8`,
`FIFO_ADDR_W = $clog2(FIFO_DEPTH)`, `DESC_WORDS = DESC_SIZE_B*8/AXI_DATA_W`, etc.

---

## 4. File List and Hierarchy Tree

### 4.1 Files (17 total — one module per file, plus one include file)

| # | File              | Module            | Role                                                  |
|---|-------------------|-------------------|-------------------------------------------------------|
| 1 | `dma_pkg.vh`      | *(include only)*  | Register offsets, bit positions, descriptor bit map   |
| 2 | `dma_top.v`       | `dma_top`         | DMA subsystem top; wiring + arbiters instantiation    |
| 3 | `dma_regs.v`      | `dma_regs`        | AXI4-Lite CSR block                                   |
| 4 | `dma_irq.v`       | `dma_irq`         | Interrupt latch, mask, coalescing                     |
| 5 | `dma_desc_tx.v`   | `dma_desc_tx`     | TX descriptor ring engine (fetch + writeback FSM)     |
| 6 | `dma_desc_rx.v`   | `dma_desc_rx`     | RX descriptor ring engine (fetch + writeback FSM)     |
| 7 | `dma_tx.v`        | `dma_tx`          | TX channel top (fetch + FIFO + stream driver)         |
| 8 | `dma_tx_fetch.v`  | `dma_tx_fetch`    | AXI read-burst engine: memory → TX FIFO               |
| 9 | `dma_tx_stream.v` | `dma_tx_stream`   | TX FIFO → AXI-Stream master (store-and-forward)       |
|10 | `dma_rx.v`        | `dma_rx`          | RX channel top (stream sink + FIFO + writer)          |
|11 | `dma_rx_stream.v` | `dma_rx_stream`   | AXI-Stream slave → RX FIFO + packet metadata          |
|12 | `dma_rx_write.v`  | `dma_rx_write`    | AXI write-burst engine: RX FIFO → memory              |
|13 | `dma_fifo.v`      | `dma_fifo`        | Generic synchronous FIFO (control logic only)         |
|14 | `dma_ram_sdp.v`   | `dma_ram_sdp`     | Simple dual-port RAM (the ONLY memory primitive)      |
|15 | `dma_axi_rd_arb.v`| `dma_axi_rd_arb`  | 2-master AXI read-channel arbiter (transaction-locked)|
|16 | `dma_axi_wr_arb.v`| `dma_axi_wr_arb`  | 2-master AXI write-channel arbiter (transaction-locked)|
|17 | `dma_sync_cell.v` | `dma_sync_cell`   | (optional) 2-FF synchronizer, reserved for future CDC |

### 4.2 Hierarchy Tree

```
dma_top
│
├── dma_regs                          (AXI4-Lite CSR)
│
├── dma_irq                           (status latch + mask + coalescing)
│
├── dma_desc_tx                       (TX descriptor engine)
│     ─ AXI RD port  ──┐
│     ─ AXI WR port ───┼─┐
│                      │ │
├── dma_desc_rx        │ │            (RX descriptor engine)
│     ─ AXI RD port ───┤ │
│     ─ AXI WR port ───┼─┤
│                      │ │
├── dma_tx             │ │            (TX data channel)
│   ├── dma_tx_fetch ──┘ │            (AXI read master, memory → FIFO)
│   ├── dma_fifo         │            (TX data FIFO)
│   │   └── dma_ram_sdp  │            (storage)
│   ├── dma_fifo         │            (TX packet-metadata FIFO)
│   │   └── dma_ram_sdp  │
│   └── dma_tx_stream    │            (FIFO → m_axis_tx)
│                        │
├── dma_rx               │            (RX data channel)
│   ├── dma_rx_stream    │            (s_axis_rx → FIFO)
│   ├── dma_fifo         │            (RX data FIFO)
│   │   └── dma_ram_sdp  │
│   ├── dma_fifo         │            (RX packet-metadata FIFO)
│   │   └── dma_ram_sdp  │
│   └── dma_rx_write ────┤            (AXI write master, FIFO → memory)
│                        │
├── dma_axi_rd_arb                    (desc_tx/desc_rx/tx_fetch → one AR/R port)
└── dma_axi_wr_arb                    (desc_tx/desc_rx/rx_write → one AW/W/B port)
```

**Arbiter note:** the read arbiter serves 3 requesters (desc_tx fetch,
desc_rx fetch, tx data fetch) and the write arbiter serves 3 requesters
(desc_tx writeback, desc_rx writeback, rx data write). Implement each as an
N-port (parameter `N_MASTERS`, default 3) transaction-locked round-robin
arbiter so it is reusable.

---

## 5. Descriptor Format (16 bytes, little-endian, ring in system memory)

Rings are contiguous arrays of `RING_SIZE` descriptors at `RING_BASE`
(16-byte aligned). Ownership handshake uses head/tail pointers **and** an
OWN bit (belt-and-braces, matches e1000-style drivers).

### 5.1 TX Descriptor

| Bytes  | Field      | Description                                            |
|--------|------------|--------------------------------------------------------|
| 0–7    | `BUF_ADDR` | 64-bit physical buffer address (byte-aligned allowed)  |
| 8–9    | `BUF_LEN`  | Buffer length in bytes (1–16383)                       |
| 10–11  | *reserved* | Write as 0                                             |
| 12–15  | `CTRL/STS` | Control (SW writes) / Status (HW writes back)          |

`CTRL/STS` word bits:

| Bit(s) | Name       | Dir | Meaning                                          |
|--------|------------|-----|--------------------------------------------------|
| 31     | `OWN`      | SW→HW | 1 = descriptor owned by hardware               |
| 30     | `SOP`      | SW→HW | First buffer of packet (scatter-gather)        |
| 29     | `EOP`      | SW→HW | Last buffer of packet                          |
| 28     | `IRQ_EN`   | SW→HW | Raise TX_DONE interrupt on completion          |
| 27–16  | *reserved* |     |                                                  |
| 15     | `DONE`     | HW→SW | Set by writeback                               |
| 14     | `ERR`      | HW→SW | AXI/underflow error occurred                   |
| 13–0   | *reserved* |     | Written as 0 by writeback                        |

Writeback clears `OWN` and sets `DONE` (and `ERR` if applicable) in one
32-bit write to bytes 12–15.

### 5.2 RX Descriptor

| Bytes  | Field      | Description                                            |
|--------|------------|--------------------------------------------------------|
| 0–7    | `BUF_ADDR` | 64-bit physical buffer address                         |
| 8–9    | `BUF_LEN`  | Max buffer size in bytes                               |
| 10–11  | `PKT_LEN`  | HW writeback: actual received length                   |
| 12–15  | `CTRL/STS` | Control / Status                                       |

`CTRL/STS` word bits:

| Bit(s) | Name       | Dir | Meaning                                          |
|--------|------------|-----|--------------------------------------------------|
| 31     | `OWN`      | SW→HW | 1 = owned by hardware (empty buffer ready)     |
| 28     | `IRQ_EN`   | SW→HW | Raise RX_DONE interrupt on completion          |
| 15     | `DONE`     | HW→SW | Packet stored                                  |
| 14     | `ERR_CRC`  | HW→SW | MAC flagged error (`tuser` at `tlast`)         |
| 13     | `ERR_TRUNC`| HW→SW | Packet longer than buffer, truncated           |
| 12     | `ERR_AXI`  | HW→SW | AXI write error (BRESP != OKAY)                |
| 11–0   | *reserved* |     |                                                  |

Writeback for RX is a single burst updating bytes 8–15 (PKT_LEN + status).

---

## 6. Register Map (offsets inside DMA CSR space; base 0x200 in unified map)

Same layout as the current design (keep software compatibility):

| Offset | Name             | Access | Bits / Meaning                                    |
|--------|------------------|--------|---------------------------------------------------|
| 0x00   | `TX_CTRL`        | RW     | [0] enable, [1] reset (self-clearing), [2] irq_en |
| 0x04   | `TX_STATUS`      | RO     | [0] busy, [1] halted, [2] error                   |
| 0x08   | `TX_DESC_LO`     | RW     | TX ring base [31:0] (16-byte aligned)             |
| 0x0C   | `TX_DESC_HI`     | RW     | TX ring base [63:32]                              |
| 0x10   | `TX_RING_SIZE`   | RW     | [15:0] number of descriptors (power of 2)         |
| 0x14   | `TX_HEAD_PTR`    | RW     | SW producer index                                 |
| 0x18   | `TX_TAIL_PTR`    | RO     | HW consumer index                                 |
| 0x1C   | `TX_PKT_CNT`     | RO     | Transmitted packet counter                        |
| 0x40   | `RX_CTRL`        | RW     | [0] enable, [1] reset (self-clearing), [2] irq_en |
| 0x44   | `RX_STATUS`      | RO     | [0] busy, [1] halted, [2] error                   |
| 0x48   | `RX_DESC_LO`     | RW     | RX ring base [31:0]                               |
| 0x4C   | `RX_DESC_HI`     | RW     | RX ring base [63:32]                              |
| 0x50   | `RX_RING_SIZE`   | RW     | [15:0] number of descriptors                      |
| 0x54   | `RX_HEAD_PTR`    | RO     | HW producer index                                 |
| 0x58   | `RX_TAIL_PTR`    | RW     | SW consumer index                                 |
| 0x5C   | `RX_PKT_CNT`     | RO     | Received packet counter                           |
| 0x80   | `INT_STATUS`     | RW1C   | [0] tx_done [1] tx_err [2] rx_done [3] rx_err [4] desc_err |
| 0x84   | `INT_MASK`       | RW     | 1 = interrupt enabled                             |
| 0x88   | `INT_COALESCE`   | RW     | [15:0] packet count threshold, [31:16] timer      |
| 0x8C   | `VERSION`        | RO     | 0x0002_0000                                       |
| 0x90   | `RX_DROP_CNT`    | RO     | Packets dropped (no descriptor / FIFO overflow)   |
| 0x94   | `TX_BYTE_CNT`    | RO     | TX byte counter                                   |
| 0x98   | `RX_BYTE_CNT`    | RO     | RX byte counter                                   |

All register offsets and every control/status/interrupt bit position are
`` `define ``d in `dma_pkg.vh` — the RTL never uses magic numbers.

---

## 7. Per-File Detailed Instructions

Each section below gives: purpose, parameters, full port list, internal
structure, FSM definition, and implementation notes. Follow them literally.

---

### 7.1 `dma_pkg.vh` — Shared Definitions (include file, NOT a module)

Guarded with `` `ifndef DMA_PKG_VH ``. Contains **only** `` `define ``s:

- All register offsets from §6 (`` `DMA_TX_CTRL 8'h00 `` …).
- Control/status/interrupt bit indices (`` `DMA_CTRL_ENABLE 0 `` …).
- Descriptor bit positions (`` `DESC_OWN 31 ``, `` `DESC_SOP 30 ``,
  `` `DESC_EOP 29 ``, `` `DESC_IRQ_EN 28 ``, `` `DESC_DONE 15 ``,
  `` `DESC_ERR 14 ``, `` `DESC_ERR_CRC 14 ``, `` `DESC_ERR_TRUNC 13 ``,
  `` `DESC_ERR_AXI 12 ``).
- Version constant.

No parameters, no logic, no module. Every `.v` file includes it.

---

### 7.2 `dma_ram_sdp.v` — Simple Dual-Port RAM (ASIC swap point)

**Purpose:** the single, technology-mappable memory primitive. For FPGA it
infers block RAM; for ASIC this file is replaced by a memory-compiler wrapper
with the identical port list.

**Parameters**

| Parameter | Default | Meaning                         |
|-----------|---------|---------------------------------|
| `DATA_W`  | 8       | Word width                      |
| `DEPTH`   | 2048    | Number of words (power of 2)    |
| `ADDR_W`  | `$clog2(DEPTH)` | Address width (localparam-style derived, expose as parameter with default `$clog2(DEPTH)`) |
| `OUT_REG` | 0       | 1 = add output register (2-cycle read latency) |

**Ports**

| Dir | Width       | Name     | Description                    |
|-----|-------------|----------|--------------------------------|
| in  | 1           | `clk`    | Single clock (sync FIFO usage) |
| in  | 1           | `wr_en`  | Write enable                   |
| in  | `ADDR_W`    | `wr_addr`| Write address                  |
| in  | `DATA_W`    | `wr_data`| Write data                     |
| in  | 1           | `rd_en`  | Read enable                    |
| in  | `ADDR_W`    | `rd_addr`| Read address                   |
| out | `DATA_W`    | `rd_data`| Read data (1-cycle latency, 2 if `OUT_REG`) |

**Implementation notes**

- `reg [DATA_W-1:0] mem [0:DEPTH-1];` — write port clocked, read port clocked
  (synchronous read). NO asynchronous read (ASIC SRAMs are synchronous).
- **No reset on the memory array or read data path** (memory compilers don't
  reset arrays). The FIFO control logic guarantees no read-before-write.
- No `rst_n` port at all — this is intentional and must be commented.
- Generate the optional output register with a `generate if (OUT_REG)`.

---

### 7.3 `dma_fifo.v` — Generic Synchronous FIFO (control only)

**Purpose:** single-clock FIFO used for TX data, RX data, and both packet
metadata FIFOs. Contains ONLY pointer/flag logic; storage is an instantiated
`dma_ram_sdp`.

**Parameters**

| Parameter        | Default | Meaning                                   |
|------------------|---------|-------------------------------------------|
| `DATA_W`         | 8       | Word width                                |
| `DEPTH`          | 2048    | Depth in words (power of 2)               |
| `AFULL_THRESH`   | DEPTH-4 | `almost_full` asserts at this fill level  |
| `AEMPTY_THRESH`  | 4       | `almost_empty` asserts at/below this level|

**Ports**

| Dir | Width            | Name          | Description                          |
|-----|------------------|---------------|--------------------------------------|
| in  | 1                | `clk`         | Clock                                |
| in  | 1                | `rst_n`       | Async active-low reset               |
| in  | 1                | `flush`       | Synchronous flush (pointers to 0)    |
| in  | 1                | `wr_en`       | Push (ignored when `full`; assert an sticky `overflow` flag instead of corrupting) |
| in  | `DATA_W`         | `wr_data`     | Push data                            |
| out | 1                | `full`        | FIFO full                            |
| out | 1                | `almost_full` | Programmable threshold flag          |
| in  | 1                | `rd_en`       | Pop (ignored when `empty`; sticky `underflow` flag) |
| out | `DATA_W`         | `rd_data`     | Pop data — **first-word-fall-through** (see notes) |
| out | 1                | `empty`       | FIFO empty                           |
| out | 1                | `almost_empty`| Programmable threshold flag          |
| out | `$clog2(DEPTH)`  | `count`       | Current fill level (`ADDR_W+1` bits) |
| out | 1                | `overflow`    | Sticky write-when-full flag          |
| out | 1                | `underflow`   | Sticky read-when-empty flag          |

**Implementation notes**

- Pointers `wr_ptr`, `rd_ptr` are `ADDR_W+1` bits. `full` when pointers differ
  only in MSB; `empty` when equal. `count = wr_ptr - rd_ptr`.
- Because `dma_ram_sdp` has synchronous read (1-cycle latency), implement
  **first-word-fall-through** with a small output holding register + prefetch
  state so `rd_data` is valid whenever `empty == 0` and `rd_en` pops in the
  same cycle. (Classic "FWFT wrapper around sync-read RAM": keep an
  `output_valid` register, prefetch from RAM whenever the output register is
  empty or being consumed.) Document this in the header.
- `flush` is synchronous and also clears the FWFT stage and sticky flags.
- Instantiate exactly one `dma_ram_sdp` with `OUT_REG = 0`.

---

### 7.4 `dma_regs.v` — AXI4-Lite Register Block

**Purpose:** implements the register map of §6. Pure CSR block: no packet
logic. Interrupt latching/coalescing lives in `dma_irq`; `dma_regs` only
exposes the RW1C status array and mask to software and wires the raw event
pulses to `dma_irq`.

**Parameters:** `ADDR_WIDTH` (system address width, for ring base registers),
`CSR_ADDR_W` (default 8).

**Ports**

- `clk`, `rst_n`.
- AXI4-Lite slave: `s_axil_awvalid/awready/awaddr[CSR_ADDR_W-1:0]`,
  `s_axil_wvalid/wready/wdata[31:0]/wstrb[3:0]`,
  `s_axil_bvalid/bready/bresp[1:0]`,
  `s_axil_arvalid/arready/araddr[CSR_ADDR_W-1:0]`,
  `s_axil_rvalid/rready/rdata[31:0]/rresp[1:0]`.
- TX channel control/status:
  out `tx_enable`, out `tx_soft_reset` (1-cycle pulse, self-clearing bit),
  out `tx_irq_en`, in `tx_busy`, in `tx_halted`, in `tx_error`,
  out `tx_ring_base[ADDR_WIDTH-1:0]`, out `tx_ring_size[15:0]`,
  out `tx_head_ptr[15:0]` (SW-written), in `tx_tail_ptr[15:0]` (HW),
  in `tx_pkt_cnt[31:0]`, in `tx_byte_cnt[31:0]`.
- RX channel: mirror image —
  out `rx_enable`, `rx_soft_reset`, `rx_irq_en`,
  in `rx_busy/rx_halted/rx_error`,
  out `rx_ring_base[ADDR_WIDTH-1:0]`, `rx_ring_size[15:0]`,
  in `rx_head_ptr[15:0]` (HW), out `rx_tail_ptr[15:0]` (SW),
  in `rx_pkt_cnt[31:0]`, in `rx_byte_cnt[31:0]`, in `rx_drop_cnt[31:0]`.
- Interrupt interface to/from `dma_irq`:
  in `int_status[4:0]` (latched value, for read), out `int_clear[4:0]`
  (RW1C write pulse), out `int_mask[4:0]`, out `int_coal_cnt[15:0]`,
  out `int_coal_time[15:0]`.

**Write FSM** — `localparam [1:0] WR_IDLE, WR_DATA, WR_RESP;`
Accept AW and W independently (either order), latch address, apply write with
byte-lane `wstrb`, respond `OKAY`. Writes to RO offsets are silently ignored
(still respond OKAY — AXI4-Lite has no SLVERR requirement here, keep it simple
and document it).

**Read FSM** — `localparam [0:0] RD_IDLE, RD_DATA;`
Latch AR address, mux register value into `s_axil_rdata`, `default:` returns
`32'hDEAD_BEEF` for undefined offsets (debug aid).

**Notes**

- `tx_soft_reset`/`rx_soft_reset` bits read back as 0 and pulse exactly one
  cycle.
- Ring base low writes clear bits [3:0] (force 16-byte alignment) — document.
- `TX_HEAD_PTR`/`RX_TAIL_PTR` are plain RW registers; the descriptor engines
  compare them against their internal pointers.

---

### 7.5 `dma_irq.v` — Interrupt Controller with Coalescing

**Purpose:** latch event pulses, apply mask, implement industry-style
interrupt coalescing (packet-count threshold OR timeout, whichever first —
like e1000 ITR / EQoS RWT).

**Parameters:** `N_INT` (default 5), `COAL_TIMER_W` (default 16),
`COAL_PRESCALE` (default 1000 — clk cycles per timer tick; at 125 MHz a tick
is 8 µs).

**Ports**

| Dir | Width  | Name            | Description                                  |
|-----|--------|-----------------|----------------------------------------------|
| in  | 1      | `clk`, `rst_n`  |                                              |
| in  | 1      | `ev_tx_done`    | Pulse: TX descriptor completed with IRQ_EN   |
| in  | 1      | `ev_tx_err`     | Pulse                                        |
| in  | 1      | `ev_rx_done`    | Pulse: RX packet written with IRQ_EN         |
| in  | 1      | `ev_rx_err`     | Pulse                                        |
| in  | 1      | `ev_desc_err`   | Pulse                                        |
| in  | 5      | `int_clear`     | RW1C clear pulses from `dma_regs`            |
| in  | 5      | `int_mask`      | From `dma_regs`                              |
| in  | 16     | `coal_cnt_thresh`, `coal_time_thresh` | Coalescing config       |
| out | 5      | `int_status`    | Latched status (to `dma_regs` for readback)  |
| out | 1      | `dma_irq`       | Level interrupt to CPU                       |

**Behavior**

- `int_status[i]` sets on event pulse, clears on `int_clear[i]` (set wins on
  collision).
- Error interrupts (`tx_err`, `rx_err`, `desc_err`) bypass coalescing — assert
  `dma_irq` immediately when unmasked.
- Done interrupts are coalesced: an internal packet counter increments on
  `ev_tx_done|ev_rx_done`; a prescaled timer runs while the counter is
  non-zero. `dma_irq` asserts when `counter >= coal_cnt_thresh` OR
  `timer >= coal_time_thresh` (thresholds of 0 = coalescing disabled, fire
  immediately). Counter and timer clear when software clears the
  corresponding status bits.
- `dma_irq` is a registered level output: `|(int_status & int_mask) && gate`.

**FSM:** `localparam [1:0] COAL_IDLE, COAL_ACCUM, COAL_FIRE;`

---

### 7.6 `dma_desc_tx.v` — TX Descriptor Ring Engine

**Purpose:** owns the TX ring consumer pointer. Fetches descriptors from
memory when `head != tail` (or when OWN=1), hands buffer address/length/flags
to `dma_tx`, performs status writeback when `dma_tx` reports completion.

**Parameters:** `ADDR_WIDTH`, `AXI_DATA_W`, `AXI_ID_W`, `AXI_ID` (default
`DESC_AXI_ID`), `RING_PTR_W` (16), `DESC_SIZE_B` (16).

**Ports**

- `clk`, `rst_n`.
- Control: in `enable`, in `soft_reset`, in `ring_base[ADDR_WIDTH-1:0]`,
  in `ring_size[15:0]`, in `head_ptr[15:0]` (from `dma_regs`, SW producer),
  out `tail_ptr[15:0]` (HW consumer, to `dma_regs`), out `busy`,
  out `desc_err` (pulse: AXI error or malformed descriptor, e.g. OWN=0 when
  head!=tail, BUF_LEN=0).
- Descriptor handoff to `dma_tx` (valid/ready):
  out `desc_valid`, in `desc_ready`,
  out `desc_buf_addr[ADDR_WIDTH-1:0]`, out `desc_buf_len[15:0]`,
  out `desc_sop`, out `desc_eop`, out `desc_irq_en`,
  out `desc_index[15:0]`.
- Writeback request from `dma_tx` (valid/ready):
  in `wb_valid`, out `wb_ready`, in `wb_index[15:0]`, in `wb_err`.
- AXI read master port (to `dma_axi_rd_arb`): full AR + R channels
  (`m_axi_arvalid/arready/araddr/arlen/arsize/arburst/arid`,
  `m_axi_rvalid/rready/rdata/rresp/rlast/rid`).
- AXI write master port (to `dma_axi_wr_arb`): full AW + W + B channels.
- Event out: out `ev_tx_done` (pulse when writeback of a descriptor with
  IRQ_EN completes).

**FSM (single, explicit):**

```verilog
localparam [3:0] ST_IDLE      = 4'd0,  // wait enable && head!=tail
                 ST_FETCH_AR  = 4'd1,  // issue AR for descriptor
                 ST_FETCH_R   = 4'd2,  // collect DESC_WORDS beats
                 ST_CHECK     = 4'd3,  // validate OWN, parse fields
                 ST_DISPATCH  = 4'd4,  // desc_valid handshake to dma_tx
                 ST_WAIT_WB   = 4'd5,  // wait wb_valid from dma_tx
                 ST_WB_AW     = 4'd6,  // writeback address (CTRL/STS word)
                 ST_WB_W      = 4'd7,  // writeback data beat(s)
                 ST_WB_B      = 4'd8,  // wait BRESP
                 ST_ADVANCE   = 4'd9,  // tail_ptr++ (mod ring_size), pulse events
                 ST_HALT      = 4'd10; // fatal error; exit only via soft_reset
```

**Implementation notes**

- Descriptor address = `ring_base + (tail_ptr * DESC_SIZE_B)` — implement the
  multiply as `{tail_ptr, 4'b0}` since `DESC_SIZE_B = 16`.
- Fetch burst: `arlen = DESC_WORDS-1`, `arsize = $clog2(AXI_BYTES)`. Handle
  both `AXI_DATA_W = 32` (4 beats) and `64` (2 beats) via `DESC_WORDS`
  localparam and generate-free indexing into a `desc_buf` word array
  (this word array is small register storage, not a RAM — allowed).
- If OWN bit is 0 in `ST_CHECK`: do NOT halt; return to `ST_IDLE` and retry
  (SW may still be writing). Only pulse `desc_err` and go `ST_HALT` on AXI
  `rresp/bresp != OKAY`.
- Writeback writes only the CTRL/STS dword (bytes 12–15): single-beat write,
  `wstrb` selects the correct 4 lanes within the AXI word based on the
  descriptor address alignment. Compute the writeback address as
  `desc_addr + 12` aligned down to `AXI_BYTES`, and shift data/strobe
  accordingly.
- Pipelining (production behavior): while `dma_tx` is transmitting descriptor
  N, this FSM may prefetch descriptor N+1 — OPTIONAL enhancement; the basic
  sequential flow above is required first. Keep a `PREFETCH` parameter
  (default 0) reserved.
- `soft_reset`: from any state return to `ST_IDLE`, clear `tail_ptr`, deassert
  all `valid`s (only after any in-flight AXI burst completes — never abandon
  an accepted AXI transaction; drain R beats / wait B first via
  `ST_HALT`-style drain).

---

### 7.7 `dma_desc_rx.v` — RX Descriptor Ring Engine

**Purpose:** owns the RX ring producer pointer (`head_ptr`). Fetches empty
buffer descriptors, hands them to `dma_rx`, writes back PKT_LEN + status when
a packet lands.

**Parameters:** identical set to `dma_desc_tx`.

**Ports:** mirror of `dma_desc_tx` with these differences:

- in `tail_ptr[15:0]` (from `dma_regs`, SW consumer),
  out `head_ptr[15:0]` (HW producer).
- Availability rule: a descriptor may be fetched when
  `((head_ptr + 1) mod ring_size) != tail_ptr` **and** OWN=1 after fetch.
- Writeback request from `dma_rx`: in `wb_valid`, out `wb_ready`,
  in `wb_index[15:0]`, in `wb_length[15:0]`, in `wb_status[3:0]`
  (`{err_axi, err_trunc, err_crc, done}`), in `wb_irq_en`.
- Writeback covers bytes 8–15 (PKT_LEN + CTRL/STS): one or two beats
  depending on `AXI_DATA_W`; same lane-shift technique as TX.
- Event outs: `ev_rx_done`, `ev_rx_err` pulses.

**FSM:** same state list/names as `dma_desc_tx` (`ST_IDLE … ST_HALT`).
Duplicate the file rather than sharing a "generic" descriptor module — the
writeback payloads and pointer roles differ; clarity beats cleverness here.

---

### 7.8 `dma_tx_fetch.v` — TX Data Read Engine (memory → FIFO)

**Purpose:** given a buffer (`addr`, `len`), issue AXI INCR read bursts and
push bytes into the TX data FIFO. Handles unaligned start addresses, 4 KB
boundary splitting, and MAX_BURST_LEN limits.

**Parameters:** `ADDR_WIDTH`, `AXI_DATA_W`, `AXI_ID_W`, `AXI_ID`
(`TX_AXI_ID`), `MAX_BURST_LEN`, `LEN_W` (16).

**Ports**

- `clk`, `rst_n`, in `soft_reset`.
- Command (valid/ready from `dma_tx`): in `cmd_valid`, out `cmd_ready`,
  in `cmd_addr[ADDR_WIDTH-1:0]`, in `cmd_len[LEN_W-1:0]`, in `cmd_eop`,
  in `cmd_meta[15:0]` (opaque, carried to `done` — carries desc_index).
- Completion: out `done_valid` (pulse), out `done_err`, out `done_meta[15:0]`.
- FIFO push: out `fifo_wr_en`, out `fifo_wr_data[7:0]`, in `fifo_afull`
  (byte-wide push; see notes), plus out `pkt_meta_wr_en`,
  out `pkt_meta_wr_data[LEN_W:0]` (`{eop, length}`) — pushed once per command
  AFTER the last byte lands (store-and-forward commit).
- AXI read master (AR + R) to `dma_axi_rd_arb`.

**FSM:**

```verilog
localparam [2:0] ST_IDLE     = 3'd0, // wait cmd_valid
                 ST_CALC     = 3'd1, // compute next burst len (4KB / MAX / remaining)
                 ST_AR       = 3'd2, // drive arvalid
                 ST_R        = 3'd3, // accept beats, byte-unpack into FIFO
                 ST_NEXT     = 3'd4, // more bytes? -> ST_CALC : ST_DONE
                 ST_DONE     = 3'd5; // pulse done_valid, push pkt meta
```

**Implementation notes**

- Burst length calculation in `ST_CALC`:
  `beats = min(MAX_BURST_LEN, beats_to_4KB_boundary, beats_remaining)` where
  beats are AXI_DATA_W words covering `[addr_aligned, end)`.
- Byte unpacking: for each accepted R beat, shift out valid bytes (skip
  leading bytes below the unaligned start on the first beat, trailing bytes
  past `len` on the last beat) into the byte-wide FIFO. Throttle `rready`
  when the unpack shift register still holds bytes, and never accept a beat
  when `fifo_afull` — `AFULL_THRESH` must leave `≥ MAX_BURST_LEN*AXI_BYTES`
  headroom because a burst, once addressed, cannot be paused indefinitely
  without deadlock risk; simplest safe rule: only issue AR when FIFO space
  `≥ burst bytes`.
- On `rresp != OKAY`: complete the burst (drain to `rlast`), set sticky error,
  finish command with `done_err = 1`.
- Scatter-gather: one `cmd` per descriptor buffer; `cmd_eop=0` buffers do not
  push packet metadata — only the `cmd_eop=1` command pushes
  `{1'b1, total_packet_length}`; keep an accumulating `pkt_len_acc` register
  cleared after each EOP.

---

### 7.9 `dma_tx_stream.v` — TX Streamer (FIFO → AXI-Stream master)

**Purpose:** store-and-forward transmitter. Waits until a COMPLETE packet is
committed (entry present in packet-metadata FIFO), then streams it to the MAC
at line rate without gaps caused by memory latency.

**Parameters:** `AXIS_DATA_W` (8), `LEN_W` (16).

**Ports**

- `clk`, `rst_n`, in `soft_reset`, in `enable`.
- Data FIFO pop: out `fifo_rd_en`, in `fifo_rd_data[7:0]`, in `fifo_empty`.
- Packet meta FIFO pop: out `meta_rd_en`, in `meta_rd_data[LEN_W:0]`
  (`{eop=1, length}`), in `meta_empty`.
- AXI-Stream master: out `m_axis_tvalid`, in `m_axis_tready`,
  out `m_axis_tdata[AXIS_DATA_W-1:0]`, out `m_axis_tlast`,
  out `m_axis_tuser` (tie 0 — no TX error injection).
- Status: out `pkt_sent` (pulse at accepted `tlast`),
  out `byte_sent` (pulse per accepted byte, for byte counter).

**FSM:**

```verilog
localparam [1:0] ST_IDLE   = 2'd0, // wait !meta_empty && enable
                 ST_STREAM = 2'd1, // shift length bytes out, tlast on final
                 ST_GAP    = 2'd2; // one idle cycle between packets (optional, keep hook)
```

**Notes:** because the data FIFO is FWFT, `m_axis_tvalid = (state==ST_STREAM)
&& !fifo_empty`; pop on `tvalid && tready`. A byte counter counts down from
`length`; assert `tlast` when it reaches 1.

---

### 7.10 `dma_tx.v` — TX Channel Top

**Purpose:** structural glue + channel-level FSM. Instantiates
`dma_tx_fetch`, data `dma_fifo` (`DATA_W=8, DEPTH=TX_FIFO_DEPTH`), metadata
`dma_fifo` (`DATA_W=LEN_W+1, DEPTH=PKT_FIFO_DEPTH`), `dma_tx_stream`.

**Parameters:** union of children's (`ADDR_WIDTH`, `AXI_DATA_W`, `AXI_ID_W`,
`TX_AXI_ID`, `MAX_BURST_LEN`, `TX_FIFO_DEPTH`, `PKT_FIFO_DEPTH`,
`AXIS_DATA_W`, `LEN_W`).

**Ports**

- `clk`, `rst_n`.
- Control: in `enable`, in `soft_reset`; out `busy`, out `halted`,
  out `error` (sticky, cleared by soft_reset).
- Descriptor side (to/from `dma_desc_tx`): in `desc_valid`, out `desc_ready`,
  in `desc_buf_addr`, `desc_buf_len`, `desc_sop`, `desc_eop`, `desc_irq_en`,
  `desc_index`; out `wb_valid`, in `wb_ready`, out `wb_index`, out `wb_err`.
- AXI read master (pass-through from `dma_tx_fetch`).
- AXI-Stream master (pass-through from `dma_tx_stream`).
- Stats: out `tx_pkt_cnt[31:0]`, out `tx_byte_cnt[31:0]` (count here, not in
  regs).

**Channel FSM:**

```verilog
localparam [2:0] CH_IDLE     = 3'd0, // wait desc_valid
                 CH_CMD      = 3'd1, // issue cmd to dma_tx_fetch
                 CH_WAIT     = 3'd2, // wait done_valid
                 CH_WB       = 3'd3, // wb handshake to dma_desc_tx
                 CH_HALT     = 3'd4; // error hold
```

**Notes:** `busy` = state != CH_IDLE || !meta_empty. Writeback for a
descriptor is issued when its fetch completes (per-descriptor completion,
even mid-packet for SG chains) — carry `desc_index` through `cmd_meta`.
`soft_reset` flushes both FIFOs and resets children.

---

### 7.11 `dma_rx_stream.v` — RX Stream Sink (AXI-Stream slave → FIFO)

**Purpose:** accepts packets from the MAC, writes bytes into the RX data
FIFO, counts length, and on `tlast` commits `{err, length}` into the packet
metadata FIFO. Implements cut-through DROP of packets that overflow the FIFO
or exceed `MAX_PKT_LEN` (rewind write pointer — see notes).

**Parameters:** `AXIS_DATA_W` (8), `LEN_W` (16), `MAX_PKT_LEN` (default 16383).

**Ports**

- `clk`, `rst_n`, in `soft_reset`, in `enable`.
- AXI-Stream slave: in `s_axis_tvalid`, out `s_axis_tready`,
  in `s_axis_tdata[7:0]`, in `s_axis_tlast`, in `s_axis_tuser` (error flag
  qualified at `tlast`).
- Data FIFO push: out `fifo_wr_en`, out `fifo_wr_data[7:0]`,
  in `fifo_afull`, in `fifo_full`.
- **Rewind interface** to the RX data FIFO: out `fifo_commit` (pulse at good
  tlast), out `fifo_rewind` (pulse to restore write pointer to last commit).
  → Requirement: the RX data FIFO instance is `dma_fifo` extended with two
  optional ports `commit`/`rewind` guarded by parameter `PKT_MODE` (default
  0). When `PKT_MODE=1` the FIFO keeps a `wr_ptr_committed` shadow register;
  `count`/`empty` seen by the reader are computed from the committed pointer.
  This keeps ONE fifo file while supporting packet drop.
- Meta FIFO push: out `meta_wr_en`, out `meta_wr_data[LEN_W+1:0]`
  (`{err_crc, err_trunc, length}`), in `meta_full`.
- Status pulses: out `pkt_rcvd`, out `pkt_dropped`, out `byte_rcvd`.

**FSM:**

```verilog
localparam [1:0] ST_RECV = 2'd0,  // normal accept & count
                 ST_DROP = 2'd1;  // discard until tlast (overflow/oversize)
```

**Notes**

- `s_axis_tready = enable` in ST_RECV unless `meta_full` (backpressure MAC
  FIFO); in ST_DROP always 1 (swallow).
- Enter ST_DROP when `fifo_full` on a push attempt or `len_cnt == MAX_PKT_LEN`;
  pulse `fifo_rewind`, count `pkt_dropped` at the terminating tlast.
- Good `tlast`: pulse `fifo_commit`, push meta with `err_crc = tuser`.

---

### 7.12 `dma_rx_write.v` — RX Data Write Engine (FIFO → memory)

**Purpose:** for each committed packet (meta FIFO entry) and each RX
descriptor handed over by `dma_desc_rx`, generate AXI INCR write bursts into
the buffer, then report `{length, status}` for writeback.

**Parameters:** `ADDR_WIDTH`, `AXI_DATA_W`, `AXI_ID_W`, `AXI_ID`
(`RX_AXI_ID`), `MAX_BURST_LEN`, `LEN_W`.

**Ports**

- `clk`, `rst_n`, in `soft_reset`, in `enable`.
- Descriptor in (from `dma_desc_rx` via `dma_rx`): in `desc_valid`,
  out `desc_ready`, in `desc_buf_addr`, in `desc_buf_len[15:0]`,
  in `desc_irq_en`, in `desc_index[15:0]`.
- Meta FIFO pop: out `meta_rd_en`, in `meta_rd_data[LEN_W+1:0]`,
  in `meta_empty`.
- Data FIFO pop: out `fifo_rd_en`, in `fifo_rd_data[7:0]`, in `fifo_empty`.
- Writeback out: out `wb_valid`, in `wb_ready`, out `wb_index[15:0]`,
  out `wb_length[15:0]`, out `wb_status[3:0]`, out `wb_irq_en`.
- AXI write master (AW + W + B) to `dma_axi_wr_arb`.
- Stats pulses: out `pkt_written`.

**FSM:**

```verilog
localparam [3:0] ST_IDLE    = 4'd0, // wait !meta_empty (packet ready)
                 ST_GETDESC = 4'd1, // wait desc_valid (buffer available)
                 ST_CALC    = 4'd2, // burst length: min(MAX, 4KB, remaining)
                 ST_AW      = 4'd3,
                 ST_W       = 4'd4, // pack bytes -> beats, wstrb for head/tail
                 ST_B       = 4'd5,
                 ST_NEXT    = 4'd6, // more? -> ST_CALC : ST_WB
                 ST_DISCARD = 4'd7, // truncation: pop+discard excess bytes
                 ST_WB      = 4'd8, // hand off writeback
                 ST_HALT    = 4'd9;
```

**Notes**

- Truncation: if `pkt_len > desc_buf_len`, write only `desc_buf_len` bytes,
  discard the rest in `ST_DISCARD`, set `err_trunc`.
- Unaligned buffer addresses supported via `wstrb` shaping on first/last
  beats (mirror of the TX unpack logic).
- `bresp != OKAY` → set `err_axi`, still write back so software can recycle
  the descriptor; pulse channel `error`.

---

### 7.13 `dma_rx.v` — RX Channel Top

Structural mirror of `dma_tx.v`: instantiates `dma_rx_stream`,
data `dma_fifo` (`PKT_MODE=1, DATA_W=8, DEPTH=RX_FIFO_DEPTH`),
meta `dma_fifo` (`DATA_W=LEN_W+2, DEPTH=PKT_FIFO_DEPTH`), `dma_rx_write`.

**Ports:** `clk/rst_n`, control (`enable`, `soft_reset`, `busy`, `halted`,
`error`), descriptor + writeback pass-through to `dma_desc_rx`, AXI-Stream
slave pass-through, AXI write master pass-through, stats
(`rx_pkt_cnt[31:0]`, `rx_byte_cnt[31:0]`, `rx_drop_cnt[31:0]` — counters
implemented HERE from the child pulses).

No FSM needed beyond counter/sticky-error logic; keep it purely structural
plus counters.

---

### 7.14 `dma_axi_rd_arb.v` — AXI Read Arbiter (N masters → 1 port)

**Purpose:** merge the AR/R channels of `dma_desc_tx`, `dma_desc_rx`,
`dma_tx_fetch` onto the single external AXI read port.

**Parameters:** `N_MASTERS` (default 3), `ADDR_WIDTH`, `AXI_DATA_W`,
`AXI_ID_W`.

**Ports:** arrays flattened as vectors (Verilog-2001: use
`[N_MASTERS*ADDR_WIDTH-1:0] s_araddr` style packed buses, with part-select
by index):

- Per-master slave side: `s_arvalid[N-1:0]`, `s_arready[N-1:0]`,
  `s_araddr`, `s_arlen`, `s_arsize`, `s_arburst`, `s_arid` (packed);
  `s_rvalid[N-1:0]`, `s_rready[N-1:0]`, shared `s_rdata/rresp/rlast/rid`
  broadcast with per-master `rvalid` demux.
- Master side: single full AR + R channel `m_axi_ar*`, `m_axi_r*`.

**FSM:**

```verilog
localparam [1:0] ARB_IDLE  = 2'd0, // round-robin scan of s_arvalid
                 ARB_ADDR  = 2'd1, // forward AR of granted master
                 ARB_DATA  = 2'd2; // route R beats until rlast
```

**Rules**

- **Transaction-locked:** grant is held from AR acceptance until the `rlast`
  beat of that burst is accepted. Only one outstanding read transaction at a
  time (simple, safe; note as future enhancement: ID-based interleaving).
- Round-robin pointer advances past the granted master after completion.
- R routing by grant register, not by RID (single-outstanding makes this
  legal).

---

### 7.15 `dma_axi_wr_arb.v` — AXI Write Arbiter

Mirror of the read arbiter for AW/W/B with the same locking rule: grant held
from AW acceptance through `wlast` and the B handshake.

**FSM:**

```verilog
localparam [1:0] ARB_IDLE = 2'd0,
                 ARB_ADDR = 2'd1,
                 ARB_DATA = 2'd2, // route W beats until wlast
                 ARB_RESP = 2'd3; // route B to granted master
```

---

### 7.16 `dma_top.v` — DMA Subsystem Top

**Purpose:** purely structural. Instantiates and wires: `dma_regs`,
`dma_irq`, `dma_desc_tx`, `dma_desc_rx`, `dma_tx`, `dma_rx`,
`dma_axi_rd_arb`, `dma_axi_wr_arb`. No FSMs, no glue logic beyond wires
(and reset OR: `ch_rst = soft_reset | ...` style pulses are generated in
`dma_regs`, not here).

**Parameters:** the full top-level set of §3, forwarded down.

**Ports**

- `clk`, `rst_n`.
- AXI4-Lite slave (config) — forwarded to `dma_regs`.
- AXI4 master (memory): single full AW/W/B/AR/R interface — driven by the
  two arbiters.
- AXI-Stream master TX (`m_axis_tx_*`: tvalid/tready/tdata/tlast/tuser) → MAC.
- AXI-Stream slave RX (`s_axis_rx_*`: tvalid/tready/tdata/tlast/tuser) ← MAC.
- out `dma_irq`.

**Checklist for wiring**

- desc_tx AR/R + desc_rx AR/R + tx_fetch AR/R → `dma_axi_rd_arb` ports 0/1/2.
- desc_tx AW/W/B + desc_rx AW/W/B + rx_write AW/W/B → `dma_axi_wr_arb` 0/1/2.
- `dma_regs.tx_head_ptr → dma_desc_tx.head_ptr`;
  `dma_desc_tx.tail_ptr → dma_regs.tx_tail_ptr`; RX mirrored.
- Event pulses (`ev_tx_done/ev_tx_err/ev_rx_done/ev_rx_err/ev_desc_err`,
  where `ev_desc_err = desc_tx.desc_err | desc_rx.desc_err`) → `dma_irq`.
- Stats counters from `dma_tx`/`dma_rx` → `dma_regs` read muxes.

---

### 7.17 `dma_sync_cell.v` — 2-FF Synchronizer (reserved)

Simple parameterized (`WIDTH`) 2-flop synchronizer with async `rst_n`. Not
used in the single-clock configuration but part of the deliverable so that a
future multi-clock variant (e.g. separate DMA/AXI clocks) has a blessed CDC
primitive. Mark registers with `(* ASYNC_REG = "TRUE" *)` attributes.

---

## 8. End-to-End Operational Flows (use these as verification scenarios)

### 8.1 TX (software → wire)

1. SW: allocate ring, write `TX_DESC_LO/HI`, `TX_RING_SIZE`, set descriptors
   with OWN=1/SOP/EOP/IRQ_EN, write buffer data, then write `TX_HEAD_PTR`.
2. SW: set `TX_CTRL.enable`.
3. `dma_desc_tx`: sees `head != tail` → fetch → OWN=1 → dispatch to `dma_tx`.
4. `dma_tx` → `dma_tx_fetch`: AXI read bursts, bytes into TX FIFO; on EOP
   buffer completion pushes `{1, pkt_len}` into meta FIFO.
5. `dma_tx_stream`: meta entry present → streams packet, `tlast` at final byte.
6. `dma_tx` → writeback req → `dma_desc_tx`: clears OWN, sets DONE,
   increments `tail_ptr`, pulses `ev_tx_done` (if IRQ_EN).
7. `dma_irq`: coalescing → `dma_irq` asserted → SW reads `INT_STATUS`,
   writes 1 to clear, reclaims descriptors up to `TX_TAIL_PTR`.

### 8.2 RX (wire → software)

1. SW: allocate ring + buffers, all descriptors OWN=1, write ring regs,
   `RX_TAIL_PTR = ring_size-1`, set `RX_CTRL.enable`.
2. MAC delivers frame on `s_axis_rx_*`; `dma_rx_stream` fills FIFO, commits
   `{tuser, 0, length}` at tlast.
3. `dma_rx_write`: pops meta, requests descriptor from `dma_desc_rx`
   (already prefetched), bursts data into buffer, hands
   `{index, length, status}` back.
4. `dma_desc_rx`: writeback PKT_LEN + DONE (+err bits), clears OWN,
   increments `head_ptr`, pulses `ev_rx_done`.
5. SW: on IRQ reads `RX_HEAD_PTR`, consumes packets, re-arms descriptors
   (OWN=1), advances `RX_TAIL_PTR`.

### 8.3 Error scenarios that MUST behave as specified

| Scenario                                | Required behavior                                                |
|-----------------------------------------|------------------------------------------------------------------|
| RX packet, no descriptor available      | Packet held in FIFO; if FIFO fills → rewind/drop, `rx_drop_cnt`++ |
| RX packet larger than buffer            | Truncate, `ERR_TRUNC`, writeback with actual buf_len              |
| MAC flags `tuser` at tlast              | Store packet anyway, `ERR_CRC` in writeback (SW decides)          |
| AXI RRESP/BRESP error on data           | Finish burst, `ERR_AXI`/`done_err`, channel `error` sticky        |
| AXI error on descriptor fetch/writeback | `desc_err` pulse, engine → `ST_HALT`, `halted=1` until soft reset |
| OWN=0 on fetched TX desc, head!=tail    | Retry from `ST_IDLE` (no error)                                   |
| soft_reset mid-burst                    | Drain in-flight AXI transaction, then reset pointers/FIFOs        |
| `head/tail` written while running       | Sampled only in `ST_IDLE` — no mid-descriptor corruption          |

---

## 9. Verification & Sign-off Requirements

1. **Lint:** Verilator `--lint-only -Wall` clean on every file.
2. **Unit TBs** (self-checking, `$fatal` on mismatch):
   - `dma_fifo`: fill/drain, simultaneous rd/wr, flush, overflow/underflow
     stickies, PKT_MODE commit/rewind, FWFT timing (data valid when !empty).
   - `dma_axi_rd_arb` / `dma_axi_wr_arb`: 3 masters random traffic, check
     transaction atomicity and fairness.
   - `dma_desc_tx` / `dma_desc_rx` against a behavioral AXI memory model.
3. **Subsystem TB:** behavioral AXI slave memory + AXI-Stream MAC BFM;
   randomized packet lengths 1–9000 B, unaligned buffers, ring wraps
   (≥ 4 full wraps), back-to-back packets, all §8.3 error injections.
4. **Protocol checks:** assert (TB-side): AR/AW never cross 4 KB; valid
   stability; wlast/rlast position; no wstrb gaps inside a packet body.
5. **Throughput target:** sustained 1 Gb/s line rate with 64-byte frames
   (148.8 kpps) at `clk = 125 MHz`, `AXI_DATA_W = 64` — verify no MAC-side
   underrun (TX) and no drops (RX) with an AXI memory model of 20-cycle
   latency.
6. **CDC:** none inside the DMA (single clock) — state this in reports.
7. **Coverage:** every FSM state and every defined state transition hit;
   every error bit exercised.

---

## 10. Implementation Order (recommended)

1. `dma_pkg.vh`, `dma_ram_sdp`, `dma_fifo` (+ unit TB) — foundation.
2. `dma_axi_rd_arb`, `dma_axi_wr_arb` (+ unit TB).
3. `dma_tx_fetch`, `dma_tx_stream`, `dma_tx` — TX data path (TB with fake
   descriptor feed).
4. `dma_rx_stream`, `dma_rx_write`, `dma_rx` — RX data path.
5. `dma_desc_tx`, `dma_desc_rx` — descriptor engines.
6. `dma_regs`, `dma_irq`.
7. `dma_top` integration + subsystem TB + §9 sign-off.

---

*End of specification.*
