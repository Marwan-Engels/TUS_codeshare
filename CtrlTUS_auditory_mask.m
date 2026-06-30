%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%                                                                         %
%                                NOTES                                    %
%                                                                         %
% Author: Marwan Engels
% Date: 30/06/2026
% Labs: Motivational & Cognitive Control lab & Cognitive Neuromodulation Lab
%       Donders Institute, Nijmegen.
%
% This script creates the Auditory Mask
% Simultaneously delivers a TUS protocol, plays an auditory masking souhnd, and records Localite Instrument markers. 
% - Can run both a full TUS protocol and a pilot version (i.e., 5 seconds stimulation) 
%
% NOTE: DEVELOPMENT STATUS: This script is currently under active development and is provided AS IS. 
% Script may be incomplete, undergo significant changes, or contain bugs. Use at your own discretion.
%
% Matlab 2023B                                                            
% PRESTUS Git version: @ e6bd1b2                                          
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%% ControlTUS Auditory Mask Sample Generator
% Author: Marwan Engels
% Date: 28-04-2026




clear, close all

% Set seed
rng(3004)

% Set input path
pathway = pwd;
dir.out = fullfile(pathway, "output");

% Create output folder
if ~exist(dir.out, 'dir')
    mkdir(dir.out);
end

%% --------------------------------------------------------------------- %
%                      Create Sample of Auditory Mask                    %
% ---------------------------------------------------------------------- %
disp('Creating auditory masking stimulus.')
% Request user inputs
%sec = input('Enter required sample length (s): '); % Input total sample length
sec = 60;
%prf = input('Enter PRF (Hz): '); % Input pulse repetition frequency
prf = 5;
%DC = input('Enter Duty Cycle (%): '); % Input Pulse duration
DC = 20;
%snr = input('Enter signal-to-noise ratio (denominator): '); % Input signal-to-noise ratio
snr = 14;
%Tukey_ms = input('Enter Tukey ramp amount (ms): '); % Tukey ramp amount
Tukey_ms = 10;
%sin_freq = input('Enter frequency of extra sine wave (kHz): ')
sin_freq = 16; % kHz

% Set basic parameters
fs = 48000; % 48kHz sampling frequency (professional music/audio standard).
t = 0:1/fs:(sec - 1/fs); % time vector
period = 1/prf; % pulse repetition period

% Create square wave
square_signal = (square(2*pi*prf*t, DC)+1)/2; % square wave

% ---------------------------------------------------------------------- 
% Create Tukey ramp
ramp_samples = round(Tukey_ms/1000 * fs); % ms ramp in samples

% Cosine onset (0 -> 1) and offset (1 -> 0) ramps
onset_ramp  = (1 - cos(pi * (0:ramp_samples-1) / (ramp_samples-1))) / 2;
offset_ramp = fliplr(onset_ramp);

% Find on-segment boundaries
padded   = [0, square_signal, 0];
rise_idx = find(diff(padded) >  0.5); % start indices of on-segments
fall_idx = find(diff(padded) < -0.5); % end indices of on-segments

for k = 1:length(rise_idx)
    on_start = rise_idx(k);
    on_end   = fall_idx(k) - 1;
    on_len   = on_end - on_start + 1;

    if on_len >= 2 * ramp_samples  % only ramp if pulse is long enough
        square_signal(on_start : on_start+ramp_samples-1) = ...
            square_signal(on_start : on_start+ramp_samples-1) .* onset_ramp;

        square_signal(on_end-ramp_samples+1 : on_end) = ...
            square_signal(on_end-ramp_samples+1 : on_end) .* offset_ramp;
    end
end

% ------------------------------------------------------------------------

% Create noise signal
noiseRatio = 1/snr; % compute noise ratio 
noise = sqrt(noiseRatio)* randn(size(t)); % generate pure noise signal

% Create x kHz sinewave signal
sine_amp = 1; % adjust this to scale the sine wave
sin_freqHZ = sin_freq*1000; % convert kHz to Hz
sine = sine_amp * sin(2*pi*sin_freqHZ*t);

% Combine signals
signal = square_signal + noise; % Squarewave + Noise
signal_sine = square_signal + noise + sine; % Alternative signal: Squarewave + Noise + 16kHz sine

