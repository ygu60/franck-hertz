%% ============================================================
%  FRANCK-HERTZ EXPERIMENT
%  Tektronix DPO2024B Data Acquisition
%
%  CH1 = Accelerating voltage signal
%  CH2 = Franck-Hertz signal
%
%  IMPORTANT:
%  NO x10 scaling is applied anywhere.
%
%  OUTPUT:
%
%  GRAPH 1:
%       CH1 and CH2 vs Time
%       -> TXT
%       -> PNG
%       -> FIG
%
%  GRAPH 2:
%       CH2 vs CH1
%       -> TXT
%       -> PNG
%       -> FIG
%
%  Each run is saved in its own folder (see section 1b):
%  <script>/<DDMMMYY>/<runID>/<runID>_*.*  + run_log.csv
%
% ============================================================

clear;
clc;
close all;


%% ============================================================
% 1. SAVE FILES IN THE SAME FOLDER AS THIS SCRIPT
% ============================================================

scriptFolder = fileparts(mfilename('fullpath'));

if isempty(scriptFolder)
    scriptFolder = pwd;
end

disp('================================================');
disp('       FRANCK-HERTZ DATA ACQUISITION');
disp('================================================');
disp(' ');



%% ============================================================
% 1b. RUN PARAMETERS AND RUN ID
% ============================================================
%
% Asks for the apparatus settings before every recording.
% The last values entered are remembered as defaults.
%
% Each run is saved in its own folder:
%
%   <script>/<DDMMMYY>/<runID>/
%
% runID example:
%   FH_20261001_134712_R03_Vr1p50_Va30p00_Vh6p30
%   (date_time_run#_reverse_accel_heater, '.' -> 'p')
%
% Every run is also appended to <script>/run_log.csv.
%
% ============================================================

paramsFile = fullfile(scriptFolder, 'last_run_params.mat');

defaults = {'', '', '', ''};
if isfile(paramsFile)
    s = load(paramsFile, 'defaults');
    defaults = s.defaults;
end

answer = inputdlg( ...
    {'V_reverse (V):', ...
     'V_acceleration (V):', ...
     'V_heater (V):', ...
     'Notes (optional):'}, ...
    'Franck-Hertz Run Parameters', ...
    [1 45; 1 45; 1 45; 3 45], ...
    defaults);

if isempty(answer)
    error('Recording cancelled: no run parameters entered.');
end

V_reverse      = str2double(answer{1});
V_acceleration = str2double(answer{2});
V_heater       = str2double(answer{3});
runNotes       = strjoin(cellstr(answer{4}), ' ');

if any(isnan([V_reverse, V_acceleration, V_heater]))
    error('V_reverse, V_acceleration and V_heater must be numbers.');
end

defaults = [answer(1:3)', {runNotes}];
save(paramsFile, 'defaults');

runTime    = datetime('now');
dateFolder = fullfile(scriptFolder, ...
    upper(char(runTime, 'ddMMMyy')));

if ~isfolder(dateFolder)
    mkdir(dateFolder);
end

% Run number = runs already recorded today + 1
runNumber = numel(dir(fullfile(dateFolder, 'FH_*'))) + 1;

runID = sprintf('FH_%s_R%02d_Vr%s_Va%s_Vh%s', ...
    char(runTime, 'yyyyMMdd_HHmmss'), ...
    runNumber, ...
    numTag(V_reverse), ...
    numTag(V_acceleration), ...
    numTag(V_heater));

runFolder = fullfile(dateFolder, runID);
mkdir(runFolder);

paramLabel = sprintf( ...
    'V_{rev} = %.2f V, V_{acc} = %.2f V, V_{heat} = %.2f V', ...
    V_reverse, V_acceleration, V_heater);

fprintf('Run ID: %s\n', runID);
fprintf('Files will be saved in:\n');
fprintf('%s\n', runFolder);
disp(' ');


%% ============================================================
% 2. OSCILLOSCOPE CONNECTION
% ============================================================

resourceName = ...
    'USB0::0x0699::0x03A3::C041827::INSTR';

% Close any connection left open from a previous run.
% (Searching by name misses it: VISA stores the name as
%  ...C041827::0::INSTR, so a second object gets created
%  and fopen fails.)
oldObj = instrfindall;

if ~isempty(oldObj)

    disp('Closing previous VISA connection...');

    fclose(oldObj);

    delete(oldObj);

end

clear oldObj;

disp('Creating VISA connection...');

visaObj = visa('NI', resourceName);

% The full record is up to 1.25 M points. In 1-byte binary
% that is ~1.25 MB per channel; a smaller buffer truncates
% the waveform ("buffer was filled before the EOI line was
% asserted").
set(visaObj, 'InputBufferSize', 4e6);
set(visaObj, 'OutputBufferSize', 50000);
set(visaObj, 'Timeout', 60);

fopen(visaObj);

disp('Oscilloscope connected.');
disp(' ');


%% ============================================================
% 3. IDENTIFY OSCILLOSCOPE
% ============================================================

idn = query(visaObj, '*IDN?');

disp('Oscilloscope:');
disp(strtrim(idn));
disp(' ');


%% ============================================================
% 3b. VERTICAL SCALE (HARD-CODED)
% ============================================================
%
% Fixed volts/div per channel. Each channel is centred on
% its expected range (cursor readings a -> b).
%
% Screen = 8 vertical divisions.
%
% ============================================================

voltsPerDiv = [1, 2.4];            % V/div: [CH1, CH2]

%                 a       b
expectedRange = [ -2.38,  8.23;    % CH1 (X), delta 10.6 V
                  -0.8,   8.8];    % CH2 (Y), delta 9.6 V

channels     = {'CH1', 'CH2'};

fprintf(visaObj, 'HEADer OFF');

for k = 1:2
    setVertical(visaObj, channels{k}, ...
        voltsPerDiv(k), ...
        mean(expectedRange(k, :)));
end

for k = 1:2
    fprintf('%s: %.3g V/div, offset %.3f V\n', channels{k}, ...
        str2double(query(visaObj, [channels{k} ':SCAle?'])), ...
        str2double(query(visaObj, [channels{k} ':OFFSet?'])));
end

pause(1);   % let the scope acquire with the new settings
disp(' ');


%% ============================================================
% 4. WAVEFORM TRANSFER SETTINGS
% ============================================================

% Transfer the WHOLE record, not just the first 100000 points
recordLength = str2double(query(visaObj, 'HORizontal:RECOrdlength?'));

% 1-byte signed binary: ~5x smaller and much faster than ASCII
fprintf(visaObj, 'DATa:ENCdg RIBinary');
fprintf(visaObj, 'DATa:WIDth 1');
fprintf(visaObj, 'DATa:RESOlution FULL');   % full record, not screen-reduced
fprintf(visaObj, 'DATa:STARt 1');
fprintf(visaObj, sprintf('DATa:STOP %d', recordLength));

% Freeze the scope so CH1 and CH2 come from the same sweep
fprintf(visaObj, 'ACQuire:STATE STOP');
pause(0.5);

fprintf('Record length = %d points\n', recordLength);
disp('Waveform transfer configured.');
disp(' ');


%% ============================================================
% 5. ACQUIRE CH1
% ============================================================

disp('-----------------------------------------------');
disp('Acquiring CH1...');
disp('CH1 = Accelerating Voltage');
disp('-----------------------------------------------');

fprintf(visaObj, 'DATa:SOUrce CH1');

pause(0.2);

% CH1 scaling
x_incr_1 = str2double(query(visaObj, 'WFMPRE:XINCR?'));
x_zero_1 = str2double(query(visaObj, 'WFMPRE:XZERO?'));

y_mult_1 = str2double(query(visaObj, 'WFMPRE:YMULT?'));
y_zero_1 = str2double(query(visaObj, 'WFMPRE:YZERO?'));
y_off_1  = str2double(query(visaObj, 'WFMPRE:YOFF?'));

% CH1 waveform
ch1_raw = readCurve(visaObj);

% Convert to voltage
CH1 = ...
    (ch1_raw - y_off_1) .* y_mult_1 + y_zero_1;

% Time
time_1 = ...
    x_zero_1 + ...
    (0:length(CH1)-1) .* x_incr_1;

disp('CH1 acquired successfully.');

fprintf('CH1 points  = %d\n', length(CH1));
fprintf('CH1 minimum = %.4f V\n', min(CH1));
fprintf('CH1 maximum = %.4f V\n', max(CH1));
fprintf('Time step   = %.6e s\n', x_incr_1);

disp(' ');


%% ============================================================
% 6. ACQUIRE CH2
% ============================================================

disp('-----------------------------------------------');
disp('Acquiring CH2...');
disp('CH2 = Franck-Hertz Signal');
disp('-----------------------------------------------');

fprintf(visaObj, 'DATa:SOUrce CH2');

pause(0.2);

% CH2 scaling
x_incr_2 = str2double(query(visaObj, 'WFMPRE:XINCR?'));
x_zero_2 = str2double(query(visaObj, 'WFMPRE:XZERO?'));

y_mult_2 = str2double(query(visaObj, 'WFMPRE:YMULT?'));
y_zero_2 = str2double(query(visaObj, 'WFMPRE:YZERO?'));
y_off_2  = str2double(query(visaObj, 'WFMPRE:YOFF?'));

% CH2 waveform
ch2_raw = readCurve(visaObj);

% Convert to voltage
CH2 = ...
    (ch2_raw - y_off_2) .* y_mult_2 + y_zero_2;

% Time
time_2 = ...
    x_zero_2 + ...
    (0:length(CH2)-1) .* x_incr_2;

disp('CH2 acquired successfully.');

fprintf('CH2 points  = %d\n', length(CH2));
fprintf('CH2 minimum = %.4f V\n', min(CH2));
fprintf('CH2 maximum = %.4f V\n', max(CH2));
fprintf('Time step   = %.6e s\n', x_incr_2);

disp(' ');


%% ============================================================
% 7. MATCH CH2 TO CH1 TIME AXIS
% ============================================================
%
% We DO NOT extrapolate outside the measured time range.
% This prevents artificial negative/extra sections in the
% Franck-Hertz curve.
%
% ============================================================

CH2_matched = interp1( ...
    time_2, ...
    CH2, ...
    time_1, ...
    'linear', ...
    NaN);

% Keep only points where both channels have valid data
valid = ~isnan(CH2_matched);

time_common = time_1(valid);
CH1_common = CH1(valid);
CH2_common = CH2_matched(valid);

time_us = time_common * 1e6;


%% ============================================================
% 8. IMPORTANT:
%    NO x10 SCALING
% ============================================================
%
% CH1 is used exactly as measured.
% CH2 is used exactly as measured.
%
% Therefore:
%
%   AcceleratingVoltage = CH1
%   FranckHertzSignal   = CH2
%
% There is NO:
%
%   10 * CH1
%
% and NO:
%
%   10 * CH2
%
% ============================================================

AcceleratingVoltage = CH1_common;

FranckHertzSignal = CH2_common;


%% ============================================================
% 9. GRAPH 1
%    CH1 AND CH2 VS TIME
% ============================================================

fig1 = figure( ...
    'Name', 'Franck-Hertz Waveforms', ...
    'NumberTitle', 'off', ...
    'Color', 'w');

scatter( ...
    time_us, ...
    CH1_common, ...
    1, ...
    'magenta');

hold on;

scatter( ...
    time_us, ...
    CH2_common, ...
    1, ...
    'cyan');

grid on;
box on;

xlabel('Time (\mus)');
ylabel('Voltage (V)');

title({'Franck-Hertz Oscilloscope Waveforms', paramLabel});

legend( ...
    'CH1: Accelerating Voltage', ...
    'CH2: Franck-Hertz Signal', ...
    'Location', 'best');

set(gca, 'FontSize', 11);


%% ============================================================
% 10. SAVE GRAPH 1 TXT
% ============================================================

data_graph1 = [ ...
    time_us(:), ...
    CH1_common(:), ...
    CH2_common(:)];

txtFile1 = fullfile( ...
    runFolder, ...
    [runID '_Waveforms.txt']);

fileID = fopen(txtFile1, 'w');

fprintf(fileID, ...
    'Time_us\tCH1_Voltage_V\tCH2_Franck_Hertz_V\n');

fclose(fileID);

dlmwrite( ...
    txtFile1, ...
    data_graph1, ...
    '-append', ...
    'delimiter', '\t', ...
    'precision', '%.9g');

disp('Graph 1 TXT saved:');
disp(txtFile1);


%% ============================================================
% 11. SAVE GRAPH 1 PNG
% ============================================================

pngFile1 = fullfile( ...
    runFolder, ...
    [runID '_Waveforms.png']);

exportgraphics( ...
    fig1, ...
    pngFile1, ...
    'Resolution', 300);

disp('Graph 1 PNG saved:');
disp(pngFile1);


%% ============================================================
% 12. SAVE GRAPH 1 FIG
% ============================================================

figFile1 = fullfile( ...
    runFolder, ...
    [runID '_Waveforms.fig']);

savefig( ...
    fig1, ...
    figFile1);

disp('Graph 1 FIG saved:');
disp(figFile1);

disp(' ');


%% ============================================================
% 13. GRAPH 2
%    FRANCK-HERTZ CURVE
%
%    X = CH1
%    Y = CH2
%
%    NO x10 SCALING
% ============================================================

fig2 = figure( ...
    'Name', 'Franck-Hertz Curve', ...
    'NumberTitle', 'off', ...
    'Color', 'w');

plot( ...
    AcceleratingVoltage, ...
    FranckHertzSignal, ...
    'LineWidth', 1.2); 
    % 1, ...        % Marker size in points^2
    % 'b', ...       % Marker color (e.g., 'b', [0 0.447 0.741])
    % 'filled'% Solid fill for better visibility with high-density data
       
grid on;
box on;

xlabel('CH1 Accelerating Voltage (V)');
ylabel('CH2 Franck-Hertz Signal (V)');

title({'Franck-Hertz Curve', paramLabel});

set(gca, 'FontSize', 11);


%% ============================================================
% 14. SAVE GRAPH 2 TXT
% ============================================================

data_graph2 = [ ...
    AcceleratingVoltage(:), ...
    FranckHertzSignal(:)];

txtFile2 = fullfile( ...
    runFolder, ...
    [runID '_Curve.txt']);

fileID = fopen(txtFile2, 'w');

fprintf(fileID, ...
    'CH1_Voltage_V\tCH2_Franck_Hertz_Signal_V\n');

fclose(fileID);

dlmwrite( ...
    txtFile2, ...
    data_graph2, ...
    '-append', ...
    'delimiter', '\t', ...
    'precision', '%.9g');

disp('Graph 2 TXT saved:');
disp(txtFile2);


%% ============================================================
% 15. SAVE GRAPH 2 PNG
% ============================================================

pngFile2 = fullfile( ...
    runFolder, ...
    [runID '_Curve.png']);

exportgraphics( ...
    fig2, ...
    pngFile2, ...
    'Resolution', 300);

disp('Graph 2 PNG saved:');
disp(pngFile2);


%% ============================================================
% 16. SAVE GRAPH 2 FIG
% ============================================================

figFile2 = fullfile( ...
    runFolder, ...
    [runID '_Curve.fig']);

savefig( ...
    fig2, ...
    figFile2);

disp('Graph 2 FIG saved:');
disp(figFile2);

disp(' ');


%% ============================================================
% 17. SAVE COMPLETE MATLAB DATA
% ============================================================

matFile = fullfile( ...
    runFolder, ...
    [runID '_Complete_Data.mat']);

runInfo = struct( ...
    'runID',          runID, ...
    'timestamp',      char(runTime, 'yyyy-MM-dd HH:mm:ss'), ...
    'runNumber',      runNumber, ...
    'V_reverse',      V_reverse, ...
    'V_acceleration', V_acceleration, ...
    'V_heater',       V_heater, ...
    'notes',          runNotes, ...
    'scope',          strtrim(idn), ...
    'voltsPerDiv',    voltsPerDiv, ...
    'recordLength',   recordLength);

save( ...
    matFile, ...
    'runInfo', ...
    'CH1', ...
    'CH2', ...
    'AcceleratingVoltage', ...
    'FranckHertzSignal', ...
    'time_1', ...
    'time_2', ...
    'time_us', ...
    'x_incr_1', ...
    'x_incr_2', ...
    'x_zero_1', ...
    'x_zero_2', ...
    'y_mult_1', ...
    'y_mult_2', ...
    'y_zero_1', ...
    'y_zero_2', ...
    'y_off_1', ...
    'y_off_2');


%% ============================================================
% 17b. RUN INFO FILE AND RUN LOG
% ============================================================
%
% <runID>_info.txt  : human-readable settings for this run
% run_log.csv       : one row per run, all runs over time
%
% ============================================================

infoFile = fullfile(runFolder, [runID '_info.txt']);

fileID = fopen(infoFile, 'w');
fprintf(fileID, 'Run ID          : %s\n', runID);
fprintf(fileID, 'Timestamp       : %s\n', runInfo.timestamp);
fprintf(fileID, 'Run number      : %d\n', runNumber);
fprintf(fileID, 'V_reverse       : %.4g V\n', V_reverse);
fprintf(fileID, 'V_acceleration  : %.4g V\n', V_acceleration);
fprintf(fileID, 'V_heater        : %.4g V\n', V_heater);
fprintf(fileID, 'Notes           : %s\n', runNotes);
fprintf(fileID, 'Oscilloscope    : %s\n', runInfo.scope);
fprintf(fileID, 'CH1 / CH2 V/div : %g / %g\n', voltsPerDiv);
fprintf(fileID, 'Record length   : %d\n', recordLength);
fprintf(fileID, 'Matched points  : %d\n', length(CH1_common));
fprintf(fileID, 'CH1 min / max   : %.4f / %.4f V\n', ...
    min(CH1_common), max(CH1_common));
fprintf(fileID, 'CH2 min / max   : %.4f / %.4f V\n', ...
    min(CH2_common), max(CH2_common));
fclose(fileID);

logFile = fullfile(scriptFolder, 'run_log.csv');
newLog  = ~isfile(logFile);

fileID = fopen(logFile, 'a');
if newLog
    fprintf(fileID, ['RunID,Timestamp,RunNumber,V_reverse_V,' ...
        'V_acceleration_V,V_heater_V,CH1_min_V,CH1_max_V,' ...
        'CH2_min_V,CH2_max_V,Points,Folder,Notes\n']);
end
fprintf(fileID, '%s,%s,%d,%.4g,%.4g,%.4g,%.4f,%.4f,%.4f,%.4f,%d,"%s","%s"\n', ...
    runID, runInfo.timestamp, runNumber, ...
    V_reverse, V_acceleration, V_heater, ...
    min(CH1_common), max(CH1_common), ...
    min(CH2_common), max(CH2_common), ...
    length(CH1_common), runFolder, ...
    strrep(runNotes, '"', '""'));
fclose(fileID);


%% ============================================================
% 18. PRINT SUMMARY
% ============================================================

disp('================================================');
disp('             ACQUISITION SUMMARY');
disp('================================================');

fprintf('\nCH1:\n');
fprintf('  Minimum = %.4f V\n', min(CH1_common));
fprintf('  Maximum = %.4f V\n', max(CH1_common));

fprintf('\nCH2:\n');
fprintf('  Minimum = %.4f V\n', min(CH2_common));
fprintf('  Maximum = %.4f V\n', max(CH2_common));

fprintf('\nNumber of matched data points = %d\n', ...
    length(CH1_common));

disp(' ');
disp('================================================');
disp('               FILES SAVED');
disp('================================================');

disp(' ');
disp('GRAPH 1 — CH1 & CH2 WAVEFORMS');

fprintf('%s\n', txtFile1);
fprintf('%s\n', pngFile1);
fprintf('%s\n', figFile1);

disp(' ');
disp('GRAPH 2 — FRANCK-HERTZ CURVE');

fprintf('%s\n', txtFile2);
fprintf('%s\n', pngFile2);
fprintf('%s\n', figFile2);

disp(' ');
fprintf('Additional MATLAB data:\n%s\n', matFile);
fprintf('Run info:\n%s\n', infoFile);
fprintf('Run log (all runs):\n%s\n', logFile);

disp(' ');


%% ============================================================
% 19. CLOSE OSCILLOSCOPE
% ============================================================

fprintf(visaObj, 'ACQuire:STATE RUN');   % resume live display

fclose(visaObj);

disp('Oscilloscope connection closed.');

disp(' ');
disp('================================================');
disp('          ACQUISITION COMPLETE');
disp('================================================');


%% ============================================================
% LOCAL FUNCTIONS
% ============================================================

function raw = readCurve(visaObj)
% Read the current DATa:SOUrce as 1-byte binary (row vector
% of raw ADC levels).
    fprintf(visaObj, 'CURVE?');
    raw = double(binblockread(visaObj, 'int8')).';
    fread(visaObj, 1);   % drop the trailing line feed
end

function tag = numTag(v)
% Filename-safe number: 1.5 -> '1p50', -2.25 -> 'm2p25'.
    tag = strrep(strrep(sprintf('%.2f', v), '.', 'p'), '-', 'm');
end

function setVertical(visaObj, ch, scale, offset)
% Set volts/div (fine resolution) and centre the signal.
    fprintf(visaObj, sprintf('%s:SCAle %g', ch, scale));
    fprintf(visaObj, sprintf('%s:OFFSet %g', ch, offset));
    fprintf(visaObj, sprintf('%s:POSition 0', ch));
end
