-- hdmi_tx.vhd: a entidade hdmi_tx do Timmy (as mesmas portas de sempre, o top.vhd nao muda); por dentro e'
--   o HDMI da hdl-util (hdmi_hdlutil.v, gerado com o sv2v a partir de hdmi_hdlutil.sv e hdl-util/*.sv).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdmi_tx is
  generic (
    FREQ     : integer := 27000000;
    VIC      : integer := 17;
    LARGO    : boolean := false;        -- (a hdl-util manda o AVI sem proporcao; fica a do VIC)
    SYNC_POS : boolean := false
  );
  port (
    clk      : in  std_logic;
    r, g, b  : in  std_logic_vector(7 downto 0);
    de, hs, vs : in std_logic;
    aud_l, aud_r : in std_logic_vector(15 downto 0);
    aud_tog  : in  std_logic;
    q0, q1, q2 : out std_logic_vector(9 downto 0)
  );
end entity;

architecture rtl of hdmi_tx is
  function sel(v17, v19, v1 : integer) return integer is
  begin
    if VIC = 19 then return v19; elsif VIC = 1 then return v1; else return v17; end if;
  end function;

  component hdmi_hdlutil
    generic (SCREEN_W, FRAME_W, SCREEN_H, FRAME_H, CEA, VIDEO_RATE, AUDIO_RATE, AUDIO_BIT_WIDTH : integer);
    port (
      clk_pixel : in std_logic;
      r, g, b   : in std_logic_vector(7 downto 0);
      de, hs, vs : in std_logic;
      aud_l, aud_r : in std_logic_vector(15 downto 0);
      aud_tog   : in std_logic;
      q0, q1, q2 : out std_logic_vector(9 downto 0)
    );
  end component;
begin
  h: hdmi_hdlutil
    generic map (SCREEN_W => sel(720, 1280, 640), FRAME_W => sel(864, 1980, 800),
                 SCREEN_H => sel(576, 720, 480),  FRAME_H => sel(625, 750, 525),
                 CEA => VIC, VIDEO_RATE => FREQ, AUDIO_RATE => 48000, AUDIO_BIT_WIDTH => 16)
    port map (clk_pixel => clk, r => r, g => g, b => b, de => de, hs => hs, vs => vs,
              aud_l => aud_l, aud_r => aud_r, aud_tog => aud_tog, q0 => q0, q1 => q1, q2 => q2);
end architecture;
