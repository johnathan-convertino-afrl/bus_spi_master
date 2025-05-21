# BUS SPI MASTER
### BUS SPI MASTER (WISHBONE STANDARD, AXI_LITE)

![image](docs/manual/img/AFRL.png)

---

  author: Jay Convertino   
  
  date: 2025.04.30
  
  details: Interface SPI Master at some rate to a AXI LITE or Wishbone Standard interface bus, duplicates Altera SPI IP registers and behavior.
  
  license: MIT   
   
  Actions:  

  [![Lint Status](../../actions/workflows/lint.yml/badge.svg)](../../actions)  
  [![Manual Status](../../actions/workflows/manual.yml/badge.svg)](../../actions)  
  
---

### Version
#### Current
  - V1.0.0 - initial release

#### Previous
  - none
#### CORES

  * AFRL:device:axi_lite_spi_master
  * AFRL:device:up_spi_master
  * AFRL:device:wishbone_classic_spi_master
### DOCUMENTATION
  For detailed usage information, please navigate to one of the following sources. They are the same, just in a different format.

  - [bus_spi_master.pdf](docs/manual/bus_spi_master.pdf)
  - [github page](https://johnathan-convertino-afrl.github.io/bus_spi_master/)

### CORES

  * AFRL:device:axi_lite_spi_master
  * AFRL:device:up_spi_master
  * AFRL:device:wishbone_classic_spi_master

### PARAMETERS

  *   ADDRESS_WIDTH    - Width of the uP address port, max 32 bit.
  *   BUS_WIDTH        - Width of the uP bus data port, only valid values are 2 or 4.
  *   WORD_WIDTH       - Width of each SPI Master word. This will also set the bits used in the TX/RX data registers. Must be less than or equal to BUS_WIDTH. VALID VALUES: 1 to 4.
  *   CLOCK_SPEED      - This is the aclk frequency in Hz, this is the the frequency used for the bus and is divided by the rate.
  *   SELECT_WIDTH     - Bit width of the slave select, defaults to 16 to match altera spi ip.
  *   DEFAULT_RATE_DIV - Default divider value of the main clock to use for the spi data output clock rate. 0 is 2 (2^(X+1) X is the DEFAULT_RATE_DIV)
  *   DEFAULT_CPOL     - Default clock polarity for the core (0 or 1).
  *   DEFAULT_CPHA     - Default clock phase for the core (0 or 1).

### REGISTERS

This is a list of registers, the manual has details on there usage.

  * 0x00 = RX_DATA_REG
  * 0x04 = TX_DATA_REG
  * 0x08 = STATUS_REG
  * 0x0C = CONTROL_REG
  * 0x10 = RESERVED
  * 0x14 = SLAVE_SELECT_REG
  * 0x18 = EOP_VALUE_REG
  * 0x1C = CONTROL_EXT_REG

### COMPONENTS
#### SRC

  * up_spi_master.v
  * wishbone_classic_spi_master.v
  * axi_lite_spi_master.v
  
#### TB

  * tb_cocotb_up.v
  * tb_cocotb_up.py
  * tb_cocotb_axi_lite.v
  * tb_cocotb_axi_lite.py
  * tb_cocotb_wishbone_standard.v
  * tb_cocotb_wishbone_standard.py

### FUSESOC

  * fusesoc_info.core created.
  * Simulation uses cocotb with icarus to run data through the core.

#### Targets

  * RUN WITH: (fusesoc run --target=sim VENDER:CORE:NAME:VERSION)
    - default (for IP integration builds)
    - lint
    - sim_cocotb

