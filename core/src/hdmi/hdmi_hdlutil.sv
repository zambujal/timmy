// hdmi_hdlutil.sv: o HDMI com som do Timmy (desde 2026-10-31) - a biblioteca hdl-util (Sameer Puri,
//   github.com/hdl-util/hdmi, MIT ou Apache-2.0; usa-se a MIT; ficheiros em hdl-util/), na versao do NanoMig
//   do djnice (github.com/djnice/NanoMig, tag aga-tn20k-2). Trocou o hdmi_tx.vhd anterior, feito para o Timmy,
//   porque esta da' som numa TV LG antiga onde o nosso nao dava (nem com AIF, estado do canal e ACR iguais aos
//   do NextNano).
//   Este ficheiro e' o hdmi.sv dessa biblioteca com o gerador de tempos trocado por contadores presos ao
//   DE do video_timex: o Timmy continua a fazer a imagem e os sincronismos; daqui saem os simbolos TMDS
//   (os OSER10 continuam no top.vhd). O resto (ilhas de dados, pacotes, ACR, amostras) e' o da biblioteca.
//   Audio: as amostras chegam com um "tog" (muda a cada amostra, 48 kHz, outro relogio); aqui faz-se
//   um flanco de subida de clk_audio por amostra, com a amostra ja' copiada e parada.
//   Alteracoes do Timmy nos ficheiros da biblioteca marcadas "(Timmy)": VIDEO_RATE inteiro, contador do CTS
//   com 20 bits, valor inicial do clk_audio_counter_wrap, codificador TMDS em dois andares (74,25 MHz).
//   Como no fork, o bit B do bloco IEC 60958 sai de 192 e 196 em 196 amostras (o contador do packet_picker
//   com <=); fica igual ao fork porque e' o que esta' provado nessa TV.
//   O Timmy compila com -verilog_std v2001, por isso o que entra no Gowin e' o hdmi_hdlutil.v:
//     sv2v --top=hdmi_hdlutil hdmi_hdlutil.sv hdl-util/*.sv > hdmi_hdlutil.v

module hdmi_hdlutil
#(
    parameter int SCREEN_W = 720,
    parameter int FRAME_W  = 864,
    parameter int SCREEN_H = 576,
    parameter int FRAME_H  = 625,
    parameter int CEA      = 17,
    parameter int VIDEO_RATE = 27000000,
    parameter int AUDIO_RATE = 48000,
    parameter int AUDIO_BIT_WIDTH = 16
)
(
    input  logic        clk_pixel,
    input  logic [7:0]  r, g, b,
    input  logic        de, hs, vs,           // hs/vs ja' com a polaridade do fio
    input  logic [15:0] aud_l, aud_r,         // PCM com sinal
    input  logic        aud_tog,
    output logic [9:0]  q0, q1, q2
);

localparam int NUM_CHANNELS = 3;
wire [10:0] frame_width   = 11'(FRAME_W);
wire [10:0] screen_width  = 11'(SCREEN_W);
wire [9:0]  frame_height  = 10'(FRAME_H);
wire [9:0]  screen_height = 10'(SCREEN_H);
wire [7:0]  cea = 8'(CEA);
// reset dos primeiros 32 pontos (os registos da biblioteca que so' o reset inicia: BCH do packet_assembler...)
logic [4:0] rst_c = 5'd0;
wire reset = rst_c != 5'd31;
always_ff @(posedge clk_pixel) if (rst_c != 5'd31) rst_c <= rst_c + 1'b1;

// ---- contadores presos ao DE (cx/cy = o ponto que entra NESTE ciclo) ----
logic [10:0] cx_r = 11'd0;
logic [9:0]  cy_r = 10'd0;
logic de_d = 1'b0, vs_d = 1'b0, nova = 1'b1;   // nova: a proxima subida do DE e' a 1.a linha do quadro
logic [10:0] cx;
logic [9:0]  cy;
always_comb begin
    if (de && !de_d) begin
        cx = 11'd0;
        cy = nova ? 10'd0 : cy_r;
    end else begin
        cx = cx_r;
        cy = cy_r;
    end
end
always_ff @(posedge clk_pixel) begin
    de_d <= de;
    vs_d <= vs;
    if (vs != vs_d) nova <= 1'b1;               // qualquer flanco do VSYNC (a polaridade nao importa)
    else if (de && !de_d) nova <= 1'b0;
    cx_r <= cx == frame_width - 1'b1 ? 11'd0 : cx + 1'b1;
    cy_r <= cx == frame_width - 1'b1 ? (cy == frame_height - 1'b1 ? 10'd0 : cy + 1'b1) : cy;
end

logic hsync, vsync;
assign hsync = hs;
assign vsync = vs;
// na biblioteca o ponto chega um ciclo depois do cx (o utilizador calcula-o a partir do cx); aqui o rgb vem
// junto com o DE, por isso atrasa-se 1 ciclo (sem isto o 1.o ponto de cada linha ficava por baixo da guarda)
logic [23:0] rgb = 24'd0;
always_ff @(posedge clk_pixel) rgb <= {r, g, b};

