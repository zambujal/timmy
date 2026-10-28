// teste.c: corre o arranque.bin num Z80 emulado com um cartao SD (SPI) de mentira em cima de uma
// imagem FAT. Verifica que as duas memorias ficam com os ficheiros do cartao.
//   teste imagem.img arranque.bin tipo [atrasos]
//     tipo: sdhc | sdsc | v1 | ausente N (o cartao so' responde depois de N comandos)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "z80emu.h"

typedef struct {
    unsigned char ram[65536], esx[8192], home[16384], boot[8192];
    int alvo, fim, border, zx_idx;
    // cartao
    FILE *img; int tipo; int ausente;        // tipo: 0 sdhc, 1 sdsc, 2 v1 (sdsc)
    int cs; unsigned char last_rx;
    unsigned char cmd[6]; int ncmd;
    unsigned char resp[600]; int nresp, iresp;
    int idle, acmd, n41, ncmds, nreads;
    long long out_count;
} CTX;

unsigned char mem_read(void *c_, int a) {
    CTX *c = c_;
    if (a < 0x2000) return c->esx[a];
    return c->ram[a];
}
void mem_write(void *c_, int a, unsigned char v) {
    CTX *c = c_;
    if (a < 0x4000) {
        if (c->alvo == 0) c->home[a] = v;
        else if (a < 0x2000) c->esx[a] = v;
        if (a >= 0x2000) c->ram[a] = v;     // a pagina da DivTIESUS
        return;
    }
    if (a >= 0xf41f && a <= 0xf43f && getenv("TRACE") && c->ncmds > 20 && c->ncmds < 40) { static int n = 0; if (n++ < 12) fprintf(stderr, "  escrita %04X <- %02X (cmd n.o %d)\n", a, v, c->ncmds); }
    c->ram[a] = v;
}

static void push(CTX *c, unsigned char b) { c->resp[c->nresp++] = b; }

static void comando(CTX *c) {
    int cmd = c->cmd[0] & 0x3f;
    unsigned long arg = ((unsigned long)c->cmd[1] << 24) | (c->cmd[2] << 16) | (c->cmd[3] << 8) | c->cmd[4];
    if (getenv("TRACE")) fprintf(stderr, "CMD%d arg=%08lx (fila: %d de %d por ler)\n", cmd, arg, c->nresp - c->iresp, c->nresp);
    c->nresp = 0; c->iresp = 0; c->ncmds++;
    if (c->ausente > 0) { c->ausente--; return; }   // sem resposta
    push(c, 0xff);                                   // NCR: 1 byte
    if (c->acmd) {
        c->acmd = 0;
        if (cmd == 41) {
            if (c->tipo == 2 && (arg & 0x40000000)) { push(c, 0x05); return; }   // hmm: v1 com HCS: ilegal? aceita na mesma
            if (++c->n41 >= 3) c->idle = 0;
            push(c, c->idle ? 0x01 : 0x00); return;
        }
    }
    switch (cmd) {
    case 0: c->idle = 1; c->n41 = 0; push(c, 0x01);
        if (getenv("TRACE")) fprintf(stderr, "  CMD0: cur_cl=%02X%02X%02X%02X lba=%02X%02X%02X%02X tmp=%02X%02X%02X%02X fat_cache=%02X%02X%02X%02X FATS[48..55]=%02X%02X%02X%02X %02X%02X%02X%02X nrest=%d nsec=%d\n",
            c->ram[0xf41e],c->ram[0xf41d],c->ram[0xf41c],c->ram[0xf41b], c->ram[0xf422],c->ram[0xf421],c->ram[0xf420],c->ram[0xf41f], c->ram[0xf426],c->ram[0xf425],c->ram[0xf424],c->ram[0xf423], c->ram[0xf42a],c->ram[0xf429],c->ram[0xf428],c->ram[0xf427], c->ram[0xf230],c->ram[0xf231],c->ram[0xf232],c->ram[0xf233],c->ram[0xf234],c->ram[0xf235],c->ram[0xf236],c->ram[0xf237], c->ram[0xf439], c->ram[0xf438]);
        break;
    case 8:
        if (c->tipo == 2) { push(c, 0x05); break; }
        push(c, 0x01); push(c, 0); push(c, 0); push(c, 0x01); push(c, 0xaa); break;
    case 55: c->acmd = 1; push(c, c->idle ? 0x01 : 0x00); break;
    case 1: if (++c->n41 >= 3) c->idle = 0; push(c, c->idle ? 0x01 : 0x00); break;
    case 58: push(c, 0x00); push(c, c->tipo == 0 ? 0xc0 : 0x80); push(c, 0xff); push(c, 0x80); push(c, 0x00); break;
    case 16: push(c, 0x00); break;
    case 17: {
        if (c->idle) { push(c, 0x01); break; }
        unsigned long lba = c->tipo == 0 ? arg : arg / 512;
        if (c->tipo != 0 && (arg % 512)) { push(c, 0x40); break; }   // erro de parametro
        unsigned char s[512];
        fseek(c->img, (long)lba * 512, SEEK_SET);
        if (fread(s, 1, 512, c->img) != 512) { if (getenv("TRACE")) fprintf(stderr, "CMD17 lba=%lu FORA\n", lba); push(c, 0x00); push(c, 0xff); push(c, 0x08); break; }   // token de erro
        c->nreads++; if (getenv("TRACE")) fprintf(stderr, "CMD17 lba=%lu\n", lba);
        push(c, 0x00); push(c, 0xff); push(c, 0xff); push(c, 0xfe);
        for (int i = 0; i < 512; i++) push(c, s[i]);
        push(c, 0x12); push(c, 0x34);
        break;
    }
    default: push(c, 0x04); break;   // ilegal
    }
}

