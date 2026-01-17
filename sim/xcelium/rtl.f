#===============================================================================
# File: rtl.f
# Description: RTL file list for Gigabit Ethernet MAC IP
#
# Usage:
#   xrun -f rtl.f ...
#
# Note:
#   All paths are relative to project_root
#   Compile order: dependencies first
#
# Author: AI-IP Generator
#===============================================================================

#-------------------------------------------------------------------------------
# MAC Core RTL (Verilog)
#-------------------------------------------------------------------------------

# CRC32 module (no dependencies)
${PROJECT_ROOT}/rtl/mac_core/mac_crc32.v

# CDC FIFO (no dependencies)
${PROJECT_ROOT}/rtl/mac_core/mac_cdc_fifo.v

# GMII interface module
${PROJECT_ROOT}/rtl/mac_core/mac_gmii_if.v

# Register block (AXI-Lite slave)
${PROJECT_ROOT}/rtl/mac_core/mac_regs.v

# TX datapath
${PROJECT_ROOT}/rtl/mac_core/mac_tx.v

# RX datapath
${PROJECT_ROOT}/rtl/mac_core/mac_rx.v

# Top-level MAC integration
${PROJECT_ROOT}/rtl/mac_core/mac_top.v

#-------------------------------------------------------------------------------
# PHY Interface RTL (Verilog)
#-------------------------------------------------------------------------------

# GMII PHY interface wrapper
${PROJECT_ROOT}/rtl/phy_if/gmii_phy_if.v

# RGMII PHY interface (behavioral DDR)
${PROJECT_ROOT}/rtl/phy_if/rgmii_phy_if.v

#-------------------------------------------------------------------------------
# DMA RTL (Verilog) - Optional
#-------------------------------------------------------------------------------

# DMA package (parameters and types)
${PROJECT_ROOT}/rtl/dma/dma_pkg.v

# DMA descriptor module
${PROJECT_ROOT}/rtl/dma/dma_desc.v

# DMA TX engine
${PROJECT_ROOT}/rtl/dma/dma_tx.v

# DMA RX engine
${PROJECT_ROOT}/rtl/dma/dma_rx.v

# DMA registers (AXI-Lite slave)
${PROJECT_ROOT}/rtl/dma/dma_regs.v

# DMA top-level integration
${PROJECT_ROOT}/rtl/dma/dma_top.v

#-------------------------------------------------------------------------------
# Ethernet Controller Integration (MAC + DMA)
#-------------------------------------------------------------------------------

# Controller registers (MAC + DMA combined)
${PROJECT_ROOT}/rtl/dma/eth_controller_regs.v

# Controller interrupt handler
${PROJECT_ROOT}/rtl/dma/eth_controller_irq.v

# Controller top-level
${PROJECT_ROOT}/rtl/dma/eth_controller_top.v
