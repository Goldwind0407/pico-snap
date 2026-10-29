"""Bake an sRGB-in 33^3 .cube from an F-Log2 (F-Gamut) -> BT.709 film LUT."""
import sys
import numpy as np
src, dst, title, gain = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
rows = [l.split() for l in open(src) if l[:1] in '0123456789.-' and len(l.split()) == 3]
L = np.array(rows, float); n = round(len(L) ** (1 / 3)); L = L.reshape(n, n, n, 3)  # [b][g][r]
m = 33
g = np.arange(m) / (m - 1)
b, gg, r = np.meshgrid(g, g, g, indexing='ij')
rgb = np.stack([r, gg, b], -1).reshape(-1, 3)
lin = np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4) * gain
M = np.array([[.6274, .3293, .0433], [.0691, .9195, .0114], [.0164, .0880, .8956]])  # BT.709 -> BT.2020 (F-Gamut)
lin = lin @ M.T
a_, b_, c_, d_, e_, f_, cut = 5.555556, .064829, .245281, .384316, 8.799461, .092864, .000889
x = np.where(lin >= cut, c_ * np.log10(np.maximum(a_ * lin + b_, 1e-9)) + d_, e_ * lin + f_)
x = np.clip(x, 0, 1) * (n - 1)
i0 = np.minimum(np.floor(x).astype(int), n - 2); t = x - i0
def at(dr, dg, db): return L[i0[:, 2] + db, i0[:, 1] + dg, i0[:, 0] + dr]
tr, tg, tb = t[:, 0:1], t[:, 1:2], t[:, 2:3]
c = ((at(0,0,0)*(1-tr)+at(1,0,0)*tr)*(1-tg)+(at(0,1,0)*(1-tr)+at(1,1,0)*tr)*tg)*(1-tb) \
  + ((at(0,0,1)*(1-tr)+at(1,0,1)*tr)*(1-tg)+(at(0,1,1)*(1-tr)+at(1,1,1)*tr)*tg)*tb
c = np.clip(c, 0, 1)
with open(dst, 'w', newline='\n') as f:
    f.write(f'TITLE "{title}"\n# sRGB in: sRGB -> linear x{gain} -> F-Gamut -> F-Log2 -> {src.split("/")[-1]}\nLUT_3D_SIZE 33\n')
    for v in c: f.write(f'{v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n')
print(dst, 'grey18->', c[np.argmin(np.abs(rgb - .46).sum(1))].round(3))
