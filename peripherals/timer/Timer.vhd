-------------------------------------------------------------------
-- Name         : Timer.vhd
-- Author       : 
-- Last changes: 12/12/2023 Natália
-- Description  : Implementação para um periférico de timer de 32 bits em VHDL com 6 níveis de comparação / saídas
-------------------------------------------------------------------



library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Timer is
    generic(
        DADDRESS_BUS_SIZE : integer := 32;
        prescaler_size : integer := 16;
        compare_size   : integer := 32
    );
    port(
        clock       : in  std_logic;
        reset       : in  std_logic;
        daddress    : in unsigned(DADDRESS_BUS_SIZE-1 downto 0);
        ddata_w     : in std_logic_vector(31 downto 0);
        ddata_r     : out std_logic_vector(31 downto 0);
        d_we        : in  std_logic;
        d_rd        : in  std_logic;
        dcsel       : in std_logic_vector(1 downto 0);
        dmask       : in std_logic_vector(3 downto 0);
        timer_interrupt : out std_logic_vector(5 downto 0);

        -- changes rk --
        ifcap       : in std_logic := '0';     -- capture flag
        ------------
        
        -- out pins --
        out_A   : out std_logic_vector(2 downto 0);
        out_B    : out std_logic_vector(2 downto 0)
    );
end entity Timer;

architecture RTL of Timer is
    signal counter                    : unsigned(31 downto 0)  := (others => '0');
    signal internal_clock             : std_logic              := '1';
    signal internal_counter_direction : std_logic              := '0'; -- @suppress "signal internal_counter_direction is never read"
    --	type counter_direction_t is (Up, Down);

    -- TIMER Signals
    signal timer_reset : std_logic;
    -- signal timer_mode  : unsigned(1 downto 0); original
    signal timer_mode  : unsigned(2 downto 0);
    signal prescaler   : unsigned(prescaler_size - 1 downto 0);
    signal top_counter : unsigned(31 downto 0);
    signal compare_0A  : unsigned(31 downto 0);
    signal compare_1A  : unsigned(31 downto 0);
    signal compare_2A  : unsigned(31 downto 0);
    signal compare_0B  : unsigned(31 downto 0);
    signal compare_1B  : unsigned(31 downto 0);
    signal compare_2B  : unsigned(31 downto 0);

    -- dead time used in modes 5 and 6 --
    signal dead_time  : unsigned(31 downto 0); 


    signal output_A    :  std_logic_vector(2 downto 0);
    signal output_B    :  std_logic_vector(2 downto 0);

    signal captured_time : std_logic_vector(31 downto 0) := (others => '0');

    signal enable_timer_irq_mask  : std_logic_vector(31 downto 0);

    signal myInterrupts_d : std_logic_vector(5 downto 0);
    signal interrupts: std_logic_vector(5 downto 0);
    signal interrupts_holder: std_logic_vector(5 downto 0);

    constant TIMER_BASE_ADDRESS : unsigned(15 downto 0):=x"0050";


