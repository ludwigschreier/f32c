--
-- Copyright (c) 2015 Davor Jadrijevic
-- All rights reserved.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions
-- are met:
-- 1. Redistributions of source code must retain the above copyright
--    notice, this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
--
-- THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
-- ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
-- FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
-- DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
-- OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
-- HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
-- LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
-- OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
-- SUCH DAMAGE.
--
-- $Id$
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

use work.f32c_pack.all;

entity de10lite_xram is
    generic (
	-- ISA: either ARCH_MI32 or ARCH_RV32
	C_arch: integer := ARCH_MI32;
	C_debug: boolean := false;

	-- Main clock: 25/50/75/83/100 MHz (works up to 75 MHz)
	C_clk_freq: integer := 75;

	-- SoC configuration options
	C_bram_size: integer := 1;
	C_boot_write_protect: boolean := false;
        C_icache_size: integer := 0;
        C_dcache_size: integer := 0;
        C_acram: boolean := true;

        C_hdmi_out: boolean := false;
        C_dvid_ddr: boolean := false;

        C_vgahdmi: boolean := true; -- simple VGA bitmap with compositing
        C_vgahdmi_cache_size: integer := 0; -- KB (0 to disable, 2,4,8,16,32 to enable)
        -- normally this should be  actual bits per pixel
        C_vgahdmi_fifo_data_width: integer range 8 to 32 := 8;
        -- width of FIFO address space -> size of fifo
        -- for 8bpp compositing use 11 -> 2048 bytes

	C_sio: integer := 1;
	C_gpio: integer := 32;
	C_simple_io: boolean := true
    );
    port (
	max10_clk1_50, max10_clk2_50: in std_logic;
	--rs232_txd: out std_logic;
	--rs232_rxd: in std_logic;
	sw: in std_logic_vector(9 downto 0);
	ledr: out std_logic_vector(9 downto 0);
	hex0, hex1, hex2, hex3, hex4, hex5: out std_logic_vector(7 downto 0);
	arduino_io: inout std_logic_vector(15 downto 0);
	gpio: inout std_logic_vector(35 downto 0);
        vga_hs, vga_vs: out std_logic;
        vga_r, vga_g, vga_b: out std_logic_vector(3 downto 0);
	--hdmi_d: out std_logic_vector(2 downto 0);
	--hdmi_clk: out std_logic;
	key: in std_logic_vector(1 downto 0)
    );
end;

architecture Behavioral of de10lite_xram is
  signal clk: std_logic;
  signal clk_pixel, clk_pixel_shift: std_logic;
  signal ram_en             : std_logic;
  signal ram_byte_we        : std_logic_vector(3 downto 0) := (others => '0');
  signal ram_address        : std_logic_vector(31 downto 0) := (others => '0');
  signal ram_data_write     : std_logic_vector(31 downto 0) := (others => '0');
  signal ram_data_read      : std_logic_vector(31 downto 0) := (others => '0');
  signal ram_ready          : std_logic := '1';
  signal S_hdmi_pd0, S_hdmi_pd1, S_hdmi_pd2: std_logic_vector(9 downto 0);
  signal tx_in: std_logic_vector(29 downto 0);
  signal tmds_d: std_logic_vector(3 downto 0);
