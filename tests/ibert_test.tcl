# BER test of the RFSoC 4x2 QSFP28 port, four lanes at 25.78125 Gb/s, through the VIO (and eye scans through In-System IBERT).
#
#   vivado -mode batch -source tests/ibert_test.tcl [-tclargs <seconds> [loopback] [pattern] [eye] [noprog]]
#
#   seconds   measurement time (default 10), one line a second
#   loopback  0 (default): through the QSFP28 (a loopback module, or a fibre loop); 2: the GTs' near-end PMA loopback
#   pattern   7, 9, 15, 23 or 31 (default): PRBS on every lane, generator and checker
#   eye       eye: then a 2-D eye scan of each receiver (out/eye_lane<l>.csv; about a minute each)
#   noprog    the FPGA already programmed
# Each lane's checker locks to its own lane's receiver: with a loopback module, TX lane l comes back on RX lane l.
# The counts are RX user clock cycles (80 bits) with the checker locked, and cycles with an error (one or more bits: at a low
# BER one bit each). At the end one error is forced on each lane's generator to show that each checker counts it.

set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set secs     [expr {$argc > 0 ? [lindex $argv 0] : 10}]
set lb       [expr {$argc > 1 ? [lindex $argv 1] : 0}]
set pat      [expr {$argc > 2 ? [lindex $argv 2] : 31}]
set eye      [expr {$argc > 3 && [lindex $argv 3] eq "eye"}]
set noprog   [expr {"noprog" in $argv}]
set f_rx     322.265625e6                 ;# RX user clock (25.78125 Gb/s / 80)
set sel      [dict get {7 1 9 2 15 3 23 4 31 5} $pat]

file mkdir [file join $repo_dir out]
set log [open [file join $repo_dir out ibert_test.txt] w]
proc say {msg} { global log; puts $msg; puts $log $msg; flush $log }

if {$noprog} {
    open_hw_manager; connect_hw_server -allow_non_jtag; open_hw_target
    set dev [lindex [get_hw_devices xczu48dr*] 0]; current_hw_device $dev
    set b [file join $repo_dir build fpga.ltx]
    if {![file exists $b]} { set b [file join $repo_dir prebuilt rfsoc4x2_ibert.ltx] }
    set_property PROBES.FILE $b $dev; set_property FULL_PROBES.FILE $b $dev; refresh_hw_device $dev
} else {
    source [file join $repo_dir scripts program.tcl]
}
set vio [lindex [get_hw_vios -of_objects [current_hw_device]] 0]
foreach p [get_hw_probes -of_objects $vio] {
    if {[get_property TYPE $p] eq "vio_input"} { set_property INPUT_VALUE_RADIX HEX $p }
}
proc probe {name} { global vio; return [get_hw_probes $name -of_objects $vio] }
proc out {name value} {
    global vio
    set p [probe $name]
    set_property OUTPUT_VALUE_RADIX UNSIGNED $p
    set_property OUTPUT_VALUE $value $p
    commit_hw_vio $p
}
proc in {name} { global vio; refresh_hw_vio $vio; return [expr "0x[get_property INPUT_VALUE [probe $name]]"] }
proc field {v lane width} { return [expr {($v >> ($width * $lane)) & ((1 << $width) - 1)}] }
set toggles [dict create vio_snap 0 vio_clear 0 vio_force 0]
proc toggle {name {mask 1}} {
    global toggles
    dict set toggles $name [expr {[dict get $toggles $name] ^ $mask}]
    out $name [dict get $toggles $name]
}
proc snapshot {} {
    global toggles
    toggle vio_snap
    for {set i 0} {$i < 100} {incr i} {
        if {(([in st] >> 8) & 1) == [dict get $toggles vio_snap]} break
        after 10
    }
    return [dict create up [in s_uptime] lock [in s_lock] err [in s_err] lost [in s_lost]]
}

# PRBS on, the loopback, then a reset of the transceivers and of the receive datapath
foreach n {vio_snap vio_clear vio_force vio_reset_rx} { out $n 0 }
out vio_txprbssel $sel; out vio_rxprbssel $sel; out vio_loopback $lb
out vio_reset_all 1; after 200; out vio_reset_all 0; after 2000
out vio_reset_rx 1; after 100; out vio_reset_rx 0; after 1000
set st [in st]
say [format "loopback %d (%s), PRBS%d; QSFP28 module %s, IntL %d; reset done tx %d rx %d, CDR stable %d; GT power good %s; PRBS locked (lane 3..0) %s" \
    $lb [expr {$lb == 2 ? {near-end PMA} : {through the QSFP28}}] $pat [expr {($st >> 14) & 1 ? {absent} : {present}}] [expr {($st >> 15) & 1}] \
    [expr {($st >> 13) & 1}] [expr {($st >> 12) & 1}] [expr {($st >> 11) & 1}] [format %04b [expr {($st >> 4) & 15}]] [format %04b [expr {$st & 15}]]]

toggle vio_clear; after 100
set p [snapshot]
set t0 [clock milliseconds]
for {set s 1} {$s <= $secs} {incr s} {
    after [expr {$t0 + 1000 * $s - [clock milliseconds]}]
    set c [snapshot]
    set line [format "%3d s:" $s]
    for {set l 0} {$l < 4} {incr l} {
        set lk [field [dict get $c lock] $l 48]; set er [field [dict get $c err] $l 48]
        set dlk [expr {$lk - [field [dict get $p lock] $l 48]}]; set der [expr {$er - [field [dict get $p err] $l 48]}]
        append line [format "  lane %d: %s %.3f Gb/s, errors %d (total %d, BER %.2e)" $l [expr {$dlk > 0 ? {locked} : {NO LOCK}}] \
            [expr {[dict get $c up] > [dict get $p up] ? $dlk * 80.0 * $f_rx / ([dict get $c up] - [dict get $p up]) / 1e9 : 0}] $der $er \
            [expr {$lk > 0 ? $er / ($lk * 80.0) : 1.0}]]
    }
    say $line
    set p $c
}
set total [snapshot]
# the checkers' self test: one error forced on each lane's generator
toggle vio_force 15; after 300
set inj [snapshot]
for {set l 0} {$l < 4} {incr l} {
    set lk [field [dict get $total lock] $l 48]; set er [field [dict get $total err] $l 48]
    set bits [expr {$lk * 80.0}]
    say [format "RESULT lane %d: %.3e bits checked, %d errors, BER %s, lock losses %d, forced error counted %d (expected 1)" \
        $l $bits $er [expr {$er == 0 ? ($bits > 0 ? [format "< %.1e" [expr {1.0 / $bits}]] : "-") : [format %.2e [expr {$er / $bits}]]}] \
        [field [dict get $total lost] $l 16] [expr {[field [dict get $inj err] $l 48] - $er}]]
}

# eye scans (In-System IBERT)
if {$eye} {
    set rxs [lsort [get_hw_sio_rxs]]
    set l 0
    foreach rx $rxs {
        set scan [create_hw_sio_scan -description "lane $l" 2d_full_eye $rx]
        set_property HORIZONTAL_INCREMENT {2} $scan
        set_property VERTICAL_INCREMENT {2} $scan
        run_hw_sio_scan $scan
        wait_on_hw_sio_scan $scan
        set f [file join $repo_dir out eye_lane$l.csv]
        write_hw_sio_scan -force $f $scan
        say "eye scan lane $l ($rx): open area [get_property Open_Area $scan], horizontal opening [get_property Horizontal_Opening $scan], -> $f"
        incr l
    }
}
close $log
