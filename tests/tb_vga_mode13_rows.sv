`timescale 1ns/1ps

module tb_vga_mode13_rows;
    logic clk_sys = 0;
    wire clk_vga;
    logic rst_n = 0;
    logic [3:0] io_address = 0;
    logic io_read = 0;
    wire [7:0] io_readdata;
    logic io_write = 0;
    logic [7:0] io_writedata = 0;
    logic io_b_cs = 0;
    logic io_c_cs = 0;
    logic io_d_cs = 0;
    logic [16:0] mem_address = 0;
    logic mem_read = 0;
    wire [7:0] mem_readdata;
    logic mem_write = 0;
    logic [7:0] mem_writedata = 0;
    wire irq;
    logic [27:0] clock_rate_vga = 28'd25_175_000;
    wire vga_ce;
    logic vga_f60 = 0;
    wire [2:0] vga_memmode;
    wire vga_blank_n;
    wire vga_off;
    wire vga_horiz_sync;
    wire vga_vert_sync;
    wire [7:0] vga_r;
    wire [7:0] vga_g;
    wire [7:0] vga_b;
    wire [17:0] vga_pal_d;
    wire [7:0] vga_pal_a;
    wire vga_pal_we;
    wire [19:0] vga_start_addr;
    wire [5:0] vga_wr_seg;
    wire [5:0] vga_rd_seg;
    wire [8:0] vga_width;
    wire [8:0] vga_stride;
    wire [10:0] vga_height;
    wire [3:0] vga_flags;
    wire vga_chain4;
    wire [3:0] vga_map_mask;
    wire [1:0] vga_read_plane;
    wire [1:0] vga_write_mode;
    logic vga_lores = 0;
    logic vga_border = 0;
    logic scanline_req_valid = 0;
    wire scanline_req_ready;
    logic scanline_frame_start = 0;
    logic [10:0] scanline_y = 0;
    wire [10:0] scanline_width;
    wire [10:0] scanline_height;
    wire [31:0] scanline_native_frames;
    wire scanline_done;

    always #5 clk_sys = ~clk_sys;
    assign clk_vga = clk_sys;

    vga #(.ONDEMAND_SCANOUT(1'b0)) dut (.*);

    // Mode 13h: max scan line 1, CRTC 09 bit 7 clear. Every framebuffer row
    // is shown on exactly two scanlines, so the row start address must
    // advance on every second line (four would stretch the picture 2x).
    initial begin : test
        integer lines;
        integer same;
        reg [15:0] last;

        force dut.ce_video = 1'b1;
        force dut.seq_8dot_char = 1'b1;
        force dut.seq_dotclock_divided = 1'b0;
        force dut.crtc_horizontal_total = 9'd7;
        force dut.crtc_horizontal_display_size = 8'd3;
        force dut.crtc_horizontal_blanking_start = 9'd4;
        force dut.crtc_horizontal_blanking_end = 6'd6;
        force dut.crtc_horizontal_retrace_start = 9'd5;
        force dut.crtc_horizontal_retrace_end = 5'd6;
        force dut.crtc_horizontal_retrace_skew = 2'd0;
        force dut.crtc_vertical_total = 11'd31;
        force dut.crtc_vertical_display_size = 11'd15;
        force dut.crtc_vertical_blanking_start = 11'd16;
        force dut.crtc_vertical_blanking_end = 8'd30;
        force dut.crtc_vertical_retrace_start = 11'd20;
        force dut.crtc_vertical_retrace_end = 4'd6;
        force dut.crtc_line_compare = 11'h3ff;
        force dut.crtc_row_max = 5'd1;
        force dut.crtc_vertical_doublescan = 1'b0;
        force dut.crtc_row_preset = 5'd0;
        force dut.crtc_address_start = 20'd0;
        force dut.crtc_address_byte_panning = 2'd0;
        force dut.crtc_address_offset = 9'd2;

        repeat (4) @(posedge clk_sys);
        rst_n = 1'b1;

        // Skip to the start of a frame, then watch its first 12 lines.
        @(posedge clk_vga iff dut.dot_memory_load_first_in_frame);
        @(posedge clk_vga);
        last = dut.memory_address;
        same = 1;
        for (lines = 1; lines < 12; lines = lines + 1) begin
            @(posedge clk_vga iff dut.dot_memory_load_first_in_line);
            @(posedge clk_vga);
            if (dut.memory_address == last) same = same + 1;
            else begin
                if (same != 2) $fatal(1, "row %h shown on %0d lines, expected 2", last, same);
                last = dut.memory_address;
                same = 1;
            end
        end

        $display("PASS: mode-13h rows repeat twice");
        $finish;
    end
endmodule
