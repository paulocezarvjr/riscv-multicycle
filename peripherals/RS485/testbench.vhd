library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.decoder_types.all;             -- @suppress 

entity RS485_testbench is
    generic(
        --! Num of 32-bits memory words
        IMEMORY_WORDS : integer := 1024; --!= 4K (1024 * 4) bytes
        DMEMORY_WORDS : integer := 1024 --!= 2k (512 * 2) bytes
    );

    port(
        ----------- SEG7 ------------
        HEX0 : out std_logic_vector(7 downto 0);
        HEX1 : out std_logic_vector(7 downto 0);
        HEX2 : out std_logic_vector(7 downto 0);
        HEX3 : out std_logic_vector(7 downto 0);
        HEX4 : out std_logic_vector(7 downto 0);
        HEX5 : out std_logic_vector(7 downto 0);
        ----------- SW ------------
        LEDR : out std_logic_vector(9 downto 0) -- @suppress 
    );

end entity RS485_testbench;

architecture RTL of RS485_testbench is
    -- Clocks and reset
    signal clk      : std_logic;
    signal clk_32x  : std_logic;
    signal clk_baud : std_logic;
    signal rst      : std_logic;

    -- Instruction bus and instruction memory
    signal address  : std_logic_vector(9 downto 0);
    signal iaddress : unsigned(15 downto 0);
    signal idata    : std_logic_vector(31 downto 0);

    -- Data bus
    signal daddress    : unsigned(31 downto 0);
    signal ddata_r     : std_logic_vector(31 downto 0);
    signal ddata_w     : std_logic_vector(31 downto 0);
    signal dmask       : std_logic_vector(3 downto 0);
    signal dcsel       : std_logic_vector(1 downto 0);
    signal d_we        : std_logic := '0';
    signal ddata_r_mem : std_logic_vector(31 downto 0);
    signal d_rd        : std_logic;
    signal d_sig       : std_logic;

    -- Modelsim debug signals
    signal cpu_state   : cpu_state_t;   -- @suppress 
    signal debugString : string(1 to 40) := (others => '0');

    -- I/O signals
    signal interrupts   : std_logic_vector(31 downto 0);
    signal ddata_r_gpio : std_logic_vector(31 downto 0);
    signal gpio_input   : std_logic_vector(31 downto 0);
    signal gpio_output  : std_logic_vector(31 downto 0);

    -- signal ddata_r_timer   : std_logic_vector(31 downto 0);
    signal timer_interrupt : std_logic_vector(5 downto 0); -- @suppress
    signal ddata_r_periph  : std_logic_vector(31 downto 0);
    signal ddata_r_sdram   : std_logic_vector(31 downto 0);

    signal gpio_interrupts  : std_logic_vector(6 downto 0);
    signal ddata_r_segments : std_logic_vector(31 downto 0);
    signal ddata_r_RS485    : std_logic_vector(31 downto 0); -- adicionando sinal do novo io do mux

    signal TX              : std_logic; -- @suppress "Signal TX is never read"
    signal RX              : std_logic;
    signal uart_interrupts : std_logic_vector(1 downto 0);

    signal rs485_dir_DE_tb : std_logic; -- @suppress "Signal rs485_dir_DE_tb is never read"

    -- UART testbench
    signal transmit_byte  : std_logic_vector(7 downto 0) := x"00";
    signal transmit_frame : std_logic_vector(9 downto 0) := (others => '1');
    signal clk_state      : boolean                      := FALSE;

