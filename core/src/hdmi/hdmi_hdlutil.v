// hdmi_hdlutil.v: GERADO com o sv2v a partir de hdmi_hdlutil.sv e hdl-util/*.sv (hdl-util/hdmi, Sameer Puri,
//   MIT ou Apache-2.0 - ver hdl-util/LICENSE-*). Nao editar: editar os .sv e, nesta pasta, refazer com
//   sv2v --top=hdmi_hdlutil hdmi_hdlutil.sv hdl-util/*.sv > hdmi_hdlutil.v
module hdmi_hdlutil (
	clk_pixel,
	r,
	g,
	b,
	de,
	hs,
	vs,
	aud_l,
	aud_r,
	aud_tog,
	q0,
	q1,
	q2
);
	reg _sv2v_0;
	parameter signed [31:0] SCREEN_W = 720;
	parameter signed [31:0] FRAME_W = 864;
	parameter signed [31:0] SCREEN_H = 576;
	parameter signed [31:0] FRAME_H = 625;
	parameter signed [31:0] CEA = 17;
	parameter signed [31:0] VIDEO_RATE = 27000000;
	parameter signed [31:0] AUDIO_RATE = 48000;
	parameter signed [31:0] AUDIO_BIT_WIDTH = 16;
	input wire clk_pixel;
	input wire [7:0] r;
	input wire [7:0] g;
	input wire [7:0] b;
	input wire de;
	input wire hs;
	input wire vs;
	input wire [15:0] aud_l;
	input wire [15:0] aud_r;
	input wire aud_tog;
	output wire [9:0] q0;
	output wire [9:0] q1;
	output wire [9:0] q2;
	localparam signed [31:0] NUM_CHANNELS = 3;
	function automatic signed [10:0] sv2v_cast_11_signed;
		input reg signed [10:0] inp;
		sv2v_cast_11_signed = inp;
	endfunction
	wire [10:0] frame_width = sv2v_cast_11_signed(FRAME_W);
	wire [10:0] screen_width = sv2v_cast_11_signed(SCREEN_W);
	function automatic signed [9:0] sv2v_cast_10_signed;
		input reg signed [9:0] inp;
		sv2v_cast_10_signed = inp;
	endfunction
	wire [9:0] frame_height = sv2v_cast_10_signed(FRAME_H);
	wire [9:0] screen_height = sv2v_cast_10_signed(SCREEN_H);
	function automatic signed [7:0] sv2v_cast_8_signed;
		input reg signed [7:0] inp;
		sv2v_cast_8_signed = inp;
	endfunction
	wire [7:0] cea = sv2v_cast_8_signed(CEA);
	reg [4:0] rst_c = 5'd0;
	wire reset = rst_c != 5'd31;
	always @(posedge clk_pixel)
		if (rst_c != 5'd31)
			rst_c <= rst_c + 1'b1;
	reg [10:0] cx_r = 11'd0;
	reg [9:0] cy_r = 10'd0;
	reg de_d = 1'b0;
	reg vs_d = 1'b0;
	reg nova = 1'b1;
	reg [10:0] cx;
	reg [9:0] cy;
	always @(*) begin
		if (_sv2v_0)
			;
		if (de && !de_d) begin
			cx = 11'd0;
			cy = (nova ? 10'd0 : cy_r);
		end
		else begin
			cx = cx_r;
			cy = cy_r;
		end
	end
	always @(posedge clk_pixel) begin
		de_d <= de;
		vs_d <= vs;
		if (vs != vs_d)
			nova <= 1'b1;
		else if (de && !de_d)
			nova <= 1'b0;
		cx_r <= (cx == (frame_width - 1'b1) ? 11'd0 : cx + 1'b1);
		cy_r <= (cx == (frame_width - 1'b1) ? (cy == (frame_height - 1'b1) ? 10'd0 : cy + 1'b1) : cy);
	end
	wire hsync;
	wire vsync;
	assign hsync = hs;
	assign vsync = vs;
	reg [23:0] rgb = 24'd0;
	always @(posedge clk_pixel) rgb <= {r, g, b};
	reg [2:0] tg = 3'd0;
	reg [15:0] am_l = 16'd0;
	reg [15:0] am_r = 16'd0;
	reg [3:0] ca_cnt = 4'd0;
	reg clk_audio = 1'b0;
	always @(posedge clk_pixel) begin
		tg <= {tg[1:0], aud_tog};
		if (tg[2] != tg[1]) begin
			am_l <= aud_l;
			am_r <= aud_r;
			ca_cnt <= 4'd1;
		end
		else if (ca_cnt != 4'd0)
			ca_cnt <= ca_cnt + 1'b1;
		clk_audio <= (ca_cnt >= 4'd3) && (ca_cnt < 4'd11);
	end
	wire [(2 * AUDIO_BIT_WIDTH) - 1:0] audio_sample_word;
	assign audio_sample_word[0+:AUDIO_BIT_WIDTH] = am_l;
	assign audio_sample_word[AUDIO_BIT_WIDTH+:AUDIO_BIT_WIDTH] = am_r;
	reg video_data_period = 0;
	always @(posedge clk_pixel) video_data_period <= (cx < screen_width) && (cy < screen_height);
	reg [2:0] mode = 3'd1;
	reg [23:0] video_data = 24'd0;
	reg [5:0] control_data = 6'd0;
	reg [11:0] data_island_data = 12'd0;
	reg video_guard = 1;
	reg video_preamble = 0;
	always @(posedge clk_pixel) begin
		video_guard <= ((cx >= (frame_width - 2)) && (cx < frame_width)) && ((cy == (frame_height - 1)) || (cy < (screen_height - 1)));
		video_preamble <= ((cx >= (frame_width - 10)) && (cx < (frame_width - 2))) && ((cy == (frame_height - 1)) || (cy < (screen_height - 1)));
	end
	reg signed [31:0] max_num_packets_alongside;
	reg [4:0] num_packets_alongside;
	function automatic signed [4:0] sv2v_cast_5_signed;
		input reg signed [4:0] inp;
		sv2v_cast_5_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		max_num_packets_alongside = ((FRAME_W - SCREEN_W) - 30) / 32;
		if (max_num_packets_alongside > 18)
			num_packets_alongside = 5'd18;
		else
			num_packets_alongside = sv2v_cast_5_signed(max_num_packets_alongside);
	end
	wire data_island_period_instantaneous;
	assign data_island_period_instantaneous = ((num_packets_alongside > 0) && (cx >= (screen_width + 14))) && (cx < ((screen_width + 14) + (num_packets_alongside * 32)));
	wire packet_enable;
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	assign packet_enable = data_island_period_instantaneous && (sv2v_cast_5((cx + screen_width) + 18) == 5'd0);
	reg data_island_guard = 0;
	reg data_island_preamble = 0;
	reg data_island_period = 0;
	always @(posedge clk_pixel) begin
		data_island_guard <= (num_packets_alongside > 0) && (((cx >= (screen_width + 12)) && (cx < (screen_width + 14))) || ((cx >= ((screen_width + 14) + (num_packets_alongside * 32))) && (cx < (((screen_width + 14) + (num_packets_alongside * 32)) + 2))));
		data_island_preamble <= ((num_packets_alongside > 0) && (cx >= (screen_width + 4))) && (cx < (screen_width + 12));
		data_island_period <= data_island_period_instantaneous;
	end
	wire [23:0] header;
	wire [223:0] sub;
	wire video_field_end;
	assign video_field_end = (cx == (screen_width - 1'b1)) && (cy == (screen_height - 1'b1));
	wire [4:0] packet_pixel_counter;
	packet_picker #(
		.VIDEO_RATE(VIDEO_RATE),
		.IT_CONTENT(1'b1),
		.AUDIO_RATE(AUDIO_RATE),
		.AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
		.VENDOR_NAME({"Timex", 24'd0}),
		.PRODUCT_DESCRIPTION({"Timextenso", 48'd0}),
		.SOURCE_DEVICE_INFORMATION(8'h08)
	) packet_picker(
		.clk_pixel(clk_pixel),
		.clk_audio(clk_audio),
		.reset(reset),
		.cea(cea),
		.video_field_end(video_field_end),
		.packet_enable(packet_enable),
		.packet_pixel_counter(packet_pixel_counter),
		.audio_sample_word(audio_sample_word),
		.header(header),
		.sub(sub)
	);
	wire [8:0] packet_data;
	packet_assembler packet_assembler(
		.clk_pixel(clk_pixel),
		.reset(reset),
		.data_island_period(data_island_period),
		.header(header),
		.sub(sub),
		.packet_data(packet_data),
		.counter(packet_pixel_counter)
	);
	always @(posedge clk_pixel) begin
		mode <= (data_island_guard ? 3'd4 : (data_island_period ? 3'd3 : (video_guard ? 3'd2 : (video_data_period ? 3'd1 : 3'd0))));
		video_data <= rgb;
		control_data <= {1'b0, data_island_preamble, 1'b0, video_preamble || data_island_preamble, vsync, hsync};
		data_island_data[11:4] <= packet_data[8:1];
		data_island_data[3] <= cx != 0;
		data_island_data[2] <= packet_data[0];
		data_island_data[1:0] <= {vsync, hsync};
	end
	wire [9:0] tmds_internal [2:0];
	genvar _gv_i_1;
	generate
		for (_gv_i_1 = 0; _gv_i_1 < NUM_CHANNELS; _gv_i_1 = _gv_i_1 + 1) begin : tmds_gen
			localparam i = _gv_i_1;
			tmds_channel #(.CN(i)) tmds_channel(
				.clk_pixel(clk_pixel),
				.video_data(video_data[(i * 8) + 7:i * 8]),
				.data_island_data(data_island_data[(i * 4) + 3:i * 4]),
				.control_data(control_data[(i * 2) + 1:i * 2]),
				.mode(mode),
				.tmds(tmds_internal[i])
			);
		end
	endgenerate
	assign q0 = tmds_internal[0];
	assign q1 = tmds_internal[1];
	assign q2 = tmds_internal[2];
	initial _sv2v_0 = 0;
endmodule
module audio_clock_regeneration_packet (
	clk_pixel,
	clk_audio,
	clk_audio_counter_wrap,
	header,
	sub
);
	parameter signed [31:0] VIDEO_RATE = 25200000;
	parameter signed [31:0] AUDIO_RATE = 48e3;
	input wire clk_pixel;
	input wire clk_audio;
	output reg clk_audio_counter_wrap;
	output wire [23:0] header;
	output wire [223:0] sub;
	function automatic signed [19:0] sv2v_cast_20_signed;
		input reg signed [19:0] inp;
		sv2v_cast_20_signed = inp;
	endfunction
	localparam [19:0] N = ((AUDIO_RATE % 125) == 0 ? sv2v_cast_20_signed((16 * AUDIO_RATE) / 125) : ((AUDIO_RATE % 225) == 0 ? sv2v_cast_20_signed((32 * AUDIO_RATE) / 225) : sv2v_cast_20_signed((AUDIO_RATE * 16) / 125)));
	localparam signed [31:0] CLK_AUDIO_COUNTER_WIDTH = $clog2(N / 128);
	function automatic [CLK_AUDIO_COUNTER_WIDTH - 1:0] sv2v_cast_C773D;
		input reg [CLK_AUDIO_COUNTER_WIDTH - 1:0] inp;
		sv2v_cast_C773D = inp;
	endfunction
	localparam [CLK_AUDIO_COUNTER_WIDTH - 1:0] CLK_AUDIO_COUNTER_END = sv2v_cast_C773D((N / 128) - 1);
	function automatic signed [CLK_AUDIO_COUNTER_WIDTH - 1:0] sv2v_cast_C773D_signed;
		input reg signed [CLK_AUDIO_COUNTER_WIDTH - 1:0] inp;
		sv2v_cast_C773D_signed = inp;
	endfunction
	reg [CLK_AUDIO_COUNTER_WIDTH - 1:0] clk_audio_counter = sv2v_cast_C773D_signed(0);
	reg internal_clk_audio_counter_wrap = 1'd0;
	always @(posedge clk_audio)
		if (clk_audio_counter == CLK_AUDIO_COUNTER_END) begin
			clk_audio_counter <= sv2v_cast_C773D_signed(0);
			internal_clk_audio_counter_wrap <= !internal_clk_audio_counter_wrap;
		end
		else
			clk_audio_counter <= clk_audio_counter + 1'd1;
	initial clk_audio_counter_wrap = 1'b0;
	reg [1:0] clk_audio_counter_wrap_synchronizer_chain = 2'd0;
	always @(posedge clk_pixel) clk_audio_counter_wrap_synchronizer_chain <= {internal_clk_audio_counter_wrap, clk_audio_counter_wrap_synchronizer_chain[1]};
	localparam signed [31:0] CYCLE_TIME_STAMP_COUNTER_WIDTH = 20;
	reg [19:0] cycle_time_stamp = 20'd0;
	reg [19:0] cycle_time_stamp_counter = 20'sd0;
	always @(posedge clk_pixel)
		if (clk_audio_counter_wrap_synchronizer_chain[1] ^ clk_audio_counter_wrap_synchronizer_chain[0]) begin
			cycle_time_stamp_counter <= 20'sd0;
			cycle_time_stamp <= cycle_time_stamp_counter + 20'sd1;
			clk_audio_counter_wrap <= !clk_audio_counter_wrap;
		end
		else
			cycle_time_stamp_counter <= cycle_time_stamp_counter + 20'sd1;
	assign header = 24'hxxxx01;
	genvar _gv_i_2;
	generate
		for (_gv_i_2 = 0; _gv_i_2 < 4; _gv_i_2 = _gv_i_2 + 1) begin : same_packet
			localparam i = _gv_i_2;
			assign sub[i * 56+:56] = {N[7:0], N[15:8], 4'd0, N[19:16], cycle_time_stamp[7:0], cycle_time_stamp[15:8], 4'd0, cycle_time_stamp[19:16], 8'd0};
		end
	endgenerate
endmodule
module audio_info_frame (
	header,
	sub
);
	parameter [2:0] AUDIO_CHANNEL_COUNT = 3'd1;
	parameter [7:0] CHANNEL_ALLOCATION = 8'h00;
	parameter [0:0] DOWN_MIX_INHIBITED = 1'b0;
	parameter [3:0] LEVEL_SHIFT_VALUE = 4'd0;
	parameter [1:0] LOW_FREQUENCY_EFFECTS_PLAYBACK_LEVEL = 2'b00;
	output wire [23:0] header;
	output wire [223:0] sub;
	localparam [3:0] AUDIO_CODING_TYPE = 4'd0;
	localparam [2:0] SAMPLING_FREQUENCY = 3'd0;
	localparam [1:0] SAMPLE_SIZE = 2'd0;
	localparam [4:0] LENGTH = 5'd10;
	localparam [7:0] VERSION = 8'd1;
	localparam [6:0] TYPE = 7'd4;
	assign header = {3'b000, LENGTH, VERSION, 1'b1, TYPE};
	wire [7:0] packet_bytes [27:0];
	assign packet_bytes[0] = 8'd1 + ~(((((((header[23:16] + header[15:8]) + header[7:0]) + packet_bytes[5]) + packet_bytes[4]) + packet_bytes[3]) + packet_bytes[2]) + packet_bytes[1]);
	assign packet_bytes[1] = {AUDIO_CODING_TYPE, 1'b0, AUDIO_CHANNEL_COUNT};
	assign packet_bytes[2] = {3'd0, SAMPLING_FREQUENCY, SAMPLE_SIZE};
	assign packet_bytes[3] = 8'd0;
	assign packet_bytes[4] = CHANNEL_ALLOCATION;
	assign packet_bytes[5] = {DOWN_MIX_INHIBITED, LEVEL_SHIFT_VALUE, 1'b0, LOW_FREQUENCY_EFFECTS_PLAYBACK_LEVEL};
	genvar _gv_i_3;
	generate
		for (_gv_i_3 = 6; _gv_i_3 < 28; _gv_i_3 = _gv_i_3 + 1) begin : pb_reserved
			localparam i = _gv_i_3;
			assign packet_bytes[i] = 8'd0;
		end
		for (_gv_i_3 = 0; _gv_i_3 < 4; _gv_i_3 = _gv_i_3 + 1) begin : pb_to_sub
			localparam i = _gv_i_3;
			assign sub[i * 56+:56] = {packet_bytes[6 + (i * 7)], packet_bytes[5 + (i * 7)], packet_bytes[4 + (i * 7)], packet_bytes[3 + (i * 7)], packet_bytes[2 + (i * 7)], packet_bytes[1 + (i * 7)], packet_bytes[0 + (i * 7)]};
		end
	endgenerate
endmodule
module audio_sample_packet (
	frame_counter,
	valid_bit,
	user_data_bit,
	audio_sample_word,
	audio_sample_word_present,
	header,
	sub
);
	reg _sv2v_0;
	parameter [0:0] GRADE = 1'b0;
	parameter [0:0] SAMPLE_WORD_TYPE = 1'b0;
	parameter [0:0] COPYRIGHT_NOT_ASSERTED = 1'b1;
	parameter [2:0] PRE_EMPHASIS = 3'b000;
	parameter [1:0] MODE = 2'b00;
	parameter [7:0] CATEGORY_CODE = 8'd0;
	parameter [3:0] SOURCE_NUMBER = 4'd0;
	parameter [3:0] SAMPLING_FREQUENCY = 4'b0000;
	parameter [1:0] CLOCK_ACCURACY = 2'b00;
	parameter [3:0] WORD_LENGTH = 0;
	parameter [3:0] ORIGINAL_SAMPLING_FREQUENCY = 4'b0000;
	parameter [0:0] LAYOUT = 1'b0;
	input wire [7:0] frame_counter;
	input wire [7:0] valid_bit;
	input wire [7:0] user_data_bit;
	input wire [191:0] audio_sample_word;
	input wire [3:0] audio_sample_word_present;
	output wire [23:0] header;
	output reg [223:0] sub;
	reg [3:0] CHANNEL_LEFT = 4'd1;
	reg [3:0] CHANNEL_RIGHT = 4'd2;
	localparam [7:0] CHANNEL_STATUS_LENGTH = 8'd192;
	wire [191:0] channel_status_left;
	assign channel_status_left = {152'd0, ORIGINAL_SAMPLING_FREQUENCY, WORD_LENGTH, 2'b00, CLOCK_ACCURACY, SAMPLING_FREQUENCY, CHANNEL_LEFT, SOURCE_NUMBER, CATEGORY_CODE, MODE, PRE_EMPHASIS, COPYRIGHT_NOT_ASSERTED, SAMPLE_WORD_TYPE, GRADE};
	wire [CHANNEL_STATUS_LENGTH - 1:0] channel_status_right;
	assign channel_status_right = {152'd0, ORIGINAL_SAMPLING_FREQUENCY, WORD_LENGTH, 2'b00, CLOCK_ACCURACY, SAMPLING_FREQUENCY, CHANNEL_RIGHT, SOURCE_NUMBER, CATEGORY_CODE, MODE, PRE_EMPHASIS, COPYRIGHT_NOT_ASSERTED, SAMPLE_WORD_TYPE, GRADE};
	assign header[19:12] = {7'b0000000, LAYOUT};
	assign header[7:0] = 8'd2;
	wire [1:0] parity_bit [3:0];
	reg [7:0] aligned_frame_counter [3:0];
	genvar _gv_i_4;
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	generate
		for (_gv_i_4 = 0; _gv_i_4 < 4; _gv_i_4 = _gv_i_4 + 1) begin : sample_based_assign
			localparam i = _gv_i_4;
			always @(*) begin
				if (_sv2v_0)
					;
				if (sv2v_cast_8(frame_counter + i) >= CHANNEL_STATUS_LENGTH)
					aligned_frame_counter[i] = sv2v_cast_8((frame_counter + i) - CHANNEL_STATUS_LENGTH);
				else
					aligned_frame_counter[i] = sv2v_cast_8(frame_counter + i);
			end
			assign header[20 + i] = (aligned_frame_counter[i] == 8'd0) && audio_sample_word_present[i];
			assign header[8 + i] = audio_sample_word_present[i];
			assign parity_bit[i][0] = ^{channel_status_left[aligned_frame_counter[i]], user_data_bit[i * 2], valid_bit[i * 2], audio_sample_word[(i * 2) * 24+:24]};
			assign parity_bit[i][1] = ^{channel_status_right[aligned_frame_counter[i]], user_data_bit[(i * 2) + 1], valid_bit[(i * 2) + 1], audio_sample_word[((i * 2) + 1) * 24+:24]};
			always @(*) begin
				if (_sv2v_0)
					;
				if (audio_sample_word_present[i])
					sub[i * 56+:56] = {parity_bit[i][1], channel_status_right[aligned_frame_counter[i]], user_data_bit[(i * 2) + 1], valid_bit[(i * 2) + 1], parity_bit[i][0], channel_status_left[aligned_frame_counter[i]], user_data_bit[i * 2], valid_bit[i * 2], audio_sample_word[((i * 2) + 1) * 24+:24], audio_sample_word[(i * 2) * 24+:24]};
				else
					sub[i * 56+:56] = 56'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
			end
		end
	endgenerate
	initial _sv2v_0 = 0;
endmodule
module auxiliary_video_information_info_frame (
	cea,
	header,
	sub
);
	parameter [1:0] VIDEO_FORMAT = 2'b00;
	parameter [0:0] ACTIVE_FORMAT_INFO_PRESENT = 1'b0;
	parameter [1:0] BAR_INFO = 2'b00;
	parameter [1:0] SCAN_INFO = 2'b00;
	parameter [1:0] COLORIMETRY = 2'b00;
	parameter [1:0] PICTURE_ASPECT_RATIO = 2'b00;
	parameter [3:0] ACTIVE_FORMAT_ASPECT_RATIO = 4'b1001;
	parameter [0:0] IT_CONTENT = 1'b0;
	parameter [2:0] EXTENDED_COLORIMETRY = 3'b000;
	parameter [1:0] RGB_QUANTIZATION_RANGE = 2'b00;
	parameter [1:0] NON_UNIFORM_PICTURE_SCALING = 2'b00;
	parameter [1:0] YCC_QUANTIZATION_RANGE = 2'b00;
	parameter [1:0] CONTENT_TYPE = 2'b00;
	parameter [3:0] PIXEL_REPETITION = 4'b0000;
	input wire [7:0] cea;
	output wire [23:0] header;
	output wire [223:0] sub;
	localparam [4:0] LENGTH = 5'd13;
	localparam [7:0] VERSION = 8'd2;
	localparam [6:0] TYPE = 7'd2;
	assign header = {3'b000, LENGTH, VERSION, 1'b1, TYPE};
	wire [7:0] packet_bytes [27:0];
	assign packet_bytes[0] = 8'd1 + ~(((((((((((((((header[23:16] + header[15:8]) + header[7:0]) + packet_bytes[13]) + packet_bytes[12]) + packet_bytes[11]) + packet_bytes[10]) + packet_bytes[9]) + packet_bytes[8]) + packet_bytes[7]) + packet_bytes[6]) + packet_bytes[5]) + packet_bytes[4]) + packet_bytes[3]) + packet_bytes[2]) + packet_bytes[1]);
	assign packet_bytes[1] = {1'b0, VIDEO_FORMAT, ACTIVE_FORMAT_INFO_PRESENT, BAR_INFO, SCAN_INFO};
	assign packet_bytes[2] = {COLORIMETRY, PICTURE_ASPECT_RATIO, ACTIVE_FORMAT_ASPECT_RATIO};
	assign packet_bytes[3] = {IT_CONTENT, EXTENDED_COLORIMETRY, RGB_QUANTIZATION_RANGE, NON_UNIFORM_PICTURE_SCALING};
	assign packet_bytes[4] = cea;
	assign packet_bytes[5] = {YCC_QUANTIZATION_RANGE, CONTENT_TYPE, PIXEL_REPETITION};
	genvar _gv_i_5;
	generate
		if (BAR_INFO != 2'b00) begin : genblk1
			assign packet_bytes[6] = 8'hff;
			assign packet_bytes[7] = 8'hff;
			assign packet_bytes[8] = 8'h00;
			assign packet_bytes[9] = 8'h00;
			assign packet_bytes[10] = 8'hff;
			assign packet_bytes[11] = 8'hff;
			assign packet_bytes[12] = 8'h00;
			assign packet_bytes[13] = 8'h00;
		end
		else begin : genblk1
			assign packet_bytes[6] = 8'h00;
			assign packet_bytes[7] = 8'h00;
			assign packet_bytes[8] = 8'h00;
			assign packet_bytes[9] = 8'h00;
			assign packet_bytes[10] = 8'h00;
			assign packet_bytes[11] = 8'h00;
			assign packet_bytes[12] = 8'h00;
			assign packet_bytes[13] = 8'h00;
		end
		for (_gv_i_5 = 14; _gv_i_5 < 28; _gv_i_5 = _gv_i_5 + 1) begin : pb_reserved
			localparam i = _gv_i_5;
			assign packet_bytes[i] = 8'd0;
		end
		for (_gv_i_5 = 0; _gv_i_5 < 4; _gv_i_5 = _gv_i_5 + 1) begin : pb_to_sub
			localparam i = _gv_i_5;
			assign sub[i * 56+:56] = {packet_bytes[6 + (i * 7)], packet_bytes[5 + (i * 7)], packet_bytes[4 + (i * 7)], packet_bytes[3 + (i * 7)], packet_bytes[2 + (i * 7)], packet_bytes[1 + (i * 7)], packet_bytes[0 + (i * 7)]};
		end
	endgenerate
endmodule
module packet_assembler (
	clk_pixel,
	reset,
	data_island_period,
	header,
	sub,
	packet_data,
	counter
);
	input wire clk_pixel;
	input wire reset;
	input wire data_island_period;
	input wire [23:0] header;
	input wire [223:0] sub;
	output wire [8:0] packet_data;
	output reg [4:0] counter;
	always @(posedge clk_pixel)
		if (reset)
			counter <= 5'd0;
		else if (data_island_period)
			counter <= counter + 5'd1;
	wire [5:0] counter_t2 = {counter, 1'b0};
	wire [5:0] counter_t2_p1 = {counter, 1'b1};
	reg [39:0] parity = 40'h0000000000;
	wire [63:0] bch [3:0];
	assign bch[0] = {parity[0+:8], sub[0+:56]};
	assign bch[1] = {parity[8+:8], sub[56+:56]};
	assign bch[2] = {parity[16+:8], sub[112+:56]};
	assign bch[3] = {parity[24+:8], sub[168+:56]};
	wire [31:0] bch4 = {parity[32+:8], header};
	assign packet_data = {bch[3][counter_t2_p1], bch[2][counter_t2_p1], bch[1][counter_t2_p1], bch[0][counter_t2_p1], bch[3][counter_t2], bch[2][counter_t2], bch[1][counter_t2], bch[0][counter_t2], bch4[counter]};
	function automatic [7:0] next_ecc;
		input [7:0] ecc;
		input [7:0] next_bch_bit;
		next_ecc = (ecc >> 1) ^ (ecc[0] ^ next_bch_bit ? 8'b10000011 : 8'd0);
	endfunction
	wire [7:0] parity_next [4:0];
	wire [31:0] parity_next_next;
	genvar _gv_i_6;
	generate
		for (_gv_i_6 = 0; _gv_i_6 < 5; _gv_i_6 = _gv_i_6 + 1) begin : parity_calc
			localparam i = _gv_i_6;
			if (i == 4) begin : genblk1
				assign parity_next[i] = next_ecc(parity[i * 8+:8], header[counter]);
			end
			else begin : genblk1
				assign parity_next[i] = next_ecc(parity[i * 8+:8], sub[(i * 56) + counter_t2]);
				assign parity_next_next[i * 8+:8] = next_ecc(parity_next[i], sub[(i * 56) + counter_t2_p1]);
			end
		end
	endgenerate
	always @(posedge clk_pixel)
		if (reset)
			parity <= 40'h0000000000;
		else if (data_island_period) begin
			if (counter < 5'd28) begin
				parity[0+:32] <= parity_next_next;
				if (counter < 5'd24)
					parity[32+:8] <= parity_next[4];
			end
			else if (counter == 5'd31)
				parity <= 40'h0000000000;
		end
		else
			parity <= 40'h0000000000;
endmodule
module packet_picker (
	clk_pixel,
	clk_audio,
	reset,
	cea,
	video_field_end,
	packet_enable,
	packet_pixel_counter,
	audio_sample_word,
	header,
	sub
);
	reg _sv2v_0;
	parameter signed [31:0] VIDEO_RATE = 0;
	parameter [0:0] IT_CONTENT = 1'b0;
	parameter signed [31:0] AUDIO_BIT_WIDTH = 0;
	parameter signed [31:0] AUDIO_RATE = 0;
	parameter [63:0] VENDOR_NAME = 0;
	parameter [127:0] PRODUCT_DESCRIPTION = 0;
	parameter [7:0] SOURCE_DEVICE_INFORMATION = 0;
	input wire clk_pixel;
	input wire clk_audio;
	input wire reset;
	input wire [7:0] cea;
	input wire video_field_end;
	input wire packet_enable;
	input wire [4:0] packet_pixel_counter;
	input wire [(2 * AUDIO_BIT_WIDTH) - 1:0] audio_sample_word;
	output wire [23:0] header;
	output wire [223:0] sub;
	reg [7:0] packet_type = 8'd0;
	wire [23:0] headers [255:0];
	wire [223:0] subs [255:0];
	assign header = headers[packet_type];
	assign sub[0+:56] = subs[packet_type][0+:56];
	assign sub[56+:56] = subs[packet_type][56+:56];
	assign sub[112+:56] = subs[packet_type][112+:56];
	assign sub[168+:56] = subs[packet_type][168+:56];
	assign headers[0] = 24'hxxxx00;
	assign subs[0][0+:56] = 56'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
	assign subs[0][56+:56] = 56'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
	assign subs[0][112+:56] = 56'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
	assign subs[0][168+:56] = 56'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
	wire clk_audio_counter_wrap;
	audio_clock_regeneration_packet #(
		.VIDEO_RATE(VIDEO_RATE),
		.AUDIO_RATE(AUDIO_RATE)
	) audio_clock_regeneration_packet(
		.clk_pixel(clk_pixel),
		.clk_audio(clk_audio),
		.clk_audio_counter_wrap(clk_audio_counter_wrap),
		.header(headers[1]),
		.sub(subs[1])
	);
	localparam [3:0] SAMPLING_FREQUENCY = (AUDIO_RATE == 32000 ? 4'b0011 : (AUDIO_RATE == 44100 ? 4'b0000 : (AUDIO_RATE == 88200 ? 4'b1000 : (AUDIO_RATE == 176400 ? 4'b1100 : (AUDIO_RATE == 48000 ? 4'b0010 : (AUDIO_RATE == 96000 ? 4'b1010 : (AUDIO_RATE == 192000 ? 4'b1110 : 4'bxxxx)))))));
	localparam signed [31:0] AUDIO_BIT_WIDTH_COMPARATOR = (AUDIO_BIT_WIDTH < 20 ? 20 : (AUDIO_BIT_WIDTH == 20 ? 25 : (AUDIO_BIT_WIDTH < 24 ? 24 : (AUDIO_BIT_WIDTH == 24 ? 29 : -1))));
	function automatic signed [2:0] sv2v_cast_3_signed;
		input reg signed [2:0] inp;
		sv2v_cast_3_signed = inp;
	endfunction
	localparam [2:0] WORD_LENGTH = sv2v_cast_3_signed(AUDIO_BIT_WIDTH_COMPARATOR - AUDIO_BIT_WIDTH);
	localparam [0:0] WORD_LENGTH_LIMIT = (AUDIO_BIT_WIDTH <= 20 ? 1'b0 : 1'b1);
	reg [(2 * AUDIO_BIT_WIDTH) - 1:0] audio_sample_word_transfer;
	reg audio_sample_word_transfer_control = 1'd0;
	always @(posedge clk_audio) begin
		audio_sample_word_transfer <= audio_sample_word;
		audio_sample_word_transfer_control <= !audio_sample_word_transfer_control;
	end
	reg [1:0] audio_sample_word_transfer_control_synchronizer_chain = 2'd0;
	always @(posedge clk_pixel) audio_sample_word_transfer_control_synchronizer_chain <= {audio_sample_word_transfer_control, audio_sample_word_transfer_control_synchronizer_chain[1]};
	reg sample_buffer_current = 1'b0;
	reg [1:0] samples_remaining = 2'd0;
	reg [191:0] audio_sample_word_buffer [1:0];
	reg [(2 * AUDIO_BIT_WIDTH) - 1:0] audio_sample_word_transfer_mux;
	always @(*) begin
		if (_sv2v_0)
			;
		if (audio_sample_word_transfer_control_synchronizer_chain[0] ^ audio_sample_word_transfer_control_synchronizer_chain[1])
			audio_sample_word_transfer_mux = audio_sample_word_transfer;
		else
			audio_sample_word_transfer_mux = {audio_sample_word_buffer[sample_buffer_current][(((samples_remaining * 2) + 1) * 24) + (23 >= (24 - AUDIO_BIT_WIDTH) ? 23 : (23 + (23 >= (24 - AUDIO_BIT_WIDTH) ? 0 + AUDIO_BIT_WIDTH : (24 - AUDIO_BIT_WIDTH) - 22)) - 1)-:(23 >= (24 - AUDIO_BIT_WIDTH) ? 0 + AUDIO_BIT_WIDTH : (24 - AUDIO_BIT_WIDTH) - 22)], audio_sample_word_buffer[sample_buffer_current][((samples_remaining * 2) * 24) + (23 >= (24 - AUDIO_BIT_WIDTH) ? 23 : (23 + (23 >= (24 - AUDIO_BIT_WIDTH) ? 0 + AUDIO_BIT_WIDTH : (24 - AUDIO_BIT_WIDTH) - 22)) - 1)-:(23 >= (24 - AUDIO_BIT_WIDTH) ? 0 + AUDIO_BIT_WIDTH : (24 - AUDIO_BIT_WIDTH) - 22)]};
	end
	reg sample_buffer_used = 1'b0;
	reg sample_buffer_ready = 1'b0;
	function automatic [23:0] sv2v_cast_24;
		input reg [23:0] inp;
		sv2v_cast_24 = inp;
	endfunction
	always @(posedge clk_pixel) begin
		if (sample_buffer_used)
			sample_buffer_ready <= 1'b0;
		if (audio_sample_word_transfer_control_synchronizer_chain[0] ^ audio_sample_word_transfer_control_synchronizer_chain[1]) begin
			audio_sample_word_buffer[sample_buffer_current][(samples_remaining * 2) * 24+:24] <= sv2v_cast_24(audio_sample_word_transfer_mux[0+:AUDIO_BIT_WIDTH]) << (24 - AUDIO_BIT_WIDTH);
			audio_sample_word_buffer[sample_buffer_current][((samples_remaining * 2) + 1) * 24+:24] <= sv2v_cast_24(audio_sample_word_transfer_mux[AUDIO_BIT_WIDTH+:AUDIO_BIT_WIDTH]) << (24 - AUDIO_BIT_WIDTH);
			if (samples_remaining == 2'd3) begin
				samples_remaining <= 2'd0;
				sample_buffer_ready <= 1'b1;
				sample_buffer_current <= !sample_buffer_current;
			end
			else
				samples_remaining <= samples_remaining + 1'd1;
		end
	end
	reg [191:0] audio_sample_word_packet;
	reg [3:0] audio_sample_word_present_packet;
	reg [7:0] frame_counter = 8'd0;
	wire signed [31:0] k;
	always @(posedge clk_pixel)
		if (reset)
			frame_counter <= 8'd0;
		else if ((packet_pixel_counter == 5'd31) && (packet_type == 8'h02)) begin
			frame_counter <= frame_counter + 8'd4;
			if (frame_counter >= 8'd192)
				frame_counter <= frame_counter - 8'd192;
		end
	audio_sample_packet #(
		.SAMPLING_FREQUENCY(SAMPLING_FREQUENCY),
		.WORD_LENGTH({WORD_LENGTH[0], WORD_LENGTH[1], WORD_LENGTH[2], WORD_LENGTH_LIMIT})
	) audio_sample_packet(
		.frame_counter(frame_counter),
		.valid_bit(8'b00000000),
		.user_data_bit(8'b00000000),
		.audio_sample_word(audio_sample_word_packet),
		.audio_sample_word_present(audio_sample_word_present_packet),
		.header(headers[2]),
		.sub(subs[2])
	);
	auxiliary_video_information_info_frame #(.IT_CONTENT(IT_CONTENT)) auxiliary_video_information_info_frame(
		.cea(cea),
		.header(headers[130]),
		.sub(subs[130])
	);
	source_product_description_info_frame #(
		.VENDOR_NAME(VENDOR_NAME),
		.PRODUCT_DESCRIPTION(PRODUCT_DESCRIPTION),
		.SOURCE_DEVICE_INFORMATION(SOURCE_DEVICE_INFORMATION)
	) source_product_description_info_frame(
		.header(headers[131]),
		.sub(subs[131])
	);
	audio_info_frame audio_info_frame(
		.header(headers[132]),
		.sub(subs[132])
	);
	reg audio_info_frame_sent = 1'b0;
	reg auxiliary_video_information_info_frame_sent = 1'b0;
	reg source_product_description_info_frame_sent = 1'b0;
	reg last_clk_audio_counter_wrap = 1'b0;
	always @(posedge clk_pixel) begin
		if (sample_buffer_used)
			sample_buffer_used <= 1'b0;
		if (reset || video_field_end) begin
			audio_info_frame_sent <= 1'b0;
			auxiliary_video_information_info_frame_sent <= 1'b0;
			source_product_description_info_frame_sent <= 1'b0;
			packet_type <= 8'bxxxxxxxx;
		end
		else if (packet_enable) begin
			if (last_clk_audio_counter_wrap ^ clk_audio_counter_wrap) begin
				packet_type <= 8'd1;
				last_clk_audio_counter_wrap <= clk_audio_counter_wrap;
			end
			else if (sample_buffer_ready) begin
				packet_type <= 8'd2;
				audio_sample_word_packet <= audio_sample_word_buffer[!sample_buffer_current];
				audio_sample_word_present_packet <= 4'b1111;
				sample_buffer_used <= 1'b1;
			end
			else if (!audio_info_frame_sent) begin
				packet_type <= 8'h84;
				audio_info_frame_sent <= 1'b1;
			end
			else if (!auxiliary_video_information_info_frame_sent) begin
				packet_type <= 8'h82;
				auxiliary_video_information_info_frame_sent <= 1'b1;
			end
			else if (!source_product_description_info_frame_sent) begin
				packet_type <= 8'h83;
				source_product_description_info_frame_sent <= 1'b1;
			end
			else
				packet_type <= 8'd0;
		end
	end
	initial _sv2v_0 = 0;
endmodule
module source_product_description_info_frame (
	header,
	sub
);
	parameter [63:0] VENDOR_NAME = 0;
	parameter [127:0] PRODUCT_DESCRIPTION = 0;
	parameter [7:0] SOURCE_DEVICE_INFORMATION = 0;
	output wire [23:0] header;
	output wire [223:0] sub;
	localparam [4:0] LENGTH = 5'd25;
	localparam [7:0] VERSION = 8'd1;
	localparam [6:0] TYPE = 7'd3;
	assign header = {3'b000, LENGTH, VERSION, 1'b1, TYPE};
	wire [7:0] packet_bytes [27:0];
	assign packet_bytes[0] = 8'd1 + ~(((((((((((((((((((((((((((header[23:16] + header[15:8]) + header[7:0]) + packet_bytes[25]) + packet_bytes[24]) + packet_bytes[23]) + packet_bytes[22]) + packet_bytes[21]) + packet_bytes[20]) + packet_bytes[19]) + packet_bytes[18]) + packet_bytes[17]) + packet_bytes[16]) + packet_bytes[15]) + packet_bytes[14]) + packet_bytes[13]) + packet_bytes[12]) + packet_bytes[11]) + packet_bytes[10]) + packet_bytes[9]) + packet_bytes[8]) + packet_bytes[7]) + packet_bytes[6]) + packet_bytes[5]) + packet_bytes[4]) + packet_bytes[3]) + packet_bytes[2]) + packet_bytes[1]);
	wire signed [7:0] vendor_name [0:7];
	wire signed [7:0] product_description [0:15];
	genvar _gv_i_7;
	generate
		for (_gv_i_7 = 0; _gv_i_7 < 8; _gv_i_7 = _gv_i_7 + 1) begin : vendor_to_bytes
			localparam i = _gv_i_7;
			assign vendor_name[i] = VENDOR_NAME[((8 - i) * 8) - 1:(7 - i) * 8];
		end
		for (_gv_i_7 = 0; _gv_i_7 < 16; _gv_i_7 = _gv_i_7 + 1) begin : product_to_bytes
			localparam i = _gv_i_7;
			assign product_description[i] = PRODUCT_DESCRIPTION[((16 - i) * 8) - 1:(15 - i) * 8];
		end
		for (_gv_i_7 = 1; _gv_i_7 < 9; _gv_i_7 = _gv_i_7 + 1) begin : pb_vendor
			localparam i = _gv_i_7;
			assign packet_bytes[i] = (vendor_name[i - 1] == 8'h30 ? 8'h00 : vendor_name[i - 1]);
		end
		for (_gv_i_7 = 9; _gv_i_7 < LENGTH; _gv_i_7 = _gv_i_7 + 1) begin : pb_product
			localparam i = _gv_i_7;
			assign packet_bytes[i] = (product_description[i - 9] == 8'h30 ? 8'h00 : product_description[i - 9]);
		end
	endgenerate
	assign packet_bytes[LENGTH] = SOURCE_DEVICE_INFORMATION;
	generate
		for (_gv_i_7 = 26; _gv_i_7 < 28; _gv_i_7 = _gv_i_7 + 1) begin : pb_reserved
			localparam i = _gv_i_7;
			assign packet_bytes[i] = 8'd0;
		end
		for (_gv_i_7 = 0; _gv_i_7 < 4; _gv_i_7 = _gv_i_7 + 1) begin : pb_to_sub
			localparam i = _gv_i_7;
			assign sub[i * 56+:56] = {packet_bytes[6 + (i * 7)], packet_bytes[5 + (i * 7)], packet_bytes[4 + (i * 7)], packet_bytes[3 + (i * 7)], packet_bytes[2 + (i * 7)], packet_bytes[1 + (i * 7)], packet_bytes[0 + (i * 7)]};
		end
	endgenerate
endmodule
module tmds_channel (
	clk_pixel,
	video_data,
	data_island_data,
	control_data,
	mode,
	tmds
);
	reg _sv2v_0;
	parameter signed [31:0] CN = 0;
	input wire clk_pixel;
	input wire [7:0] video_data;
	input wire [3:0] data_island_data;
	input wire [1:0] control_data;
	input wire [2:0] mode;
	output reg [9:0] tmds;
	reg signed [4:0] acc = 5'sd0;
	reg [8:0] q_m;
	reg [9:0] q_out;
	wire [9:0] video_coding;
	assign video_coding = q_out;
	reg [3:0] N1D;
	reg signed [4:0] N1c;
	reg signed [4:0] N1q_m07;
	wire signed [4:0] N0q_m07;
	reg [8:0] q_mc;
	always @(*) begin
		if (_sv2v_0)
			;
		N1D = ((((((video_data[0] + video_data[1]) + video_data[2]) + video_data[3]) + video_data[4]) + video_data[5]) + video_data[6]) + video_data[7];
		case (((((((q_mc[0] + q_mc[1]) + q_mc[2]) + q_mc[3]) + q_mc[4]) + q_mc[5]) + q_mc[6]) + q_mc[7])
			4'b0000: N1c = 5'sd0;
			4'b0001: N1c = 5'sd1;
			4'b0010: N1c = 5'sd2;
			4'b0011: N1c = 5'sd3;
			4'b0100: N1c = 5'sd4;
			4'b0101: N1c = 5'sd5;
			4'b0110: N1c = 5'sd6;
			4'b0111: N1c = 5'sd7;
			4'b1000: N1c = 5'sd8;
			default: N1c = 5'sd0;
		endcase
	end
	assign N0q_m07 = 5'sd8 - N1q_m07;
	reg signed [4:0] acc_add;
	integer i;
	always @(*) begin
		if (_sv2v_0)
			;
		if ((N1D > 4'd4) || ((N1D == 4'd4) && (video_data[0] == 1'd0))) begin
			q_mc[0] = video_data[0];
			for (i = 0; i < 7; i = i + 1)
				q_mc[i + 1] = q_mc[i] ~^ video_data[i + 1];
			q_mc[8] = 1'b0;
		end
		else begin
			q_mc[0] = video_data[0];
			for (i = 0; i < 7; i = i + 1)
				q_mc[i + 1] = q_mc[i] ^ video_data[i + 1];
			q_mc[8] = 1'b1;
		end
	end
	reg [2:0] mode_r = 3'd0;
	reg [1:0] control_data_r = 2'd0;
	reg [3:0] data_island_data_r = 4'd0;
	always @(posedge clk_pixel) begin
		q_m <= q_mc;
		N1q_m07 <= N1c;
		mode_r <= mode;
		control_data_r <= control_data;
		data_island_data_r <= data_island_data;
	end
	always @(*) begin
		if (_sv2v_0)
			;
		if ((acc == 5'sd0) || (N1q_m07 == N0q_m07)) begin
			if (q_m[8]) begin
				acc_add = N1q_m07 - N0q_m07;
				q_out = {~q_m[8], q_m[8], q_m[7:0]};
			end
			else begin
				acc_add = N0q_m07 - N1q_m07;
				q_out = {~q_m[8], q_m[8], ~q_m[7:0]};
			end
		end
		else if (((acc > 5'sd0) && (N1q_m07 > N0q_m07)) || ((acc < 5'sd0) && (N1q_m07 < N0q_m07))) begin
			q_out = {1'b1, q_m[8], ~q_m[7:0]};
			acc_add = (N0q_m07 - N1q_m07) + (q_m[8] ? 5'sd2 : 5'sd0);
		end
		else begin
			q_out = {1'b0, q_m[8], q_m[7:0]};
			acc_add = (N1q_m07 - N0q_m07) - (~q_m[8] ? 5'sd2 : 5'sd0);
		end
	end
	always @(posedge clk_pixel) acc <= (mode_r != 3'd1 ? 5'sd0 : acc + acc_add);
	reg [9:0] control_coding;
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (control_data_r)
			2'b00: control_coding = 10'b1101010100;
			2'b01: control_coding = 10'b0010101011;
			2'b10: control_coding = 10'b0101010100;
			2'b11: control_coding = 10'b1010101011;
		endcase
	end
	reg [9:0] terc4_coding;
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (data_island_data_r)
			4'b0000: terc4_coding = 10'b1010011100;
			4'b0001: terc4_coding = 10'b1001100011;
			4'b0010: terc4_coding = 10'b1011100100;
			4'b0011: terc4_coding = 10'b1011100010;
			4'b0100: terc4_coding = 10'b0101110001;
			4'b0101: terc4_coding = 10'b0100011110;
			4'b0110: terc4_coding = 10'b0110001110;
			4'b0111: terc4_coding = 10'b0100111100;
			4'b1000: terc4_coding = 10'b1011001100;
			4'b1001: terc4_coding = 10'b0100111001;
			4'b1010: terc4_coding = 10'b0110011100;
			4'b1011: terc4_coding = 10'b1011000110;
			4'b1100: terc4_coding = 10'b1010001110;
			4'b1101: terc4_coding = 10'b1001110001;
			4'b1110: terc4_coding = 10'b0101100011;
			4'b1111: terc4_coding = 10'b1011000011;
		endcase
	end
	wire [9:0] video_guard_band;
	generate
		if ((CN == 0) || (CN == 2)) begin : genblk1
			assign video_guard_band = 10'b1011001100;
		end
		else begin : genblk1
			assign video_guard_band = 10'b0100110011;
		end
	endgenerate
	wire [9:0] data_guard_band;
	generate
		if ((CN == 1) || (CN == 2)) begin : genblk2
			assign data_guard_band = 10'b0100110011;
		end
		else begin : genblk2
			assign data_guard_band = (control_data_r == 2'b00 ? 10'b1010001110 : (control_data_r == 2'b01 ? 10'b1001110001 : (control_data_r == 2'b10 ? 10'b0101100011 : 10'b1011000011)));
		end
	endgenerate
	always @(posedge clk_pixel)
		case (mode_r)
			3'd0: tmds <= control_coding;
			3'd1: tmds <= video_coding;
			3'd2: tmds <= video_guard_band;
			3'd3: tmds <= terc4_coding;
			3'd4: tmds <= data_guard_band;
		endcase
	initial _sv2v_0 = 0;
endmodule
