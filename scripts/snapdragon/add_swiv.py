#!/usr/bin/env python3
import struct, sys, zlib

SWIV_MAGIC = 0x56495753
SWIV_SH_TYPE = 0xd3574956

def compute_swiv_crc(data):
    e_phoff   = struct.unpack_from('<I', data, 0x1c)[0]
    e_phentsz = struct.unpack_from('<H', data, 0x2a)[0]
    e_phnum   = struct.unpack_from('<H', data, 0x2c)[0]
    buf = bytearray()
    loads = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsz
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = \
            struct.unpack_from('<IIIIIIII', data, off)
        if p_type == 1:
            seg = data[p_offset:p_offset + p_filesz]
            seg += b'\x00' * (p_memsz - p_filesz)
            buf += seg
            loads.append((p_offset, p_filesz, p_memsz))
    crc = zlib.crc32(bytes(buf)) & 0xffffffff
    return crc, loads

def add_swiv(infile, outfile):
    data = bytearray(open(infile, 'rb').read())

    e_shoff   = struct.unpack_from('<I', data, 0x20)[0]
    e_shentsz = struct.unpack_from('<H', data, 0x2e)[0]
    e_shnum   = struct.unpack_from('<H', data, 0x30)[0]

    swiv_off = len(data)
    data += struct.pack('<II', SWIV_MAGIC, 0) + b'\x00' * 8

    new_sht_off = len(data)
    data += data[e_shoff:e_shoff + e_shnum * e_shentsz]
    data += struct.pack('<10I', 0, SWIV_SH_TYPE, 0, 0, swiv_off, 16, 0, 0, 0, 0)

    struct.pack_into('<I', data, 0x20, new_sht_off)
    struct.pack_into('<H', data, 0x30, e_shnum + 1)

    crc, loads = compute_swiv_crc(data)
    struct.pack_into('<I', data, swiv_off + 4, crc)

    open(outfile, 'wb').write(data)
    print(f'[swiv] {infile}')
    print(f'[swiv] LOAD segments: {[(hex(o), hex(fs), hex(ms)) for o, fs, ms in loads]}')
    print(f'[swiv] computed CRC32 = 0x{crc:08x} (over finalized LOAD segs incl. ELF header)')
    print(f'[swiv] wrote {outfile} (SWIV@0x{swiv_off:x}, SHT@0x{new_sht_off:x}, shnum {e_shnum}->{e_shnum+1})')

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print('usage: add_swiv.py <in.skel.so> <out.skel.so>')
        sys.exit(1)
    add_swiv(sys.argv[1], sys.argv[2])