% Normalize signal to avoid clipping
signal = signal./max(abs(signal));
signal_sine = signal_sine./max(abs(signal_sine));

% ---------------------------------------------------------------------- %
%                          Fourier Transformation                        %
% ---------------------------------------------------------------------- %
% Fourier / Frequency spectrum
T   = sec; % total sample duration
L   = fs * T;
Fsh = L / 2;
f   = (0:L-1)/L*fs - fs/2;

% Signal
Y        = fft(signal) / L;
full_amp = abs(fftshift(Y));

% Signal + sine
Y_sine        = fft(signal_sine) / L;
full_amp_sine = abs(fftshift(Y_sine));

%% ---------------------------------------------------------------------- %
%                             Plot Wavelets                              %
% ---------------------------------------------------------------------- %
disp('Plotting wavelets')
figure()

% --- Waveform ---
subplot(3,1,1);
hold on
plot(t, signal, '-r', 'linewidth', .7);
plot(t, square_signal, '-b', 'linewidth', 1.3);
hold off
axis([0 1 -.5 2]);
title(['Waveform for ', num2str(prf), 'Hz TUS protocol']);
xlabel('Time (s)');
ylabel('Amplitude (normalized)');
legend('Signal with noise', 'TUS on-off');
set(gca, 'FontSize', 14);

% --- Frequency spectrum (signal) ---
subplot(3,1,2);
plot(f((Fsh+1):(2*Fsh-1)), full_amp((Fsh+1):(2*Fsh-1)));
xlim([0 20000]);
title('Frequency Spectrum - Signal');
xlabel('Frequency (Hz)');
ylabel('Power (a.u.)');
set(gca, 'FontSize', 14);

% --- Frequency spectrum (signal + sine) ---
subplot(3,1,3);
plot(f((Fsh+1):(2*Fsh-1)), full_amp_sine((Fsh+1):(2*Fsh-1)), 'color', [0.8 0 0.8]);
xlim([0 20000]);
title(['Frequency Spectrum - Signal + ', num2str(sin_freq), 'kHz Sine']);
xlabel('Frequency (Hz)');
ylabel('Power (a.u.)');
set(gca, 'FontSize', 14);


% Save after all subplots are drawn
% PNG
disp('Saving png...')
saveas(gcf, fullfile(dir.out, [num2str(T),'sec_',num2str(prf),'Hz_',num2str(DC),'DC', num2str(Tukey_ms),'msTukeyRamp_1', num2str(snr),'SNR_', 'Waveform.png']));
%PDF
disp('Saving pdf...')
exportgraphics(gcf, fullfile(dir.out, [num2str(prf), 'Hz_Waveform.pdf']), 'ContentType', 'vector');

%%
% ---------------------------------------------------------------------- %
%                          Save Signal as .txt                           %
% ---------------------------------------------------------------------- %
N = 1:length(square_signal);
M = [N; t; square_signal; signal]';

%csvwrite('M1TUS2.0_mask.txt', M)
%%
% ---------------------------------------------------------------------- %
%                           Save File as .wav                            %
% ---------------------------------------------------------------------- %
disp('Saving sound file: SquareWave+Noise')
% Safe .wav file
filename = fullfile(dir.out, ['CtrlTUS_auditorymask_squarewave_dur', ...
    num2str(T), 's_prf', ...
    num2str(prf), 'Hz_', ...
    num2str(DC), 'DC_', ...
    num2str(Tukey_ms), 'msTukeyRamp_', ...
    num2str(snr), 'SNR', ...
    '.wav']);

audiowrite(filename, signal, fs);

fprintf('Saving sound file: SquareWave+Noise+%g\n', sin_freq)

% Safe .wav file
filename_sine = fullfile(dir.out, ['CtrlTUS_auditorymask_squarewave_', ...
    num2str(sin_freq), 'kHzsine_dur', ...
    num2str(T), 's_prf', ...
    num2str(prf), 'Hz_', ...
    num2str(DC), 'DC_', ...
    num2str(Tukey_ms), 'msTukeyRamp_', ...
    num2str(snr), 'SNR', ...
    '.wav']);

audiowrite(filename_sine, signal_sine, fs);

disp('Script finished successfully.')