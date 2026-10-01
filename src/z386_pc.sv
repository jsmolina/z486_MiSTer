// z386 (copied from Marty_MiSTer, see src/z386/UPSTREAM.md) behind the z486
// port list, so system.sv swaps CPUs at build time (cpu_z386.qip).
//
// The core advances on a 16 MHz clock enable taken from clk; memory, video,
// timers and every other SoC block keep running on clk as before.
//
// The SoC answers ready/resp_valid on any clk cycle, but the core only
// samples them on an enable, so:
//   * an accepted request hides valid/inta and hands ready to the core on its
//     next enable;
//   * read words wait in a small FIFO and go to the core one per enable,
//     never on the enable that delivers ready (the core counts a read as
//     pending only from that enable on);
//   * a code fetch the core discards (code_abort) is answered no further:
//     one not yet taken never goes out, words still owed are dropped.
//
// L1 caches are off, as on a real 386DX: every access is a bus cycle, which
// makes A20 masking here safe and leaves nothing for DMA snoops to invalidate.
// ponytail: no 387. ESC opcodes run as NOPs, so a BIOS probe finds no FPU.
module z386_pc #(
    parameter PROTECT_UMA_ROM = 0,
    parameter DCACHE_SET_BITS = 7,           // unused: z486 interface
    parameter ICACHE_SET_BITS = 7,           // unused: z486 interface
    parameter ENABLE_X87 = 0,                // unused: z486 interface
    parameter ENABLE_DEVICE_MMIO = 0,        // unused: nothing is cached
    parameter [31:0] DEVICE_MMIO_MASK = 32'hff00_0000,
    parameter [6:0] CLOCK_RATE_MHZ = 7'd85,
    parameter [6:0] CPU_MHZ = 7'd16
)
(
    input              clk,
    input              reset_n,
    input              device_mmio_enable,
    input      [31:0]  device_mmio_base,

    output     [31:2]  addr,
    output      [3:0]  be,
    output      [7:0]  burstcount,
    output             line_read,
    input      [31:0]  din,
    input      [127:0] line_din,
    output     [31:0]  dout,
    output             valid,
    input              ready,
    output             write,
    output             io,
    input              resp_valid,
    input              line_resp_valid,

    input              intr,
    input              nmi,
    output             inta,

    input      [31:0]  snoop_addr,
    input              snoop_valid,

    input              a20_enable,
    input       [1:0]  cpu_speed_sel,        // ignored: fixed CPU_MHZ

    input              single_step,

    output     [15:0]  dbg_CS,
    output     [31:0]  dbg_EIP,
    output     [31:0]  dbg_CS_base,
    output             dbg_pe,
    output             dbg_vm,
    output     [31:0]  dbg_x87_state,

    output reg         triple_fault_reset
);

// ---- CPU_MHZ enable: CPU_MHZ pulses every CLOCK_RATE_MHZ clocks ----
reg [7:0] ce_acc = 8'd0;
reg       ce = 1'b0;
always @(posedge clk) begin
    if (ce_acc + CPU_MHZ >= CLOCK_RATE_MHZ) begin
        ce_acc <= ce_acc + CPU_MHZ - CLOCK_RATE_MHZ;
        ce     <= 1'b1;
    end else begin
        ce_acc <= ce_acc + CPU_MHZ;
        ce     <= 1'b0;
    end
end

// ---- core ----
wire [31:2] c_addr;
wire [31:0] c_din;
wire        c_valid, c_ready, c_resp, c_io, c_inta, c_code, c_abort, c_shutdown;