begin

    interrupts_holder<=output_B(2) & output_A(2) & output_B(1) & output_A(1) & output_B(0) & output_A(0) ;
    interrupts <= interrupts_holder and enable_timer_irq_mask(5 downto 0);


    interrupt_edge : process (clock, reset) is
    begin
        if reset = '1' then
            myInterrupts_d <= (others => '0');
            timer_interrupt<=(others => '0');
        elsif rising_edge(clock) then

            myInterrupts_d <= interrupts;
            timer_interrupt <= not myInterrupts_d and interrupts;

        end if;
    end process interrupt_edge;

    -- Output register
    p0: process(clock, reset)
    begin
        if reset = '1' then
            timer_reset<='0';
            timer_mode <="000";
            prescaler  <= (others => '0');
            top_counter<= (others => '0');
            compare_0A <= (others => '0');
            compare_0B <= (others => '0');
            compare_1A <= (others => '0');
            compare_1B <= (others => '0');
            compare_2A <= (others => '0');
            compare_2B <= (others => '0');
            enable_timer_irq_mask<=(others => '0');

            dead_time <= (others => '0'); -- 

        else
            if rising_edge(clock) then
                if (d_we = '1') and (dcsel = "10") then
                    -- ToDo: Simplify compartors
                    -- ToDo: Maybe use byte addressing?  
                    --       x"01" (word addressing) is x"04" (byte addressing)

                    -- defines the address for each variable that will be changed by the software
                    if daddress(15 downto 0) =(TIMER_BASE_ADDRESS + x"0000") then -- TIMER_ADDRESS
                        timer_reset <= ddata_w(0);
                    elsif daddress(15 downto 0) =(TIMER_BASE_ADDRESS + x"0001") then -- TIMER_ADDRESS
                        timer_mode <= unsigned(ddata_w(2 downto 0));
                    elsif daddress(15 downto 0) =(TIMER_BASE_ADDRESS + x"0002") then -- TIMER_ADDRESS
                        prescaler <= unsigned(ddata_w(prescaler_size - 1 downto 0));
                    elsif daddress(15 downto 0) =(TIMER_BASE_ADDRESS + x"0003") then -- TIMER_ADDRESS
                        top_counter <= unsigned(ddata_w);
                    elsif daddress(15 downto 0) =(TIMER_BASE_ADDRESS + x"0004") then -- TIMER_ADDRESS
                        compare_0A <= unsigned(ddata_w);
                    elsif daddress(15 downto 0) =(TIMER_BASE_ADDRESS + x"0005") then -- TIMER_ADDRESS
                        compare_0B <= unsigned(ddata_w);
                    elsif daddress(15 downto 0) =(TIMER_BASE_ADDRESS + x"0006") then -- TIMER_ADDRESS
                        compare_1A <= unsigned(ddata_w);
                    elsif daddress(15 downto 0) =(TIMER_BASE_ADDRESS + x"0007") then -- TIMER_ADDRESS
                        compare_1B <= unsigned(ddata_w);
                    elsif daddress(15 downto 0) =(TIMER_BASE_ADDRESS + x"0008") then -- TIMER_ADDRESS
                        compare_2A <= unsigned(ddata_w);
                    elsif daddress(15 downto 0) =(TIMER_BASE_ADDRESS + x"0009") then -- TIMER_ADDRESS
                        compare_2B <= unsigned(ddata_w);
                    elsif daddress(15 downto 0) =(TIMER_BASE_ADDRESS + x"000b") then -- TIMER_ADDRESS
                        enable_timer_irq_mask <= ddata_w;

                    elsif daddress(15 downto 0) =(TIMER_BASE_ADDRESS + x"000d") then -- TIMER_ADDRESS 
                        dead_time <= unsigned(ddata_w); -- dead_time added in the next adress avaiable "000d"
            
                    end if;
                end if;
            end if;
        end if;
    end process p0;

    -- Input register
    pi: process(clock, reset)
    begin
        if reset = '1' then
            ddata_r <= (others => '0');
        else
            if rising_edge(clock) then
                ddata_r <= (others => '0');
                if (d_rd = '1') and (dcsel = "10") then
                    if daddress(15 downto 0) = (TIMER_BASE_ADDRESS +x"0000") then
                    --ddata_r(4 downto 0) <= SW(4 downto 0);
                    elsif daddress(15 downto 0) =(TIMER_BASE_ADDRESS + x"0004")then
                    --ddata_r(7 downto 0) <= data_out;
                    elsif daddress(15 downto 0) =(TIMER_BASE_ADDRESS + x"000a") then
                        ddata_r(2 downto 0) <= output_A(2 downto 0);
                        ddata_r(5 downto 3) <= output_B(2 downto 0);
                    elsif daddress(15 downto 0) = (TIMER_BASE_ADDRESS + x"000c") then
                        ddata_r <= captured_time;
                    end if;
                end if;
            end if;
        end if;

    end process pi;


    --Prescaler
    p1 : process(clock, reset, prescaler) is
        variable temp_counter : unsigned(prescaler_size - 1 downto 0) := (others => '0');
    begin
        if reset = '1' then
            temp_counter := (others => '0');
            internal_clock <= '0';
        else
            if prescaler /= x"0001" then
                if rising_edge(clock) then
                    temp_counter := temp_counter + 1;
                    if temp_counter >= prescaler - 1 then
                        internal_clock <= not (internal_clock);
                        temp_counter   := (others => '0');
                    else
                        internal_clock <= '1'; -- todo
                    end if;
                else
                -- internal_clock <= '';
                end if;
            else
                internal_clock <= clock;
            end if;
        end if;
    end process p1;

    p2 : process(internal_clock, reset) is
        variable internal_output_A : std_logic_vector(2 downto 0) := (others => '0');
        variable internal_output_B : std_logic_vector(2 downto 0) := (others => '0');
        variable counter_direction : std_logic                    := '0';
        --variable time              : std_logic_vector(31 downto 0)        := (others => '0');
        variable ifc               : std_logic := '0';
        
        variable c :unsigned(31 downto 0):= (others => '0'); -- counter implemented using variable, used in modes 5 and 6

    begin
        if reset = '1' then
            internal_output_A := (others => '0');
            internal_output_B := (others => '0');
            output_A <= internal_output_A;
            output_B <= internal_output_B;
            counter_direction := '0';
            ifc := '0';
        else
            if rising_edge(internal_clock) then
                if timer_reset = '1' then
                    internal_output_A := (others => '0');
                    internal_output_B := (others => '0');
                    counter           <= (others => '0');
                    counter_direction := '0';
                    captured_time <= (others => '0');
                    c := (others => '0');
                    
                else
                    case timer_mode is
                        when "000" =>    -- one shot mode

                            if counter >= compare_0A - 1 then
                                internal_output_A(0) := '1';
                            else
                                internal_output_A(0) := '0';
                                counter              <= counter + 1;
                            end if;

                            if counter >= compare_0B - 1 then
                                internal_output_B(0) := '1';
                            else
                                internal_output_B(0) := '0';
                                counter              <= counter + 1;
                            end if;

                            if counter >= compare_1A - 1 then
                                internal_output_A(1) := '1';
                            else
                                internal_output_A(1) := '0';
                                counter              <= counter + 1;
                            end if;

                            if counter >= compare_1B - 1 then
                                internal_output_B(1) := '1';
                            else
                                internal_output_B(1) := '0';
                                counter              <= counter + 1;
                            end if;

                            if counter >= compare_2A - 1 then
                                internal_output_A(2) := '1';
                            else
                                internal_output_A(2) := '0';
                                counter              <= counter + 1;
                            end if;

                            if counter >= compare_2B - 1 then
                                internal_output_B(2) := '1';
                            else
                                internal_output_B(2) := '0';
                                counter              <= counter + 1;
                            end if;

                        when "011" =>    -- clear on compare mode, counter is as sawtooth wave

                            -- the counter resets if reaches B comparator.
                            -- the output has a rectangular waveform like a simple PWM, but active when between A and B comparators
                            if counter >= top_counter - 1 then
                                counter <= (others => '0');
                            else
                                counter <= counter + 1;
                            end if;

                            if (counter >= compare_0A - 1) and (counter < compare_0B - 1) then
                                internal_output_A(0) := '1';
                                internal_output_B(0) := '0';
                            else
                                internal_output_A(0) := '0';
                                internal_output_B(0) := '1';
                            end if;

                            if (counter >= compare_1A - 1) and (counter < compare_1B - 1) then
                                internal_output_A(1) := '1';
                                internal_output_B(1) := '0';
                            else
                                internal_output_A(1) := '0';
                                internal_output_B(1) := '1';
                            end if;

                            if (counter >= compare_2A - 1) and (counter < compare_2B - 1) then
                                internal_output_A(2) := '1';
                                internal_output_B(2) := '0';
                            else
                                internal_output_A(2) := '0';
                                internal_output_B(2) := '1';
                            end if;

                        when "010" =>    -- clear on compare mode, counter is a centered triangle wave

                            -- the counter change its direction (up or down) when it reaches its maximum possible value
                            -- the output has a rectangular waveform centered to the top value, active when between A and B comparators. 
                            if counter_direction = '0' then
                                if counter >= top_counter - 1 then
                                    counter_direction := '1';
                                    counter           <= counter - 1;
                                else
                                    counter <= counter + 1;
                                end if;

                                if counter >= compare_0A - 1 then
                                    internal_output_A(0) := '1';
                                else
                                    internal_output_A(0) := '0';
                                end if;

                                if counter >= compare_0B - 1 then
                                    internal_output_B(0) := '0';
                                else
                                    internal_output_B(0) := '1';
                                end if;

                                if counter >= compare_1A - 1 then
                                    internal_output_A(1) := '1';
                                else
                                    internal_output_A(1) := '0';
                                end if;

                                if counter >= compare_1B - 1 then
                                    internal_output_B(1) := '0';
                                else
                                    internal_output_B(1) := '1';
                                end if;

                                if counter >= compare_2A - 1 then
                                    internal_output_A(2) := '1';
                                else
                                    internal_output_A(2) := '0';
                                end if;

                                if counter >= compare_2B - 1 then
                                    internal_output_B(2) := '0';
                                else
                                    internal_output_B(2) := '1';
                                end if;

                            else
                                if counter <= 0 then
                                    counter_direction := '0';
                                    counter           <= counter + 1;
                                else
                                    counter <= counter - 1;
                                end if;

                                if counter > compare_0A - 1 then
                                    internal_output_A(0) := '1';
                                else
                                    internal_output_A(0) := '0';
                                end if;

                                if counter > compare_0B - 1 then
                                    internal_output_B(0) := '0';
                                else
                                    internal_output_B(0) := '1';
                                end if;

                                if counter > compare_1A - 1 then
                                    internal_output_A(1) := '1';
                                else
                                    internal_output_A(1) := '0';
                                end if;

                                if counter > compare_1B - 1 then
                                    internal_output_B(1) := '0';
                                else
                                    internal_output_B(1) := '1';
                                end if;

                                if counter > compare_2A - 1 then
                                    internal_output_A(2) := '1';
                                else
                                    internal_output_A(2) := '0';
                                end if;

                                if counter > compare_2B - 1 then
                                    internal_output_B(2) := '0';
                                else
                                    internal_output_B(2) := '1';
                                end if;

                            end if;

                            internal_counter_direction <= counter_direction;

                        when "001" =>    -- clear on top mode, counter is as sawtooth wave

                            -- the counter resets if reaches its maximum possible value
                            -- the output has a rectangular waveform like a simple PWM
                            if counter >= top_counter - 1 then
                                counter <= (others => '0');
                            else
                                counter <= counter + 1;
                            end if;

                            if counter >= compare_0A - 1 then
                                internal_output_A(0) := '1';
                            else
                                internal_output_A(0) := '0';
                            end if;

                            if counter >= compare_0B - 1 then
                                internal_output_B(0) := '1';
                            else
                                internal_output_B(0) := '0';
                            end if;

                            if counter >= compare_1A - 1 then
                                internal_output_A(1) := '1';
                            else
                                internal_output_A(1) := '0';
                            end if;

                            if counter >= compare_1B - 1 then
                                internal_output_B(1) := '1';
                            else
                                internal_output_B(1) := '0';
                            end if;

                            if counter >= compare_2A - 1 then
                                internal_output_A(2) := '1';
                            else
                                internal_output_A(2) := '0';
                            end if;

                            if counter >= compare_2B - 1 then
                                internal_output_B(2) := '1';
                            else
                                internal_output_B(2) := '0';
                            end if;

                        when "100" =>     -- capture timer
                            if ifcap = '1' and ifc = '0' then
                                captured_time <= std_logic_vector(counter);
                                ifc := '1';
                            elsif ifcap = '0' then
                                ifc := '0';
                            end if;

                            counter <= counter +1;


                        when "101" =>    --Mode 5 - PWM mode counter up/down

                            -- The counter change its direction (up or down) when it reaches its maximum possible value
                            -- Complementary outputs a and b with dead time


                            if counter_direction = '0' then
                                -- when the count is increasing, count until top_counter - 1
                                if c >= top_counter - 1 then
                                    counter_direction := '1'; -- then it starts to decrease
                                    c := c - 1;
                                else
                                    c := c + 1;
                                end if;

                            else

                                if c <= 0 then
                                    -- Decrease until zero and start increasing again
                                    counter_direction := '0';
                                    c  := c + 1;
                                else
                                    c := c - 1;
                                end if;
                            end if;

                           -- if comparison value is between the dead_time limit the outputs will be zero
                            if (compare_0A  <= dead_time) or (compare_0A >= top_counter-dead_time-1) then
                                internal_output_A(0) := '0';
                                internal_output_B(0) := '0';
                            else
                                -- Comparisons to define output0A and its complement, output0B
                                if c > compare_0A + dead_time  then
                                    internal_output_A(0) := '1';
                                else
                                    internal_output_A(0) := '0';
                                end if;

                                if c >= compare_0A - dead_time  then
                                    internal_output_B(0) := '0';
                                else
                                    internal_output_B(0) := '1';
                                end if;

                            end if;
                        
                             -- Comparisons to define output1A and output1B
                            if (compare_1A  <= dead_time) or (compare_1A >= top_counter-dead_time-1) then
                                internal_output_A(1) := '0';
                                internal_output_B(1) := '0';
                            else
                                if c > compare_1A + dead_time then
                                    internal_output_A(1) := '1';
                                else
                                    internal_output_A(1) := '0';
                                end if;

                                if c >= compare_1A - dead_time  then
                                    internal_output_B(1) := '0';
                                else
                                    internal_output_B(1) := '1';
                                end if;

                            end if;

                            -- Comparisons to define output2A and output2B
                            if (compare_2A  <= dead_time) or (compare_2A >= top_counter-dead_time-1) then
                                internal_output_A(2) := '0';
                                internal_output_B(2) := '0';
                            else
                                if c > compare_2A + dead_time then
                                    internal_output_A(2) := '1';
                                else
                                    internal_output_A(2) := '0';
                                end if;

                                if c >= compare_2A - dead_time  then
                                    internal_output_B(2) := '0';
                                else
                                    internal_output_B(2) := '1';
                                end if;
                            end if;



                        when "110" =>  -- Mode 6 - PWM mode with counter up

                            -- The counter resets if reaches its maximum possible value
                            -- Complementary outputs a and b with dead time
                            
                            
                            -- Counter 
                            if c >= top_counter - 1 then
                                c := (others => '0');
                            else
                                c := c + 1;
                            end if;


                             -- Comparisons to define output0A and output0B
                            if (compare_0A -dead_time <= dead_time) or (compare_0A + dead_time >= top_counter-dead_time-1) then
                                internal_output_A(0) := '0';
                                internal_output_B(0) := '0';

                            else
                                if (c >= dead_time) and (c< compare_0A-dead_time) then
                                    internal_output_A(0) := '1';
                                else
                                    internal_output_A(0) :=  '0';
                                end if;

                               

                                if (c >= compare_0A + dead_time) and (c<= top_counter-dead_time-1) then
                                    internal_output_B(0) := '1';
                                else
                                    internal_output_B(0) := '0';
                                end if;

                            end if;
                           
                           
                             -- Comparisons to define output1A and output1B
                            if (compare_1A -dead_time <= dead_time) or (compare_1A + dead_time>= top_counter-dead_time-1) then
                                internal_output_A(1) := '0';
                                internal_output_B(1) := '0';

                            else
                                if (c >= dead_time) and (c< compare_1A-dead_time) then
                                    internal_output_A(1) := '1';
                                else
                                    internal_output_A(1) :=  '0';
                                end if;


                                if (c >= compare_1A + dead_time) and (c<= top_counter-dead_time-1) then
                                    internal_output_B(1) := '1';
                                else
                                    internal_output_B(1) := '0';
                                end if;
                            end if;
                            
                            
                             -- Comparisons to define output2A and output2B
                            if (compare_2A -dead_time <= dead_time) or (compare_2A + dead_time >= top_counter-dead_time-1) then
                                internal_output_A(2) := '0';
                                internal_output_B(2) := '0';

                            else
                                if (c >= dead_time) and (c< compare_2A-dead_time) then
                                    internal_output_A(2) := '1';
                                else
                                    internal_output_A(2) :=  '0';
                                end if;
 

                                if (c >= compare_2A + dead_time) and (c<= top_counter-dead_time-1) then
                                    internal_output_B(2) := '1';
                                else
                                    internal_output_B(2) := '0';
                                end if;
                            end if;


                        when others =>
                            internal_output_A := (others => '0');
                            internal_output_B := (others => '0');


                    end case;
                end if;
            end if;

            output_A <= internal_output_A;
            output_B <= internal_output_B;

        end if;


    end process p2;

    -- add the sginals output_A e output_B to the output pins
    out_A <= output_A;
    out_B <= output_B;

end architecture RTL;
