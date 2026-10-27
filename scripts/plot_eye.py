# 2-D eye scans of the four lanes (out/eye_lane<l>.csv from tests/ibert_test.tcl ... eye) as one picture.
#   python3 scripts/plot_eye.py [csv directory (default out)] [picture (default <csv directory>/eye_scans.png)] [title note]
# The scan covers one UI (-0.5 .. 0.5 UI around the eye centre); it is drawn from -1 to 1 UI, repeated once on each side
# (the dashed lines mark the scanned UI), so that the whole eye and both crossings are seen.
import os, sys, numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

def load(f):
    meta, rows = {}, []
    lines = open(f).read().splitlines()
    i = lines.index("Scan Start")
    for l in lines[:i]:
        k, _, v = l.partition(","); meta[k] = v
    hdr = [int(x) for x in lines[i + 1].split(",")[1:]]
    for l in lines[i + 2:]:
        if l.startswith("Scan End") or not l.strip(): break
        p = l.split(","); rows.append([int(p[0])] + [float(x) for x in p[1:]])
    a = np.array(rows)
    return meta, np.array(hdr), a[:, 0], a[:, 1:]

src = sys.argv[1] if len(sys.argv) > 1 else "out"
dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(src, "eye_scans.png")
note = sys.argv[3] if len(sys.argv) > 3 else ""
fig, axs = plt.subplots(2, 2, figsize=(14, 10), constrained_layout=True)
for l, ax in enumerate(axs.flat):
    meta, h, v, ber = load(os.path.join(src, f"eye_lane{l}.csv"))
    ui = h / (2.0 * h.max())                              # -0.5 .. 0.5 UI
    z = np.log10(np.clip(ber, 1e-12, 1))
    x = np.concatenate([ui[:-1] - 1, ui, ui[1:] + 1])     # -1.5 .. 1.5 UI, the edge columns once
    zz = np.concatenate([z[:, :-1], z, z[:, 1:]], axis=1)
    im = ax.pcolormesh(x, v, zz, cmap="jet", vmin=-7, vmax=0, shading="nearest")
    ax.contour(x, v, zz, levels=[-6, -4, -2], colors="w", linewidths=0.5, alpha=0.7)
    for b in (-0.5, 0.5): ax.axvline(b, color="w", ls="--", lw=0.8, alpha=0.8)
    ax.set_xlim(-1, 1); ax.set_ylim(v.min(), v.max())
    ax.set_title(f"Lane {l} (MGT X0Y{4 + l}): open area {meta['Open Area']}, "
                 f"H {float(meta['Horizontal Percentage']):.1f}% UI, V {float(meta['Vertical Percentage']):.1f}%", fontsize=11)
    ax.set_xlabel("Horizontal offset (UI)"); ax.set_ylabel("Vertical offset (codes)")
fig.colorbar(im, ax=axs, shrink=0.8, label="log10(BER)")
fig.suptitle("RFSoC 4x2 QSFP28, In-System IBERT 2-D eye scans: 25.78125 Gb/s PRBS31 through an SR4 module and an MPO loopback plug\n"
             f"dwell BER {meta['Dwell BER']}, {meta['Horizontal Increment']}-tap steps, {meta['Date and Time Started']}" + (f"; {note}" if note else ""),
             fontsize=12)
fig.savefig(dst, dpi=120)
print(dst)
