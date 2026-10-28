// Gerado com o sv2v a partir de rtl/sid do C64_MiSTer (sid_top, sid_voice, sid_envelope, sid_dac: GPL;
// sid_filter: Alexey Melnikov / Dag Lem (reDIP-SID), CERN-OHL-S v2). Mudou: "function f(wire" -> "function f(input";
// sid_tables substituido por sid_tables_8580 (so' o 8580, tabelas em case).
`default_nettype wire
module sid_dac (vin, vout);
	// so' o 6581 usa a DAC nao linear; no Timmy os dois SID sao 8580: passa direito
	parameter BITS = 12;
	input wire [BITS - 1:0] vin;
	output wire [BITS - 1:0] vout;
	assign vout = vin;
endmodule
module sid_envelope (
	clock,
	ce_1m,
	reset,
	gate,
	att_dec,
	sus_rel,
	envelope
);
	input clock;
	input ce_1m;
	input reset;
	input gate;
	input [7:0] att_dec;
	input [7:0] sus_rel;
	output reg [7:0] envelope;
	localparam ST_RELEASE = 0;
	localparam ST_ATTACK = 1;
	localparam ST_DEC_SUS = 2;
	reg [1:0] state;
	wire [239:0] rates = 240'h0010007c01f005e0128036c0850138030e0f403d08c351e84b71e625fa12;
	wire [14:0] rate_period = rates[(15 - (state == ST_ATTACK ? att_dec[7:4] : (state == ST_DEC_SUS ? att_dec[3:0] : sus_rel[3:0]))) * 15+:15];
	always @(posedge clock) begin : sv2v_autoblock_1
		reg hold_zero;
		reg [4:0] exponential_counter_period;
		reg gate_edge;
		reg [14:0] rate_counter;
		reg [4:0] exponential_counter;
		case (envelope)
			'hff: exponential_counter_period <= 0;
			'h5d: exponential_counter_period <= 1;
			'h36: exponential_counter_period <= 3;
			'h1a: exponential_counter_period <= 7;
			'he: exponential_counter_period <= 15;
			'h6: exponential_counter_period <= 29;
			'h0: exponential_counter_period <= 0;
		endcase
		if (reset) begin
			state <= ST_RELEASE;
			gate_edge <= gate;
			envelope <= 0;
			hold_zero <= 1;
			exponential_counter <= 0;
			exponential_counter_period <= 0;
			rate_counter <= 0;
		end
		else if (ce_1m) begin
			rate_counter <= rate_counter + 1'd1;
			if (rate_counter == rate_period) begin
				rate_counter <= 0;
				exponential_counter <= exponential_counter + 1'b1;
				if ((state == ST_ATTACK) || (exponential_counter == exponential_counter_period)) begin
					exponential_counter <= 0;
					case (state)
						ST_ATTACK: begin
							envelope <= envelope + 1'b1;
							if (envelope == 8'hfe)
								state <= ST_DEC_SUS;
						end
						ST_DEC_SUS:
							if ((envelope != {2 {sus_rel[7:4]}}) && !hold_zero)
								envelope <= envelope - 1'b1;
						ST_RELEASE:
							if (!hold_zero)
								envelope <= envelope - 1'b1;
					endcase
					if ((state != ST_ATTACK) && (envelope == 1))
						hold_zero <= 1;
				end
			end
			gate_edge <= gate;
			if (~gate_edge & gate) begin
				state <= ST_ATTACK;
				hold_zero <= 0;
			end
			if (gate_edge & ~gate)
				state <= ST_RELEASE;
		end
	end
endmodule
module sid_filter (
	clk,
	state,
	mode,
	F0,
	Res_Filt,
	Mode_Vol,
	voice1,
	voice2,
	voice3,
	ext_in,
	audio
);
	reg _sv2v_0;
	input clk;
	input [2:0] state;
	input mode;
	input [15:0] F0;
	input [7:0] Res_Filt;
	input [7:0] Mode_Vol;
	input signed [21:0] voice1;
	input signed [21:0] voice2;
	input signed [21:0] voice3;
	input signed [21:0] ext_in;
	output wire [17:0] audio;
	function automatic signed [23:0] sv2v_cast_24_signed;
		input reg signed [23:0] inp;
		sv2v_cast_24_signed = inp;
	endfunction
	localparam signed [23:0] MIXER_DC_6581 = sv2v_cast_24_signed((-1 << 20) / 18);
	function signed [15:0] clamp;
		input signed [16:0] x;
		clamp = (^x[16:15] ? {x[16], {15 {x[15]}}} : x[15:0]);
	endfunction
	function signed [17:0] clamp18;
		input signed [18:0] x;
		clamp18 = (^x[18:17] ? {x[18], {17 {x[17]}}} : x[17:0]);
	endfunction
	localparam [15:0] COMP_KNEE = 16'd3000;
	localparam [4:0] COMP_HG = 5'd6;
	localparam signed [16:0] DC_LP = -17'sd3840;
	function automatic [20:0] sv2v_cast_21;
		input reg [20:0] inp;
		sv2v_cast_21 = inp;
	endfunction
	function automatic [15:0] sv2v_cast_16;
		input reg [15:0] inp;
		sv2v_cast_16 = inp;
	endfunction
	function signed [15:0] compress;
		input signed [15:0] x;
		reg [15:0] ax;
		reg [15:0] over;
		reg [15:0] comp;
		begin
			ax = (x[15] ? -x : x);
			over = ax - COMP_KNEE;
			comp = COMP_KNEE + sv2v_cast_16((sv2v_cast_21(over) * COMP_HG) >> 4);
			compress = (ax <= COMP_KNEE ? x : (x[15] ? -comp : comp));
		end
	endfunction
	wire [351:0] _1_Q_lsl10_tbl = 352'hb514b261c69838f61ceb68674c3d74ac754ea2d38258b514c26145d800eadaeb165a8a6130a2e400758d798b;
	reg signed [33:0] c;
	reg s;
	reg signed [15:0] a;
	reg signed [17:0] b;
	wire signed [33:0] m = a * b;
	wire signed [33:0] o = (s ? c - m : c + m);
	reg signed [17:0] vlp;
	reg signed [17:0] vlp2;
	reg signed [17:0] vlp_next;
	reg signed [17:0] vbp;
	reg signed [17:0] vbp2;
	reg signed [17:0] vbp_next;
	reg signed [17:0] vhp;
	reg signed [17:0] vhp2;
	reg signed [17:0] vhp_next;
	reg signed [18:0] dv;
	reg signed [16:0] tmix;
	reg signed [16:0] tmix_s;
	reg signed [16:0] center;
	reg signed [16:0] center_s;
	reg signed [15:0] tmix_c;
	reg signed [15:0] tmix_c_r;
	function automatic signed [18:0] sv2v_cast_19_signed;
		input reg signed [18:0] inp;
		sv2v_cast_19_signed = inp;
	endfunction
	function automatic signed [16:0] sv2v_cast_17_signed;
		input reg signed [16:0] inp;
		sv2v_cast_17_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		dv = sv2v_cast_19_signed(o >>> 17);
		vlp_next = clamp18(vlp + dv);
		vbp_next = clamp18(vbp + dv);
		vhp_next = clamp18(o[10+:19]);
		tmix = ((Mode_Vol[4] ? sv2v_cast_17_signed(vlp2 >>> 2) : {17 {1'sb0}}) + (Mode_Vol[5] ? sv2v_cast_17_signed(vbp2 >>> 2) : {17 {1'sb0}})) + (Mode_Vol[6] ? sv2v_cast_17_signed(vhp_next >>> 2) : {17 {1'sb0}});
		center = (!mode && Mode_Vol[4] ? DC_LP : 17'sd0);
		tmix_c = (mode ? clamp(tmix_s) : clamp(sv2v_cast_17_signed(compress(clamp(tmix_s - center_s))) + center_s));
	end
	function automatic [17:0] sv2v_cast_18;
		input reg [17:0] inp;
		sv2v_cast_18 = inp;
	endfunction
	function automatic signed [33:0] sv2v_cast_34_signed;
		input reg signed [33:0] inp;
		sv2v_cast_34_signed = inp;
	endfunction
	always @(posedge clk) begin : sv2v_autoblock_1
		reg [10:0] _1_Q_lsl10;
		reg signed [17:0] vi;
		reg signed [15:0] vd;
		vi = 0;
		vd = 0;
		case (state)
			2: begin
				_1_Q_lsl10 <= _1_Q_lsl10_tbl[(31 - {mode, Res_Filt[7:4]}) * 11+:11];
				vi <= sv2v_cast_18(((((Res_Filt[0] ? sv2v_cast_24_signed(voice1) : {24 {1'sb0}}) + (Res_Filt[1] ? sv2v_cast_24_signed(voice2) : {24 {1'sb0}})) + (Res_Filt[2] ? sv2v_cast_24_signed(voice3) : {24 {1'sb0}})) + (Res_Filt[3] ? sv2v_cast_24_signed(ext_in) : {24 {1'sb0}})) >>> 5);
				vd <= sv2v_cast_16((((((mode ? {24 {1'sb0}} : MIXER_DC_6581) + (Res_Filt[0] ? {24 {1'sb0}} : sv2v_cast_24_signed(voice1))) + (Res_Filt[1] ? {24 {1'sb0}} : sv2v_cast_24_signed(voice2))) + (Res_Filt[2] | Mode_Vol[7] ? {24 {1'sb0}} : sv2v_cast_24_signed(voice3))) + (Res_Filt[3] ? {24 {1'sb0}} : sv2v_cast_24_signed(ext_in))) >>> 7);
				c <= 0;
				s <= 1;
				a <= F0;
				b <= vbp;
			end
			3: begin
				{vlp, vlp2} <= {vlp2, vlp_next};
				c <= 0;
				s <= 1;
				b <= vhp;
			end
			4: begin
				{vbp, vbp2} <= {vbp2, vbp_next};
				c <= -(sv2v_cast_34_signed(vlp2) + sv2v_cast_34_signed(vi)) << 10;
				s <= 0;
				a <= _1_Q_lsl10;
				b <= vbp_next;
			end
			5: begin
				{vhp, vhp2} <= {vhp2, vhp_next};
				tmix_s <= tmix;
				center_s <= center;
			end
			6: tmix_c_r <= tmix_c;
			7: begin
				c <= 0;
				s <= 0;
				a <= {12'b000000000000, Mode_Vol[3:0]};
				b <= clamp(sv2v_cast_17_signed(vd) + sv2v_cast_17_signed(tmix_c_r));
			end
		endcase
	end
	assign audio = o[19:2];
	initial _sv2v_0 = 0;
endmodule
module sid_voice (
	clock,
	ce_1m,
	reset,
	mode,
	freq,
	pw,
	control,
	att_dec,
	sus_rel,
	osc_msb_in,
	_st_out,
	p_t_out,
	ps__out,
	pst_out,
	acc_t,
	osc_msb_out,
	voice_out,
	osc_out,
	env_out
);
	reg _sv2v_0;
	input clock;
	input ce_1m;
	input reset;
	input mode;
	input [15:0] freq;
	input [11:0] pw;
	input [7:0] control;
	input [7:0] att_dec;
	input [7:0] sus_rel;
	input osc_msb_in;
	input [7:0] _st_out;
	input [7:0] p_t_out;
	input [7:0] ps__out;
	input [7:0] pst_out;
	output wire [11:0] acc_t;
	output wire osc_msb_out;
	output wire [21:0] voice_out;
	output wire [7:0] osc_out;
	output wire [7:0] env_out;
	localparam [12:0] WAVEFORM_DC_6581 = 13'h0380;
	localparam [12:0] WAVEFORM_DC_8580 = 13'h0800;
	function automatic [21:0] sv2v_cast_22;
		input reg [21:0] inp;
		sv2v_cast_22 = inp;
	endfunction
	localparam signed [21:0] VOICE_DC_6581 = sv2v_cast_22('h340 * 'hff);
	localparam signed [21:0] VOICE_DC_8580 = 22'h000000;
	localparam WF_0_TTL_6581 = 23'd200000;
	localparam WF_0_TTL_8580 = 23'd5000000;
	localparam NOISE_TTL_6581 = 24'h008000;
	localparam NOISE_TTL_8580 = 24'h950000;
	wire test_ctrl = control[3];
	wire ringmod_ctrl = control[2];
	wire sync_ctrl = control[1];
	reg [23:0] oscillator;
	assign osc_msb_out = oscillator[23];
	reg signed [21:0] dca_out;
	assign voice_out = dca_out;
	reg [7:0] wave_out;
	assign osc_out = wave_out;
	wire [7:0] envelope;
	assign env_out = envelope;
	sid_envelope adsr(
		.clock(clock),
		.ce_1m(ce_1m),
		.reset(reset),
		.gate(control[0]),
		.att_dec(att_dec),
		.sus_rel(sus_rel),
		.envelope(envelope)
	);
	reg osc_msb_in_prv;
	always @(posedge clock) begin : sv2v_autoblock_1
		reg test_delay;
		if (ce_1m) begin
			osc_msb_in_prv <= osc_msb_in;
			test_delay <= mode & test_ctrl;
			oscillator <= (((reset || test_ctrl) || test_delay) || ((sync_ctrl && ~osc_msb_in) && osc_msb_in_prv) ? 24'd0 : oscillator + freq);
		end
	end
	assign acc_t = {oscillator[23], oscillator[22:12] ^ {11 {~control[5] & ((ringmod_ctrl & ~osc_msb_in) ^ oscillator[23])}}};
	reg [11:0] noise;
	reg [11:0] saw_tri;
	reg pulse;
	always @(posedge clock) begin : sv2v_autoblock_2
		reg clk;
		reg clk_d;
		reg osc_edge;
		reg [23:0] noise_age;
		reg [22:0] lfsr_noise;
		if (reset) begin
			saw_tri <= 0;
			pulse <= 0;
			noise <= 0;
			osc_edge <= 0;
			lfsr_noise <= 1'sb1;
			noise_age <= 0;
		end
		else if (ce_1m) begin
			osc_edge <= oscillator[19];
			clk <= ~((reset || test_ctrl) || (~osc_edge & oscillator[19]));
			clk_d <= clk;
			saw_tri <= acc_t;
			pulse <= test_ctrl || (oscillator[23:12] >= pw);
			noise <= {lfsr_noise[20], lfsr_noise[18], lfsr_noise[14], lfsr_noise[11], lfsr_noise[9], lfsr_noise[5], lfsr_noise[2], lfsr_noise[0], 4'b0000};
			if (~clk) begin
				if (noise_age >= (mode ? NOISE_TTL_8580 : NOISE_TTL_6581))
					noise <= 1'sb1;
				else
					noise_age <= noise_age + 1'd1;
			end
			else begin
				noise_age <= 0;
				if (clk & ~clk_d)
					lfsr_noise <= {lfsr_noise[21:0], ((reset | test_ctrl) | lfsr_noise[22]) ^ lfsr_noise[17]};
				else if (control[7] & |control[6:4]) begin
					lfsr_noise[20] <= lfsr_noise[20] & wave_out[7];
					lfsr_noise[18] <= lfsr_noise[18] & wave_out[6];
					lfsr_noise[14] <= lfsr_noise[14] & wave_out[5];
					lfsr_noise[11] <= lfsr_noise[11] & wave_out[4];
					lfsr_noise[9] <= lfsr_noise[9] & wave_out[3];
					lfsr_noise[5] <= lfsr_noise[5] & wave_out[2];
					lfsr_noise[2] <= lfsr_noise[2] & wave_out[1];
					lfsr_noise[0] <= lfsr_noise[0] & wave_out[0];
				end
			end
		end
	end
	reg [11:0] norm;
	reg [7:0] comb;
	always @(*) begin
		if (_sv2v_0)
			;
		case (control[7:4])
			4'b0001: norm = {saw_tri[10:0], 1'b0};
			4'b0010: norm = saw_tri;
			4'b0100: norm = {12 {pulse}};
			4'b1000: norm = noise;
			default: norm = 0;
		endcase
		case (control[7:4])
			4'b0011: comb = _st_out;
			4'b0101: comb = p_t_out & {8 {pulse}};
			4'b0110: comb = ps__out & {8 {pulse}};
			4'b0111: comb = pst_out & {8 {pulse}};
			default: comb = 0;
		endcase
	end
	wire [11:0] norm_6581;
	sid_dac #(.BITS(12)) waveform_dac(
		.vin(norm),
		.vout(norm_6581)
	);
	reg [11:0] norm_dac;
	always @(posedge clock) norm_dac <= (mode ? norm : norm_6581);
	wire [7:0] env_6581;
	sid_dac #(.BITS(8)) envelope_dac(
		.vin(envelope),
		.vout(env_6581)
	);
	always @(posedge clock)
		if (ce_1m)
			wave_out <= norm[11:4] | comb;
	function automatic [12:0] sv2v_cast_13;
		input reg [12:0] inp;
		sv2v_cast_13 = inp;
	endfunction
	always @(posedge clock) begin : sv2v_autoblock_3
		reg [23:0] keep_cnt;
		reg signed [8:0] env_dac;
		reg signed [12:0] dac_out;
		if (ce_1m) begin
			if (control[7:4]) begin
				keep_cnt <= (mode ? WF_0_TTL_8580 : WF_0_TTL_6581);
				dac_out <= sv2v_cast_13({1'b0, norm_dac | {comb, 4'b0000}}) - (mode ? WAVEFORM_DC_8580 : WAVEFORM_DC_6581);
			end
			else if (keep_cnt)
				keep_cnt <= keep_cnt - 1'd1;
			else
				dac_out <= 0;
			env_dac <= (mode ? envelope : env_6581);
			dca_out <= (mode ? VOICE_DC_8580 : VOICE_DC_6581) + (dac_out * env_dac);
		end
	end
	initial _sv2v_0 = 0;
endmodule
module sid_top (
	reset,
	clk,
	ce_1m,
	cs,
	we,
	addr,
	data_in,
	data_out,
	fc_offset_l,
	pot_x_l,
	pot_y_l,
	ext_in_l,
	audio_l,
	fc_offset_r,
	pot_x_r,
	pot_y_r,
	ext_in_r,
	audio_r,
	filter_en,
	mode,
	cfg,
	ld_clk,
	ld_addr,
	ld_data,
	ld_wr
);
	parameter MULTI_FILTERS = 1;
	parameter DUAL = 1;
	input reset;
	input clk;
	input ce_1m;
	localparam N = (DUAL ? 2 : 1);
	input [N - 1:0] cs;
	input we;
	input [4:0] addr;
	input [7:0] data_in;
	output wire [7:0] data_out;
	input [12:0] fc_offset_l;
	input [7:0] pot_x_l;
	input [7:0] pot_y_l;
	input [17:0] ext_in_l;
	output wire [17:0] audio_l;
	input [12:0] fc_offset_r;
	input [7:0] pot_x_r;
	input [7:0] pot_y_r;
	input [17:0] ext_in_r;
	output wire [17:0] audio_r;
	input [N - 1:0] filter_en;
	input [N - 1:0] mode;
	input [(N * 2) - 1:0] cfg;
	input ld_clk;
	input [11:0] ld_addr;
	input [15:0] ld_data;
	input ld_wr;
	reg [15:0] Voice_1_Freq [0:N - 1];
	reg [11:0] Voice_1_Pw [0:N - 1];
	reg [7:0] Voice_1_Control [0:N - 1];
	reg [7:0] Voice_1_Att_dec [0:N - 1];
	reg [7:0] Voice_1_Sus_Rel [0:N - 1];
	reg [15:0] Voice_2_Freq [0:N - 1];
	reg [11:0] Voice_2_Pw [0:N - 1];
	reg [7:0] Voice_2_Control [0:N - 1];
	reg [7:0] Voice_2_Att_dec [0:N - 1];
	reg [7:0] Voice_2_Sus_Rel [0:N - 1];
	reg [15:0] Voice_3_Freq [0:N - 1];
	reg [11:0] Voice_3_Pw [0:N - 1];
	reg [7:0] Voice_3_Control [0:N - 1];
	reg [7:0] Voice_3_Att_dec [0:N - 1];
	reg [7:0] Voice_3_Sus_Rel [0:N - 1];
	reg [10:0] Filter_Fc [0:N - 1];
	reg [7:0] Filter_Res_Filt [0:N - 1];
	reg [7:0] Filter_Mode_Vol [0:N - 1];
	wire [7:0] Misc_Osc3 [0:N - 1];
	wire [7:0] Misc_Env3 [0:N - 1];
	wire [21:0] voice_1 [0:N - 1];
	wire [21:0] voice_2 [0:N - 1];
	wire [21:0] voice_3 [0:N - 1];
	wire voice_1_PA_MSB [0:N - 1];
	wire voice_2_PA_MSB [0:N - 1];
	wire voice_3_PA_MSB [0:N - 1];
	reg [7:0] _st_out [0:(N * 3) - 1];
	reg [7:0] p_t_out [0:(N * 3) - 1];
	reg [7:0] ps__out [0:(N * 3) - 1];
	reg [7:0] pst_out [0:(N * 3) - 1];
	wire [11:0] acc_t [0:(N * 3) - 1];
	reg [17:0] audio [0:N - 1];
	reg [7:0] bus_data [0:N - 1];
	reg [12:0] Fc_offset [0:N - 1];
	genvar _gv_i_2;
	generate
		for (_gv_i_2 = 0; _gv_i_2 < N; _gv_i_2 = _gv_i_2 + 1) begin : chip
			localparam i = _gv_i_2;
			sid_voice v1(
				.clock(clk),
				.ce_1m(ce_1m),
				.reset(reset),
				.mode(mode[i]),
				.freq(Voice_1_Freq[i]),
				.pw(Voice_1_Pw[i]),
				.control(Voice_1_Control[i]),
				.att_dec(Voice_1_Att_dec[i]),
				.sus_rel(Voice_1_Sus_Rel[i]),
				.osc_msb_in(voice_3_PA_MSB[i]),
				.osc_msb_out(voice_1_PA_MSB[i]),
				.voice_out(voice_1[i]),
				._st_out(_st_out[(i * 3) + 0]),
				.p_t_out(p_t_out[(i * 3) + 0]),
				.ps__out(ps__out[(i * 3) + 0]),
				.pst_out(pst_out[(i * 3) + 0]),
				.acc_t(acc_t[(i * 3) + 0])
			);
			sid_voice v2(
				.clock(clk),
				.ce_1m(ce_1m),
				.reset(reset),
				.mode(mode[i]),
				.freq(Voice_2_Freq[i]),
				.pw(Voice_2_Pw[i]),
				.control(Voice_2_Control[i]),
				.att_dec(Voice_2_Att_dec[i]),
				.sus_rel(Voice_2_Sus_Rel[i]),
				.osc_msb_in(voice_1_PA_MSB[i]),
				.osc_msb_out(voice_2_PA_MSB[i]),
				.voice_out(voice_2[i]),
				._st_out(_st_out[(i * 3) + 1]),
				.p_t_out(p_t_out[(i * 3) + 1]),
				.ps__out(ps__out[(i * 3) + 1]),
				.pst_out(pst_out[(i * 3) + 1]),
				.acc_t(acc_t[(i * 3) + 1])
			);
			sid_voice v3(
				.clock(clk),
				.ce_1m(ce_1m),
				.reset(reset),
				.mode(mode[i]),
				.freq(Voice_3_Freq[i]),
				.pw(Voice_3_Pw[i]),
				.control(Voice_3_Control[i]),
				.att_dec(Voice_3_Att_dec[i]),
				.sus_rel(Voice_3_Sus_Rel[i]),
				.osc_msb_in(voice_2_PA_MSB[i]),
				.osc_msb_out(voice_3_PA_MSB[i]),
				.voice_out(voice_3[i]),
				.osc_out(Misc_Osc3[i]),
				.env_out(Misc_Env3[i]),
				._st_out(_st_out[(i * 3) + 2]),
				.p_t_out(p_t_out[(i * 3) + 2]),
				.ps__out(ps__out[(i * 3) + 2]),
				.pst_out(pst_out[(i * 3) + 2]),
				.acc_t(acc_t[(i * 3) + 2])
			);
			always @(posedge clk) Fc_offset[i] <= (i ? fc_offset_r : fc_offset_l);
			always @(posedge clk)
				if (reset) begin
					Voice_1_Freq[i] <= 0;
					Voice_1_Pw[i] <= 0;
					Voice_1_Control[i] <= 0;
					Voice_1_Att_dec[i] <= 0;
					Voice_1_Sus_Rel[i] <= 0;
					Voice_2_Freq[i] <= 0;
					Voice_2_Pw[i] <= 0;
					Voice_2_Control[i] <= 0;
					Voice_2_Att_dec[i] <= 0;
					Voice_2_Sus_Rel[i] <= 0;
					Voice_3_Freq[i] <= 0;
					Voice_3_Pw[i] <= 0;
					Voice_3_Control[i] <= 0;
					Voice_3_Att_dec[i] <= 0;
					Voice_3_Sus_Rel[i] <= 0;
					Filter_Fc[i] <= 0;
					Filter_Res_Filt[i] <= 0;
					Filter_Mode_Vol[i] <= 0;
				end
				else if (cs[i]) begin
					if (we) begin
						bus_data[i] <= data_in;
						case (addr)
							5'h00: Voice_1_Freq[i][7:0] <= data_in;
							5'h01: Voice_1_Freq[i][15:8] <= data_in;
							5'h02: Voice_1_Pw[i][7:0] <= data_in;
							5'h03: Voice_1_Pw[i][11:8] <= data_in[3:0];
							5'h04: Voice_1_Control[i] <= data_in;
							5'h05: Voice_1_Att_dec[i] <= data_in;
							5'h06: Voice_1_Sus_Rel[i] <= data_in;
							5'h07: Voice_2_Freq[i][7:0] <= data_in;
							5'h08: Voice_2_Freq[i][15:8] <= data_in;
							5'h09: Voice_2_Pw[i][7:0] <= data_in;
							5'h0a: Voice_2_Pw[i][11:8] <= data_in[3:0];
							5'h0b: Voice_2_Control[i] <= data_in;
							5'h0c: Voice_2_Att_dec[i] <= data_in;
							5'h0d: Voice_2_Sus_Rel[i] <= data_in;
							5'h0e: Voice_3_Freq[i][7:0] <= data_in;
							5'h0f: Voice_3_Freq[i][15:8] <= data_in;
							5'h10: Voice_3_Pw[i][7:0] <= data_in;
							5'h11: Voice_3_Pw[i][11:8] <= data_in[3:0];
							5'h12: Voice_3_Control[i] <= data_in;
							5'h13: Voice_3_Att_dec[i] <= data_in;
							5'h14: Voice_3_Sus_Rel[i] <= data_in;
							5'h15: Filter_Fc[i][2:0] <= data_in[2:0];
							5'h16: Filter_Fc[i][10:3] <= data_in;
							5'h17: Filter_Res_Filt[i] <= data_in;
							5'h18: Filter_Mode_Vol[i] <= data_in;
						endcase
					end
					else
						case (addr)
							5'h19: bus_data[i] = (i ? pot_x_r : pot_x_l);
							5'h1a: bus_data[i] = (i ? pot_y_r : pot_y_l);
							5'h1b: bus_data[i] = Misc_Osc3[i];
							5'h1c: bus_data[i] = Misc_Env3[i];
						endcase
				end
		end
	endgenerate
	wire [15:0] F0;
	reg [3:0] state;
	wire n = DUAL && state[3];
	wire [7:0] f__st_out;
	reg [11:0] f_acc_t;
	wire [7:0] f_p_t_out;
	wire [7:0] f_ps__out;
	wire [7:0] f_pst_out;
	sid_tables #(MULTI_FILTERS) sid_tables(
		.clock(clk),
		.mode(mode[n]),
		.acc_t(f_acc_t),
		._st_out(f__st_out),
		.p_t_out(f_p_t_out),
		.ps__out(f_ps__out),
		.pst_out(f_pst_out),
		.cfg(cfg[n * 2+:2]),
		.Fc(Filter_Fc[n]),
		.Fc_offset(Fc_offset[n]),
		.F0(F0),
		.ld_clk(ld_clk),
		.ld_addr(ld_addr),
		.ld_data(ld_data),
		.ld_wr(ld_wr)
	);
	always @(posedge clk) begin : sv2v_autoblock_1
		reg [2:0] v;
		if (~&state)
			state <= state + 1'd1;
		if (ce_1m)
			state <= 0;
		case (state)
			1, 3, 5, 7, 9, 11: begin
				f_acc_t <= acc_t[state[3:1]];
				v <= state[3:1];
			end
		endcase
		case (state)
			3, 5, 7: begin
				_st_out[v] <= f__st_out;
				p_t_out[v] <= f_p_t_out;
				ps__out[v] <= f_ps__out;
				pst_out[v] <= f_pst_out;
			end
			9, 11, 13:
				if (DUAL) begin
					_st_out[v] <= f__st_out;
					p_t_out[v] <= f_p_t_out;
					ps__out[v] <= f_ps__out;
					pst_out[v] <= f_pst_out;
				end
		endcase
	end
	wire [17:0] faudio;
	function automatic signed [21:0] sv2v_cast_22_signed;
		input reg signed [21:0] inp;
		sv2v_cast_22_signed = inp;
	endfunction
	sid_filter sid_filter(
		.clk(clk),
		.state(state[2:0]),
		.mode(mode[n]),
		.F0(F0),
		.Res_Filt(Filter_Res_Filt[n]),
		.Mode_Vol(Filter_Mode_Vol[n]),
		.voice1(voice_1[n]),
		.voice2(voice_2[n]),
		.voice3(voice_3[n]),
		.ext_in(sv2v_cast_22_signed($signed({(n ? ext_in_r : ext_in_l), 3'b000}))),
		.audio(faudio)
	);
	always @(posedge clk) begin : sv2v_autoblock_2
		reg [17:0] audio0;
		if (state == 8)
			audio0 <= faudio;
		if (state == 15) begin
			audio[n] <= faudio;
			audio[0] <= audio0;
		end
	end
	assign data_out = (cs[0] ? bus_data[0] : bus_data[N - 1]);
	assign audio_l = audio[0];
	assign audio_r = audio[N - 1];
endmodule
// sid_tables_8580.v: as tabelas do sid_tables.sv (C64_MiSTer, GPL) so' para o 8580, em Verilog-2001
// simples (case -> logica, sem BSRAM; a BSRAM do Timmy esta' cheia). Filtro do 8580: F0 = Fc*5 (sem tabela).
module sid_tables (
  input clock, input mode,
  input [11:0] acc_t,
  output reg [7:0] _st_out, output reg [7:0] p_t_out, output reg [7:0] ps__out, output reg [7:0] pst_out,
  input [1:0] cfg, input [10:0] Fc, input [12:0] Fc_offset, output [15:0] F0,
  input ld_clk, input [11:0] ld_addr, input [15:0] ld_data, input ld_wr);
parameter MULTI_FILTERS = 0;
function [7:0] t_pt;
  input [10:0] x;
  case (x)
    11'd255: t_pt = 8'h07;
    11'd507: t_pt = 8'h1c;
    11'd509: t_pt = 8'h3c;
    11'd510: t_pt = 8'h3f;
    11'd511: t_pt = 8'h3f;
    11'd765: t_pt = 8'h0c;
    11'd766: t_pt = 8'h5e;
    11'd767: t_pt = 8'h5f;
    11'd887: t_pt = 8'h40;
    11'd891: t_pt = 8'h40;
    11'd892: t_pt = 8'h40;
    11'd893: t_pt = 8'h60;
    11'd894: t_pt = 8'h60;
    11'd895: t_pt = 8'h6f;
    11'd927: t_pt = 8'h40;
    11'd942: t_pt = 8'h40;
    11'd943: t_pt = 8'h40;
    11'd947: t_pt = 8'h40;
    11'd948: t_pt = 8'h40;
    11'd949: t_pt = 8'h40;
    11'd950: t_pt = 8'h40;
    11'd951: t_pt = 8'h60;
    11'd952: t_pt = 8'h40;
    11'd953: t_pt = 8'h40;
    11'd954: t_pt = 8'h60;
    11'd955: t_pt = 8'h60;
    11'd956: t_pt = 8'h60;
    11'd957: t_pt = 8'h60;
    11'd958: t_pt = 8'h70;
    11'd959: t_pt = 8'h77;
    11'd965: t_pt = 8'h40;
    11'd966: t_pt = 8'h40;
    11'd967: t_pt = 8'h40;
    11'd968: t_pt = 8'h40;
    11'd969: t_pt = 8'h40;
    11'd970: t_pt = 8'h40;
    11'd971: t_pt = 8'h40;
    11'd972: t_pt = 8'h40;
    11'd973: t_pt = 8'h60;
    11'd974: t_pt = 8'h60;
    11'd975: t_pt = 8'h60;
    11'd976: t_pt = 8'h40;
    11'd977: t_pt = 8'h40;
    11'd978: t_pt = 8'h40;
    11'd979: t_pt = 8'h60;
    11'd980: t_pt = 8'h60;
    11'd981: t_pt = 8'h60;
    11'd982: t_pt = 8'h60;
    11'd983: t_pt = 8'h70;
    11'd984: t_pt = 8'h60;
    11'd985: t_pt = 8'h60;
    11'd986: t_pt = 8'h60;
    11'd987: t_pt = 8'h70;
    11'd988: t_pt = 8'h70;
    11'd989: t_pt = 8'h70;
    11'd990: t_pt = 8'h78;
    11'd991: t_pt = 8'h7b;
    11'd992: t_pt = 8'h60;
    11'd993: t_pt = 8'h60;
    11'd994: t_pt = 8'h60;
    11'd995: t_pt = 8'h70;
    11'd996: t_pt = 8'h60;
    11'd997: t_pt = 8'h70;
    11'd998: t_pt = 8'h70;
    11'd999: t_pt = 8'h70;
    11'd1000: t_pt = 8'h70;
    11'd1001: t_pt = 8'h70;
    11'd1002: t_pt = 8'h70;
    11'd1003: t_pt = 8'h78;
    11'd1004: t_pt = 8'h78;
    11'd1005: t_pt = 8'h78;
    11'd1006: t_pt = 8'h78;
    11'd1007: t_pt = 8'h7c;
    11'd1008: t_pt = 8'h78;
    11'd1009: t_pt = 8'h78;
    11'd1010: t_pt = 8'h78;
    11'd1011: t_pt = 8'h7c;
    11'd1012: t_pt = 8'h78;
    11'd1013: t_pt = 8'h7c;
    11'd1014: t_pt = 8'h7c;
    11'd1015: t_pt = 8'h7e;
    11'd1016: t_pt = 8'h7c;
    11'd1017: t_pt = 8'h7e;
    11'd1018: t_pt = 8'h7e;
    11'd1019: t_pt = 8'h7f;
    11'd1020: t_pt = 8'h7f;
    11'd1021: t_pt = 8'h7f;
    11'd1022: t_pt = 8'h7f;
    11'd1023: t_pt = 8'h7f;
    11'd1151: t_pt = 8'h80;
    11'd1213: t_pt = 8'h80;
    11'd1214: t_pt = 8'h80;
    11'd1215: t_pt = 8'h80;
    11'd1231: t_pt = 8'h80;
    11'd1239: t_pt = 8'h80;
    11'd1242: t_pt = 8'h80;
    11'd1243: t_pt = 8'h80;
    11'd1244: t_pt = 8'h80;
    11'd1245: t_pt = 8'h80;
    11'd1246: t_pt = 8'h80;
    11'd1247: t_pt = 8'h80;
    11'd1251: t_pt = 8'h80;
    11'd1252: t_pt = 8'h80;
    11'd1253: t_pt = 8'h80;
    11'd1254: t_pt = 8'h80;
    11'd1255: t_pt = 8'h80;
    11'd1256: t_pt = 8'h80;
    11'd1257: t_pt = 8'h80;
    11'd1258: t_pt = 8'h80;
    11'd1259: t_pt = 8'h80;
    11'd1260: t_pt = 8'h80;
    11'd1261: t_pt = 8'h80;
    11'd1262: t_pt = 8'h80;
    11'd1263: t_pt = 8'h80;
    11'd1264: t_pt = 8'h80;
    11'd1265: t_pt = 8'h80;
    11'd1266: t_pt = 8'h80;
    11'd1267: t_pt = 8'h80;
    11'd1268: t_pt = 8'h80;
    11'd1269: t_pt = 8'h80;
    11'd1270: t_pt = 8'h80;
    11'd1271: t_pt = 8'h80;
    11'd1272: t_pt = 8'h80;
    11'd1273: t_pt = 8'h80;
    11'd1274: t_pt = 8'h80;
    11'd1275: t_pt = 8'h80;
    11'd1276: t_pt = 8'h80;
    11'd1277: t_pt = 8'h80;
    11'd1278: t_pt = 8'h8e;
    11'd1279: t_pt = 8'h9f;
    11'd1311: t_pt = 8'h80;
    11'd1323: t_pt = 8'h80;
    11'd1325: t_pt = 8'h80;
    11'd1326: t_pt = 8'h80;
    11'd1327: t_pt = 8'h80;
    11'd1330: t_pt = 8'h80;
    11'd1331: t_pt = 8'h80;
    11'd1332: t_pt = 8'h80;
    11'd1333: t_pt = 8'h80;
    11'd1334: t_pt = 8'h80;
    11'd1335: t_pt = 8'h80;
    11'd1336: t_pt = 8'h80;
    11'd1337: t_pt = 8'h80;
    11'd1338: t_pt = 8'h80;
    11'd1339: t_pt = 8'h80;
    11'd1340: t_pt = 8'h80;
    11'd1341: t_pt = 8'h80;
    11'd1342: t_pt = 8'h80;
    11'd1343: t_pt = 8'h80;
    11'd1347: t_pt = 8'h80;
    11'd1349: t_pt = 8'h80;
    11'd1350: t_pt = 8'h80;
    11'd1351: t_pt = 8'h80;
    11'd1352: t_pt = 8'h80;
    11'd1353: t_pt = 8'h80;
    11'd1354: t_pt = 8'h80;
    11'd1355: t_pt = 8'h80;
    11'd1356: t_pt = 8'h80;
    11'd1357: t_pt = 8'h80;
    11'd1358: t_pt = 8'h80;
    11'd1359: t_pt = 8'h80;
    11'd1360: t_pt = 8'h80;
    11'd1361: t_pt = 8'h80;
    11'd1362: t_pt = 8'h80;
    11'd1363: t_pt = 8'h80;
    11'd1364: t_pt = 8'h80;
    11'd1365: t_pt = 8'h80;
    11'd1366: t_pt = 8'h80;
    11'd1367: t_pt = 8'h80;
    11'd1368: t_pt = 8'h80;
    11'd1369: t_pt = 8'h80;
    11'd1370: t_pt = 8'h80;
    11'd1371: t_pt = 8'h80;
    11'd1372: t_pt = 8'h80;
    11'd1373: t_pt = 8'h80;
    11'd1374: t_pt = 8'h80;
    11'd1375: t_pt = 8'h80;
    11'd1376: t_pt = 8'h80;
    11'd1377: t_pt = 8'h80;
    11'd1378: t_pt = 8'h80;
    11'd1379: t_pt = 8'h80;
    11'd1380: t_pt = 8'h80;
    11'd1381: t_pt = 8'h80;
    11'd1382: t_pt = 8'h80;
    11'd1383: t_pt = 8'h80;
    11'd1384: t_pt = 8'h80;
    11'd1385: t_pt = 8'h80;
    11'd1386: t_pt = 8'h80;
    11'd1387: t_pt = 8'h80;
    11'd1388: t_pt = 8'h80;
    11'd1389: t_pt = 8'h80;
    11'd1390: t_pt = 8'h80;
    11'd1391: t_pt = 8'h80;
    11'd1392: t_pt = 8'h80;
    11'd1393: t_pt = 8'h80;
    11'd1394: t_pt = 8'h80;
    11'd1395: t_pt = 8'h80;
    11'd1396: t_pt = 8'h80;
    11'd1397: t_pt = 8'h80;
    11'd1398: t_pt = 8'h80;
    11'd1399: t_pt = 8'h80;
    11'd1400: t_pt = 8'h80;
    11'd1401: t_pt = 8'h80;
    11'd1402: t_pt = 8'h80;
    11'd1403: t_pt = 8'h80;
    11'd1404: t_pt = 8'h80;
    11'd1405: t_pt = 8'h80;
    11'd1406: t_pt = 8'h80;
    11'd1407: t_pt = 8'haf;
    11'd1408: t_pt = 8'h80;
    11'd1409: t_pt = 8'h80;
    11'd1410: t_pt = 8'h80;
    11'd1411: t_pt = 8'h80;
    11'd1412: t_pt = 8'h80;
    11'd1413: t_pt = 8'h80;
    11'd1414: t_pt = 8'h80;
    11'd1415: t_pt = 8'h80;
    11'd1416: t_pt = 8'h80;
    11'd1417: t_pt = 8'h80;
    11'd1418: t_pt = 8'h80;
    11'd1419: t_pt = 8'h80;
    11'd1420: t_pt = 8'h80;
    11'd1421: t_pt = 8'h80;
    11'd1422: t_pt = 8'h80;
    11'd1423: t_pt = 8'h80;
    11'd1424: t_pt = 8'h80;
    11'd1425: t_pt = 8'h80;
    11'd1426: t_pt = 8'h80;
    11'd1427: t_pt = 8'h80;
    11'd1428: t_pt = 8'h80;
    11'd1429: t_pt = 8'h80;
    11'd1430: t_pt = 8'h80;
    11'd1431: t_pt = 8'h80;
    11'd1432: t_pt = 8'h80;
    11'd1433: t_pt = 8'h80;
    11'd1434: t_pt = 8'h80;
    11'd1435: t_pt = 8'h80;
    11'd1436: t_pt = 8'h80;
    11'd1437: t_pt = 8'h80;
    11'd1438: t_pt = 8'h80;
    11'd1439: t_pt = 8'h80;
    11'd1440: t_pt = 8'h80;
    11'd1441: t_pt = 8'h80;
    11'd1442: t_pt = 8'h80;
    11'd1443: t_pt = 8'h80;
    11'd1444: t_pt = 8'h80;
    11'd1445: t_pt = 8'h80;
    11'd1446: t_pt = 8'h80;
    11'd1447: t_pt = 8'h80;
    11'd1448: t_pt = 8'h80;
    11'd1449: t_pt = 8'h80;
    11'd1450: t_pt = 8'h80;
    11'd1451: t_pt = 8'h80;
    11'd1452: t_pt = 8'h80;
    11'd1453: t_pt = 8'h80;
    11'd1454: t_pt = 8'h80;
    11'd1455: t_pt = 8'h80;
    11'd1456: t_pt = 8'h80;
    11'd1457: t_pt = 8'h80;
    11'd1458: t_pt = 8'h80;
    11'd1459: t_pt = 8'h80;
    11'd1460: t_pt = 8'h80;
    11'd1461: t_pt = 8'h80;
    11'd1462: t_pt = 8'h80;
    11'd1463: t_pt = 8'h80;
    11'd1464: t_pt = 8'h80;
    11'd1465: t_pt = 8'h80;
    11'd1466: t_pt = 8'h80;
    11'd1467: t_pt = 8'ha0;
    11'd1468: t_pt = 8'ha0;
    11'd1469: t_pt = 8'ha0;
    11'd1470: t_pt = 8'ha0;
    11'd1471: t_pt = 8'hb7;
    11'd1472: t_pt = 8'h80;
    11'd1473: t_pt = 8'h80;
    11'd1474: t_pt = 8'h80;
    11'd1475: t_pt = 8'h80;
    11'd1476: t_pt = 8'h80;
    11'd1477: t_pt = 8'h80;
    11'd1478: t_pt = 8'h80;
    11'd1479: t_pt = 8'h80;
    11'd1480: t_pt = 8'h80;
    11'd1481: t_pt = 8'h80;
    11'd1482: t_pt = 8'h80;
    11'd1483: t_pt = 8'h80;
    11'd1484: t_pt = 8'h80;
    11'd1485: t_pt = 8'h80;
    11'd1486: t_pt = 8'h80;
    11'd1487: t_pt = 8'ha0;
    11'd1488: t_pt = 8'h80;
    11'd1489: t_pt = 8'h80;
    11'd1490: t_pt = 8'h80;
    11'd1491: t_pt = 8'h80;
    11'd1492: t_pt = 8'h80;
    11'd1493: t_pt = 8'h80;
    11'd1494: t_pt = 8'ha0;
    11'd1495: t_pt = 8'ha0;
    11'd1496: t_pt = 8'ha0;
    11'd1497: t_pt = 8'ha0;
    11'd1498: t_pt = 8'ha0;
    11'd1499: t_pt = 8'hb0;
    11'd1500: t_pt = 8'ha0;
    11'd1501: t_pt = 8'hb0;
    11'd1502: t_pt = 8'hb0;
    11'd1503: t_pt = 8'hbb;
    11'd1504: t_pt = 8'ha0;
    11'd1505: t_pt = 8'ha0;
    11'd1506: t_pt = 8'ha0;
    11'd1507: t_pt = 8'ha0;
    11'd1508: t_pt = 8'ha0;
    11'd1509: t_pt = 8'ha0;
    11'd1510: t_pt = 8'hb0;
    11'd1511: t_pt = 8'hb0;
    11'd1512: t_pt = 8'ha0;
    11'd1513: t_pt = 8'hb0;
    11'd1514: t_pt = 8'hb0;
    11'd1515: t_pt = 8'hb8;
    11'd1516: t_pt = 8'hb0;
    11'd1517: t_pt = 8'hb8;
    11'd1518: t_pt = 8'hb8;
    11'd1519: t_pt = 8'hbc;
    11'd1520: t_pt = 8'hb0;
    11'd1521: t_pt = 8'hb8;
    11'd1522: t_pt = 8'hb8;
    11'd1523: t_pt = 8'hb8;
    11'd1524: t_pt = 8'hb8;
    11'd1525: t_pt = 8'hbc;
    11'd1526: t_pt = 8'hbc;
    11'd1527: t_pt = 8'hbe;
    11'd1528: t_pt = 8'hbc;
    11'd1529: t_pt = 8'hbc;
    11'd1530: t_pt = 8'hbe;
    11'd1531: t_pt = 8'hbf;
    11'd1532: t_pt = 8'hbe;
    11'd1533: t_pt = 8'hbf;
    11'd1534: t_pt = 8'hbf;
    11'd1535: t_pt = 8'hbf;
    11'd1536: t_pt = 8'h80;
    11'd1537: t_pt = 8'h80;
    11'd1538: t_pt = 8'h80;
    11'd1539: t_pt = 8'h80;
    11'd1540: t_pt = 8'h80;
    11'd1541: t_pt = 8'h80;
    11'd1542: t_pt = 8'h80;
    11'd1543: t_pt = 8'h80;
    11'd1544: t_pt = 8'h80;
    11'd1545: t_pt = 8'h80;
    11'd1546: t_pt = 8'h80;
    11'd1547: t_pt = 8'h80;
    11'd1548: t_pt = 8'h80;
    11'd1549: t_pt = 8'h80;
    11'd1550: t_pt = 8'h80;
    11'd1551: t_pt = 8'h80;
    11'd1552: t_pt = 8'h80;
    11'd1553: t_pt = 8'h80;
    11'd1554: t_pt = 8'h80;
    11'd1555: t_pt = 8'h80;
    11'd1556: t_pt = 8'h80;
    11'd1557: t_pt = 8'h80;
    11'd1558: t_pt = 8'h80;
    11'd1559: t_pt = 8'h80;
    11'd1560: t_pt = 8'h80;
    11'd1561: t_pt = 8'h80;
    11'd1562: t_pt = 8'h80;
    11'd1563: t_pt = 8'h80;
    11'd1564: t_pt = 8'h80;
    11'd1565: t_pt = 8'h80;
    11'd1566: t_pt = 8'h80;
    11'd1567: t_pt = 8'h80;
    11'd1568: t_pt = 8'h80;
    11'd1569: t_pt = 8'h80;
    11'd1570: t_pt = 8'h80;
    11'd1571: t_pt = 8'h80;
    11'd1572: t_pt = 8'h80;
    11'd1573: t_pt = 8'h80;
    11'd1574: t_pt = 8'h80;
    11'd1575: t_pt = 8'h80;
    11'd1576: t_pt = 8'h80;
    11'd1577: t_pt = 8'h80;
    11'd1578: t_pt = 8'h80;
    11'd1579: t_pt = 8'h80;
    11'd1580: t_pt = 8'h80;
    11'd1581: t_pt = 8'h80;
    11'd1582: t_pt = 8'h80;
    11'd1583: t_pt = 8'h80;
    11'd1584: t_pt = 8'h80;
    11'd1585: t_pt = 8'h80;
    11'd1586: t_pt = 8'h80;
    11'd1587: t_pt = 8'h80;
    11'd1588: t_pt = 8'h80;
    11'd1589: t_pt = 8'h80;
    11'd1590: t_pt = 8'h80;
    11'd1591: t_pt = 8'h80;
    11'd1592: t_pt = 8'h80;
    11'd1593: t_pt = 8'h80;
    11'd1594: t_pt = 8'h80;
    11'd1595: t_pt = 8'h80;
    11'd1596: t_pt = 8'h80;
    11'd1597: t_pt = 8'h80;
    11'd1598: t_pt = 8'hc0;
    11'd1599: t_pt = 8'hc0;
    11'd1600: t_pt = 8'h80;
    11'd1601: t_pt = 8'h80;
    11'd1602: t_pt = 8'h80;
    11'd1603: t_pt = 8'h80;
    11'd1604: t_pt = 8'h80;
    11'd1605: t_pt = 8'h80;
    11'd1606: t_pt = 8'h80;
    11'd1607: t_pt = 8'h80;
    11'd1608: t_pt = 8'h80;
    11'd1609: t_pt = 8'h80;
    11'd1610: t_pt = 8'h80;
    11'd1611: t_pt = 8'h80;
    11'd1612: t_pt = 8'h80;
    11'd1613: t_pt = 8'h80;
    11'd1614: t_pt = 8'h80;
    11'd1615: t_pt = 8'h80;
    11'd1616: t_pt = 8'h80;
    11'd1617: t_pt = 8'h80;
    11'd1618: t_pt = 8'h80;
    11'd1619: t_pt = 8'h80;
    11'd1620: t_pt = 8'h80;
    11'd1621: t_pt = 8'h80;
    11'd1622: t_pt = 8'h80;
    11'd1623: t_pt = 8'hc0;
    11'd1624: t_pt = 8'h80;
    11'd1625: t_pt = 8'h80;
    11'd1626: t_pt = 8'hc0;
    11'd1627: t_pt = 8'hc0;
    11'd1628: t_pt = 8'hc0;
    11'd1629: t_pt = 8'hc0;
    11'd1630: t_pt = 8'hc0;
    11'd1631: t_pt = 8'hc0;
    11'd1632: t_pt = 8'h80;
    11'd1633: t_pt = 8'h80;
    11'd1634: t_pt = 8'h80;
    11'd1635: t_pt = 8'hc0;
    11'd1636: t_pt = 8'h80;
    11'd1637: t_pt = 8'hc0;
    11'd1638: t_pt = 8'hc0;
    11'd1639: t_pt = 8'hc0;
    11'd1640: t_pt = 8'hc0;
    11'd1641: t_pt = 8'hc0;
    11'd1642: t_pt = 8'hc0;
    11'd1643: t_pt = 8'hc0;
    11'd1644: t_pt = 8'hc0;
    11'd1645: t_pt = 8'hc0;
    11'd1646: t_pt = 8'hc0;
    11'd1647: t_pt = 8'hc0;
    11'd1648: t_pt = 8'hc0;
    11'd1649: t_pt = 8'hc0;
    11'd1650: t_pt = 8'hc0;
    11'd1651: t_pt = 8'hc0;
    11'd1652: t_pt = 8'hc0;
    11'd1653: t_pt = 8'hc0;
    11'd1654: t_pt = 8'hc0;
    11'd1655: t_pt = 8'hc0;
    11'd1656: t_pt = 8'hc0;
    11'd1657: t_pt = 8'hc0;
    11'd1658: t_pt = 8'hc0;
    11'd1659: t_pt = 8'hc0;
    11'd1660: t_pt = 8'hc0;
    11'd1661: t_pt = 8'hc0;
    11'd1662: t_pt = 8'hc0;
    11'd1663: t_pt = 8'hcf;
    11'd1664: t_pt = 8'h80;
    11'd1665: t_pt = 8'h80;
    11'd1666: t_pt = 8'h80;
    11'd1667: t_pt = 8'h80;
    11'd1668: t_pt = 8'h80;
    11'd1669: t_pt = 8'h80;
    11'd1670: t_pt = 8'hc0;
    11'd1671: t_pt = 8'hc0;
    11'd1672: t_pt = 8'hc0;
    11'd1673: t_pt = 8'h80;
    11'd1674: t_pt = 8'hc0;
    11'd1675: t_pt = 8'hc0;
    11'd1676: t_pt = 8'hc0;
    11'd1677: t_pt = 8'hc0;
    11'd1678: t_pt = 8'hc0;
    11'd1679: t_pt = 8'hc0;
    11'd1680: t_pt = 8'hc0;
    11'd1681: t_pt = 8'hc0;
    11'd1682: t_pt = 8'hc0;
    11'd1683: t_pt = 8'hc0;
    11'd1684: t_pt = 8'hc0;
    11'd1685: t_pt = 8'hc0;
    11'd1686: t_pt = 8'hc0;
    11'd1687: t_pt = 8'hc0;
    11'd1688: t_pt = 8'hc0;
    11'd1689: t_pt = 8'hc0;
    11'd1690: t_pt = 8'hc0;
    11'd1691: t_pt = 8'hc0;
    11'd1692: t_pt = 8'hc0;
    11'd1693: t_pt = 8'hc0;
    11'd1694: t_pt = 8'hc0;
    11'd1695: t_pt = 8'hc0;
    11'd1696: t_pt = 8'hc0;
    11'd1697: t_pt = 8'hc0;
    11'd1698: t_pt = 8'hc0;
    11'd1699: t_pt = 8'hc0;
    11'd1700: t_pt = 8'hc0;
    11'd1701: t_pt = 8'hc0;
    11'd1702: t_pt = 8'hc0;
    11'd1703: t_pt = 8'hc0;
    11'd1704: t_pt = 8'hc0;
    11'd1705: t_pt = 8'hc0;
    11'd1706: t_pt = 8'hc0;
    11'd1707: t_pt = 8'hc0;
    11'd1708: t_pt = 8'hc0;
    11'd1709: t_pt = 8'hc0;
    11'd1710: t_pt = 8'hc0;
    11'd1711: t_pt = 8'hc0;
    11'd1712: t_pt = 8'hc0;
    11'd1713: t_pt = 8'hc0;
    11'd1714: t_pt = 8'hc0;
    11'd1715: t_pt = 8'hc0;
    11'd1716: t_pt = 8'hc0;
    11'd1717: t_pt = 8'hc0;
    11'd1718: t_pt = 8'hc0;
    11'd1719: t_pt = 8'hc0;
    11'd1720: t_pt = 8'hc0;
    11'd1721: t_pt = 8'hc0;
    11'd1722: t_pt = 8'hc0;
    11'd1723: t_pt = 8'hc0;
    11'd1724: t_pt = 8'hc0;
    11'd1725: t_pt = 8'hc0;
    11'd1726: t_pt = 8'hc0;
    11'd1727: t_pt = 8'hd7;
    11'd1728: t_pt = 8'hc0;
    11'd1729: t_pt = 8'hc0;
    11'd1730: t_pt = 8'hc0;
    11'd1731: t_pt = 8'hc0;
    11'd1732: t_pt = 8'hc0;
    11'd1733: t_pt = 8'hc0;
    11'd1734: t_pt = 8'hc0;
    11'd1735: t_pt = 8'hc0;
    11'd1736: t_pt = 8'hc0;
    11'd1737: t_pt = 8'hc0;
    11'd1738: t_pt = 8'hc0;
    11'd1739: t_pt = 8'hc0;
    11'd1740: t_pt = 8'hc0;
    11'd1741: t_pt = 8'hc0;
    11'd1742: t_pt = 8'hc0;
    11'd1743: t_pt = 8'hc0;
    11'd1744: t_pt = 8'hc0;
    11'd1745: t_pt = 8'hc0;
    11'd1746: t_pt = 8'hc0;
    11'd1747: t_pt = 8'hc0;
    11'd1748: t_pt = 8'hc0;
    11'd1749: t_pt = 8'hc0;
    11'd1750: t_pt = 8'hc0;
    11'd1751: t_pt = 8'hc0;
    11'd1752: t_pt = 8'hc0;
    11'd1753: t_pt = 8'hc0;
    11'd1754: t_pt = 8'hc0;
    11'd1755: t_pt = 8'hc0;
    11'd1756: t_pt = 8'hc0;
    11'd1757: t_pt = 8'hd0;
    11'd1758: t_pt = 8'hd0;
    11'd1759: t_pt = 8'hd9;
    11'd1760: t_pt = 8'hc0;
    11'd1761: t_pt = 8'hc0;
    11'd1762: t_pt = 8'hc0;
    11'd1763: t_pt = 8'hc0;
    11'd1764: t_pt = 8'hc0;
    11'd1765: t_pt = 8'hc0;
    11'd1766: t_pt = 8'hc0;
    11'd1767: t_pt = 8'hd0;
    11'd1768: t_pt = 8'hc0;
    11'd1769: t_pt = 8'hd0;
    11'd1770: t_pt = 8'hd0;
    11'd1771: t_pt = 8'hd0;
    11'd1772: t_pt = 8'hd0;
    11'd1773: t_pt = 8'hd8;
    11'd1774: t_pt = 8'hd8;
    11'd1775: t_pt = 8'hdc;
    11'd1776: t_pt = 8'hd0;
    11'd1777: t_pt = 8'hd0;
    11'd1778: t_pt = 8'hd8;
    11'd1779: t_pt = 8'hd8;
    11'd1780: t_pt = 8'hd8;
    11'd1781: t_pt = 8'hdc;
    11'd1782: t_pt = 8'hdc;
    11'd1783: t_pt = 8'hde;
    11'd1784: t_pt = 8'hdc;
    11'd1785: t_pt = 8'hdc;
    11'd1786: t_pt = 8'hde;
    11'd1787: t_pt = 8'hdf;
    11'd1788: t_pt = 8'hde;
    11'd1789: t_pt = 8'hdf;
    11'd1790: t_pt = 8'hdf;
    11'd1791: t_pt = 8'hdf;
    11'd1792: t_pt = 8'hc0;
    11'd1793: t_pt = 8'hc0;
    11'd1794: t_pt = 8'hc0;
    11'd1795: t_pt = 8'hc0;
    11'd1796: t_pt = 8'hc0;
    11'd1797: t_pt = 8'hc0;
    11'd1798: t_pt = 8'hc0;
    11'd1799: t_pt = 8'hc0;
    11'd1800: t_pt = 8'hc0;
    11'd1801: t_pt = 8'hc0;
    11'd1802: t_pt = 8'hc0;
    11'd1803: t_pt = 8'hc0;
    11'd1804: t_pt = 8'hc0;
    11'd1805: t_pt = 8'hc0;
    11'd1806: t_pt = 8'hc0;
    11'd1807: t_pt = 8'hc0;
    11'd1808: t_pt = 8'hc0;
    11'd1809: t_pt = 8'hc0;
    11'd1810: t_pt = 8'hc0;
    11'd1811: t_pt = 8'hc0;
    11'd1812: t_pt = 8'hc0;
    11'd1813: t_pt = 8'hc0;
    11'd1814: t_pt = 8'hc0;
    11'd1815: t_pt = 8'hc0;
    11'd1816: t_pt = 8'hc0;
    11'd1817: t_pt = 8'hc0;
    11'd1818: t_pt = 8'hc0;
    11'd1819: t_pt = 8'he0;
    11'd1820: t_pt = 8'hc0;
    11'd1821: t_pt = 8'he0;
    11'd1822: t_pt = 8'he0;
    11'd1823: t_pt = 8'he0;
    11'd1824: t_pt = 8'hc0;
    11'd1825: t_pt = 8'hc0;
    11'd1826: t_pt = 8'hc0;
    11'd1827: t_pt = 8'hc0;
    11'd1828: t_pt = 8'hc0;
    11'd1829: t_pt = 8'hc0;
    11'd1830: t_pt = 8'hc0;
    11'd1831: t_pt = 8'he0;
    11'd1832: t_pt = 8'hc0;
    11'd1833: t_pt = 8'hc0;
    11'd1834: t_pt = 8'he0;
    11'd1835: t_pt = 8'he0;
    11'd1836: t_pt = 8'he0;
    11'd1837: t_pt = 8'he0;
    11'd1838: t_pt = 8'he0;
    11'd1839: t_pt = 8'he0;
    11'd1840: t_pt = 8'he0;
    11'd1841: t_pt = 8'he0;
    11'd1842: t_pt = 8'he0;
    11'd1843: t_pt = 8'he0;
    11'd1844: t_pt = 8'he0;
    11'd1845: t_pt = 8'he0;
    11'd1846: t_pt = 8'he0;
    11'd1847: t_pt = 8'he0;
    11'd1848: t_pt = 8'he0;
    11'd1849: t_pt = 8'he0;
    11'd1850: t_pt = 8'he0;
    11'd1851: t_pt = 8'he0;
    11'd1852: t_pt = 8'he0;
    11'd1853: t_pt = 8'he0;
    11'd1854: t_pt = 8'he0;
    11'd1855: t_pt = 8'he7;
    11'd1856: t_pt = 8'he0;
    11'd1857: t_pt = 8'he0;
    11'd1858: t_pt = 8'he0;
    11'd1859: t_pt = 8'he0;
    11'd1860: t_pt = 8'he0;
    11'd1861: t_pt = 8'he0;
    11'd1862: t_pt = 8'he0;
    11'd1863: t_pt = 8'he0;
    11'd1864: t_pt = 8'he0;
    11'd1865: t_pt = 8'he0;
    11'd1866: t_pt = 8'he0;
    11'd1867: t_pt = 8'he0;
    11'd1868: t_pt = 8'he0;
    11'd1869: t_pt = 8'he0;
    11'd1870: t_pt = 8'he0;
    11'd1871: t_pt = 8'he0;
    11'd1872: t_pt = 8'he0;
    11'd1873: t_pt = 8'he0;
    11'd1874: t_pt = 8'he0;
    11'd1875: t_pt = 8'he0;
    11'd1876: t_pt = 8'he0;
    11'd1877: t_pt = 8'he0;
    11'd1878: t_pt = 8'he0;
    11'd1879: t_pt = 8'he0;
    11'd1880: t_pt = 8'he0;
    11'd1881: t_pt = 8'he0;
    11'd1882: t_pt = 8'he0;
    11'd1883: t_pt = 8'he0;
    11'd1884: t_pt = 8'he0;
    11'd1885: t_pt = 8'he0;
    11'd1886: t_pt = 8'he0;
    11'd1887: t_pt = 8'he8;
    11'd1888: t_pt = 8'he0;
    11'd1889: t_pt = 8'he0;
    11'd1890: t_pt = 8'he0;
    11'd1891: t_pt = 8'he0;
    11'd1892: t_pt = 8'he0;
    11'd1893: t_pt = 8'he0;
    11'd1894: t_pt = 8'he0;
    11'd1895: t_pt = 8'he0;
    11'd1896: t_pt = 8'he0;
    11'd1897: t_pt = 8'he0;
    11'd1898: t_pt = 8'he0;
    11'd1899: t_pt = 8'he0;
    11'd1900: t_pt = 8'he0;
    11'd1901: t_pt = 8'he0;
    11'd1902: t_pt = 8'he8;
    11'd1903: t_pt = 8'hec;
    11'd1904: t_pt = 8'he0;
    11'd1905: t_pt = 8'he0;
    11'd1906: t_pt = 8'he0;
    11'd1907: t_pt = 8'he8;
    11'd1908: t_pt = 8'he8;
    11'd1909: t_pt = 8'he8;
    11'd1910: t_pt = 8'hec;
    11'd1911: t_pt = 8'hee;
    11'd1912: t_pt = 8'hec;
    11'd1913: t_pt = 8'hec;
    11'd1914: t_pt = 8'hec;
    11'd1915: t_pt = 8'hee;
    11'd1916: t_pt = 8'hee;
    11'd1917: t_pt = 8'hef;
    11'd1918: t_pt = 8'hef;
    11'd1919: t_pt = 8'hef;
    11'd1920: t_pt = 8'he0;
    11'd1921: t_pt = 8'he0;
    11'd1922: t_pt = 8'he0;
    11'd1923: t_pt = 8'he0;
    11'd1924: t_pt = 8'he0;
    11'd1925: t_pt = 8'he0;
    11'd1926: t_pt = 8'he0;
    11'd1927: t_pt = 8'he0;
    11'd1928: t_pt = 8'he0;
    11'd1929: t_pt = 8'he0;
    11'd1930: t_pt = 8'he0;
    11'd1931: t_pt = 8'he0;
    11'd1932: t_pt = 8'he0;
    11'd1933: t_pt = 8'hf0;
    11'd1934: t_pt = 8'hf0;
    11'd1935: t_pt = 8'hf0;
    11'd1936: t_pt = 8'he0;
    11'd1937: t_pt = 8'he0;
    11'd1938: t_pt = 8'hf0;
    11'd1939: t_pt = 8'hf0;
    11'd1940: t_pt = 8'hf0;
    11'd1941: t_pt = 8'hf0;
    11'd1942: t_pt = 8'hf0;
    11'd1943: t_pt = 8'hf0;
    11'd1944: t_pt = 8'hf0;
    11'd1945: t_pt = 8'hf0;
    11'd1946: t_pt = 8'hf0;
    11'd1947: t_pt = 8'hf0;
    11'd1948: t_pt = 8'hf0;
    11'd1949: t_pt = 8'hf0;
    11'd1950: t_pt = 8'hf0;
    11'd1951: t_pt = 8'hf0;
    11'd1952: t_pt = 8'hf0;
    11'd1953: t_pt = 8'hf0;
    11'd1954: t_pt = 8'hf0;
    11'd1955: t_pt = 8'hf0;
    11'd1956: t_pt = 8'hf0;
    11'd1957: t_pt = 8'hf0;
    11'd1958: t_pt = 8'hf0;
    11'd1959: t_pt = 8'hf0;
    11'd1960: t_pt = 8'hf0;
    11'd1961: t_pt = 8'hf0;
    11'd1962: t_pt = 8'hf0;
    11'd1963: t_pt = 8'hf0;
    11'd1964: t_pt = 8'hf0;
    11'd1965: t_pt = 8'hf0;
    11'd1966: t_pt = 8'hf0;
    11'd1967: t_pt = 8'hf4;
    11'd1968: t_pt = 8'hf0;
    11'd1969: t_pt = 8'hf0;
    11'd1970: t_pt = 8'hf0;
    11'd1971: t_pt = 8'hf0;
    11'd1972: t_pt = 8'hf0;
    11'd1973: t_pt = 8'hf0;
    11'd1974: t_pt = 8'hf0;
    11'd1975: t_pt = 8'hf4;
    11'd1976: t_pt = 8'hf0;
    11'd1977: t_pt = 8'hf4;
    11'd1978: t_pt = 8'hf4;
    11'd1979: t_pt = 8'hf6;
    11'd1980: t_pt = 8'hf6;
    11'd1981: t_pt = 8'hf7;
    11'd1982: t_pt = 8'hf7;
    11'd1983: t_pt = 8'hf7;
    11'd1984: t_pt = 8'hf0;
    11'd1985: t_pt = 8'hf0;
    11'd1986: t_pt = 8'hf0;
    11'd1987: t_pt = 8'hf8;
    11'd1988: t_pt = 8'hf0;
    11'd1989: t_pt = 8'hf8;
    11'd1990: t_pt = 8'hf8;
    11'd1991: t_pt = 8'hf8;
    11'd1992: t_pt = 8'hf8;
    11'd1993: t_pt = 8'hf8;
    11'd1994: t_pt = 8'hf8;
    11'd1995: t_pt = 8'hf8;
    11'd1996: t_pt = 8'hf8;
    11'd1997: t_pt = 8'hf8;
    11'd1998: t_pt = 8'hf8;
    11'd1999: t_pt = 8'hf8;
    11'd2000: t_pt = 8'hf8;
    11'd2001: t_pt = 8'hf8;
    11'd2002: t_pt = 8'hf8;
    11'd2003: t_pt = 8'hf8;
    11'd2004: t_pt = 8'hf8;
    11'd2005: t_pt = 8'hf8;
    11'd2006: t_pt = 8'hf8;
    11'd2007: t_pt = 8'hf8;
    11'd2008: t_pt = 8'hf8;
    11'd2009: t_pt = 8'hf8;
    11'd2010: t_pt = 8'hf8;
    11'd2011: t_pt = 8'hfa;
    11'd2012: t_pt = 8'hfa;
    11'd2013: t_pt = 8'hfb;
    11'd2014: t_pt = 8'hfb;
    11'd2015: t_pt = 8'hfb;
    11'd2016: t_pt = 8'hf8;
    11'd2017: t_pt = 8'hfc;
    11'd2018: t_pt = 8'hfc;
    11'd2019: t_pt = 8'hfc;
    11'd2020: t_pt = 8'hfc;
    11'd2021: t_pt = 8'hfc;
    11'd2022: t_pt = 8'hfc;
    11'd2023: t_pt = 8'hfc;
    11'd2024: t_pt = 8'hfc;
    11'd2025: t_pt = 8'hfc;
    11'd2026: t_pt = 8'hfc;
    11'd2027: t_pt = 8'hfc;
    11'd2028: t_pt = 8'hfc;
    11'd2029: t_pt = 8'hfd;
    11'd2030: t_pt = 8'hfd;
    11'd2031: t_pt = 8'hfd;
    11'd2032: t_pt = 8'hfe;
    11'd2033: t_pt = 8'hfe;
    11'd2034: t_pt = 8'hfe;
    11'd2035: t_pt = 8'hfe;
    11'd2036: t_pt = 8'hfe;
    11'd2037: t_pt = 8'hfe;
    11'd2038: t_pt = 8'hfe;
    11'd2039: t_pt = 8'hfe;
    11'd2040: t_pt = 8'hff;
    11'd2041: t_pt = 8'hff;
    11'd2042: t_pt = 8'hff;
    11'd2043: t_pt = 8'hff;
    11'd2044: t_pt = 8'hff;
    11'd2045: t_pt = 8'hff;
    11'd2046: t_pt = 8'hff;
    11'd2047: t_pt = 8'hff;
    default: t_pt = 8'h00;
  endcase
endfunction
function [7:0] t_ps;
  input [11:0] x;
  case (x)
    12'd127: t_ps = 8'h03;
    12'd191: t_ps = 8'h01;
    12'd255: t_ps = 8'h0f;
    12'd383: t_ps = 8'h07;
    12'd447: t_ps = 8'h03;
    12'd479: t_ps = 8'h01;
    12'd509: t_ps = 8'h07;
    12'd510: t_ps = 8'h07;
    12'd511: t_ps = 8'h1f;
    12'd639: t_ps = 8'h03;
    12'd703: t_ps = 8'h03;
    12'd735: t_ps = 8'h01;
    12'd766: t_ps = 8'h01;
    12'd767: t_ps = 8'h0f;
    12'd831: t_ps = 8'h01;
    12'd895: t_ps = 8'h17;
    12'd959: t_ps = 8'h3b;
    12'd991: t_ps = 8'h3d;
    12'd1007: t_ps = 8'h3e;
    12'd1015: t_ps = 8'h3f;
    12'd1017: t_ps = 8'h0c;
    12'd1018: t_ps = 8'h1c;
    12'd1019: t_ps = 8'h3f;
    12'd1020: t_ps = 8'h1e;
    12'd1021: t_ps = 8'h3f;
    12'd1022: t_ps = 8'h3f;
    12'd1023: t_ps = 8'h3f;
    12'd1151: t_ps = 8'h03;
    12'd1215: t_ps = 8'h01;
    12'd1279: t_ps = 8'h0f;
    12'd1343: t_ps = 8'h01;
    12'd1407: t_ps = 8'h07;
    12'd1471: t_ps = 8'h0b;
    12'd1503: t_ps = 8'h0a;
    12'd1519: t_ps = 8'h5e;
    12'd1527: t_ps = 8'h5f;
    12'd1531: t_ps = 8'h5f;
    12'd1532: t_ps = 8'h0c;
    12'd1533: t_ps = 8'h5f;
    12'd1534: t_ps = 8'h5f;
    12'd1535: t_ps = 8'h5f;
    12'd1599: t_ps = 8'h01;
    12'd1663: t_ps = 8'h47;
    12'd1727: t_ps = 8'h43;
    12'd1759: t_ps = 8'h65;
    12'd1775: t_ps = 8'h6e;
    12'd1783: t_ps = 8'h6f;
    12'd1785: t_ps = 8'h40;
    12'd1786: t_ps = 8'h40;
    12'd1787: t_ps = 8'h6f;
    12'd1788: t_ps = 8'h40;
    12'd1789: t_ps = 8'h6f;
    12'd1790: t_ps = 8'h6f;
    12'd1791: t_ps = 8'h6f;
    12'd1855: t_ps = 8'h63;
    12'd1886: t_ps = 8'h40;
    12'd1887: t_ps = 8'h61;
    12'd1895: t_ps = 8'h40;
    12'd1899: t_ps = 8'h40;
    12'd1901: t_ps = 8'h40;
    12'd1902: t_ps = 8'h40;
    12'd1903: t_ps = 8'h70;
    12'd1906: t_ps = 8'h40;
    12'd1907: t_ps = 8'h40;
    12'd1908: t_ps = 8'h40;
    12'd1909: t_ps = 8'h40;
    12'd1910: t_ps = 8'h40;
    12'd1911: t_ps = 8'h70;
    12'd1912: t_ps = 8'h40;
    12'd1913: t_ps = 8'h60;
    12'd1914: t_ps = 8'h60;
    12'd1915: t_ps = 8'h77;
    12'd1916: t_ps = 8'h60;
    12'd1917: t_ps = 8'h77;
    12'd1918: t_ps = 8'h77;
    12'd1919: t_ps = 8'h77;
    12'd1935: t_ps = 8'h40;
    12'd1942: t_ps = 8'h40;
    12'd1943: t_ps = 8'h60;
    12'd1945: t_ps = 8'h40;
    12'd1946: t_ps = 8'h40;
    12'd1947: t_ps = 8'h60;
    12'd1948: t_ps = 8'h40;
    12'd1949: t_ps = 8'h60;
    12'd1950: t_ps = 8'h60;
    12'd1951: t_ps = 8'h79;
    12'd1953: t_ps = 8'h40;
    12'd1954: t_ps = 8'h40;
    12'd1955: t_ps = 8'h40;
    12'd1956: t_ps = 8'h40;
    12'd1957: t_ps = 8'h40;
    12'd1958: t_ps = 8'h40;
    12'd1959: t_ps = 8'h60;
    12'd1960: t_ps = 8'h40;
    12'd1961: t_ps = 8'h40;
    12'd1962: t_ps = 8'h40;
    12'd1963: t_ps = 8'h60;
    12'd1964: t_ps = 8'h60;
    12'd1965: t_ps = 8'h60;
    12'd1966: t_ps = 8'h60;
    12'd1967: t_ps = 8'h78;
    12'd1968: t_ps = 8'h40;
    12'd1969: t_ps = 8'h60;
    12'd1970: t_ps = 8'h60;
    12'd1971: t_ps = 8'h60;
    12'd1972: t_ps = 8'h60;
    12'd1973: t_ps = 8'h60;
    12'd1974: t_ps = 8'h60;
    12'd1975: t_ps = 8'h78;
    12'd1976: t_ps = 8'h60;
    12'd1977: t_ps = 8'h70;
    12'd1978: t_ps = 8'h70;
    12'd1979: t_ps = 8'h78;
    12'd1980: t_ps = 8'h70;
    12'd1981: t_ps = 8'h79;
    12'd1982: t_ps = 8'h7b;
    12'd1983: t_ps = 8'h7b;
    12'd1984: t_ps = 8'h60;
    12'd1985: t_ps = 8'h60;
    12'd1986: t_ps = 8'h60;
    12'd1987: t_ps = 8'h60;
    12'd1988: t_ps = 8'h60;
    12'd1989: t_ps = 8'h60;
    12'd1990: t_ps = 8'h60;
    12'd1991: t_ps = 8'h70;
    12'd1992: t_ps = 8'h60;
    12'd1993: t_ps = 8'h60;
    12'd1994: t_ps = 8'h60;
    12'd1995: t_ps = 8'h70;
    12'd1996: t_ps = 8'h60;
    12'd1997: t_ps = 8'h70;
    12'd1998: t_ps = 8'h70;
    12'd1999: t_ps = 8'h7c;
    12'd2000: t_ps = 8'h60;
    12'd2001: t_ps = 8'h70;
    12'd2002: t_ps = 8'h70;
    12'd2003: t_ps = 8'h70;
    12'd2004: t_ps = 8'h70;
    12'd2005: t_ps = 8'h70;
    12'd2006: t_ps = 8'h70;
    12'd2007: t_ps = 8'h7c;
    12'd2008: t_ps = 8'h70;
    12'd2009: t_ps = 8'h78;
    12'd2010: t_ps = 8'h78;
    12'd2011: t_ps = 8'h7c;
    12'd2012: t_ps = 8'h78;
    12'd2013: t_ps = 8'h7c;
    12'd2014: t_ps = 8'h7c;
    12'd2015: t_ps = 8'h7d;
    12'd2016: t_ps = 8'h70;
    12'd2017: t_ps = 8'h78;
    12'd2018: t_ps = 8'h78;
    12'd2019: t_ps = 8'h78;
    12'd2020: t_ps = 8'h78;
    12'd2021: t_ps = 8'h78;
    12'd2022: t_ps = 8'h78;
    12'd2023: t_ps = 8'h7c;
    12'd2024: t_ps = 8'h78;
    12'd2025: t_ps = 8'h7c;
    12'd2026: t_ps = 8'h7c;
    12'd2027: t_ps = 8'h7e;
    12'd2028: t_ps = 8'h7c;
    12'd2029: t_ps = 8'h7e;
    12'd2030: t_ps = 8'h7e;
    12'd2031: t_ps = 8'h7e;
    12'd2032: t_ps = 8'h7c;
    12'd2033: t_ps = 8'h7c;
    12'd2034: t_ps = 8'h7c;
    12'd2035: t_ps = 8'h7e;
    12'd2036: t_ps = 8'h7e;
    12'd2037: t_ps = 8'h7f;
    12'd2038: t_ps = 8'h7f;
    12'd2039: t_ps = 8'h7f;
    12'd2040: t_ps = 8'h7e;
    12'd2041: t_ps = 8'h7f;
    12'd2042: t_ps = 8'h7f;
    12'd2043: t_ps = 8'h7f;
    12'd2044: t_ps = 8'h7f;
    12'd2045: t_ps = 8'h7f;
    12'd2046: t_ps = 8'h7f;
    12'd2047: t_ps = 8'hff;
    12'd2175: t_ps = 8'h03;
    12'd2239: t_ps = 8'h01;
    12'd2303: t_ps = 8'h8f;
    12'd2367: t_ps = 8'h01;
    12'd2431: t_ps = 8'h87;
    12'd2495: t_ps = 8'h83;
    12'd2526: t_ps = 8'h80;
    12'd2527: t_ps = 8'h8d;
    12'd2535: t_ps = 8'h80;
    12'd2539: t_ps = 8'h80;
    12'd2541: t_ps = 8'h80;
    12'd2542: t_ps = 8'h80;
    12'd2543: t_ps = 8'h8e;
    12'd2547: t_ps = 8'h80;
    12'd2548: t_ps = 8'h80;
    12'd2549: t_ps = 8'h80;
    12'd2550: t_ps = 8'h80;
    12'd2551: t_ps = 8'h8f;
    12'd2552: t_ps = 8'h80;
    12'd2553: t_ps = 8'h80;
    12'd2554: t_ps = 8'h80;
    12'd2555: t_ps = 8'h9f;
    12'd2556: t_ps = 8'h80;
    12'd2557: t_ps = 8'h9f;
    12'd2558: t_ps = 8'h9f;
    12'd2559: t_ps = 8'h9f;
    12'd2623: t_ps = 8'h01;
    12'd2671: t_ps = 8'h80;
    12'd2679: t_ps = 8'h80;
    12'd2683: t_ps = 8'h80;
    12'd2685: t_ps = 8'h80;
    12'd2686: t_ps = 8'h80;
    12'd2687: t_ps = 8'h87;
    12'd2719: t_ps = 8'h80;
    12'd2735: t_ps = 8'h80;
    12'd2743: t_ps = 8'h80;
    12'd2747: t_ps = 8'h80;
    12'd2748: t_ps = 8'h80;
    12'd2749: t_ps = 8'h80;
    12'd2750: t_ps = 8'h80;
    12'd2751: t_ps = 8'h83;
    12'd2767: t_ps = 8'h80;
    12'd2773: t_ps = 8'h80;
    12'd2774: t_ps = 8'h80;
    12'd2775: t_ps = 8'h80;
    12'd2777: t_ps = 8'h80;
    12'd2778: t_ps = 8'h80;
    12'd2779: t_ps = 8'h80;
    12'd2780: t_ps = 8'h80;
    12'd2781: t_ps = 8'h80;
    12'd2782: t_ps = 8'h80;
    12'd2783: t_ps = 8'h81;
    12'd2784: t_ps = 8'h80;
    12'd2785: t_ps = 8'h80;
    12'd2786: t_ps = 8'h80;
    12'd2787: t_ps = 8'h80;
    12'd2788: t_ps = 8'h80;
    12'd2789: t_ps = 8'h80;
    12'd2790: t_ps = 8'h80;
    12'd2791: t_ps = 8'h80;
    12'd2792: t_ps = 8'h80;
    12'd2793: t_ps = 8'h80;
    12'd2794: t_ps = 8'h80;
    12'd2795: t_ps = 8'h80;
    12'd2796: t_ps = 8'h80;
    12'd2797: t_ps = 8'h80;
    12'd2798: t_ps = 8'h80;
    12'd2799: t_ps = 8'h84;
    12'd2800: t_ps = 8'h80;
    12'd2801: t_ps = 8'h80;
    12'd2802: t_ps = 8'h80;
    12'd2803: t_ps = 8'h80;
    12'd2804: t_ps = 8'h80;
    12'd2805: t_ps = 8'h80;
    12'd2806: t_ps = 8'h80;
    12'd2807: t_ps = 8'h87;
    12'd2808: t_ps = 8'h80;
    12'd2809: t_ps = 8'h80;
    12'd2810: t_ps = 8'h80;
    12'd2811: t_ps = 8'h87;
    12'd2812: t_ps = 8'h80;
    12'd2813: t_ps = 8'h8f;
    12'd2814: t_ps = 8'haf;
    12'd2815: t_ps = 8'haf;
    12'd2831: t_ps = 8'h80;
    12'd2839: t_ps = 8'h80;
    12'd2843: t_ps = 8'h80;
    12'd2844: t_ps = 8'h80;
    12'd2845: t_ps = 8'h80;
    12'd2846: t_ps = 8'h80;
    12'd2847: t_ps = 8'h80;
    12'd2851: t_ps = 8'h80;
    12'd2854: t_ps = 8'h80;
    12'd2855: t_ps = 8'h80;
    12'd2857: t_ps = 8'h80;
    12'd2858: t_ps = 8'h80;
    12'd2859: t_ps = 8'h80;
    12'd2860: t_ps = 8'h80;
    12'd2861: t_ps = 8'h80;
    12'd2862: t_ps = 8'h80;
    12'd2863: t_ps = 8'h80;
    12'd2864: t_ps = 8'h80;
    12'd2865: t_ps = 8'h80;
    12'd2866: t_ps = 8'h80;
    12'd2867: t_ps = 8'h80;
    12'd2868: t_ps = 8'h80;
    12'd2869: t_ps = 8'h80;
    12'd2870: t_ps = 8'h80;
    12'd2871: t_ps = 8'h80;
    12'd2872: t_ps = 8'h80;
    12'd2873: t_ps = 8'h80;
    12'd2874: t_ps = 8'h80;
    12'd2875: t_ps = 8'h80;
    12'd2876: t_ps = 8'h80;
    12'd2877: t_ps = 8'h80;
    12'd2878: t_ps = 8'h80;
    12'd2879: t_ps = 8'h83;
    12'd2880: t_ps = 8'h80;
    12'd2881: t_ps = 8'h80;
    12'd2882: t_ps = 8'h80;
    12'd2883: t_ps = 8'h80;
    12'd2884: t_ps = 8'h80;
    12'd2885: t_ps = 8'h80;
    12'd2886: t_ps = 8'h80;
    12'd2887: t_ps = 8'h80;
    12'd2888: t_ps = 8'h80;
    12'd2889: t_ps = 8'h80;
    12'd2890: t_ps = 8'h80;
    12'd2891: t_ps = 8'h80;
    12'd2892: t_ps = 8'h80;
    12'd2893: t_ps = 8'h80;
    12'd2894: t_ps = 8'h80;
    12'd2895: t_ps = 8'h80;
    12'd2896: t_ps = 8'h80;
    12'd2897: t_ps = 8'h80;
    12'd2898: t_ps = 8'h80;
    12'd2899: t_ps = 8'h80;
    12'd2900: t_ps = 8'h80;
    12'd2901: t_ps = 8'h80;
    12'd2902: t_ps = 8'h80;
    12'd2903: t_ps = 8'h80;
    12'd2904: t_ps = 8'h80;
    12'd2905: t_ps = 8'h80;
    12'd2906: t_ps = 8'h80;
    12'd2907: t_ps = 8'h80;
    12'd2908: t_ps = 8'h80;
    12'd2909: t_ps = 8'h80;
    12'd2910: t_ps = 8'h80;
    12'd2911: t_ps = 8'h81;
    12'd2912: t_ps = 8'h80;
    12'd2913: t_ps = 8'h80;
    12'd2914: t_ps = 8'h80;
    12'd2915: t_ps = 8'h80;
    12'd2916: t_ps = 8'h80;
    12'd2917: t_ps = 8'h80;
    12'd2918: t_ps = 8'h80;
    12'd2919: t_ps = 8'h80;
    12'd2920: t_ps = 8'h80;
    12'd2921: t_ps = 8'h80;
    12'd2922: t_ps = 8'h80;
    12'd2923: t_ps = 8'h80;
    12'd2924: t_ps = 8'h80;
    12'd2925: t_ps = 8'h80;
    12'd2926: t_ps = 8'h80;
    12'd2927: t_ps = 8'ha0;
    12'd2928: t_ps = 8'h80;
    12'd2929: t_ps = 8'h80;
    12'd2930: t_ps = 8'h80;
    12'd2931: t_ps = 8'h80;
    12'd2932: t_ps = 8'h80;
    12'd2933: t_ps = 8'h80;
    12'd2934: t_ps = 8'h80;
    12'd2935: t_ps = 8'ha0;
    12'd2936: t_ps = 8'h80;
    12'd2937: t_ps = 8'h80;
    12'd2938: t_ps = 8'h80;
    12'd2939: t_ps = 8'ha0;
    12'd2940: t_ps = 8'h80;
    12'd2941: t_ps = 8'ha3;
    12'd2942: t_ps = 8'hb7;
    12'd2943: t_ps = 8'hb7;
    12'd2944: t_ps = 8'h80;
    12'd2945: t_ps = 8'h80;
    12'd2946: t_ps = 8'h80;
    12'd2947: t_ps = 8'h80;
    12'd2948: t_ps = 8'h80;
    12'd2949: t_ps = 8'h80;
    12'd2950: t_ps = 8'h80;
    12'd2951: t_ps = 8'h80;
    12'd2952: t_ps = 8'h80;
    12'd2953: t_ps = 8'h80;
    12'd2954: t_ps = 8'h80;
    12'd2955: t_ps = 8'h80;
    12'd2956: t_ps = 8'h80;
    12'd2957: t_ps = 8'h80;
    12'd2958: t_ps = 8'h80;
    12'd2959: t_ps = 8'h80;
    12'd2960: t_ps = 8'h80;
    12'd2961: t_ps = 8'h80;
    12'd2962: t_ps = 8'h80;
    12'd2963: t_ps = 8'h80;
    12'd2964: t_ps = 8'h80;
    12'd2965: t_ps = 8'h80;
    12'd2966: t_ps = 8'h80;
    12'd2967: t_ps = 8'h80;
    12'd2968: t_ps = 8'h80;
    12'd2969: t_ps = 8'h80;
    12'd2970: t_ps = 8'h80;
    12'd2971: t_ps = 8'h80;
    12'd2972: t_ps = 8'h80;
    12'd2973: t_ps = 8'h80;
    12'd2974: t_ps = 8'h80;
    12'd2975: t_ps = 8'hb1;
    12'd2976: t_ps = 8'h80;
    12'd2977: t_ps = 8'h80;
    12'd2978: t_ps = 8'h80;
    12'd2979: t_ps = 8'h80;
    12'd2980: t_ps = 8'h80;
    12'd2981: t_ps = 8'h80;
    12'd2982: t_ps = 8'h80;
    12'd2983: t_ps = 8'h80;
    12'd2984: t_ps = 8'h80;
    12'd2985: t_ps = 8'h80;
    12'd2986: t_ps = 8'h80;
    12'd2987: t_ps = 8'h80;
    12'd2988: t_ps = 8'h80;
    12'd2989: t_ps = 8'h80;
    12'd2990: t_ps = 8'h80;
    12'd2991: t_ps = 8'hb0;
    12'd2992: t_ps = 8'h80;
    12'd2993: t_ps = 8'h80;
    12'd2994: t_ps = 8'h80;
    12'd2995: t_ps = 8'h80;
    12'd2996: t_ps = 8'h80;
    12'd2997: t_ps = 8'h80;
    12'd2998: t_ps = 8'h80;
    12'd2999: t_ps = 8'hb0;
    12'd3000: t_ps = 8'h80;
    12'd3001: t_ps = 8'ha0;
    12'd3002: t_ps = 8'ha0;
    12'd3003: t_ps = 8'hb0;
    12'd3004: t_ps = 8'ha0;
    12'd3005: t_ps = 8'hb8;
    12'd3006: t_ps = 8'hb9;
    12'd3007: t_ps = 8'hbb;
    12'd3008: t_ps = 8'h80;
    12'd3009: t_ps = 8'h80;
    12'd3010: t_ps = 8'h80;
    12'd3011: t_ps = 8'h80;
    12'd3012: t_ps = 8'h80;
    12'd3013: t_ps = 8'h80;
    12'd3014: t_ps = 8'h80;
    12'd3015: t_ps = 8'ha0;
    12'd3016: t_ps = 8'h80;
    12'd3017: t_ps = 8'h80;
    12'd3018: t_ps = 8'h80;
    12'd3019: t_ps = 8'ha0;
    12'd3020: t_ps = 8'h80;
    12'd3021: t_ps = 8'ha0;
    12'd3022: t_ps = 8'ha0;
    12'd3023: t_ps = 8'hb8;
    12'd3024: t_ps = 8'h80;
    12'd3025: t_ps = 8'ha0;
    12'd3026: t_ps = 8'ha0;
    12'd3027: t_ps = 8'ha0;
    12'd3028: t_ps = 8'ha0;
    12'd3029: t_ps = 8'ha0;
    12'd3030: t_ps = 8'ha0;
    12'd3031: t_ps = 8'hb8;
    12'd3032: t_ps = 8'ha0;
    12'd3033: t_ps = 8'hb0;
    12'd3034: t_ps = 8'hb0;
    12'd3035: t_ps = 8'hb8;
    12'd3036: t_ps = 8'hb0;
    12'd3037: t_ps = 8'hbc;
    12'd3038: t_ps = 8'hbc;
    12'd3039: t_ps = 8'hbd;
    12'd3040: t_ps = 8'ha0;
    12'd3041: t_ps = 8'hb0;
    12'd3042: t_ps = 8'hb0;
    12'd3043: t_ps = 8'hb0;
    12'd3044: t_ps = 8'hb0;
    12'd3045: t_ps = 8'hb8;
    12'd3046: t_ps = 8'hb8;
    12'd3047: t_ps = 8'hbc;
    12'd3048: t_ps = 8'hb0;
    12'd3049: t_ps = 8'hb8;
    12'd3050: t_ps = 8'hb8;
    12'd3051: t_ps = 8'hbc;
    12'd3052: t_ps = 8'hb8;
    12'd3053: t_ps = 8'hbc;
    12'd3054: t_ps = 8'hbe;
    12'd3055: t_ps = 8'hbe;
    12'd3056: t_ps = 8'hb8;
    12'd3057: t_ps = 8'hbc;
    12'd3058: t_ps = 8'hbc;
    12'd3059: t_ps = 8'hbe;
    12'd3060: t_ps = 8'hbc;
    12'd3061: t_ps = 8'hbe;
    12'd3062: t_ps = 8'hbe;
    12'd3063: t_ps = 8'hbf;
    12'd3064: t_ps = 8'hbe;
    12'd3065: t_ps = 8'hbf;
    12'd3066: t_ps = 8'hbf;
    12'd3067: t_ps = 8'hbf;
    12'd3068: t_ps = 8'hbf;
    12'd3069: t_ps = 8'hbf;
    12'd3070: t_ps = 8'hbf;
    12'd3071: t_ps = 8'hbf;
    12'd3075: t_ps = 8'h80;
    12'd3079: t_ps = 8'h80;
    12'd3083: t_ps = 8'h80;
    12'd3087: t_ps = 8'h80;
    12'd3089: t_ps = 8'h80;
    12'd3090: t_ps = 8'h80;
    12'd3091: t_ps = 8'h80;
    12'd3092: t_ps = 8'h80;
    12'd3093: t_ps = 8'h80;
    12'd3094: t_ps = 8'h80;
    12'd3095: t_ps = 8'h80;
    12'd3097: t_ps = 8'h80;
    12'd3098: t_ps = 8'h80;
    12'd3099: t_ps = 8'h80;
    12'd3100: t_ps = 8'h80;
    12'd3101: t_ps = 8'h80;
    12'd3102: t_ps = 8'h80;
    12'd3103: t_ps = 8'h80;
    12'd3104: t_ps = 8'h80;
    12'd3105: t_ps = 8'h80;
    12'd3106: t_ps = 8'h80;
    12'd3107: t_ps = 8'h80;
    12'd3108: t_ps = 8'h80;
    12'd3109: t_ps = 8'h80;
    12'd3110: t_ps = 8'h80;
    12'd3111: t_ps = 8'h80;
    12'd3112: t_ps = 8'h80;
    12'd3113: t_ps = 8'h80;
    12'd3114: t_ps = 8'h80;
    12'd3115: t_ps = 8'h80;
    12'd3116: t_ps = 8'h80;
    12'd3117: t_ps = 8'h80;
    12'd3118: t_ps = 8'h80;
    12'd3119: t_ps = 8'h80;
    12'd3120: t_ps = 8'h80;
    12'd3121: t_ps = 8'h80;
    12'd3122: t_ps = 8'h80;
    12'd3123: t_ps = 8'h80;
    12'd3124: t_ps = 8'h80;
    12'd3125: t_ps = 8'h80;
    12'd3126: t_ps = 8'h80;
    12'd3127: t_ps = 8'h80;
    12'd3128: t_ps = 8'h80;
    12'd3129: t_ps = 8'h80;
    12'd3130: t_ps = 8'h80;
    12'd3131: t_ps = 8'h80;
    12'd3132: t_ps = 8'h80;
    12'd3133: t_ps = 8'h80;
    12'd3134: t_ps = 8'h80;
    12'd3135: t_ps = 8'h81;
    12'd3136: t_ps = 8'h80;
    12'd3137: t_ps = 8'h80;
    12'd3138: t_ps = 8'h80;
    12'd3139: t_ps = 8'h80;
    12'd3140: t_ps = 8'h80;
    12'd3141: t_ps = 8'h80;
    12'd3142: t_ps = 8'h80;
    12'd3143: t_ps = 8'h80;
    12'd3144: t_ps = 8'h80;
    12'd3145: t_ps = 8'h80;
    12'd3146: t_ps = 8'h80;
    12'd3147: t_ps = 8'h80;
    12'd3148: t_ps = 8'h80;
    12'd3149: t_ps = 8'h80;
    12'd3150: t_ps = 8'h80;
    12'd3151: t_ps = 8'h80;
    12'd3152: t_ps = 8'h80;
    12'd3153: t_ps = 8'h80;
    12'd3154: t_ps = 8'h80;
    12'd3155: t_ps = 8'h80;
    12'd3156: t_ps = 8'h80;
    12'd3157: t_ps = 8'h80;
    12'd3158: t_ps = 8'h80;
    12'd3159: t_ps = 8'h80;
    12'd3160: t_ps = 8'h80;
    12'd3161: t_ps = 8'h80;
    12'd3162: t_ps = 8'h80;
    12'd3163: t_ps = 8'h80;
    12'd3164: t_ps = 8'h80;
    12'd3165: t_ps = 8'h80;
    12'd3166: t_ps = 8'h80;
    12'd3167: t_ps = 8'h80;
    12'd3168: t_ps = 8'h80;
    12'd3169: t_ps = 8'h80;
    12'd3170: t_ps = 8'h80;
    12'd3171: t_ps = 8'h80;
    12'd3172: t_ps = 8'h80;
    12'd3173: t_ps = 8'h80;
    12'd3174: t_ps = 8'h80;
    12'd3175: t_ps = 8'h80;
    12'd3176: t_ps = 8'h80;
    12'd3177: t_ps = 8'h80;
    12'd3178: t_ps = 8'h80;
    12'd3179: t_ps = 8'h80;
    12'd3180: t_ps = 8'h80;
    12'd3181: t_ps = 8'h80;
    12'd3182: t_ps = 8'h80;
    12'd3183: t_ps = 8'h80;
    12'd3184: t_ps = 8'h80;
    12'd3185: t_ps = 8'h80;
    12'd3186: t_ps = 8'h80;
    12'd3187: t_ps = 8'h80;
    12'd3188: t_ps = 8'h80;
    12'd3189: t_ps = 8'h80;
    12'd3190: t_ps = 8'h80;
    12'd3191: t_ps = 8'h80;
    12'd3192: t_ps = 8'h80;
    12'd3193: t_ps = 8'h80;
    12'd3194: t_ps = 8'h80;
    12'd3195: t_ps = 8'h80;
    12'd3196: t_ps = 8'h80;
    12'd3197: t_ps = 8'h80;
    12'd3198: t_ps = 8'h80;
    12'd3199: t_ps = 8'hc7;
    12'd3200: t_ps = 8'h80;
    12'd3201: t_ps = 8'h80;
    12'd3202: t_ps = 8'h80;
    12'd3203: t_ps = 8'h80;
    12'd3204: t_ps = 8'h80;
    12'd3205: t_ps = 8'h80;
    12'd3206: t_ps = 8'h80;
    12'd3207: t_ps = 8'h80;
    12'd3208: t_ps = 8'h80;
    12'd3209: t_ps = 8'h80;
    12'd3210: t_ps = 8'h80;
    12'd3211: t_ps = 8'h80;
    12'd3212: t_ps = 8'h80;
    12'd3213: t_ps = 8'h80;
    12'd3214: t_ps = 8'h80;
    12'd3215: t_ps = 8'h80;
    12'd3216: t_ps = 8'h80;
    12'd3217: t_ps = 8'h80;
    12'd3218: t_ps = 8'h80;
    12'd3219: t_ps = 8'h80;
    12'd3220: t_ps = 8'h80;
    12'd3221: t_ps = 8'h80;
    12'd3222: t_ps = 8'h80;
    12'd3223: t_ps = 8'h80;
    12'd3224: t_ps = 8'h80;
    12'd3225: t_ps = 8'h80;
    12'd3226: t_ps = 8'h80;
    12'd3227: t_ps = 8'h80;
    12'd3228: t_ps = 8'h80;
    12'd3229: t_ps = 8'h80;
    12'd3230: t_ps = 8'h80;
    12'd3231: t_ps = 8'h80;
    12'd3232: t_ps = 8'h80;
    12'd3233: t_ps = 8'h80;
    12'd3234: t_ps = 8'h80;
    12'd3235: t_ps = 8'h80;
    12'd3236: t_ps = 8'h80;
    12'd3237: t_ps = 8'h80;
    12'd3238: t_ps = 8'h80;
    12'd3239: t_ps = 8'h80;
    12'd3240: t_ps = 8'h80;
    12'd3241: t_ps = 8'h80;
    12'd3242: t_ps = 8'h80;
    12'd3243: t_ps = 8'h80;
    12'd3244: t_ps = 8'h80;
    12'd3245: t_ps = 8'h80;
    12'd3246: t_ps = 8'h80;
    12'd3247: t_ps = 8'h80;
    12'd3248: t_ps = 8'h80;
    12'd3249: t_ps = 8'h80;
    12'd3250: t_ps = 8'h80;
    12'd3251: t_ps = 8'h80;
    12'd3252: t_ps = 8'h80;
    12'd3253: t_ps = 8'h80;
    12'd3254: t_ps = 8'h80;
    12'd3255: t_ps = 8'h80;
    12'd3256: t_ps = 8'h80;
    12'd3257: t_ps = 8'h80;
    12'd3258: t_ps = 8'h80;
    12'd3259: t_ps = 8'h80;
    12'd3260: t_ps = 8'h80;
    12'd3261: t_ps = 8'h80;
    12'd3262: t_ps = 8'hc0;
    12'd3263: t_ps = 8'hc3;
    12'd3264: t_ps = 8'h80;
    12'd3265: t_ps = 8'h80;
    12'd3266: t_ps = 8'h80;
    12'd3267: t_ps = 8'h80;
    12'd3268: t_ps = 8'h80;
    12'd3269: t_ps = 8'h80;
    12'd3270: t_ps = 8'h80;
    12'd3271: t_ps = 8'h80;
    12'd3272: t_ps = 8'h80;
    12'd3273: t_ps = 8'h80;
    12'd3274: t_ps = 8'h80;
    12'd3275: t_ps = 8'h80;
    12'd3276: t_ps = 8'h80;
    12'd3277: t_ps = 8'h80;
    12'd3278: t_ps = 8'h80;
    12'd3279: t_ps = 8'hc0;
    12'd3280: t_ps = 8'h80;
    12'd3281: t_ps = 8'h80;
    12'd3282: t_ps = 8'h80;
    12'd3283: t_ps = 8'h80;
    12'd3284: t_ps = 8'h80;
    12'd3285: t_ps = 8'h80;
    12'd3286: t_ps = 8'h80;
    12'd3287: t_ps = 8'hc0;
    12'd3288: t_ps = 8'h80;
    12'd3289: t_ps = 8'h80;
    12'd3290: t_ps = 8'h80;
    12'd3291: t_ps = 8'hc0;
    12'd3292: t_ps = 8'h80;
    12'd3293: t_ps = 8'hc0;
    12'd3294: t_ps = 8'hc0;
    12'd3295: t_ps = 8'hc1;
    12'd3296: t_ps = 8'h80;
    12'd3297: t_ps = 8'h80;
    12'd3298: t_ps = 8'h80;
    12'd3299: t_ps = 8'h80;
    12'd3300: t_ps = 8'h80;
    12'd3301: t_ps = 8'h80;
    12'd3302: t_ps = 8'h80;
    12'd3303: t_ps = 8'hc0;
    12'd3304: t_ps = 8'h80;
    12'd3305: t_ps = 8'h80;
    12'd3306: t_ps = 8'h80;
    12'd3307: t_ps = 8'hc0;
    12'd3308: t_ps = 8'hc0;
    12'd3309: t_ps = 8'hc0;
    12'd3310: t_ps = 8'hc0;
    12'd3311: t_ps = 8'hc0;
    12'd3312: t_ps = 8'hc0;
    12'd3313: t_ps = 8'hc0;
    12'd3314: t_ps = 8'hc0;
    12'd3315: t_ps = 8'hc0;
    12'd3316: t_ps = 8'hc0;
    12'd3317: t_ps = 8'hc0;
    12'd3318: t_ps = 8'hc0;
    12'd3319: t_ps = 8'hc7;
    12'd3320: t_ps = 8'hc0;
    12'd3321: t_ps = 8'hc0;
    12'd3322: t_ps = 8'hc0;
    12'd3323: t_ps = 8'hc7;
    12'd3324: t_ps = 8'hc0;
    12'd3325: t_ps = 8'hcf;
    12'd3326: t_ps = 8'hcf;
    12'd3327: t_ps = 8'hcf;
    12'd3328: t_ps = 8'h80;
    12'd3329: t_ps = 8'h80;
    12'd3330: t_ps = 8'h80;
    12'd3331: t_ps = 8'h80;
    12'd3332: t_ps = 8'h80;
    12'd3333: t_ps = 8'h80;
    12'd3334: t_ps = 8'h80;
    12'd3335: t_ps = 8'h80;
    12'd3336: t_ps = 8'h80;
    12'd3337: t_ps = 8'h80;
    12'd3338: t_ps = 8'h80;
    12'd3339: t_ps = 8'h80;
    12'd3340: t_ps = 8'h80;
    12'd3341: t_ps = 8'h80;
    12'd3342: t_ps = 8'h80;
    12'd3343: t_ps = 8'h80;
    12'd3344: t_ps = 8'h80;
    12'd3345: t_ps = 8'h80;
    12'd3346: t_ps = 8'h80;
    12'd3347: t_ps = 8'h80;
    12'd3348: t_ps = 8'h80;
    12'd3349: t_ps = 8'h80;
    12'd3350: t_ps = 8'h80;
    12'd3351: t_ps = 8'h80;
    12'd3352: t_ps = 8'h80;
    12'd3353: t_ps = 8'h80;
    12'd3354: t_ps = 8'h80;
    12'd3355: t_ps = 8'h80;
    12'd3356: t_ps = 8'h80;
    12'd3357: t_ps = 8'h80;
    12'd3358: t_ps = 8'h80;
    12'd3359: t_ps = 8'hc0;
    12'd3360: t_ps = 8'h80;
    12'd3361: t_ps = 8'h80;
    12'd3362: t_ps = 8'h80;
    12'd3363: t_ps = 8'h80;
    12'd3364: t_ps = 8'h80;
    12'd3365: t_ps = 8'h80;
    12'd3366: t_ps = 8'h80;
    12'd3367: t_ps = 8'h80;
    12'd3368: t_ps = 8'h80;
    12'd3369: t_ps = 8'h80;
    12'd3370: t_ps = 8'h80;
    12'd3371: t_ps = 8'h80;
    12'd3372: t_ps = 8'h80;
    12'd3373: t_ps = 8'h80;
    12'd3374: t_ps = 8'h80;
    12'd3375: t_ps = 8'hc0;
    12'd3376: t_ps = 8'h80;
    12'd3377: t_ps = 8'h80;
    12'd3378: t_ps = 8'h80;
    12'd3379: t_ps = 8'h80;
    12'd3380: t_ps = 8'h80;
    12'd3381: t_ps = 8'h80;
    12'd3382: t_ps = 8'hc0;
    12'd3383: t_ps = 8'hc0;
    12'd3384: t_ps = 8'h80;
    12'd3385: t_ps = 8'hc0;
    12'd3386: t_ps = 8'hc0;
    12'd3387: t_ps = 8'hc0;
    12'd3388: t_ps = 8'hc0;
    12'd3389: t_ps = 8'hc0;
    12'd3390: t_ps = 8'hc0;
    12'd3391: t_ps = 8'hc3;
    12'd3392: t_ps = 8'h80;
    12'd3393: t_ps = 8'h80;
    12'd3394: t_ps = 8'h80;
    12'd3395: t_ps = 8'h80;
    12'd3396: t_ps = 8'h80;
    12'd3397: t_ps = 8'h80;
    12'd3398: t_ps = 8'h80;
    12'd3399: t_ps = 8'hc0;
    12'd3400: t_ps = 8'h80;
    12'd3401: t_ps = 8'h80;
    12'd3402: t_ps = 8'h80;
    12'd3403: t_ps = 8'hc0;
    12'd3404: t_ps = 8'h80;
    12'd3405: t_ps = 8'hc0;
    12'd3406: t_ps = 8'hc0;
    12'd3407: t_ps = 8'hc0;
    12'd3408: t_ps = 8'h80;
    12'd3409: t_ps = 8'hc0;
    12'd3410: t_ps = 8'hc0;
    12'd3411: t_ps = 8'hc0;
    12'd3412: t_ps = 8'hc0;
    12'd3413: t_ps = 8'hc0;
    12'd3414: t_ps = 8'hc0;
    12'd3415: t_ps = 8'hc0;
    12'd3416: t_ps = 8'hc0;
    12'd3417: t_ps = 8'hc0;
    12'd3418: t_ps = 8'hc0;
    12'd3419: t_ps = 8'hc0;
    12'd3420: t_ps = 8'hc0;
    12'd3421: t_ps = 8'hc0;
    12'd3422: t_ps = 8'hc0;
    12'd3423: t_ps = 8'hc1;
    12'd3424: t_ps = 8'hc0;
    12'd3425: t_ps = 8'hc0;
    12'd3426: t_ps = 8'hc0;
    12'd3427: t_ps = 8'hc0;
    12'd3428: t_ps = 8'hc0;
    12'd3429: t_ps = 8'hc0;
    12'd3430: t_ps = 8'hc0;
    12'd3431: t_ps = 8'hc0;
    12'd3432: t_ps = 8'hc0;
    12'd3433: t_ps = 8'hc0;
    12'd3434: t_ps = 8'hc0;
    12'd3435: t_ps = 8'hc0;
    12'd3436: t_ps = 8'hc0;
    12'd3437: t_ps = 8'hc0;
    12'd3438: t_ps = 8'hc0;
    12'd3439: t_ps = 8'hc0;
    12'd3440: t_ps = 8'hc0;
    12'd3441: t_ps = 8'hc0;
    12'd3442: t_ps = 8'hc0;
    12'd3443: t_ps = 8'hc0;
    12'd3444: t_ps = 8'hc0;
    12'd3445: t_ps = 8'hc0;
    12'd3446: t_ps = 8'hc0;
    12'd3447: t_ps = 8'hc0;
    12'd3448: t_ps = 8'hc0;
    12'd3449: t_ps = 8'hc0;
    12'd3450: t_ps = 8'hc0;
    12'd3451: t_ps = 8'hc0;
    12'd3452: t_ps = 8'hc0;
    12'd3453: t_ps = 8'hc1;
    12'd3454: t_ps = 8'hc7;
    12'd3455: t_ps = 8'hd7;
    12'd3456: t_ps = 8'hc0;
    12'd3457: t_ps = 8'hc0;
    12'd3458: t_ps = 8'hc0;
    12'd3459: t_ps = 8'hc0;
    12'd3460: t_ps = 8'hc0;
    12'd3461: t_ps = 8'hc0;
    12'd3462: t_ps = 8'hc0;
    12'd3463: t_ps = 8'hc0;
    12'd3464: t_ps = 8'hc0;
    12'd3465: t_ps = 8'hc0;
    12'd3466: t_ps = 8'hc0;
    12'd3467: t_ps = 8'hc0;
    12'd3468: t_ps = 8'hc0;
    12'd3469: t_ps = 8'hc0;
    12'd3470: t_ps = 8'hc0;
    12'd3471: t_ps = 8'hc0;
    12'd3472: t_ps = 8'hc0;
    12'd3473: t_ps = 8'hc0;
    12'd3474: t_ps = 8'hc0;
    12'd3475: t_ps = 8'hc0;
    12'd3476: t_ps = 8'hc0;
    12'd3477: t_ps = 8'hc0;
    12'd3478: t_ps = 8'hc0;
    12'd3479: t_ps = 8'hc0;
    12'd3480: t_ps = 8'hc0;
    12'd3481: t_ps = 8'hc0;
    12'd3482: t_ps = 8'hc0;
    12'd3483: t_ps = 8'hc0;
    12'd3484: t_ps = 8'hc0;
    12'd3485: t_ps = 8'hc0;
    12'd3486: t_ps = 8'hc0;
    12'd3487: t_ps = 8'hc0;
    12'd3488: t_ps = 8'hc0;
    12'd3489: t_ps = 8'hc0;
    12'd3490: t_ps = 8'hc0;
    12'd3491: t_ps = 8'hc0;
    12'd3492: t_ps = 8'hc0;
    12'd3493: t_ps = 8'hc0;
    12'd3494: t_ps = 8'hc0;
    12'd3495: t_ps = 8'hc0;
    12'd3496: t_ps = 8'hc0;
    12'd3497: t_ps = 8'hc0;
    12'd3498: t_ps = 8'hc0;
    12'd3499: t_ps = 8'hc0;
    12'd3500: t_ps = 8'hc0;
    12'd3501: t_ps = 8'hc0;
    12'd3502: t_ps = 8'hc0;
    12'd3503: t_ps = 8'hd0;
    12'd3504: t_ps = 8'hc0;
    12'd3505: t_ps = 8'hc0;
    12'd3506: t_ps = 8'hc0;
    12'd3507: t_ps = 8'hc0;
    12'd3508: t_ps = 8'hc0;
    12'd3509: t_ps = 8'hc0;
    12'd3510: t_ps = 8'hc0;
    12'd3511: t_ps = 8'hd0;
    12'd3512: t_ps = 8'hc0;
    12'd3513: t_ps = 8'hc0;
    12'd3514: t_ps = 8'hc0;
    12'd3515: t_ps = 8'hd0;
    12'd3516: t_ps = 8'hc0;
    12'd3517: t_ps = 8'hd0;
    12'd3518: t_ps = 8'hd8;
    12'd3519: t_ps = 8'hdb;
    12'd3520: t_ps = 8'hc0;
    12'd3521: t_ps = 8'hc0;
    12'd3522: t_ps = 8'hc0;
    12'd3523: t_ps = 8'hc0;
    12'd3524: t_ps = 8'hc0;
    12'd3525: t_ps = 8'hc0;
    12'd3526: t_ps = 8'hc0;
    12'd3527: t_ps = 8'hc0;
    12'd3528: t_ps = 8'hc0;
    12'd3529: t_ps = 8'hc0;
    12'd3530: t_ps = 8'hc0;
    12'd3531: t_ps = 8'hc0;
    12'd3532: t_ps = 8'hc0;
    12'd3533: t_ps = 8'hc0;
    12'd3534: t_ps = 8'hc0;
    12'd3535: t_ps = 8'hd8;
    12'd3536: t_ps = 8'hc0;
    12'd3537: t_ps = 8'hc0;
    12'd3538: t_ps = 8'hc0;
    12'd3539: t_ps = 8'hc0;
    12'd3540: t_ps = 8'hc0;
    12'd3541: t_ps = 8'hc0;
    12'd3542: t_ps = 8'hc0;
    12'd3543: t_ps = 8'hd8;
    12'd3544: t_ps = 8'hc0;
    12'd3545: t_ps = 8'hc0;
    12'd3546: t_ps = 8'hc0;
    12'd3547: t_ps = 8'hd8;
    12'd3548: t_ps = 8'hd0;
    12'd3549: t_ps = 8'hd8;
    12'd3550: t_ps = 8'hd8;
    12'd3551: t_ps = 8'hdd;
    12'd3552: t_ps = 8'hc0;
    12'd3553: t_ps = 8'hc0;
    12'd3554: t_ps = 8'hc0;
    12'd3555: t_ps = 8'hd0;
    12'd3556: t_ps = 8'hc0;
    12'd3557: t_ps = 8'hd0;
    12'd3558: t_ps = 8'hd0;
    12'd3559: t_ps = 8'hdc;
    12'd3560: t_ps = 8'hd0;
    12'd3561: t_ps = 8'hd8;
    12'd3562: t_ps = 8'hd8;
    12'd3563: t_ps = 8'hdc;
    12'd3564: t_ps = 8'hd8;
    12'd3565: t_ps = 8'hdc;
    12'd3566: t_ps = 8'hdc;
    12'd3567: t_ps = 8'hde;
    12'd3568: t_ps = 8'hd8;
    12'd3569: t_ps = 8'hdc;
    12'd3570: t_ps = 8'hdc;
    12'd3571: t_ps = 8'hde;
    12'd3572: t_ps = 8'hdc;
    12'd3573: t_ps = 8'hde;
    12'd3574: t_ps = 8'hde;
    12'd3575: t_ps = 8'hdf;
    12'd3576: t_ps = 8'hde;
    12'd3577: t_ps = 8'hdf;
    12'd3578: t_ps = 8'hdf;
    12'd3579: t_ps = 8'hdf;
    12'd3580: t_ps = 8'hdf;
    12'd3581: t_ps = 8'hdf;
    12'd3582: t_ps = 8'hdf;
    12'd3583: t_ps = 8'hdf;
    12'd3584: t_ps = 8'hc0;
    12'd3585: t_ps = 8'hc0;
    12'd3586: t_ps = 8'hc0;
    12'd3587: t_ps = 8'hc0;
    12'd3588: t_ps = 8'hc0;
    12'd3589: t_ps = 8'hc0;
    12'd3590: t_ps = 8'hc0;
    12'd3591: t_ps = 8'hc0;
    12'd3592: t_ps = 8'hc0;
    12'd3593: t_ps = 8'hc0;
    12'd3594: t_ps = 8'hc0;
    12'd3595: t_ps = 8'hc0;
    12'd3596: t_ps = 8'hc0;
    12'd3597: t_ps = 8'hc0;
    12'd3598: t_ps = 8'hc0;
    12'd3599: t_ps = 8'hc0;
    12'd3600: t_ps = 8'hc0;
    12'd3601: t_ps = 8'hc0;
    12'd3602: t_ps = 8'hc0;
    12'd3603: t_ps = 8'hc0;
    12'd3604: t_ps = 8'hc0;
    12'd3605: t_ps = 8'hc0;
    12'd3606: t_ps = 8'hc0;
    12'd3607: t_ps = 8'hc0;
    12'd3608: t_ps = 8'hc0;
    12'd3609: t_ps = 8'hc0;
    12'd3610: t_ps = 8'hc0;
    12'd3611: t_ps = 8'hc0;
    12'd3612: t_ps = 8'hc0;
    12'd3613: t_ps = 8'hc0;
    12'd3614: t_ps = 8'hc0;
    12'd3615: t_ps = 8'hc0;
    12'd3616: t_ps = 8'hc0;
    12'd3617: t_ps = 8'hc0;
    12'd3618: t_ps = 8'hc0;
    12'd3619: t_ps = 8'hc0;
    12'd3620: t_ps = 8'hc0;
    12'd3621: t_ps = 8'hc0;
    12'd3622: t_ps = 8'hc0;
    12'd3623: t_ps = 8'hc0;
    12'd3624: t_ps = 8'hc0;
    12'd3625: t_ps = 8'hc0;
    12'd3626: t_ps = 8'hc0;
    12'd3627: t_ps = 8'hc0;
    12'd3628: t_ps = 8'hc0;
    12'd3629: t_ps = 8'hc0;
    12'd3630: t_ps = 8'hc0;
    12'd3631: t_ps = 8'hc0;
    12'd3632: t_ps = 8'hc0;
    12'd3633: t_ps = 8'hc0;
    12'd3634: t_ps = 8'hc0;
    12'd3635: t_ps = 8'hc0;
    12'd3636: t_ps = 8'hc0;
    12'd3637: t_ps = 8'hc0;
    12'd3638: t_ps = 8'hc0;
    12'd3639: t_ps = 8'hc0;
    12'd3640: t_ps = 8'hc0;
    12'd3641: t_ps = 8'hc0;
    12'd3642: t_ps = 8'hc0;
    12'd3643: t_ps = 8'hc0;
    12'd3644: t_ps = 8'hc0;
    12'd3645: t_ps = 8'hc0;
    12'd3646: t_ps = 8'hc0;
    12'd3647: t_ps = 8'he3;
    12'd3648: t_ps = 8'hc0;
    12'd3649: t_ps = 8'hc0;
    12'd3650: t_ps = 8'hc0;
    12'd3651: t_ps = 8'hc0;
    12'd3652: t_ps = 8'hc0;
    12'd3653: t_ps = 8'hc0;
    12'd3654: t_ps = 8'hc0;
    12'd3655: t_ps = 8'hc0;
    12'd3656: t_ps = 8'hc0;
    12'd3657: t_ps = 8'hc0;
    12'd3658: t_ps = 8'hc0;
    12'd3659: t_ps = 8'hc0;
    12'd3660: t_ps = 8'hc0;
    12'd3661: t_ps = 8'hc0;
    12'd3662: t_ps = 8'hc0;
    12'd3663: t_ps = 8'hc0;
    12'd3664: t_ps = 8'hc0;
    12'd3665: t_ps = 8'hc0;
    12'd3666: t_ps = 8'hc0;
    12'd3667: t_ps = 8'hc0;
    12'd3668: t_ps = 8'hc0;
    12'd3669: t_ps = 8'hc0;
    12'd3670: t_ps = 8'hc0;
    12'd3671: t_ps = 8'he0;
    12'd3672: t_ps = 8'hc0;
    12'd3673: t_ps = 8'hc0;
    12'd3674: t_ps = 8'hc0;
    12'd3675: t_ps = 8'he0;
    12'd3676: t_ps = 8'hc0;
    12'd3677: t_ps = 8'he0;
    12'd3678: t_ps = 8'he0;
    12'd3679: t_ps = 8'he1;
    12'd3680: t_ps = 8'hc0;
    12'd3681: t_ps = 8'hc0;
    12'd3682: t_ps = 8'hc0;
    12'd3683: t_ps = 8'hc0;
    12'd3684: t_ps = 8'hc0;
    12'd3685: t_ps = 8'hc0;
    12'd3686: t_ps = 8'hc0;
    12'd3687: t_ps = 8'he0;
    12'd3688: t_ps = 8'hc0;
    12'd3689: t_ps = 8'hc0;
    12'd3690: t_ps = 8'hc0;
    12'd3691: t_ps = 8'he0;
    12'd3692: t_ps = 8'he0;
    12'd3693: t_ps = 8'he0;
    12'd3694: t_ps = 8'he0;
    12'd3695: t_ps = 8'he0;
    12'd3696: t_ps = 8'hc0;
    12'd3697: t_ps = 8'he0;
    12'd3698: t_ps = 8'he0;
    12'd3699: t_ps = 8'he0;
    12'd3700: t_ps = 8'he0;
    12'd3701: t_ps = 8'he0;
    12'd3702: t_ps = 8'he0;
    12'd3703: t_ps = 8'he0;
    12'd3704: t_ps = 8'he0;
    12'd3705: t_ps = 8'he0;
    12'd3706: t_ps = 8'he0;
    12'd3707: t_ps = 8'he0;
    12'd3708: t_ps = 8'he0;
    12'd3709: t_ps = 8'he1;
    12'd3710: t_ps = 8'he3;
    12'd3711: t_ps = 8'he7;
    12'd3712: t_ps = 8'hc0;
    12'd3713: t_ps = 8'hc0;
    12'd3714: t_ps = 8'hc0;
    12'd3715: t_ps = 8'hc0;
    12'd3716: t_ps = 8'hc0;
    12'd3717: t_ps = 8'hc0;
    12'd3718: t_ps = 8'hc0;
    12'd3719: t_ps = 8'he0;
    12'd3720: t_ps = 8'hc0;
    12'd3721: t_ps = 8'hc0;
    12'd3722: t_ps = 8'hc0;
    12'd3723: t_ps = 8'he0;
    12'd3724: t_ps = 8'hc0;
    12'd3725: t_ps = 8'he0;
    12'd3726: t_ps = 8'he0;
    12'd3727: t_ps = 8'he0;
    12'd3728: t_ps = 8'hc0;
    12'd3729: t_ps = 8'hc0;
    12'd3730: t_ps = 8'hc0;
    12'd3731: t_ps = 8'he0;
    12'd3732: t_ps = 8'hc0;
    12'd3733: t_ps = 8'he0;
    12'd3734: t_ps = 8'he0;
    12'd3735: t_ps = 8'he0;
    12'd3736: t_ps = 8'he0;
    12'd3737: t_ps = 8'he0;
    12'd3738: t_ps = 8'he0;
    12'd3739: t_ps = 8'he0;
    12'd3740: t_ps = 8'he0;
    12'd3741: t_ps = 8'he0;
    12'd3742: t_ps = 8'he0;
    12'd3743: t_ps = 8'he0;
    12'd3744: t_ps = 8'he0;
    12'd3745: t_ps = 8'he0;
    12'd3746: t_ps = 8'he0;
    12'd3747: t_ps = 8'he0;
    12'd3748: t_ps = 8'he0;
    12'd3749: t_ps = 8'he0;
    12'd3750: t_ps = 8'he0;
    12'd3751: t_ps = 8'he0;
    12'd3752: t_ps = 8'he0;
    12'd3753: t_ps = 8'he0;
    12'd3754: t_ps = 8'he0;
    12'd3755: t_ps = 8'he0;
    12'd3756: t_ps = 8'he0;
    12'd3757: t_ps = 8'he0;
    12'd3758: t_ps = 8'he0;
    12'd3759: t_ps = 8'he0;
    12'd3760: t_ps = 8'he0;
    12'd3761: t_ps = 8'he0;
    12'd3762: t_ps = 8'he0;
    12'd3763: t_ps = 8'he0;
    12'd3764: t_ps = 8'he0;
    12'd3765: t_ps = 8'he0;
    12'd3766: t_ps = 8'he0;
    12'd3767: t_ps = 8'he0;
    12'd3768: t_ps = 8'he0;
    12'd3769: t_ps = 8'he0;
    12'd3770: t_ps = 8'he0;
    12'd3771: t_ps = 8'he0;
    12'd3772: t_ps = 8'he0;
    12'd3773: t_ps = 8'he0;
    12'd3774: t_ps = 8'he0;
    12'd3775: t_ps = 8'heb;
    12'd3776: t_ps = 8'he0;
    12'd3777: t_ps = 8'he0;
    12'd3778: t_ps = 8'he0;
    12'd3779: t_ps = 8'he0;
    12'd3780: t_ps = 8'he0;
    12'd3781: t_ps = 8'he0;
    12'd3782: t_ps = 8'he0;
    12'd3783: t_ps = 8'he0;
    12'd3784: t_ps = 8'he0;
    12'd3785: t_ps = 8'he0;
    12'd3786: t_ps = 8'he0;
    12'd3787: t_ps = 8'he0;
    12'd3788: t_ps = 8'he0;
    12'd3789: t_ps = 8'he0;
    12'd3790: t_ps = 8'he0;
    12'd3791: t_ps = 8'he0;
    12'd3792: t_ps = 8'he0;
    12'd3793: t_ps = 8'he0;
    12'd3794: t_ps = 8'he0;
    12'd3795: t_ps = 8'he0;
    12'd3796: t_ps = 8'he0;
    12'd3797: t_ps = 8'he0;
    12'd3798: t_ps = 8'he0;
    12'd3799: t_ps = 8'he0;
    12'd3800: t_ps = 8'he0;
    12'd3801: t_ps = 8'he0;
    12'd3802: t_ps = 8'he0;
    12'd3803: t_ps = 8'he8;
    12'd3804: t_ps = 8'he0;
    12'd3805: t_ps = 8'he8;
    12'd3806: t_ps = 8'he8;
    12'd3807: t_ps = 8'hed;
    12'd3808: t_ps = 8'he0;
    12'd3809: t_ps = 8'he0;
    12'd3810: t_ps = 8'he0;
    12'd3811: t_ps = 8'he0;
    12'd3812: t_ps = 8'he0;
    12'd3813: t_ps = 8'he0;
    12'd3814: t_ps = 8'he0;
    12'd3815: t_ps = 8'hec;
    12'd3816: t_ps = 8'he0;
    12'd3817: t_ps = 8'he0;
    12'd3818: t_ps = 8'he0;
    12'd3819: t_ps = 8'hec;
    12'd3820: t_ps = 8'he8;
    12'd3821: t_ps = 8'hec;
    12'd3822: t_ps = 8'hec;
    12'd3823: t_ps = 8'hee;
    12'd3824: t_ps = 8'he8;
    12'd3825: t_ps = 8'he8;
    12'd3826: t_ps = 8'he8;
    12'd3827: t_ps = 8'hec;
    12'd3828: t_ps = 8'hec;
    12'd3829: t_ps = 8'hee;
    12'd3830: t_ps = 8'hee;
    12'd3831: t_ps = 8'hef;
    12'd3832: t_ps = 8'hec;
    12'd3833: t_ps = 8'hef;
    12'd3834: t_ps = 8'hef;
    12'd3835: t_ps = 8'hef;
    12'd3836: t_ps = 8'hef;
    12'd3837: t_ps = 8'hef;
    12'd3838: t_ps = 8'hef;
    12'd3839: t_ps = 8'hef;
    12'd3840: t_ps = 8'he0;
    12'd3841: t_ps = 8'he0;
    12'd3842: t_ps = 8'he0;
    12'd3843: t_ps = 8'he0;
    12'd3844: t_ps = 8'he0;
    12'd3845: t_ps = 8'he0;
    12'd3846: t_ps = 8'he0;
    12'd3847: t_ps = 8'he0;
    12'd3848: t_ps = 8'he0;
    12'd3849: t_ps = 8'he0;
    12'd3850: t_ps = 8'he0;
    12'd3851: t_ps = 8'he0;
    12'd3852: t_ps = 8'he0;
    12'd3853: t_ps = 8'he0;
    12'd3854: t_ps = 8'he0;
    12'd3855: t_ps = 8'he0;
    12'd3856: t_ps = 8'he0;
    12'd3857: t_ps = 8'he0;
    12'd3858: t_ps = 8'he0;
    12'd3859: t_ps = 8'he0;
    12'd3860: t_ps = 8'he0;
    12'd3861: t_ps = 8'he0;
    12'd3862: t_ps = 8'he0;
    12'd3863: t_ps = 8'he0;
    12'd3864: t_ps = 8'he0;
    12'd3865: t_ps = 8'he0;
    12'd3866: t_ps = 8'he0;
    12'd3867: t_ps = 8'he0;
    12'd3868: t_ps = 8'he0;
    12'd3869: t_ps = 8'he0;
    12'd3870: t_ps = 8'he0;
    12'd3871: t_ps = 8'hf0;
    12'd3872: t_ps = 8'he0;
    12'd3873: t_ps = 8'he0;
    12'd3874: t_ps = 8'he0;
    12'd3875: t_ps = 8'he0;
    12'd3876: t_ps = 8'he0;
    12'd3877: t_ps = 8'he0;
    12'd3878: t_ps = 8'he0;
    12'd3879: t_ps = 8'hf0;
    12'd3880: t_ps = 8'he0;
    12'd3881: t_ps = 8'he0;
    12'd3882: t_ps = 8'he0;
    12'd3883: t_ps = 8'hf0;
    12'd3884: t_ps = 8'he0;
    12'd3885: t_ps = 8'hf0;
    12'd3886: t_ps = 8'hf0;
    12'd3887: t_ps = 8'hf0;
    12'd3888: t_ps = 8'he0;
    12'd3889: t_ps = 8'he0;
    12'd3890: t_ps = 8'he0;
    12'd3891: t_ps = 8'hf0;
    12'd3892: t_ps = 8'hf0;
    12'd3893: t_ps = 8'hf0;
    12'd3894: t_ps = 8'hf0;
    12'd3895: t_ps = 8'hf0;
    12'd3896: t_ps = 8'hf0;
    12'd3897: t_ps = 8'hf0;
    12'd3898: t_ps = 8'hf0;
    12'd3899: t_ps = 8'hf0;
    12'd3900: t_ps = 8'hf0;
    12'd3901: t_ps = 8'hf0;
    12'd3902: t_ps = 8'hf0;
    12'd3903: t_ps = 8'hf3;
    12'd3904: t_ps = 8'he0;
    12'd3905: t_ps = 8'he0;
    12'd3906: t_ps = 8'he0;
    12'd3907: t_ps = 8'hf0;
    12'd3908: t_ps = 8'hf0;
    12'd3909: t_ps = 8'hf0;
    12'd3910: t_ps = 8'hf0;
    12'd3911: t_ps = 8'hf0;
    12'd3912: t_ps = 8'hf0;
    12'd3913: t_ps = 8'hf0;
    12'd3914: t_ps = 8'hf0;
    12'd3915: t_ps = 8'hf0;
    12'd3916: t_ps = 8'hf0;
    12'd3917: t_ps = 8'hf0;
    12'd3918: t_ps = 8'hf0;
    12'd3919: t_ps = 8'hf0;
    12'd3920: t_ps = 8'hf0;
    12'd3921: t_ps = 8'hf0;
    12'd3922: t_ps = 8'hf0;
    12'd3923: t_ps = 8'hf0;
    12'd3924: t_ps = 8'hf0;
    12'd3925: t_ps = 8'hf0;
    12'd3926: t_ps = 8'hf0;
    12'd3927: t_ps = 8'hf0;
    12'd3928: t_ps = 8'hf0;
    12'd3929: t_ps = 8'hf0;
    12'd3930: t_ps = 8'hf0;
    12'd3931: t_ps = 8'hf0;
    12'd3932: t_ps = 8'hf0;
    12'd3933: t_ps = 8'hf0;
    12'd3934: t_ps = 8'hf0;
    12'd3935: t_ps = 8'hf5;
    12'd3936: t_ps = 8'hf0;
    12'd3937: t_ps = 8'hf0;
    12'd3938: t_ps = 8'hf0;
    12'd3939: t_ps = 8'hf0;
    12'd3940: t_ps = 8'hf0;
    12'd3941: t_ps = 8'hf0;
    12'd3942: t_ps = 8'hf0;
    12'd3943: t_ps = 8'hf0;
    12'd3944: t_ps = 8'hf0;
    12'd3945: t_ps = 8'hf0;
    12'd3946: t_ps = 8'hf0;
    12'd3947: t_ps = 8'hf0;
    12'd3948: t_ps = 8'hf0;
    12'd3949: t_ps = 8'hf4;
    12'd3950: t_ps = 8'hf4;
    12'd3951: t_ps = 8'hf6;
    12'd3952: t_ps = 8'hf0;
    12'd3953: t_ps = 8'hf0;
    12'd3954: t_ps = 8'hf0;
    12'd3955: t_ps = 8'hf4;
    12'd3956: t_ps = 8'hf0;
    12'd3957: t_ps = 8'hf4;
    12'd3958: t_ps = 8'hf6;
    12'd3959: t_ps = 8'hf7;
    12'd3960: t_ps = 8'hf4;
    12'd3961: t_ps = 8'hf6;
    12'd3962: t_ps = 8'hf6;
    12'd3963: t_ps = 8'hf7;
    12'd3964: t_ps = 8'hf7;
    12'd3965: t_ps = 8'hf7;
    12'd3966: t_ps = 8'hf7;
    12'd3967: t_ps = 8'hf7;
    12'd3968: t_ps = 8'hf0;
    12'd3969: t_ps = 8'hf0;
    12'd3970: t_ps = 8'hf0;
    12'd3971: t_ps = 8'hf0;
    12'd3972: t_ps = 8'hf0;
    12'd3973: t_ps = 8'hf0;
    12'd3974: t_ps = 8'hf0;
    12'd3975: t_ps = 8'hf8;
    12'd3976: t_ps = 8'hf0;
    12'd3977: t_ps = 8'hf0;
    12'd3978: t_ps = 8'hf0;
    12'd3979: t_ps = 8'hf0;
    12'd3980: t_ps = 8'hf0;
    12'd3981: t_ps = 8'hf8;
    12'd3982: t_ps = 8'hf8;
    12'd3983: t_ps = 8'hf8;
    12'd3984: t_ps = 8'hf0;
    12'd3985: t_ps = 8'hf0;
    12'd3986: t_ps = 8'hf0;
    12'd3987: t_ps = 8'hf8;
    12'd3988: t_ps = 8'hf0;
    12'd3989: t_ps = 8'hf8;
    12'd3990: t_ps = 8'hf8;
    12'd3991: t_ps = 8'hf8;
    12'd3992: t_ps = 8'hf8;
    12'd3993: t_ps = 8'hf8;
    12'd3994: t_ps = 8'hf8;
    12'd3995: t_ps = 8'hf8;
    12'd3996: t_ps = 8'hf8;
    12'd3997: t_ps = 8'hf8;
    12'd3998: t_ps = 8'hf8;
    12'd3999: t_ps = 8'hf9;
    12'd4000: t_ps = 8'hf8;
    12'd4001: t_ps = 8'hf8;
    12'd4002: t_ps = 8'hf8;
    12'd4003: t_ps = 8'hf8;
    12'd4004: t_ps = 8'hf8;
    12'd4005: t_ps = 8'hf8;
    12'd4006: t_ps = 8'hf8;
    12'd4007: t_ps = 8'hf8;
    12'd4008: t_ps = 8'hf8;
    12'd4009: t_ps = 8'hf8;
    12'd4010: t_ps = 8'hf8;
    12'd4011: t_ps = 8'hf8;
    12'd4012: t_ps = 8'hf8;
    12'd4013: t_ps = 8'hf8;
    12'd4014: t_ps = 8'hf8;
    12'd4015: t_ps = 8'hfa;
    12'd4016: t_ps = 8'hf8;
    12'd4017: t_ps = 8'hf8;
    12'd4018: t_ps = 8'hf8;
    12'd4019: t_ps = 8'hf8;
    12'd4020: t_ps = 8'hf8;
    12'd4021: t_ps = 8'hf8;
    12'd4022: t_ps = 8'hf8;
    12'd4023: t_ps = 8'hfb;
    12'd4024: t_ps = 8'hf8;
    12'd4025: t_ps = 8'hfa;
    12'd4026: t_ps = 8'hfa;
    12'd4027: t_ps = 8'hfb;
    12'd4028: t_ps = 8'hfb;
    12'd4029: t_ps = 8'hfb;
    12'd4030: t_ps = 8'hfb;
    12'd4031: t_ps = 8'hfb;
    12'd4032: t_ps = 8'hf8;
    12'd4033: t_ps = 8'hf8;
    12'd4034: t_ps = 8'hf8;
    12'd4035: t_ps = 8'hfc;
    12'd4036: t_ps = 8'hf8;
    12'd4037: t_ps = 8'hfc;
    12'd4038: t_ps = 8'hfc;
    12'd4039: t_ps = 8'hfc;
    12'd4040: t_ps = 8'hfc;
    12'd4041: t_ps = 8'hfc;
    12'd4042: t_ps = 8'hfc;
    12'd4043: t_ps = 8'hfc;
    12'd4044: t_ps = 8'hfc;
    12'd4045: t_ps = 8'hfc;
    12'd4046: t_ps = 8'hfc;
    12'd4047: t_ps = 8'hfc;
    12'd4048: t_ps = 8'hfc;
    12'd4049: t_ps = 8'hfc;
    12'd4050: t_ps = 8'hfc;
    12'd4051: t_ps = 8'hfc;
    12'd4052: t_ps = 8'hfc;
    12'd4053: t_ps = 8'hfc;
    12'd4054: t_ps = 8'hfc;
    12'd4055: t_ps = 8'hfd;
    12'd4056: t_ps = 8'hfc;
    12'd4057: t_ps = 8'hfc;
    12'd4058: t_ps = 8'hfc;
    12'd4059: t_ps = 8'hfd;
    12'd4060: t_ps = 8'hfd;
    12'd4061: t_ps = 8'hfd;
    12'd4062: t_ps = 8'hfd;
    12'd4063: t_ps = 8'hfd;
    12'd4064: t_ps = 8'hfc;
    12'd4065: t_ps = 8'hfc;
    12'd4066: t_ps = 8'hfe;
    12'd4067: t_ps = 8'hfe;
    12'd4068: t_ps = 8'hfe;
    12'd4069: t_ps = 8'hfe;
    12'd4070: t_ps = 8'hfe;
    12'd4071: t_ps = 8'hfe;
    12'd4072: t_ps = 8'hfe;
    12'd4073: t_ps = 8'hfe;
    12'd4074: t_ps = 8'hfe;
    12'd4075: t_ps = 8'hfe;
    12'd4076: t_ps = 8'hfe;
    12'd4077: t_ps = 8'hfe;
    12'd4078: t_ps = 8'hfe;
    12'd4079: t_ps = 8'hfe;
    12'd4080: t_ps = 8'hff;
    12'd4081: t_ps = 8'hff;
    12'd4082: t_ps = 8'hff;
    12'd4083: t_ps = 8'hff;
    12'd4084: t_ps = 8'hff;
    12'd4085: t_ps = 8'hff;
    12'd4086: t_ps = 8'hff;
    12'd4087: t_ps = 8'hff;
    12'd4088: t_ps = 8'hff;
    12'd4089: t_ps = 8'hff;
    12'd4090: t_ps = 8'hff;
    12'd4091: t_ps = 8'hff;
    12'd4092: t_ps = 8'hff;
    12'd4093: t_ps = 8'hff;
    12'd4094: t_ps = 8'hff;
    12'd4095: t_ps = 8'hff;
    default: t_ps = 8'h00;
  endcase
endfunction
always @(posedge clock) begin
  p_t_out <= t_pt(acc_t[10:0]);
  ps__out <= t_ps(acc_t);
  _st_out <= {
		((acc_t & 'he7e) == 'he7e) | ((acc_t & 'he80) == 'he80) | ((acc_t & 'hf00) == 'hf00) | ((acc_t & 'he7d) == 'he7d),
		((acc_t & 'h7f8) == 'h7f8) | ((acc_t & 'hf00) == 'hf00),
		((acc_t & 'h7e0) == 'h7e0) | ((acc_t & 'hf0f) == 'hf0f) | ((acc_t & 'hf1b) == 'hf1b) | ((acc_t & 'hbfe) == 'hbfe) | ((acc_t & 'hf1e) == 'hf1e) | ((acc_t & 'hf40) == 'hf40) | ((acc_t & 'hf30) == 'hf30) | ((acc_t & 'hf29) == 'hf29) | ((acc_t & 'hf26) == 'hf26) | ((acc_t & 'hf80) == 'hf80),
		((acc_t & 'h7e0) == 'h7e0) | ((acc_t & 'h3f0) == 'h3f0) | ((acc_t & 'hdfe) == 'hdfe) | ((acc_t & 'h5ff) == 'h5ff) | ((acc_t & 'hf80) == 'hf80),
		((acc_t & 'h7e0) == 'h7e0) | ((acc_t & 'h3f0) == 'h3f0) | ((acc_t & 'hfc0) == 'hfc0) | ((acc_t & 'h1f8) == 'h1f8) | ((acc_t & 'heff) == 'heff),
		((acc_t & 'h0fc) == 'h0fc) | ((acc_t & 'h1f8) == 'h1f8) | ((acc_t & 'h3f0) == 'h3f0) | ((acc_t & 'hfe0) == 'hfe0),
		((acc_t & 'h07e) == 'h07e) | ((acc_t & 'hff0) == 'hff0) | ((acc_t & 'h7f7) == 'h7f7) | ((acc_t & 'h1f8) == 'h1f8) | ((acc_t & 'h0fc) == 'h0fc),
		((acc_t & 'hdbf) == 'hdbf) | ((acc_t & 'h0fc) == 'h0fc) | ((acc_t & 'h3fa) == 'h3fa) | ((acc_t & 'h7f8) == 'h7f8) | ((acc_t & 'h3bf) == 'h3bf) | ((acc_t & 'h07e) == 'h07e)
	};
  pst_out <= {
		((acc_t & 'he89) == 'he89) | ((acc_t & 'he3e) == 'he3e) | ((acc_t & 'hec0) == 'hec0) | ((acc_t & 'he8a) == 'he8a) | ((acc_t & 'hdf7) == 'hdf7) | ((acc_t & 'hdf8) == 'hdf8) | ((acc_t & 'he85) == 'he85) | ((acc_t & 'he6a) == 'he6a) | ((acc_t & 'he90) == 'he90) | ((acc_t & 'he83) == 'he83) | ((acc_t & 'he67) == 'he67) | ((acc_t & 'hea0) == 'hea0) | ((acc_t & 'hf00) == 'hf00) | ((acc_t & 'he5e) == 'he5e) | ((acc_t & 'he70) == 'he70) | ((acc_t & 'he6c) == 'he6c),
		((acc_t & 'heee) == 'heee) | ((acc_t & 'h7ef) == 'h7ef) | ((acc_t & 'h7f2) == 'h7f2) | ((acc_t & 'h7f4) == 'h7f4) | ((acc_t & 'hef0) == 'hef0) | ((acc_t & 'h7f8) == 'h7f8) | ((acc_t & 'hf00) == 'hf00) | ((acc_t & 'h7f1) == 'h7f1),
		((acc_t & 'hf78) == 'hf78) | ((acc_t & 'h7f0) == 'h7f0) | ((acc_t & 'h7ee) == 'h7ee) | ((acc_t & 'hf74) == 'hf74) | ((acc_t & 'hf6f) == 'hf6f) | ((acc_t & 'hf80) == 'hf80) | ((acc_t & 'hbff) == 'hbff),
		((acc_t & 'hdff) == 'hdff) | ((acc_t & 'hbfe) == 'hbfe) | ((acc_t & 'h7ef) == 'h7ef) | ((acc_t & 'h7f2) == 'h7f2) | ((acc_t & 'h3ff) == 'h3ff) | ((acc_t & 'h7f4) == 'h7f4) | ((acc_t & 'hfc0) == 'hfc0) | ((acc_t & 'hfb8) == 'hfb8) | ((acc_t & 'h7f8) == 'h7f8) | ((acc_t & 'hfb6) == 'hfb6),
		((acc_t & 'hbfe) == 'hbfe) | ((acc_t & 'hfdc) == 'hfdc) | ((acc_t & 'hdfe) == 'hdfe) | ((acc_t & 'h7f7) == 'h7f7) | ((acc_t & 'hfda) == 'hfda) | ((acc_t & 'hbfd) == 'hbfd) | ((acc_t & 'h7f8) == 'h7f8) | ((acc_t & 'h3ff) == 'h3ff) | ((acc_t & 'hfe0) == 'hfe0) | ((acc_t & 'heff) == 'heff),
		((acc_t & 'hfeb) == 'hfeb) | ((acc_t & 'h7fa) == 'h7fa) | ((acc_t & 'hbfe) == 'hbfe) | ((acc_t & 'hdfe) == 'hdfe) | ((acc_t & 'hff0) == 'hff0) | ((acc_t & 'h7fc) == 'h7fc) | ((acc_t & 'h3ff) == 'h3ff) | ((acc_t & 'hfec) == 'hfec) | ((acc_t & 'heff) == 'heff),
		((acc_t & 'hff6) == 'hff6) | ((acc_t & 'hdff) == 'hdff) | ((acc_t & 'hf7f) == 'hf7f) | ((acc_t & 'hbfe) == 'hbfe) | ((acc_t & 'h7fc) == 'h7fc) | ((acc_t & 'hff5) == 'hff5) | ((acc_t & 'h3ff) == 'h3ff) | ((acc_t & 'hff8) == 'hff8) | ((acc_t & 'heff) == 'heff),
		((acc_t & 'hdff) == 'hdff) | ((acc_t & 'hf7f) == 'hf7f) | ((acc_t & 'hffa) == 'hffa) | ((acc_t & 'h7fe) == 'h7fe) | ((acc_t & 'hff9) == 'hff9) | ((acc_t & 'hffc) == 'hffc) | ((acc_t & 'h3ff) == 'h3ff) | ((acc_t & 'heff) == 'heff)
	};
end
assign F0 = {3'b000, Fc, 2'b00} + Fc;
endmodule
