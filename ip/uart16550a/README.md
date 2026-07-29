# UART 16550A Implementation

## Overview

This folder contains a custom implementation of the UART 16550A. This IP is optimized for a minimal SoC environment, and strips away legacy or unused pins (like legacy modem controls) in favor of a simplified interface.

The core components of this IP include:

* RX and TX FIFOs
* Receive (RSR) and Transmit (TSR) Shift Registers
* Baud Rate Generator
* Interrupt Controller

## Interface Pinout

Unlike the standard UART 16550A footprint, this implementation uses a simplified bus interface:

| Signal      | Direction | Description           |
| ---         | ---       | ---                   |
| `clk`       | Input     | System clock          |
| `rst`       | Input     | System reset          |
| `reg_addr`  | Input     | Register address      |
| `reg_re`    | Input     | Register read enable  |
| `reg_we`    | Input     | Register write enable |
| `reg_wdata` | Input     | Register write data   |
| `reg_rdata` | Output    | Register read data    |
| `rx`        | Input     | Serial data input     |
| `tx`        | Output    | Serial data output    |
| `intr`      | Output    | Interrupt request     |

## Register Map

| Offset | DLAB | Register | Description | Access |
| --- | --- | --- | --- | --- |
| `0x0` | 0 | RBR / THR | Receiver Buffer / Transmitter Holding | R / W |
| `0x0` | 1 | DLL | Divisor Latch LSB | R/W |
| `0x1` | 0 | IER | Interrupt Enable | R/W |
| `0x1` | 1 | DLM | Divisor Latch MSB | R/W |
| `0x2` | X | IIR | Interrupt Identification | R |
| `0x2` | X | FCR | FIFO Control | W |
| `0x3` | X | LCR | Line Control | R/W |
| `0x4` | X | MCR | Modem Control | R/W |
| `0x5` | X | LSR | Line Status | R |
| `0x6` | X | MSR | Modem Status | R |
| `0x7` | X | SCR | Scratchpad | R/W |

---

## Register Bit Fields

### LCR (Line Control Register)

In almost all use cases, this is set to `0x03` (normal operation) or `0x83` (programming the baud generator). In a minimal SoC environment, parity bits (3-5) may be tied to 0.

* **[0]** Word length select bit 0 (WLS0)
* **[1]** Word length select bit 1 (WLS1)
> *Note on WLS:* 8-bit word length is standard, requiring both [0] and [1] to be set.

* **[2] Number of stop bits (STB)**
> *Important Note:* This bit specifies either one, one and one-half, or two stop bits in each transmitted character. When bit 2 is cleared, one stop bit is generated. When bit 2 is set, the number of stop bits generated depends on the word length selected with bits 0 and 1. **The receiver clocks only the first stop bit regardless of the number of stop bits selected.**

* **[3]** Parity enable (PEN)
* **[4]** Even parity select (EPS)
* **[5]** Stick parity (can share logic with EPS if optimizing)
* **[6]** Break control (forces TX/SOUT to 0)
* **[7]** DLAB (Must be cleared to read/write RBR, THR, or IER)

### FCR (FIFO Control Register)

* **[0]** FIFO enable (Changing this bit clears the FIFOs)
* **[1]** Receiver FIFO reset (Clears FIFO and its counter; self-clearing)
* **[2]** Transmitter FIFO reset (Clears FIFO and its counter; self-clearing)
* **[3]** DMA mode select
* **[4:5]** *Reserved*
* **[6]** Receiver trigger LSB
* **[7]** Receiver trigger MSB
> *Note:* Bits 6-7 choose the RX FIFO trigger level: 1, 4, 8, or 14 bytes.

### IER (Interrupt Enable Register)

Bits 4-7 are unused and always cleared.

* **[0]** Enables the received data available interrupt (ERBI)
* **[1]** Enables the THRE interrupt (ETBEI)
* **[2]** Enables the receiver line status interrupt (ELSI)
* **[3]** Enables the modem status interrupt (EDSSI)

### IIR (Interrupt Identification Register)

Bits 4-5 are unused and always cleared. Priorities (Highest to lowest): 1. ELSI, 2. ERBI/Timeout, 3. ETBEI, 4. EDSSI.