static unsigned char spi(CTX *c, unsigned char tx) {
    if (!c->cs) return 0xff;
    unsigned char rx = 0xff;
    if (c->iresp < c->nresp) rx = c->resp[c->iresp++];
    if (c->ncmd == 0) {
        if ((tx & 0xc0) == 0x40) { c->cmd[0] = tx; c->ncmd = 1; }
    } else {
        c->cmd[c->ncmd++] = tx;
        if (c->ncmd == 6) { c->ncmd = 0; comando(c); }
    }
    return rx;
}

unsigned char io_in(void *c_, int port) {
    CTX *c = c_;
    if ((port & 0xff) == 0xeb) { unsigned char x = c->last_rx; c->last_rx = spi(c, 0xff); return x; }
    return 0xff;
}
void io_out(void *c_, int port, unsigned char v) {
    CTX *c = c_;
    c->out_count++;
    int lo = port & 0xff;
    if (lo == 0xe7) { if ((v & 3) != 0) { int novo = !(v & 1); if (!novo && c->cs && getenv("TRACE")) fprintf(stderr, "  CS off: consumidos %d de %d (cmd %d)\n", c->iresp, c->nresp, c->cmd[0] & 0x3f); c->cs = novo; if (!c->cs) { c->ncmd = 0; c->nresp = c->iresp = 0; } } return; }
    if (lo == 0xeb) { c->last_rx = spi(c, v); return; }
    if (port == 0xfc3b) { c->zx_idx = v; return; }
    if (port == 0xfd3b) { if (c->zx_idx == 0xa4) { c->alvo = v & 1; if (v & 0x80) c->fim = 1; } return; }
    if (lo == 0xfe) { c->border = v & 7; return; }
}

static void ecra(CTX *c, const char *nome) {
    // o ecra (256x192) em texto: so' as linhas com alguma coisa, 1 caracter por ponto (2 pontos por caracter horizontal)
    FILE *f = fopen(nome, "w");
    for (int y = 0; y < 192; y++) {
        int addr = 0x4000 | ((y & 0xc0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2);
        int vazio = 1; for (int x = 0; x < 32; x++) if (c->ram[addr + x]) vazio = 0;
        if (vazio) continue;
        fprintf(f, "%3d ", y);
        for (int x = 0; x < 256; x++) fputc((c->ram[addr + x / 8] >> (7 - x % 8)) & 1 ? '#' : ' ', f);
        fputc('\n', f);
    }
    fclose(f);
}

int main(int argc, char **argv) {
    CTX c; memset(&c, 0, sizeof c);
    c.img = fopen(argv[1], "rb"); if (!c.img) { perror(argv[1]); return 1; }
    FILE *b = fopen(argv[2], "rb"); fread(c.boot, 1, 8192, b); fclose(b);
    memcpy(c.esx, c.boot, 8192);
    c.tipo = !strcmp(argv[3], "sdhc") ? 0 : !strcmp(argv[3], "sdsc") ? 1 : 2;
    c.ausente = argc > 4 ? atoi(argv[4]) : 0;
    const char *ecra_f = argc > 5 ? argv[5] : "ecra.txt";
    Z80_STATE z; Z80Reset(&z);
    long long t = 0; int tentativas = 0; int ult_border = -1;
    unsigned short hist[64]; int ih = 0; int passo = getenv("TRACE2") != NULL;
    while (!c.fim && t < 400000000LL) {
        if (passo) {
            hist[ih++ & 63] = z.pc;
            if (z.pc == 0x0109) { fprintf(stderr, "erro_leitura! ultimos PC:"); for (int k = 1; k <= 24; k++) fprintf(stderr, " %04X", hist[(ih - 1 - k) & 63]); fprintf(stderr, "\n  cur_cl=%02X%02X%02X%02X lba=%02X%02X%02X%02X tmp=%02X%02X%02X%02X nsec=%d nrest=%d A=%02X\n", c.ram[0xf400+0x1b+3],c.ram[0xf400+0x1b+2],c.ram[0xf400+0x1b+1],c.ram[0xf400+0x1b], c.ram[0xf400+0x1f+3],c.ram[0xf400+0x1f+2],c.ram[0xf400+0x1f+1],c.ram[0xf400+0x1f], c.ram[0xf400+0x23+3],c.ram[0xf400+0x23+2],c.ram[0xf400+0x23+1],c.ram[0xf400+0x23], c.ram[0xf400+0x38], c.ram[0xf400+0x39], z.registers.byte[Z80_A]); if (++tentativas > 1) break; }
            t += Z80Emulate(&z, 1, &c);
            continue;
        }
        t += Z80Emulate(&z, getenv("CHUNK") ? atoi(getenv("CHUNK")) : 10000, &c);
        if (c.border != ult_border) { ult_border = c.border; if (c.border == 2) tentativas++; }
    }
    ecra(&c, ecra_f);
    printf("T=%lld comandos=%d leituras=%d erros(vermelho)=%d fim=%d border=%d\n", t, c.ncmds, c.nreads, tentativas, c.fim, c.border);
    if (!c.fim) { printf("NAO ACABOU\n"); return 2; }
    // compara com os ficheiros esperados
    FILE *f1 = fopen("rom_esperada.bin", "rb"), *f2 = fopen("esx_esperado.bin", "rb");
    unsigned char e1[16384], e2[8192];
    fread(e1, 1, 16384, f1); fread(e2, 1, 8192, f2);
    int ok1 = !memcmp(e1, c.home, 16384), ok2 = !memcmp(e2, c.esx, 8192);
    printf("ROM %s, esxDOS %s\n", ok1 ? "IGUAL" : "DIFERENTE", ok2 ? "IGUAL" : "DIFERENTE");
    return (ok1 && ok2) ? 0 : 3;
}
