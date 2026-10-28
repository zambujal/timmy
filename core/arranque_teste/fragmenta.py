# fragmenta.py imagem.img inicio_particao: espalha os clusters do TC2048.ROM e do ESXMMC.BIN pela FAT
import sys, struct
p = sys.argv[1]; ini = int(sys.argv[2]) * 512
d = bytearray(open(p, 'rb').read())
b = d[ini:ini + 512]
bps = struct.unpack_from('<H', b, 0x0b)[0]; spc = b[0x0d]; rsvd = struct.unpack_from('<H', b, 0x0e)[0]; nf = b[0x10]
rootent = struct.unpack_from('<H', b, 0x11)[0]; spf16 = struct.unpack_from('<H', b, 0x16)[0]; spf32 = struct.unpack_from('<I', b, 0x24)[0]
fat32 = spf16 == 0; spf = spf32 if fat32 else spf16
fat_off = ini + rsvd * 512
root_off = fat_off + nf * spf * 512
data_off = root_off + (0 if fat32 else rootent * 32)
def cl_off(c): return data_off + (c - 2) * spc * 512
def fat_get(c):
    if fat32: return struct.unpack_from('<I', d, fat_off + c * 4)[0] & 0x0fffffff
    return struct.unpack_from('<H', d, fat_off + c * 2)[0]
def fat_set(c, v):
    for k in range(nf):
        o = fat_off + k * spf * 512
        if fat32: struct.pack_into('<I', d, o + c * 4, v)
        else: struct.pack_into('<H', d, o + c * 2, v)
def chain(c):
    r = []
    while 2 <= c < (0x0ffffff8 if fat32 else 0xfff8): r.append(c); c = fat_get(c)
    return r
# procura /SYS/ROMS
def find(dir_clusters_or_off, name):
    for off in dir_clusters_or_off:
        for e in range(0, spc * 512 if off >= data_off else 512, 32):
            ent = d[off + e: off + e + 32]
            if ent[0] == 0: return None
            if ent[:11] == name:
                cl = struct.unpack_from('<H', ent, 0x1a)[0] | (struct.unpack_from('<H', ent, 0x14)[0] << 16 if fat32 else 0)
                return cl
    return None
root = [cl_off(c) for c in chain(struct.unpack_from('<I', b, 0x2c)[0])] if fat32 else [root_off + k * 512 for k in range(rootent // 16)]
sys_cl = find(root, b'SYS        '); roms_cl = find([cl_off(c) for c in chain(sys_cl)], b'ROMS       ')
roms = [cl_off(c) for c in chain(roms_cl)]
nclu_total = (len(d) - data_off) // (spc * 512)
livre = [c for c in range(2, nclu_total + 2) if fat_get(c) == 0]
for nome in (b'TC2048  ROM', b'ESXMMC  BIN'):
    c0 = find(roms, nome); ch = chain(c0)
    # move todos os clusters menos o 1.o para clusters livres do fim, por ordem inversa
    novos = [livre.pop() for _ in ch[1:]]
    for old, new in zip(ch[1:], novos):
        d[cl_off(new):cl_off(new) + spc * 512] = d[cl_off(old):cl_off(old) + spc * 512]
        fat_set(old, 0)
    seq = [ch[0]] + novos
    for a, bb in zip(seq, seq[1:]): fat_set(a, bb)
    fat_set(seq[-1], 0x0fffffff if fat32 else 0xffff)
    print(nome, ch, '->', seq)
open(p, 'wb').write(d)
