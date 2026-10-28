# le_ecra.py: le as linhas de texto do ecra (ecra.txt) com a nossa letra 5x7 -> texto
import sys
sys.path.insert(0, '..')
from fonte import G, ORDEM
linhas = {}
for l in open(sys.argv[1]):
    y = int(l[:3]); linhas[y] = l[4:].rstrip('\n')
def glifo(c):
    return [r for r in G[c]]
out = []
for fila in range(24):
    y0 = fila * 8
    if not any((y0 + k) in linhas for k in range(8)): continue
    txt = ''
    for col in range(32):
        cel = [linhas.get(y0 + k, '').ljust(256)[col*8:(col+1)*8] for k in range(7)]
        pad = [(r[1:6].replace('#', '#')) for r in cel]
        ach = ' '
        for c in ORDEM:
            if [row.replace(' ', ' ') for row in G[c]] == [p.replace('.', ' ') for p in pad]: ach = c; break
        txt += ach
    out.append("%2d: %s" % (fila, txt.rstrip()))
print('\n'.join(out))
