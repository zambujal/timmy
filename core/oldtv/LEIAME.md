# Timmy old TV

Variante do core para TVs antigas (LCD de 2005 ou antes) que dão imagem mas não som com o Timmy normal.
Compila-se com `core/faz_oldtv.sh`, que usa as mesmas fontes do Timmy com duas trocas, só na cópia que compila:

- 576p50 (720x576, 27 MHz, 4:3) em vez de 720p50 (`MODO720 := false` no `top.vhd`);
- o HDMI da biblioteca **hdl-util** (`hdl-util/`, de Sameer Puri, github.com/hdl-util/hdmi, MIT ou Apache-2.0;
  usa-se a MIT) em vez do `src/hdmi_tx.vhd`. É a versão do NanoMig do djnice (github.com/djnice/NanoMig,
  tag `aga-tn20k-2`), que dá som numa TV LG antiga onde o Timmy normal, o NextNano a 720p e o NanoMig
  original não davam.

Ficheiros:
- `hdmi_oldtv.sv`: o `hdmi.sv` da hdl-util com o gerador de tempos trocado por contadores presos ao DE do
  `video_timex` (o Timmy continua a fazer a imagem e os sincronismos) e a entrada de áudio do Timmy.
- `hdl-util/*.sv`: os pacotes e o codificador TMDS. Alterações do Timmy marcadas `(Timmy)`: VIDEO_RATE inteiro,
  contador do CTS com 20 bits, valor inicial do `clk_audio_counter_wrap`.
- `hdmi_oldtv.v`: tudo isto convertido para Verilog-2001 pelo sv2v (o Timmy compila com `-verilog_std v2001`).
- `hdmi_tx_oldtv.vhd`: a entidade `hdmi_tx` com as mesmas portas do `src/hdmi_tx.vhd`, por isso o `top.vhd` não muda.

Verificado em simulação (iverilog, 3 quadros a 576p, sinal TMDS descodificado): imagem ponto a ponto, guardas,
ECC de todos os pacotes, ACR ~1000/s com CTS 27000, 48 kHz sem amostras perdidas, paridade, AVI/AIF/SPD por
quadro. Como no fork, o bit B do bloco IEC 60958 aparece de 192 e 196 em 196 amostras (o contador do
`packet_picker` com `<=`); fica igual ao fork porque é o que está provado nessa TV.