z386 #(.PROTECT_UMA_ROM(PROTECT_UMA_ROM)) core386 (
    .clk(clk),
    .clk_en(ce),
    .cache_enable(1'b0),
    .ram_size(2'd0),            // Towns memory map: only steers caching, which is off
    .reset_n(reset_n),
    .addr(c_addr),
    .be(be),
    .burstcount(burstcount),
    .din(c_din),
    .dout(dout),
    .valid(c_valid),
    .ready(c_ready),
    .write(write),
    .io(c_io),
    .code(c_code),
    .code_abort(c_abort),
    .lock(),
    .more(),
    .resp_valid(c_resp),
    .intr(intr),
    .nmi(nmi),
    .inta(c_inta),
    .shutdown(c_shutdown),
    .halt(),
    .code_queued(),
    .snoop_addr(32'd0),
    .snoop_valid(1'b0),
    .single_step(single_step),
    .dbg_CS(dbg_CS),
    .dbg_EIP(dbg_EIP),
    .dbg_CS_base(dbg_CS_base),
    .dbg_pe(dbg_pe),
    .dbg_pg(),
    .dbg_vm(dbg_vm),
    .dbg_retire(),
    .dbg_next_eip(),
    .dbg_gpr(),
    .dbg_seg(),
    .dbg_halted(),
    .dbg_stopped_in_hlt(),
    .dbg_state_sel(6'd0),
    .dbg_state(),
    .dbg_store_pending()
);

assign addr          = {c_addr[31:21], c_addr[20] & a20_enable, c_addr[19:2]};
assign line_read     = 1'b0;
assign dbg_x87_state = 32'd0;

// A shutdown cycle asks the board to pulse RESET (system.sv warm reset).
always @(posedge clk) triple_fault_reset <= c_shutdown;

// ---- request handshake ----
// No new cycle while words of a discarded fetch are still arriving (drop):
// system.sv steers resp_valid by io/inta, so those stay low until they are
// in. A code request still waiting in the core when it discards the fetch
// is acknowledged to the core and never reaches the bus.
reg  [7:0] drop;                            // words still to come that are discarded
reg  acc;                                   // taken; ready goes to the core next enable
wire quiet     = reset_n && drop == 8'd0;
wire dead_code = c_valid && c_code && c_abort;
assign valid   = quiet && c_valid && !acc && !dead_code;
assign inta    = quiet && c_inta && !acc;
assign io      = quiet && c_io;
assign c_ready = ce && (acc || dead_code);
wire   take    = valid && ready;

always @(posedge clk) begin
    if (!reset_n)  acc <= 1'b0;
    else if (take) acc <= 1'b1;
    else if (ce)   acc <= 1'b0;
end

// ---- read responses ----
// I/O and INTA answer resp_valid with ready even for writes, so only words
// owed to a taken read count.
reg  [7:0] owed;                            // words the SoC still sends
reg        code_rd;                         // the read in flight is a code fetch
wire       take_read = take && !write;
wire       resp_in   = resp_valid && (owed != 8'd0 || take_read);
wire       abort     = ce && c_abort && code_rd;

reg [31:0] fifo [0:7];                      // one burst (<= 4 words) at a time
reg  [2:0] wp, rp;
wire       keep = resp_in && drop == 8'd0;
assign c_resp = ce && !acc && !c_abort && wp != rp;
assign c_din  = fifo[rp];

always @(posedge clk) begin
    if (keep) fifo[wp] <= din;
    if (!reset_n) begin
        owed <= 8'd0;
        drop <= 8'd0;
        wp <= 3'd0;
        rp <= 3'd0;
        code_rd <= 1'b0;
    end else begin
        owed <= owed + (take_read ? burstcount : 8'd0) - resp_in;
        if (take_read)
            code_rd <= c_code;
        if (keep)
            wp <= wp + 3'd1;
        if (abort) begin
            // Everything owed so far belongs to the discarded fetch; one
            // arriving now is flushed with the FIFO.
            drop <= owed - resp_in;
            rp <= keep ? wp + 3'd1 : wp;
        end else begin
            if (resp_in && drop != 8'd0)
                drop <= drop - 8'd1;
            if (c_resp)
                rp <= rp + 3'd1;
        end
    end
end

endmodule
