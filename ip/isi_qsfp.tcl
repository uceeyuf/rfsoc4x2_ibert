# In-System IBERT for the four QSFP28 channels (eye scans in the Vivado hardware manager), as the GT wizard's example design
# instantiates it for ip/gt_qsfp.tcl
create_ip -name in_system_ibert -vendor xilinx.com -library ip -module_name isi_qsfp
set_property -dict [list \
    CONFIG.C_GT_TYPE {GTY} \
    CONFIG.C_GTS_USED {X0Y4 X0Y5 X0Y6 X0Y7} \
    CONFIG.C_ENABLE_INPUT_PORTS {true} \
] [get_ips isi_qsfp]