begin

    clock_driver : process
        constant period : time := 1000 ns;
    begin
        clk <= '0';
        wait for period / 2;
        clk <= '1';
        wait for period / 2;
    end process clock_driver;

    --! Division unit clock
    clock_driver_32x : process
        constant period : time := 20 ns;
    begin
        clk_32x <= '0';
        wait for period / 2;
        clk_32x <= '1';
        wait for period / 2;
    end process clock_driver_32x;

    clock_baud : process
        constant period : time := 26041 ns;
    begin
        clk_baud <= '0';
        wait for period / 2;
        clk_baud <= '1';
        wait for period / 2;
    end process clock_baud;

    clock_baud_9600 : process
        constant period : time := 104 us;
    begin
        clk_state <= FALSE;
        wait for period / 2;
        clk_state <= TRUE;
        wait for period / 2;
    end process clock_baud_9600;

    reset : process is
    begin
        rst <= '1';
        wait for 150 ns;
        rst <= '0';
        wait;
    end process reset;

    -- IMem shoud be read from instruction and data buses
    -- Not enough RAM ports for instruction bus, data bus and in-circuit programming
    instr_mux : entity work.instructionbusmux -- @suppress 
        port map(
            d_rd     => d_rd,
            dcsel    => dcsel,
            daddress => daddress,
            iaddress => iaddress,
            address  => address
        );

    -- 32-bits x 1024 words quartus RAM (dual port: portA -> riscV, portB -> In-System Mem Editor
    iram_quartus_inst : entity work.iram_quartus -- @suppress 
        port map(
            address => address(9 downto 0),
            byteena => "1111",
            clock   => clk,
            data    => (others => '0'),
            wren    => '0',
            q       => idata
        );

    -- dmemory_address <= daddress;
    -- Data Memory RAM
    dmem : entity work.dmemory          -- @suppress 
        generic map(
            MEMORY_WORDS => DMEMORY_WORDS
        )
        port map(
            rst        => rst,
            clk        => clk,
            data       => ddata_w,
            address    => daddress,
            we         => d_we,
            signal_ext => d_sig,
            csel       => dcsel(0),
            dmask      => dmask,
            q          => ddata_r_mem
        );

    -- Adress space mux ((check sections.ld) -> Data chip select:
    -- 0x00000    ->    Instruction memory
    -- 0x20000    ->    Data memory
    -- 0x40000    ->    Input/Output generic address space
    -- 0x60000    ->    SDRAM address space
    data_bus_mux : entity work.databusmux -- @suppress 
        port map(
            dcsel          => dcsel,
            idata          => idata,
            ddata_r_mem    => ddata_r_mem,
            ddata_r_periph => ddata_r_periph,
            ddata_r_sdram  => ddata_r_sdram,
            ddata_r        => ddata_r
        );

    io_data_bus_mux : entity work.iodatabusmux -- @suppress 
        port map(
            daddress               => daddress,
            ddata_r_gpio           => ddata_r_gpio,
            ddata_r_segments       => ddata_r_segments,
            ddata_r_uart           => (others => '0'),
            ddata_r_adc            => (others => '0'),
            ddata_r_i2c            => (others => '0'),
            ddata_r_timer          => (others => '0'),
            ddata_r_dif_fil        => (others => '0'),
            ddata_r_stepmot        => (others => '0'),
            ddata_r_lcd            => (others => '0'),
            ddata_r_fir_fil        => (others => '0'),
            ddata_r_nn_accelerator => (others => '0'),
            ddata_r_spwm           => (others => '0'),
            ddata_r_crc            => (others => '0'),
            ddata_r_key            => (others => '0'),
            ddata_r_accelerometer  => (others => '0'),
            ddata_r_RS485          => ddata_r_RS485, -- adicionando novo io do mux
            ddata_r_periph         => ddata_r_periph
        );

    -- Softcore instatiation
    myRiscv : entity work.core          -- @suppress 
        port map(
            clk        => clk,
            rst        => rst,
            clk_32x    => clk_32x,
            iaddress   => iaddress,
            idata      => idata,
            daddress   => daddress,
            ddata_r    => ddata_r,
            ddata_w    => ddata_w,
            d_we       => d_we,
            d_rd       => d_rd,
            d_sig      => d_sig,
            dcsel      => dcsel,
            dmask      => dmask,
            interrupts => interrupts,
            state      => cpu_state
        );

    -- Group IRQ signals.
    irq_signals : process(timer_interrupt, gpio_interrupts, uart_interrupts)
    begin
        interrupts               <= (others => '0');
        interrupts(24 downto 18) <= gpio_interrupts(6 downto 0);
        interrupts(30 downto 25) <= timer_interrupt;
        interrupts(31)           <= uart_interrupts(0);
    end process;

    -- Generic GPIO module instantiation
    generic_gpio : entity work.gpio     -- @suppress 
        port map(
            clk             => clk,
            rst             => rst,
            daddress        => daddress,
            ddata_w         => ddata_w,
            ddata_r         => ddata_r_gpio,
            d_we            => d_we,
            d_rd            => d_rd,
            dcsel           => dcsel,
            dmask           => dmask,
            input           => gpio_input,
            output          => gpio_output,
            gpio_interrupts => gpio_interrupts
        );

    generic_displays : entity work.led_displays -- @suppress 
        port map(
            clk      => clk,
            rst      => rst,
            daddress => daddress,
            ddata_w  => ddata_w,
            ddata_r  => ddata_r_segments,
            d_we     => d_we,
            d_rd     => d_rd,
            dcsel    => dcsel,
            dmask    => dmask,
            hex0     => HEX0,
            hex1     => HEX1,
            hex2     => HEX2,
            hex3     => HEX3,
            hex4     => HEX4,
            hex5     => HEX5,
            hex6     => open,
            hex7     => open
        );

    -- RS485_UART module instantiation
    generic_RS485_uart : entity work.RS485
        generic map(
            MY_CHIPSELECT   => "10",
            MY_WORD_ADDRESS => x"0170"
        )
        port map(
            clk          => clk,
            rst          => rst,
            clk_baud     => clk_baud,
            daddress     => daddress,
            ddata_w      => ddata_w,
            -- ddata_r      => ddata_r_RS485, -- [RS485]trocando iobus
            ddata_r      => ddata_r_RS485, -- [RS485]trocando iobus
            d_we         => d_we,
            d_rd         => d_rd,
            dcsel        => dcsel,
            dmask        => dmask,
            tx_out       => TX,
            rx_out       => RX,
            interrupts   => uart_interrupts,
            rs485_dir_DE => rs485_dir_DE_tb -- [RS485]adicionado para verificar sinal DE
        );

    -- ddata_r_RS485 <= x"45674567";

    data_transmit_proc : process
    begin
        RX <= '1';
        wait on transmit_frame;         -- Espera até que transmit_frame mude
        wait for 10 us;
        for i in 0 to 9 loop
            RX <= (transmit_frame(i));
            wait until clk_state;
        end loop;
    end process;

    process
    begin
        wait for 8700 us;
        -- wait for 300 us;

        transmit_byte  <= x"81";
        transmit_frame <= (others => '0'); -- Valor temporário para forçar a mudança
        wait for 1 ns;                  -- Pequeno atraso para garantir que a mudança ocorra
        transmit_frame <= '1' & transmit_byte & '0';

        wait for 1042 us;

        transmit_byte  <= x"00";
        transmit_frame <= (others => '0'); -- Valor temporário para forçar a mudança
        wait for 1 ns;                  -- Pequeno atraso para garantir que a mudança ocorra
        transmit_frame <= '1' & transmit_byte & '0';

        wait for 1042 us;

        transmit_byte  <= x"FD";
        transmit_frame <= (others => '0'); -- Valor temporário para forçar a mudança
        wait for 1 ns;                  -- Pequeno atraso para garantir que a mudança ocorra
        transmit_frame <= '1' & transmit_byte & '0';

        wait for 1042 us;

        transmit_byte  <= x"00";
        transmit_frame <= (others => '0'); -- Valor temporário para forçar a mudança
        wait for 1 ns;                  -- Pequeno atraso para garantir que a mudança ocorra
        transmit_frame <= '1' & transmit_byte & '0';

        wait for 1042 us;

        transmit_byte  <= x"00";
        transmit_frame <= (others => '0'); -- Valor temporário para forçar a mudança
        wait for 1 ns;                  -- Pequeno atraso para garantir que a mudança ocorra
        transmit_frame <= '1' & transmit_byte & '0';

        wait for 1042 us;

        transmit_byte  <= x"00";
        transmit_frame <= (others => '0'); -- Valor temporário para forçar a mudança
        wait for 1 ns;                  -- Pequeno atraso para garantir que a mudança ocorra
        transmit_frame <= '1' & transmit_byte & '0';

        wait for 1042 us;

        transmit_byte  <= x"00";
        transmit_frame <= (others => '0'); -- Valor temporário para forçar a mudança
        wait for 1 ns;                  -- Pequeno atraso para garantir que a mudança ocorra
        transmit_frame <= '1' & transmit_byte & '0';

        wait for 1042 us;

        transmit_byte  <= x"80";
        transmit_frame <= (others => '0'); -- Valor temporário para forçar a mudança
        wait for 1 ns;                  -- Pequeno atraso para garantir que a mudança ocorra
        transmit_frame <= '1' & transmit_byte & '0';

        wait;
    end process;

    -- FileOutput DEBUG 
    debug : entity work.trace_debug     -- @suppress 
        generic map(
            MEMORY_WORDS => IMEMORY_WORDS
        )
        port map(
            pc   => iaddress,
            data => idata,
            inst => debugString
        );

end architecture RTL;
