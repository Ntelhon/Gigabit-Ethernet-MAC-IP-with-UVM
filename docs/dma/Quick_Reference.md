# DMA Quick Reference

Quick reference for integrating and using the Ethernet DMA subsystem.

---

## Parameter Quick Reference

```verilog
eth_controller_top #(
    // === DMA Control ===
    .DMA_ENABLE         (1),         // 1=enabled, 0=bypass
    
    // === MAC Parameters ===
    .AXI_ADDR_WIDTH     (8),         // MAC register address width
    .AXI_DATA_WIDTH     (32),        // Fixed: 32-bit
    .TX_FIFO_DEPTH      (4),         // Log2(FIFO depth)
    .RX_FIFO_DEPTH      (4),
    .MIN_FRAME_SIZE     (64),
    .MAX_FRAME_SIZE     (1518),
    .IFG_BYTES          (12),
    
    // === DMA Parameters ===
    .DMA_ADDR_WIDTH     (8),         // DMA register address width
    .M_AXI_ADDR_WIDTH   (32),        // Memory address width (32 or 64)
    .M_AXI_DATA_WIDTH   (64),        // Memory data width (32/64/128)
    .M_AXI_ID_WIDTH     (4),
    .M_AXI_MAX_BURST    (16),        // Max AXI burst length
    .DESC_ADDR_WIDTH    (32),        // Descriptor address width
    .DESC_RING_DEPTH    (8),         // Log2(ring size): 2^8 = 256 desc
    .BUF_SIZE_WIDTH     (14)         // Max buffer: 2^14 = 16KB
) u_eth (...);
```

---

## Register Quick Reference

### MAC Registers (Base Address: Configure in SoC)

```c
#define MAC_ADDR_LO       0x00   // RW: MAC address [31:0]
#define MAC_ADDR_HI       0x04   // RW: MAC address [47:32]
#define MAC_CONTROL       0x08   // RW: [1:0] = {rx_en, tx_en}
#define MAC_STATUS        0x0C   // RO: [1:0] = {rx_active, tx_active}
#define MAC_INT_STATUS    0x10   // RW1C: Interrupt status
#define MAC_INT_MASK      0x14   // RW: Interrupt mask
#define MAC_TX_FRAME_CNT  0x18   // RO: TX frame count
#define MAC_RX_FRAME_CNT  0x1C   // RO: RX frame count
#define MAC_RX_ERR_CNT    0x20   // RO: RX error count
#define MAC_VERSION       0x24   // RO: 0x00010000
```

### DMA Registers (Base Address: Configure in SoC)

```c
#define DMA_CONTROL          0x00   // RW: [2:0] = {reset, rx_en, tx_en}
#define DMA_STATUS           0x04   // RO: [1:0] = {rx_busy, tx_busy}
#define TX_DESC_BASE_LO      0x08   // RW: TX descriptor base [31:0]
#define TX_DESC_BASE_HI      0x0C   // RW: TX descriptor base [63:32]
#define TX_DESC_RING_SIZE    0x10   // RW: Log2(TX ring size)
#define RX_DESC_BASE_LO      0x14   // RW: RX descriptor base [31:0]
#define RX_DESC_BASE_HI      0x18   // RW: RX descriptor base [63:32]
#define RX_DESC_RING_SIZE    0x1C   // RW: Log2(RX ring size)
#define DMA_INT_STATUS       0x20   // RW1C: Interrupt status
#define DMA_INT_MASK         0x24   // RW: Interrupt mask
#define TX_PKT_COUNT         0x28   // RO: TX packet count
#define RX_PKT_COUNT         0x2C   // RO: RX packet count
#define TX_ERR_COUNT         0x30   // RO: TX error count
#define RX_ERR_COUNT         0x34   // RO: RX error count
#define DMA_VERSION          0x38   // RO: 0x00010000
```

---

## Descriptor Quick Reference

### TX Descriptor Layout (128 bits / 16 bytes)

```c
struct eth_tx_desc {
    uint64_t buffer_addr;    // [63:0]   Physical address
    uint16_t buffer_len;     // [79:64]  Packet length (bytes)
    uint16_t reserved0;      // [95:80]  Reserved
    uint16_t control;        // [111:96] Control bits
    uint16_t status;         // [127:112] Status bits (written by DMA)
};

// Control bits
#define DESC_OWN      (1 << 0)   // Bit 96:  0=CPU, 1=DMA
#define DESC_LAST     (1 << 1)   // Bit 97:  Last descriptor
#define DESC_CRC_EN   (1 << 2)   // Bit 98:  Enable CRC (unused)
#define DESC_INT_EN   (1 << 3)   // Bit 99:  Interrupt enable

// Status bits (read-only, written by DMA)
#define DESC_DONE     (1 << 0)   // Bit 112: Transmission done
#define DESC_ERR      (1 << 1)   // Bit 113: Error occurred
```

