# Primary clock: 30 ns period
create_clock -name clk -period 30.000 [get_ports clk_i]


# Optional: clock uncertainty (jitter / margin)
# (Safe small value for synthesis-level reporting)
set_clock_uncertainty 0.200 [get_clocks clk]

# Optional: group the clock (helps some reports)
set_clock_groups -asynchronous -group [get_clocks clk]
