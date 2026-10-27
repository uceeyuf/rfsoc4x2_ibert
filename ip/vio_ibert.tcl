# BER test control and counters (100 MHz; the counters are a snapshot taken on request in the RX user clock).
#   in0 {QSFP28 IntL, ModPrsL, tx_done, rx_done, cdr_stable, tx_active, rx_active, snapshot acknowledge, gtpowergood 3..0,
#   PRBS locked 3..0}; snapshot: in1 RX user clock cycles (322.27 MHz), in2 cycles with the checker locked (lane l at
#   [48 l]; 80 bits a cycle), in3 those with a PRBS error, in4 lock losses (lane l at [16 l])
#   out0 TX PRBS (TXPRBSSEL: 0 off, 1 PRBS7, 2 PRBS9, 3 PRBS15, 4 PRBS23, 5 PRBS31), out1 RX PRBS (RXPRBSSEL, the same),
#   out2 loopback (0 normal, 2 near-end PMA), out3 reset all, out4 reset the RX datapath, out5 snapshot toggle,
#   out6 clear toggle, out7 forced-error toggles (one per lane)
create_ip -name vio -vendor xilinx.com -library ip -module_name vio_ibert
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN {5} \
    CONFIG.C_PROBE_IN0_WIDTH {16} \
    CONFIG.C_PROBE_IN1_WIDTH {48} \
    CONFIG.C_PROBE_IN2_WIDTH {192} \
    CONFIG.C_PROBE_IN3_WIDTH {192} \
    CONFIG.C_PROBE_IN4_WIDTH {64} \
    CONFIG.C_NUM_PROBE_OUT {8} \
    CONFIG.C_PROBE_OUT0_WIDTH {4} \
    CONFIG.C_PROBE_OUT0_INIT_VAL {0x5} \
    CONFIG.C_PROBE_OUT1_WIDTH {4} \
    CONFIG.C_PROBE_OUT1_INIT_VAL {0x5} \
    CONFIG.C_PROBE_OUT2_WIDTH {3} \
    CONFIG.C_PROBE_OUT3_WIDTH {1} \
    CONFIG.C_PROBE_OUT4_WIDTH {1} \
    CONFIG.C_PROBE_OUT5_WIDTH {1} \
    CONFIG.C_PROBE_OUT6_WIDTH {1} \
    CONFIG.C_PROBE_OUT7_WIDTH {4} \
    CONFIG.C_EN_PROBE_IN_ACTIVITY {0} \
] [get_ips vio_ibert]
