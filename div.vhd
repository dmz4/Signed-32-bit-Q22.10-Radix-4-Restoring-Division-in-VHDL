library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ================================================================
-- Entity: div
-- Description:
-- Signed 32-bit Q22.10 Radix-4 Restoring Division implementation.
-- This module performs fixed-point division using a two-bit-per-
-- iteration restoring algorithm (Radix-4) with sign handling.
-- ================================================================
entity div is
    Port (
        clk     : in  STD_LOGIC;                     -- Clock signal
        reset   : in  STD_LOGIC;                     -- Synchronous reset
        start   : in  STD_LOGIC;                     -- Start signal
        A       : in  STD_LOGIC_VECTOR (31 downto 0); -- Dividend (Q22.10)
        B       : in  STD_LOGIC_VECTOR (31 downto 0); -- Divisor (Q22.10)
        done    : out STD_LOGIC;                     -- Done signal (high when division finishes)
        r       : out STD_LOGIC_VECTOR (31 downto 0)  -- Quotient (Q22.10)
    );
end div;

architecture Behavioral of div is

    -- FSM states
    type States is (RS, Sleep, Pro, Inicio, Reg, Op, Res);
    signal current_state : States := Sleep;

    -- Internal registers (42 bits to accommodate Q22.10 format shift)
    signal Aaux, Baux, A_reg, B_reg, Q, M, Acc, Acc1, Acc_1, Acc1_2 : std_logic_vector(41 downto 0) := (others => '0');
    signal AQ, AQreg, AQreg_1, AQnext, AQnext_1 : std_logic_vector(83 downto 0) := (others => '0');
    signal sign : std_logic := '0';

    -- Constants
    constant one  : unsigned(41 downto 0) := "000000000000000000000000000000000000000001"; -- Constant 1 for two's complement
    constant onec : unsigned(31 downto 0) := "00000000000000000000000000000001";          -- Constant 1 for 32-bit

    -- Iteration counter
    signal counter : natural range 0 to 42 := 0;
    
begin

    -- ================================
    -- Radix-4 intermediate operations
    -- ================================

    -- Shift left by 1 for the next partial remainder
    AQreg <= std_logic_vector(shift_left(unsigned(AQ), 1));

    -- Extract accumulator (upper half of AQ register)
    Acc <= AQreg(83 downto 42);

    -- First subtraction step
    Acc1 <= std_logic_vector(signed(Acc) - signed(M));
    AQnext <= (Acc & AQreg(41 downto 1) & '0') when Acc1(41) = '1'
              else (Acc1 & AQreg(41 downto 1) & '1');
    
    -- Second subtraction step
    AQreg_1 <= std_logic_vector(shift_left(unsigned(AQnext), 1));
    Acc_1 <= AQreg_1(83 downto 42);
    Acc1_2 <= std_logic_vector(signed(Acc_1) - signed(M));
    AQnext_1 <= (Acc_1 & AQreg_1(41 downto 1) & '0') when Acc1_2(41) = '1'
                else (Acc1_2 & AQreg_1(41 downto 1) & '1');
    
    -- =====================================
    -- FSM for division process
    -- =====================================
    process (clk, reset)
    begin
        if reset = '1' then
            -- Reset all registers
            current_state <= RS;
            counter <= 0;
            done <= '0';
            r <= (others => '0');
        elsif rising_edge(clk) then
            case current_state is 
                
                -- Reset state
                when RS =>
                    A_reg <= (others => '0');
                    B_reg <= (others => '0');
                    done <= '0';
                    Q  <= (others => '0');
                    r <= (others => '0');
                    M <= (others => '0');
                    AQ <= (others => '0');
                    sign <= '0';
                    current_state <= Sleep;
                
                -- Wait for start signal
                when Sleep =>
                    if start = '1' then
                        current_state <= Pro;
                    else
                        current_state <= Sleep;
                    end if;
                    
                -- Pre-processing: resize and shift for Q22.10 format
                when Pro =>
                    Aaux <= std_logic_vector(shift_left(resize(signed(A), 42), 10)); -- Shift for fractional bits
                    Baux <= std_logic_vector(resize(signed(B), 42));
                    current_state <= Inicio;

                -- Sign adjustment and two's complement conversion if needed
                when Inicio =>
                    if (A(31) = '1') then
                        A_reg <= std_logic_vector(unsigned(NOT Aaux) + one);
                    else
                        A_reg <= Aaux;
                    end if;

                    if (B(31) = '1') then
                        B_reg <= std_logic_vector(unsigned(NOT Baux) + one);
                    else
                        B_reg <= Baux;
                    end if;

                    -- Determine sign of the result
                    sign <= A(31) XOR B(31);
                    current_state <= Reg;

                -- Initialize registers for division
                when Reg =>
                    AQ <= Q & A_reg;
                    M <= B_reg;
                    current_state <= Op;

                -- Iterative Radix-4 division steps
                when Op =>
                    AQ <= AQnext_1;
                    if counter < 20 then
                        counter <= counter + 1;
                        current_state <= Op;
                    else
                        counter <= 0;
                        current_state <= Res;
                    end if;

                -- Apply sign to result and finish
                when Res =>
                    if sign = '1' then
                        r <= std_logic_vector(unsigned(NOT(AQ(31 downto 0))) + onec);
                    else
                        r <= AQ(31 downto 0);
                    end if;
                    done <= '1';
                    current_state <= Sleep;
                        
                when others =>
                    done <= '0';
                    r <= (others => '0');
            end case;
        end if;    
    end process;

end Behavioral;
