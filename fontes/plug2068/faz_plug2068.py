#!/usr/bin/env python3
# faz_plug2068.py: faz o BIN/PLUG2068/TAP (plugin TAP para o modo TC2068) a partir do plugin TAP do
# esxDOS (BIN/BPLUGINS/TAP, de Bob Fossil) + o stub68.bin montado do stub68.asm (sjasmplus).
#   python3 faz_plug2068.py BIN/BPLUGINS/TAP BIN/PLUG2068/TAP [stub68.bin]
# O plugin original tem 2865 bytes; em 8071h tem XOR A / RST 8 / DB 90h (o auto-load), que passa a
# JP 8B31h (o stub, colado no fim). Nada do esxDOS e' distribuido aqui.
import sys, os, hashlib
src, dst = sys.argv[1], sys.argv[2]
stub = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(__file__), 'stub68.bin')
t = bytearray(open(src, 'rb').read())
if len(t) != 2865 or t[0x71:0x74] != bytes([0xAF, 0xCF, 0x90]):
    sys.exit("isto nao parece o plugin TAP do esxDOS que conheco (2865 bytes, AF CF 90 em 8071h; md5 bd2512de16de45ec485edd6b47cd39dd)")
t[0x71:0x74] = bytes([0xC3, 0x31, 0x8B])
t += open(stub, 'rb').read()
open(dst, 'wb').write(t)
print(dst, len(t), "bytes")
