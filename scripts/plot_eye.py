# 2-D eye scans of the four lanes (out/eye_lane<l>.csv from tests/ibert_test.tcl ... eye) as one picture.
#   python3 scripts/plot_eye.py [csv directory (default out)] [picture (default out/eye_scans.png)]
import os, sys, numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
def load(f):
    meta, rows, hdr = {}, [], None
    lines = open(f).read().splitlines()
    i = lines.index("Scan Start")
    for l in lines[:i]:
        k, _, v = l.partition(","); meta[k] = v
    hdr = [int(x) for x in lines[i+1].split(",")[1:]]
    for l in lines[i+2:]:
        if l.startswith("Scan End") or not l.strip(): break
        p = l.split(","); rows.append([int(p[0])] + [float(x) for x in p[1:]])
    a = np.array(rows); return meta, np.array(hdr), a[:,0], a[:,1:]
src = sys.argv[1] if len(sys.argv) > 1 else "out"
dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(src, "eye_scans.png")
fig, axs = plt.subplots(2, 2, figsize=(12, 9), constrained_layout=True)
for l, ax in enumerate(axs.flat):
    meta, h, v, ber = load(os.path.join(src, f"eye_lane{l}.csv"))
    ui = h / (2 * h.max()) # -0.5 .. 0.5 UI
    z = np.log10(np.clip(ber, 1e-12, 1))
    im = ax.pcolormesh(ui, v, z, cmap="jet", vmin=-7, vmax=0, shading="nearest")
    ax.contour(ui, v, z, levels=[-6, -5, -4, -3, -2], colors="w", linewidths=0.4, alpha=0.6)
    ax.set_title(f"Lane {l} (MGT X0Y{4+l})  open area {meta['Open Area']}, "
                 f"H {meta['Horizontal Opening']} taps ({float(meta['Horizontal Percentage']):.1f}% UI), V {meta['Vertical Percentage']}%", fontsize=10)
    ax.set_xlabel("Horizontal offset (UI)"); ax.set_ylabel("Vertical offset (codes)")
    ax.set_xlim(-0.5, 0.5)
fig.colorbar(im, ax=axs, shrink=0.8, label="log10(BER)")
fig.suptitle("RFSoC 4x2 QSFP28 In-System IBERT 2-D eye scans: 25.78125 Gb/s PRBS31, SR4 module + MPO loopback plug\n"
             "(GTY, 156.25 MHz ref, QPLL0 fractional-N; dwell BER 1e-7, 1-tap steps; " + meta["Date and Time Started"] + ")", fontsize=11)
fig.savefig(dst, dpi=130)
print(dst)