// ---- audio: um flanco de subida de clk_audio por amostra ----
logic [2:0]  tg = 3'd0;
logic [15:0] am_l = 16'd0, am_r = 16'd0;
logic [3:0]  ca_cnt = 4'd0;
logic        clk_audio = 1'b0;
always_ff @(posedge clk_pixel) begin
    tg <= {tg[1:0], aud_tog};
    if (tg[2] != tg[1]) begin                   // amostra nova (os dados estao parados ha' ~20 us)
        am_l <= aud_l; am_r <= aud_r;
        ca_cnt <= 4'd1;
    end else if (ca_cnt != 4'd0)
        ca_cnt <= ca_cnt + 1'b1;
    clk_audio <= ca_cnt >= 4'd3 && ca_cnt < 4'd11;   // sobe 2 ciclos depois da copia, desce 8 depois
end
logic [AUDIO_BIT_WIDTH-1:0] audio_sample_word [1:0];
assign audio_sample_word[0] = am_l;
assign audio_sample_word[1] = am_r;

// ---- daqui para baixo: o hdmi.sv da hdl-util (versao do NanoMig), sem o gerador de tempos ----
logic video_data_period = 0;
always_ff @(posedge clk_pixel)
    video_data_period <= cx < screen_width && cy < screen_height;

logic [2:0] mode = 3'd1;
logic [23:0] video_data = 24'd0;
logic [5:0] control_data = 6'd0;
logic [11:0] data_island_data = 12'd0;

logic video_guard = 1;
logic video_preamble = 0;
always_ff @(posedge clk_pixel) begin
    video_guard <= cx >= frame_width - 2 && cx < frame_width && (cy == frame_height - 1 || cy < screen_height - 1);
    video_preamble <= cx >= frame_width - 10 && cx < frame_width - 2 && (cy == frame_height - 1 || cy < screen_height - 1);
end

int max_num_packets_alongside;
logic [4:0] num_packets_alongside;
always_comb begin
    max_num_packets_alongside = (FRAME_W - SCREEN_W - 2 - 8 - 4 - 2 - 2 - 8 - 4) / 32;
    if (max_num_packets_alongside > 18)
        num_packets_alongside = 5'd18;
    else
        num_packets_alongside = 5'(max_num_packets_alongside);
end

logic data_island_period_instantaneous;
assign data_island_period_instantaneous = num_packets_alongside > 0 && cx >= screen_width + 14 && cx < screen_width + 14 + num_packets_alongside * 32;
logic packet_enable;
assign packet_enable = data_island_period_instantaneous && 5'(cx + screen_width + 18) == 5'd0;

logic data_island_guard = 0;
logic data_island_preamble = 0;
logic data_island_period = 0;
always_ff @(posedge clk_pixel) begin
    data_island_guard <= num_packets_alongside > 0 && (
        (cx >= screen_width + 12 && cx < screen_width + 14) ||
        (cx >= screen_width + 14 + num_packets_alongside * 32 && cx < screen_width + 14 + num_packets_alongside * 32 + 2));
    data_island_preamble <= num_packets_alongside > 0 && cx >= screen_width + 4 && cx < screen_width + 12;
    data_island_period <= data_island_period_instantaneous;
end

logic [23:0] header;
logic [55:0] sub [3:0];
logic video_field_end;
assign video_field_end = cx == screen_width - 1'b1 && cy == screen_height - 1'b1;
logic [4:0] packet_pixel_counter;
packet_picker #(
    .VIDEO_RATE(VIDEO_RATE),
    .IT_CONTENT(1'b1),
    .AUDIO_RATE(AUDIO_RATE),
    .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
    .VENDOR_NAME({"Timmy", 24'd0}),
    .PRODUCT_DESCRIPTION({"Timex", 88'd0}),
    .SOURCE_DEVICE_INFORMATION(8'h08)       // 08h = jogos
) packet_picker (.clk_pixel(clk_pixel), .clk_audio(clk_audio), .reset(reset), .cea(cea), .video_field_end(video_field_end), .packet_enable(packet_enable), .packet_pixel_counter(packet_pixel_counter), .audio_sample_word(audio_sample_word), .header(header), .sub(sub));
logic [8:0] packet_data;
packet_assembler packet_assembler (.clk_pixel(clk_pixel), .reset(reset), .data_island_period(data_island_period), .header(header), .sub(sub), .packet_data(packet_data), .counter(packet_pixel_counter));

always_ff @(posedge clk_pixel) begin
    mode <= data_island_guard ? 3'd4 : data_island_period ? 3'd3 : video_guard ? 3'd2 : video_data_period ? 3'd1 : 3'd0;
    video_data <= rgb;
    control_data <= {{1'b0, data_island_preamble}, {1'b0, video_preamble || data_island_preamble}, {vsync, hsync}};
    data_island_data[11:4] <= packet_data[8:1];
    data_island_data[3] <= cx != 0;
    data_island_data[2] <= packet_data[0];
    data_island_data[1:0] <= {vsync, hsync};
end

logic [9:0] tmds_internal [NUM_CHANNELS-1:0];
genvar i;
generate
    for (i = 0; i < NUM_CHANNELS; i++) begin: tmds_gen
        tmds_channel #(.CN(i)) tmds_channel (.clk_pixel(clk_pixel), .video_data(video_data[i*8+7:i*8]), .data_island_data(data_island_data[i*4+3:i*4]), .control_data(control_data[i*2+1:i*2]), .mode(mode), .tmds(tmds_internal[i]));
    end
endgenerate

assign q0 = tmds_internal[0];
assign q1 = tmds_internal[1];
assign q2 = tmds_internal[2];

endmodule
