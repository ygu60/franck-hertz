function d = load_run(file)
% LOAD_RUN  Rebuild full Franck-Hertz data from a <runID>_compact.mat file.
%
%   d = load_run('FH_20261001_135549_R01_Vr6p00_Va40p00_Vh8p00_compact.mat')
%
% The compact file holds only the raw 8-bit scope samples, the scope
% scaling and the run settings. Everything else is recomputed exactly:
%
%   d.runInfo                       run settings (V_reverse, V_acceleration, ...)
%   d.CH1, d.CH2                    voltages (V)
%   d.time_1, d.time_2              time axes (s)
%   d.time_us                       time axis (us)
%   d.AcceleratingVoltage           = CH1
%   d.FranckHertzSignal             = CH2 on CH1's time axis

    s = load(file);
    sc = s.scope;

    d.runInfo = s.runInfo;

    d.CH1 = (double(s.ch1_raw) - sc.y_off(1)) .* sc.y_mult(1) + sc.y_zero(1);
    d.CH2 = (double(s.ch2_raw) - sc.y_off(2)) .* sc.y_mult(2) + sc.y_zero(2);

    d.time_1 = sc.x_zero(1) + (0:numel(d.CH1)-1) .* sc.x_incr(1);
    d.time_2 = sc.x_zero(2) + (0:numel(d.CH2)-1) .* sc.x_incr(2);

    CH2_matched = interp1(d.time_2, d.CH2, d.time_1, 'linear', NaN);
    valid = ~isnan(CH2_matched);

    d.time_us             = d.time_1(valid) * 1e6;
    d.AcceleratingVoltage = d.CH1(valid);
    d.FranckHertzSignal   = CH2_matched(valid);
end
