// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Yijie Yu
//
// RFSoC 4x2: bit-error-rate test of the QSFP28 port, four GTY lanes at 25.78125 Gb/s (100GBASE-SR4 / CAUI-4 rate).
//   100 MHz board clock: the GTs' free-running / DRP clock, the In-System IBERT core, the VIO
//   156.25 MHz QSFP28 reference clock (AA33 / AA34): QPLL0, fractional-N
//   the GTs' own PRBS generators and checkers (PRBS31 by default, selected by the VIO), counted per lane in the
//   RX user clock (322.27 MHz, 80 bits a cycle): cycles locked, cycles with an error, lock losses; the counters are
//   copied on request (snapshot toggle) and read by the VIO (tests/ibert_test.tcl)
//   In-System IBERT: eye scans of the four receivers in the Vivado hardware manager

`resetall
`timescale 1ns / 1ps
`default_nettype none

module fpga (
    input  wire         clk_p,              // 100 MHz
    input  wire         clk_n,

    // QSFP28
    output wire [3:0]   qsfp0_tx_p,
    output wire [3:0]   qsfp0_tx_n,
    input  wire [3:0]   qsfp0_rx_p,
    input  wire [3:0]   qsfp0_rx_n,
    input  wire         qsfp0_mgt_refclk_0_p,
    input  wire         qsfp0_mgt_refclk_0_n,
    output wire         qsfp0_modsell,
    output wire         qsfp0_resetl,
    input  wire         qsfp0_modprsl,
    input  wire         qsfp0_intl,
    output wire         qsfp0_lpmode
);

// the module out of reset, in high-power mode (LPMode low: the lasers on), not selected (no I2C)
assign qsfp0_modsell = 1'b1;
assign qsfp0_resetl  = 1'b1;
assign qsfp0_lpmode  = 1'b0;

// ---------------------------------------------------------------- clocks
wire clk_ibuf, clk100;
IBUFDS clk_ibufds (.I(clk_p), .IB(clk_n), .O(clk_ibuf));
BUFG   clk_bufg   (.I(clk_ibuf), .O(clk100));

wire refclk;
IBUFDS_GTE4 #(.REFCLK_EN_TX_PATH(1'b0), .REFCLK_HROW_CK_SEL(2'b00), .REFCLK_ICNTL_RX(2'b00))
    refclk_ibuf (.I(qsfp0_mgt_refclk_0_p), .IB(qsfp0_mgt_refclk_0_n), .CEB(1'b0), .O(refclk), .ODIV2());

// ---------------------------------------------------------------- VIO controls (100 MHz)
wire [3:0]  vio_txprbssel, vio_rxprbssel;
wire [2:0]  vio_loopback;
wire        vio_reset_all, vio_reset_rx, vio_snap, vio_clear;
wire [3:0]  vio_force;                   // toggles: one forced error per change, per lane

// a reset of everything after configuration (the reference clock and the QPLL settle first)
reg  [23:0] por = 24'd0;
always @(posedge clk100) if (!por[23]) por <= por + 1'b1;
wire reset_all = !por[23] || vio_reset_all;

// ---------------------------------------------------------------- the transceivers
wire        tx_usrclk2, rx_usrclk2, tx_active, rx_active, tx_done, rx_done, cdr_stable;
wire [3:0]  gtpowergood, rxprbserr, rxprbslocked, rxpmaresetdone, txpmaresetdone;
wire [3:0]  txprbsforceerr;
wire [39:0] drpaddr;
wire [63:0] drpdi, drpdo;
wire [3:0]  drpen, drpwe, drprdy, eyescanreset, rxlpmen;
wire [11:0] rxrate;
wire [19:0] txdiffctrl, txprecursor, txpostcursor;
wire        drpclk_isi;

gt_qsfp gt_i (
    .gtwiz_userclk_tx_reset_in(1'b0), .gtwiz_userclk_tx_srcclk_out(), .gtwiz_userclk_tx_usrclk_out(),
    .gtwiz_userclk_tx_usrclk2_out(tx_usrclk2), .gtwiz_userclk_tx_active_out(tx_active),
    .gtwiz_userclk_rx_reset_in(1'b0), .gtwiz_userclk_rx_srcclk_out(), .gtwiz_userclk_rx_usrclk_out(),
    .gtwiz_userclk_rx_usrclk2_out(rx_usrclk2), .gtwiz_userclk_rx_active_out(rx_active),
    .gtwiz_reset_clk_freerun_in(clk100), .gtwiz_reset_all_in(reset_all),
    .gtwiz_reset_tx_pll_and_datapath_in(1'b0), .gtwiz_reset_tx_datapath_in(1'b0),
    .gtwiz_reset_rx_pll_and_datapath_in(1'b0), .gtwiz_reset_rx_datapath_in(vio_reset_rx),
    .gtwiz_reset_rx_cdr_stable_out(cdr_stable), .gtwiz_reset_tx_done_out(tx_done), .gtwiz_reset_rx_done_out(rx_done),
    .gtrefclk00_in(refclk), .qpll0outclk_out(), .qpll0outrefclk_out(),
    .drpaddr_in(drpaddr), .drpclk_in({4{clk100}}), .drpdi_in(drpdi), .drpen_in(drpen), .drpwe_in(drpwe),
    .drpdo_out(drpdo), .drprdy_out(drprdy),
    .eyescanreset_in(eyescanreset), .rxlpmen_in(rxlpmen), .rxrate_in(rxrate),
    .txdiffctrl_in(txdiffctrl), .txpostcursor_in(txpostcursor), .txprecursor_in(txprecursor),
    .gtyrxn_in(qsfp0_rx_n), .gtyrxp_in(qsfp0_rx_p), .gtytxn_out(qsfp0_tx_n), .gtytxp_out(qsfp0_tx_p),
    .loopback_in({4{vio_loopback}}),
    .rxprbscntreset_in(4'b0000), .rxprbssel_in({4{vio_rxprbssel}}),
    .txprbsforceerr_in(txprbsforceerr), .txprbssel_in({4{vio_txprbssel}}),
    .txctrl0_in(64'd0), .txctrl1_in(64'd0), .txdata_in(512'd0),     // (the PRBS generators replace the data)
    .gtpowergood_out(gtpowergood), .rxctrl0_out(), .rxctrl1_out(), .rxdata_out(),
    .rxpmaresetdone_out(rxpmaresetdone), .rxprbserr_out(rxprbserr), .rxprbslocked_out(rxprbslocked),
    .txpmaresetdone_out(txpmaresetdone), .txprgdivresetdone_out()
);

// In-System IBERT: the DRP and the analog settings of the four channels (the defaults: LPM equalization, swing 11000b)
isi_qsfp isi_i (
    .drpclk_o(drpclk_isi),
    .gt0_drpen_o(drpen[0]), .gt0_drpwe_o(drpwe[0]), .gt0_drpaddr_o(drpaddr[9:0]),   .gt0_drpdi_o(drpdi[15:0]),  .gt0_drprdy_i(drprdy[0]), .gt0_drpdo_i(drpdo[15:0]),
    .gt1_drpen_o(drpen[1]), .gt1_drpwe_o(drpwe[1]), .gt1_drpaddr_o(drpaddr[19:10]), .gt1_drpdi_o(drpdi[31:16]), .gt1_drprdy_i(drprdy[1]), .gt1_drpdo_i(drpdo[31:16]),
    .gt2_drpen_o(drpen[2]), .gt2_drpwe_o(drpwe[2]), .gt2_drpaddr_o(drpaddr[29:20]), .gt2_drpdi_o(drpdi[47:32]), .gt2_drprdy_i(drprdy[2]), .gt2_drpdo_i(drpdo[47:32]),
    .gt3_drpen_o(drpen[3]), .gt3_drpwe_o(drpwe[3]), .gt3_drpaddr_o(drpaddr[39:30]), .gt3_drpdi_o(drpdi[63:48]), .gt3_drprdy_i(drprdy[3]), .gt3_drpdo_i(drpdo[63:48]),
    .eyescanreset_o(eyescanreset), .rxrate_o(rxrate), .txdiffctrl_o(txdiffctrl), .txprecursor_o(txprecursor),
    .txpostcursor_o(txpostcursor), .rxlpmen_o(rxlpmen),
    .rxrate_i({4{3'b000}}), .txdiffctrl_i({4{5'b11000}}), .txprecursor_i({4{5'b00000}}), .txpostcursor_i({4{5'b00000}}),
    .rxlpmen_i({4{1'b1}}), .rxoutclk_i({4{rx_usrclk2}}), .drpclk_i({4{clk100}}), .clk(clk100)
);

// ---------------------------------------------------------------- forced errors: a one-cycle pulse per toggle (TX user clock)
wire [3:0] force_t;
xpm_cdc_array_single #(.DEST_SYNC_FF(3), .INIT_SYNC_FF(1), .SRC_INPUT_REG(0), .WIDTH(4)) force_cdc (.src_clk(1'b0), .src_in(vio_force), .dest_clk(tx_usrclk2), .dest_out(force_t));
reg  [3:0] force_d = 4'd0;
always @(posedge tx_usrclk2) force_d <= force_t;
assign txprbsforceerr = force_t ^ force_d;

// ---------------------------------------------------------------- per-lane counters (RX user clock)
wire snap_r, clear_r;
xpm_cdc_single #(.DEST_SYNC_FF(3), .INIT_SYNC_FF(1), .SRC_INPUT_REG(0)) snap_cdc (.src_clk(1'b0), .src_in(vio_snap), .dest_clk(rx_usrclk2), .dest_out(snap_r));
xpm_cdc_single #(.DEST_SYNC_FF(3), .INIT_SYNC_FF(1), .SRC_INPUT_REG(0)) clear_cdc (.src_clk(1'b0), .src_in(vio_clear), .dest_clk(rx_usrclk2), .dest_out(clear_r));
reg  snap_d = 1'b0, clear_d = 1'b0;
always @(posedge rx_usrclk2) begin snap_d <= snap_r; clear_d <= clear_r; end
wire snap_p = snap_r != snap_d, clear_p = clear_r != clear_d;

reg  [3:0]   lk = 4'd0, er = 4'd0, lk_d = 4'd0;
reg  [47:0]  uptime = 48'd0;
reg  [47:0]  lock_cyc [0:3];
reg  [47:0]  err_cyc [0:3];
reg  [15:0]  lost [0:3];
reg  [47:0]  s_uptime = 48'd0;
reg  [191:0] s_lock = 192'd0, s_err = 192'd0;
reg  [63:0]  s_lost = 64'd0;
reg          snap_ack = 1'b0;
integer i;
initial for (i = 0; i < 4; i = i + 1) begin lock_cyc[i] = 48'd0; err_cyc[i] = 48'd0; lost[i] = 16'd0; end
always @(posedge rx_usrclk2) begin
    lk <= rxprbslocked; er <= rxprbserr; lk_d <= lk;
    uptime <= uptime + 1'b1;
    for (i = 0; i < 4; i = i + 1) begin
        if (lk[i]) lock_cyc[i] <= lock_cyc[i] + 1'b1;
        if (lk[i] && er[i]) err_cyc[i] <= err_cyc[i] + 1'b1;
        if (lk_d[i] && !lk[i]) lost[i] <= lost[i] + 1'b1;
    end
    if (clear_p) begin
        uptime <= 48'd0;
        for (i = 0; i < 4; i = i + 1) begin lock_cyc[i] <= 48'd0; err_cyc[i] <= 48'd0; lost[i] <= 16'd0; end
    end
    if (snap_p) begin
        s_uptime <= uptime;
        for (i = 0; i < 4; i = i + 1) begin
            s_lock[48 * i +: 48] <= lock_cyc[i]; s_err[48 * i +: 48] <= err_cyc[i]; s_lost[16 * i +: 16] <= lost[i];
        end
        snap_ack <= snap_r;
    end
end

// ---------------------------------------------------------------- status, VIO (100 MHz)
wire [3:0] locked_s;
xpm_cdc_array_single #(.DEST_SYNC_FF(3), .INIT_SYNC_FF(1), .SRC_INPUT_REG(0), .WIDTH(4)) lk_cdc (.src_clk(1'b0), .src_in(lk), .dest_clk(clk100), .dest_out(locked_s));
wire ack_s;
xpm_cdc_single #(.DEST_SYNC_FF(3), .INIT_SYNC_FF(1), .SRC_INPUT_REG(0)) ack_cdc (.src_clk(1'b0), .src_in(snap_ack), .dest_clk(clk100), .dest_out(ack_s));
wire [15:0] st = {qsfp0_intl, qsfp0_modprsl, tx_done, rx_done, cdr_stable, tx_active, rx_active, ack_s,
                  gtpowergood, locked_s};

vio_ibert vio_i (
    .clk(clk100),
    .probe_in0(st),             // {intl, modprsl, tx_done, rx_done, cdr_stable, tx_active, rx_active, snap_ack, gtpowergood 3..0, prbs locked 3..0}
    .probe_in1(s_uptime),
    .probe_in2(s_lock),         // lane l at [48 l]: RX user clock cycles with the PRBS checker locked (80 bits each)
    .probe_in3(s_err),          // ... of them with an error
    .probe_in4(s_lost),         // lane l at [16 l]: lock losses
    .probe_out0(vio_txprbssel),
    .probe_out1(vio_rxprbssel),
    .probe_out2(vio_loopback),
    .probe_out3(vio_reset_all),
    .probe_out4(vio_reset_rx),
    .probe_out5(vio_snap),
    .probe_out6(vio_clear),
    .probe_out7(vio_force)
);

endmodule

`resetall