* **[0]** 0 if interrupt pending
* **[1]** Interrupt ID bit 1
* **[2]** Interrupt ID bit 2
* **[3]** Interrupt ID bit 3 (Always cleared in non-FIFO mode; otherwise set with bit 2 for time-out interrupt)
* **[6]** FIFOs enabled
* **[7]** FIFOs enabled

### LSR (Line Status Register)

* **[0] Data ready (DR):** Set when character received into RBR/FIFO. Cleared by reading all data.
* **[1] Overrun error (OE):** Set when character in RBR is overwritten before being read. Cleared by reading LSR.
* **[2] Parity error (PE)** Set when the received character does not have valid parity as configured by the LCR. Cleared every time the CPU reads the LSR.
* **[3] Framing error (FE):** Set when received character lacks a valid stop bit. Cleared by reading LSR.
* **[4] Break interrupt (BI):** Set when RX data is low for longer than a full-word transmission. Cleared by reading LSR. Only one `0` character is loaded into the FIFO during a break.
* **[5] Transmitter holding register empty (THRE):** Set when THR is empty (or TX FIFO is empty in FIFO mode). Cleared when CPU loads THR (or writes at least 1 byte to TX FIFO).
* **[6] Transmitter empty (TEMT):** Set when THR and TSR (and TX FIFO) are both empty.
* **[7] Error in receiver FIFO:** Set when at least one PE, FE, or BI error is in the FIFO. Cleared by reading LSR when no errors remain.

### MCR (Modem Control Register)

*(Primarily stubbed/ignored in this implementation)*

* **[0]** Data terminal ready (DTR)
* **[1]** Request to send (RTS)
* **[2]** OUT1
* **[3]** OUT2
* **[4]** Loop
* **[5]** Autoflow control enable (AFE)

### MSR (Modem Status Register)

*(Primarily stubbed/ignored in this implementation)*

* **[0]** Delta clear to send
* **[1]** Delta data set ready
* **[2]** Trailing edge ring indicator
* **[3]** Delta data carrier detect
* **[4]** Clear to send
* **[5]** Data set ready
* **[6]** Ring indicator
* **[7]** Data carrier detect

---

## Hardware Design Considerations & Rules of Thumb

* **Datapath vs. Control Path:** Mask control paths strictly, but leave data paths "dumb". Do not overcomplicate data path assignments.
* **Oversampling:** 16x oversampling is used to sample in the middle of the bit (typically around tick 7 or 8). This ensures stable sampling and compensates for the slight delay between the 1->0 RX start transition and external baud generator alignment.
* **Clock Domains:** The baud rate generator is *only* used for serializing RX and TX. All other operations take place on the system clock.
* **State Machines:** Use robust state definitions (e.g., `IDLE`, `RECORD`, `STOP`). Use `default` statements in case blocks to prevent inferred latches upon power-up and add protection against transient faults (e.g., bit flips in noisy environments).
* **Error Handling:** Never assume only one error can happen at a time (e.g., `logic [1:0] rx_err`). Always verify multi-error conditions.
* **Optimization:** In ASICs, equality checks like `(a == b)` are generally faster and cheaper to synthesize than magnitude comparators `(a < b)`. Optimize TX/RX assignments, especially regarding empty flags and shift register initialization.
* **Triple Voting (Triple Modular Redundancy):** If deploying this IP in harsh, electrically noisy, or high-radiation environments (e.g., aerospace or heavy industrial), consider implementing majority voting (TMR) to mitigate Single Event Upsets (SEUs).
    * **RX Sampling:** Instead of relying on a single sample at the 8th tick of the 16x baud clock, sample at the 7th, 8th, and 9th ticks. A majority vote of these three samples determines the final bit value, effectively filtering out brief voltage spikes on the `rx` line.
    * **State Machines & Control Registers:** For extreme reliability, instantiate critical state machines and configuration registers (like `LCR` and `FCR`) three times. Feed their outputs into a majority voter circuit so that a random transient fault cannot accidentally change the baud rate or reset the FIFOs mid-transmission.
## Example Device Tree (DTS) Node

```dts
uart0: serial@10000000 {
    compatible = "ns16550a";
    reg = <0x0 0x10000000 0x0 0x100>;
    interrupts = <10>;
    interrupt-parent = <&plic>;
    clock-frequency = <100000000>;
    reg-shift = <0>;
    reg-io-width = <1>;
    status = "okay";
};

```