### RX Descriptor Layout (128 bits / 16 bytes)

```c
struct eth_rx_desc {
    uint64_t buffer_addr;    // [63:0]   Physical address
    uint16_t buffer_len;     // [79:64]  Buffer size (max packet)
    uint16_t reserved0;      // [95:80]  Reserved
    uint16_t control;        // [111:96] Control bits
    uint16_t status;         // [127:112] Status bits (written by DMA)
};

// Control bits
#define DESC_OWN      (1 << 0)   // Bit 96:  0=CPU, 1=DMA
#define DESC_WRAP     (1 << 1)   // Bit 97:  Wrap to ring start
#define DESC_INT_EN   (1 << 2)   // Bit 98:  Interrupt enable

// Status bits (read-only, written by DMA)
#define DESC_DONE     (1 << 0)   // Bit 112: Reception done
#define DESC_ERR      (1 << 1)   // Bit 113: Error occurred
#define DESC_CRC_ERR  (1 << 2)   // Bit 114: CRC error
#define STATUS_LEN_MASK 0x1FFF   // Bits [127:115]: Actual length
#define STATUS_LEN_SHIFT 3
```

---

## Initialization Code Template

```c
// 1. Reset DMA
write32(DMA_CONTROL, 0x04);  // Set reset bit
while (read32(DMA_CONTROL) & 0x04);  // Wait for self-clear

// 2. Configure MAC address
write32(MAC_ADDR_LO, 0x44332211);
write32(MAC_ADDR_HI, 0x00006655);

// 3. Allocate descriptor rings
tx_desc_ring = memalign(4096, 4096);  // 256 descriptors
rx_desc_ring = memalign(4096, 4096);

// 4. Initialize TX descriptors
for (int i = 0; i < 256; i++) {
    tx_desc_ring[i].buffer_addr = 0;
    tx_desc_ring[i].buffer_len = 0;
    tx_desc_ring[i].control = 0;  // OWN=0 (CPU owns)
    tx_desc_ring[i].status = 0;
}

// 5. Initialize RX descriptors
for (int i = 0; i < 256; i++) {
    rx_buffers[i] = memalign(64, 2048);
    rx_desc_ring[i].buffer_addr = virt_to_phys(rx_buffers[i]);
    rx_desc_ring[i].buffer_len = 2048;
    rx_desc_ring[i].control = DESC_OWN | DESC_INT_EN;  // DMA owns
    if (i == 255) rx_desc_ring[i].control |= DESC_WRAP;
    rx_desc_ring[i].status = 0;
}

// 6. Program DMA
write32(TX_DESC_BASE_LO, virt_to_phys(tx_desc_ring) & 0xFFFFFFFF);
write32(TX_DESC_BASE_HI, virt_to_phys(tx_desc_ring) >> 32);
write32(TX_DESC_RING_SIZE, 8);  // log2(256)

write32(RX_DESC_BASE_LO, virt_to_phys(rx_desc_ring) & 0xFFFFFFFF);
write32(RX_DESC_BASE_HI, virt_to_phys(rx_desc_ring) >> 32);
write32(RX_DESC_RING_SIZE, 8);

// 7. Enable interrupts
write32(DMA_INT_MASK, 0x0F);  // All interrupts

// 8. Enable MAC
write32(MAC_CONTROL, 0x03);  // TX_EN | RX_EN

// 9. Enable DMA
write32(DMA_CONTROL, 0x03);  // TX_EN | RX_EN
```

---

## Send Packet Template

```c
int send_packet(uint8_t *data, uint16_t len) {
    // Get current TX descriptor
    struct eth_tx_desc *desc = &tx_desc_ring[tx_index];
    
    // Check if free
    if (desc->control & DESC_OWN)
        return -EBUSY;
    
    // Copy data to buffer
    memcpy(tx_buffers[tx_index], data, len);
    flush_dcache(tx_buffers[tx_index], len);
    
    // Setup descriptor
    desc->buffer_addr = virt_to_phys(tx_buffers[tx_index]);
    desc->buffer_len = len;
    desc->control = DESC_OWN | DESC_LAST | DESC_INT_EN;
    
    // Advance index
    tx_index = (tx_index + 1) % 256;
    
    return 0;
}
```

---

## Receive Packet Handler Template

```c
void rx_interrupt_handler(void) {
    while (1) {
        struct eth_rx_desc *desc = &rx_desc_ring[rx_index];
        
        // Check if packet available
        if (desc->control & DESC_OWN)
            break;  // DMA still owns
        
        if (!(desc->status & DESC_DONE))
            break;  // Not done yet
        
        // Check errors
        if (desc->status & DESC_ERR) {
            // Handle error
            stats.rx_errors++;
        } else {
            // Get length
            uint16_t len = (desc->status >> STATUS_LEN_SHIFT) & STATUS_LEN_MASK;
            
            // Invalidate cache
            invalidate_dcache(rx_buffers[rx_index], len);
            
            // Process packet
            process_packet(rx_buffers[rx_index], len);
        }
        
        // Give back to DMA
        desc->control = DESC_OWN | DESC_INT_EN;
        if (rx_index == 255)
            desc->control |= DESC_WRAP;
        desc->status = 0;
        
        rx_index = (rx_index + 1) % 256;
    }
    
    // Clear interrupt
    write32(DMA_INT_STATUS, 0x02);  // RX_DONE
}
```

