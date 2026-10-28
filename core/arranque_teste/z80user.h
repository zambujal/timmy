#ifndef __Z80USER_INCLUDED__
#define __Z80USER_INCLUDED__
#ifdef __cplusplus
extern "C" {
#endif
unsigned char mem_read(void *ctx, int a);
void mem_write(void *ctx, int a, unsigned char v);
unsigned char io_in(void *ctx, int port);
void io_out(void *ctx, int port, unsigned char v);
#define Z80_READ_BYTE(address, x)  { (x) = mem_read(context, (address) & 0xffff); }
#define Z80_FETCH_BYTE(address, x) Z80_READ_BYTE((address), (x))
#define Z80_READ_WORD(address, x)  { (x) = mem_read(context, (address) & 0xffff) | (mem_read(context, ((address) + 1) & 0xffff) << 8); }
#define Z80_FETCH_WORD(address, x) Z80_READ_WORD((address), (x))
#define Z80_WRITE_BYTE(address, x) { mem_write(context, (address) & 0xffff, (x)); }
#define Z80_WRITE_WORD(address, x) { mem_write(context, (address) & 0xffff, (x)); mem_write(context, ((address) + 1) & 0xffff, (x) >> 8); }
#define Z80_READ_WORD_INTERRUPT(address, x)  Z80_READ_WORD((address), (x))
#define Z80_WRITE_WORD_INTERRUPT(address, x) Z80_WRITE_WORD((address), (x))
#define Z80_INPUT_BYTE(port, x)  { (x) = io_in(context, (port) & 0xffff); }
#define Z80_OUTPUT_BYTE(port, x) { io_out(context, (port) & 0xffff, (x)); }
#ifdef __cplusplus
}
#endif
#endif