begin
    G_25m_clk: if C_clk_freq = 25 generate
    clkgen_25: entity work.clk_50M_25M_125MP_125MN_100M_83M33
    port map(
      inclk0 => max10_clk1_50, --  50 MHz input from board
      inclk1 => max10_clk2_50, --  50 MHz input from board (backup clock)
      c0 => clk,               --  25 MHz
      c1 => open,              -- 125 MHz positive
      c2 => open,              -- 125 MHz negative
      c3 => open,              -- 100 MHz
      c4 => open               --  83.333 MHz
    );
    end generate;

    G_50m_clk: if C_clk_freq = 50 generate
    clk <= max10_clk1_50;
    clkgen_50: entity work.clk_50M_25M_125MP_125MN_100M_83M33
    port map(
      inclk0 => max10_clk1_50, --  50 MHz input from board
      inclk1 => max10_clk2_50, --  50 MHz input from board (backup clock)
      c0 => clk_pixel,         --  25 MHz
      c1 => open,              -- 125 MHz positive
      c2 => open,              -- 125 MHz negative
      c3 => open,              -- 100 MHz
      c4 => open               --  83.333 MHz
    );
    end generate;

    G_75M_clk: if C_clk_freq = 75 generate
    clkgen_75: entity work.clk_50M_25M_250M_75M
    port map(
      inclk0 => max10_clk1_50, --  50 MHz input from board
      inclk1 => max10_clk2_50, --  50 MHz input from board (backup clock)
      c0 => clk_pixel,         --  25 MHz
      c1 => open,              -- 250 MHz
      c2 => clk                --  75 MHz
    );
    end generate;

    G_83m_clk: if C_clk_freq = 83 generate
    clkgen_83: entity work.clk_50M_25M_125MP_125MN_100M_83M33
    port map(
      inclk0 => max10_clk1_50, --  50 MHz input from board
      inclk1 => max10_clk2_50, --  50 MHz input from board (backup clock)
      c0 => open,              --  25 MHz
      c1 => open,              -- 125 MHz positive
      c2 => open,              -- 125 MHz negative
      c3 => open,              -- 100 MHz
      c4 => clk                --  83.333 MHz
    );
    end generate;

    G_100m_clk: if C_clk_freq = 100 generate
    clkgen_100: entity work.clk_50M_25M_125MP_125MN_100M_83M33
    port map(
      inclk0 => max10_clk1_50, --  50 MHz input from board
      inclk1 => max10_clk2_50, --  50 MHz input from board (backup clock)
      c0 => open,              --  25 MHz
      c1 => open,              -- 125 MHz positive
      c2 => open,              -- 125 MHz negative
      c3 => clk,               -- 100 MHz
      c4 => open               --  83.333 MHz
    );
    end generate;

    -- generic XRAM glue
    glue_xram: entity work.glue_xram
    generic map (
      C_arch => C_arch,
      C_clk_freq => C_clk_freq,
      C_bram_size => C_bram_size,
      C_boot_write_protect => C_boot_write_protect,
      C_icache_size => C_icache_size,
      C_dcache_size => C_dcache_size,
      C_acram => C_acram,
      -- vga simple bitmap
      C_dvid_ddr => C_dvid_ddr,
      C_vgahdmi => C_vgahdmi,
      C_vgahdmi_cache_size => C_vgahdmi_cache_size,
      C_vgahdmi_fifo_data_width => C_vgahdmi_fifo_data_width,
      C_debug => C_debug
    )
    port map (
      clk => clk,
      clk_pixel => clk_pixel,
      clk_pixel_shift => clk_pixel_shift,
      sio_txd(0) => arduino_io(10), sio_rxd(0) => arduino_io(11),
      spi_sck => open, spi_ss => open, spi_mosi => open, spi_miso => "",
      acram_en => ram_en,
      acram_addr(29 downto 2) => ram_address(29 downto 2),
      acram_byte_we(3 downto 0) => ram_byte_we(3 downto 0),
      acram_data_rd(31 downto 0) => ram_data_read(31 downto 0),
      acram_data_wr(31 downto 0) => ram_data_write(31 downto 0),
      acram_ready => ram_ready,
      -- ***** VGA *****
      vga_vsync => vga_vs,
      vga_hsync => vga_hs,
      vga_r(7 downto 4) => vga_r(3 downto 0),
      vga_r(3 downto 0) => open,
      vga_g(7 downto 4) => vga_g(3 downto 0),
      vga_g(3 downto 0) => open,
      vga_b(7 downto 4) => vga_b(3 downto 0),
      vga_b(3 downto 0) => open,
      -- ***** HDMI *****
      --dvi_r => S_hdmi_pd2, dvi_g => S_hdmi_pd1, dvi_b => S_hdmi_pd0,
      --gpio(35 downto 0) => gpio(35 downto 0), gpio(127 downto 36) => open,
      simple_out(9 downto 0) => ledr(9 downto 0),
      simple_out(10) => hex0(7),
      simple_out(11) => hex1(7),
      simple_out(12) => hex2(7),
      simple_out(13) => hex3(7),
      simple_out(14) => hex4(7),
      simple_out(15) => hex5(7),
      simple_out(31 downto 16) => open,
      simple_in(9 downto 0) => sw(9 downto 0), simple_in(31 downto 9) => open
    );

    acram_emulation: entity work.acram_emu
    generic map
    (
      C_addr_width => 15
    )
    port map
    (
      clk => clk,
      acram_a => ram_address(16 downto 2),
      acram_d_wr => ram_data_write,
      acram_d_rd => ram_data_read,
      acram_byte_we => ram_byte_we,
      acram_en => ram_en
    );

    -- generic "differential" output buffering for HDMI clock and video
    --hdmi_output1: entity work.hdmi_out
    --  port map
    --  (
    --    tmds_in_rgb    => tmds_rgb,
    --    tmds_out_rgb_p => hdmi_dp,   -- D2+ red  D1+ green  D0+ blue
    --    tmds_out_rgb_n => hdmi_dn,   -- D2- red  D1- green  D0+ blue
    --    tmds_in_clk    => tmds_clk,
    --    tmds_out_clk_p => hdmi_clkp, -- CLK+ clock
    --    tmds_out_clk_n => hdmi_clkn  -- CLK- clock
    --  );

    -- true differential, vendor-specific
    -- tx_in <= S_HDMI_PD2 & S_HDMI_PD1 & S_HDMI_PD0; -- this would be normal bit order, but
    -- generic serializer follows vendor specific serializer style
    --tx_in <=  S_HDMI_PD2(0) & S_HDMI_PD2(1) & S_HDMI_PD2(2) & S_HDMI_PD2(3) & S_HDMI_PD2(4) & S_HDMI_PD2(5) & S_HDMI_PD2(6) & S_HDMI_PD2(7) & S_HDMI_PD2(8) & S_HDMI_PD2(9) &
    --          S_HDMI_PD1(0) & S_HDMI_PD1(1) & S_HDMI_PD1(2) & S_HDMI_PD1(3) & S_HDMI_PD1(4) & S_HDMI_PD1(5) & S_HDMI_PD1(6) & S_HDMI_PD1(7) & S_HDMI_PD1(8) & S_HDMI_PD1(9) &
    --          S_HDMI_PD0(0) & S_HDMI_PD0(1) & S_HDMI_PD0(2) & S_HDMI_PD0(3) & S_HDMI_PD0(4) & S_HDMI_PD0(5) & S_HDMI_PD0(6) & S_HDMI_PD0(7) & S_HDMI_PD0(8) & S_HDMI_PD0(9);

    --vendorspec_serializer_inst: entity work.serializer
    --PORT MAP
    --(
    --    tx_in => tx_in,
    --    tx_inclock => CLK_PIXEL_SHIFT, -- NOTE: vendor-specific serializer needs CLK_PIXEL x5
    --    tx_syncclock => CLK_PIXEL,
    --    tx_out => tmds_d(2 downto 0)
    --);
    --hdmi_clk <= CLK_PIXEL;
    --hdmi_d   <= tmds_d(2 downto 0);

end Behavioral;