---

## Common Issues & Solutions

### Issue: No packets transmitted

**Check**:
1. MAC TX enabled? `read32(MAC_CONTROL) & 0x01`
2. DMA TX enabled? `read32(DMA_CONTROL) & 0x01`
3. Descriptor OWN bit set? `desc->control & DESC_OWN`
4. Descriptor ring base programmed correctly?

### Issue: No packets received

**Check**:
1. MAC RX enabled? `read32(MAC_CONTROL) & 0x02`
2. DMA RX enabled? `read32(DMA_CONTROL) & 0x02`
3. RX descriptors owned by DMA? `desc->control & DESC_OWN`
4. PHY link up?

### Issue: AXI bus errors

**Check**:
1. Descriptor addresses aligned to 16 bytes
2. Buffer addresses aligned to 8 bytes
3. Memory addresses within valid range
4. AXI master connected correctly

### Issue: Data corruption

**Check**:
1. Cache coherency (flush TX, invalidate RX)
2. Buffer size sufficient (>= 1518 bytes for RX)
3. No buffer overlap
4. Correct endianness

---

## Performance Tuning

### For Maximum Throughput

```verilog
.M_AXI_DATA_WIDTH   (64),        // Wider bus
.M_AXI_MAX_BURST    (16),        // Longer bursts
.DESC_RING_DEPTH    (10),        // 1024 descriptors
```

```c
// Larger RX buffers
rx_buffer_size = 2048;  // Or 4096

// Batch interrupt processing
interrupt_coalescing = 10;  // Process 10 packets per interrupt
```

### For Low Latency

```verilog
.M_AXI_DATA_WIDTH   (32),        // Simpler
.M_AXI_MAX_BURST    (4),         // Shorter bursts
.DESC_RING_DEPTH    (6),         // 64 descriptors
```

```c
// Smaller RX buffers
rx_buffer_size = 1536;

// Immediate interrupt
interrupt_coalescing = 1;  // Process immediately
```

### For Low Power

```verilog
.DMA_ENABLE         (0),         // Bypass DMA if possible
```

Or:
```c
// Disable DMA when idle
if (no_traffic)
    write32(DMA_CONTROL, 0x00);  // Disable TX and RX
```

---

## Memory Budget Calculator

```
Ring Size (descriptors) = 2^DESC_RING_DEPTH

Descriptor Memory = Ring Size × 16 bytes
TX Buffers Memory = Ring Size × max_packet_size
RX Buffers Memory = Ring Size × max_packet_size

Total = Descriptor Memory + TX Buffers + RX Buffers

Example (DESC_RING_DEPTH=8, max_packet=2048):
  Descriptors: 256 × 16 = 4 KB
  TX Buffers:  256 × 2KB = 512 KB
  RX Buffers:  256 × 2KB = 512 KB
  Total:                  ~1 MB
```

---

## Debug Checklist

When something goes wrong:

- [ ] Read DMA_STATUS register - is DMA busy/idle?
- [ ] Read MAC_STATUS register - is MAC active?
- [ ] Read DMA_INT_STATUS - any error interrupts?
- [ ] Read TX_ERR_COUNT / RX_ERR_COUNT - non-zero?
- [ ] Check descriptor ring - OWN bits correct?
- [ ] Verify memory addresses are physical, not virtual
- [ ] Check cache coherency operations
- [ ] Verify PHY link status (GMII signals)
- [ ] Run loopback test (TX → PHY → RX)
- [ ] Check AXI interconnect configuration

---

## Useful Registers to Monitor

```c
// DMA health check
printf("DMA Status: 0x%08x\n", read32(DMA_STATUS));
printf("TX Done: %u, RX Done: %u\n",
       read32(TX_PKT_COUNT), read32(RX_PKT_COUNT));
printf("TX Err: %u, RX Err: %u\n",
       read32(TX_ERR_COUNT), read32(RX_ERR_COUNT));

// MAC health check
printf("MAC Status: 0x%08x\n", read32(MAC_STATUS));
printf("MAC TX: %u, MAC RX: %u\n",
       read32(MAC_TX_FRAME_CNT), read32(MAC_RX_FRAME_CNT));
```

---

For complete documentation, see:
- [DMA Architecture](DMA_Architecture.md)
- [Integration Guide](DMA_Integration_Guide.md)
- [Verification Plan](DMA_UVM_Verification_Plan.md)
