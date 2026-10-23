function cfg = config()
%CONFIG  All measurement and analysis parameters in one place.

cfg.lang = 'tr';                        % figure language: 'tr' or 'en'

% --- Devices (case-insensitive substring of the Windows device name) ---
cfg.dev.stethoscope = 'Teensy';         % "Dijital Ses Arabirimi (Teensy Audio)"
cfg.dev.reference   = '';               % reference mic disabled (cheap mics proved unreliable); e.g. 'Mikrofon (Realtek'
cfg.dev.speaker     = 'Headphones';     % laptop (XPS 17) 3.5 mm jack -> headset driver in the box; desktop: 'Realtek'

% --- Recording formats (native formats reported by Windows) ---
cfg.rec.fsSteth  = 44100;  cfg.rec.chSteth = 2;   % Teensy UAC: 2 ch / 44.1 kHz / 16 bit
cfg.rec.fsRef    = 48000;  cfg.rec.chRef   = 1;   % Realtek mic in: 48 kHz / 16 bit
cfg.rec.nBits    = 16;
cfg.rec.stethChannel = 1;               % INMP441 is on the left I2S channel
cfg.rec.tailMargin   = 2.0;             % s recorded after playback ends
cfg.rec.externalStartWindow = 12;       % s countdown to press play in 'external' mode

% --- Stimulus (stepped pure tones) ---
cfg.stim.fs          = 48000;
cfg.stim.freqs       = [30:10:200, 225:25:500, 550:50:1000];          % model band
cfg.stim.freqsExt    = [1100 1250 1500 1750 2000 2500 3000 4000 5000 6000]; % roll-off
cfg.stim.toneDur     = 2.0;             % s
cfg.stim.gapDur      = 0.5;             % s silence between tones
cfg.stim.fadeDur     = 0.02;            % s raised-cosine fade in/out
cfg.stim.amp         = 0.125;           % digital peak amplitude (-18 dBFS); 0.5 clipped the Teensy at 2 kHz with the wired headset
cfg.stim.leadSilence = 2.0;             % s, lets the Bluetooth link wake up
cfg.stim.noiseDur    = 4.0;             % s in-run silence used as noise floor
cfg.stim.chirpDur    = 0.5;             % s sync chirp at start and end
cfg.stim.chirpF      = [300 3000];      % Hz, log sweep inside both devices' band

% --- Heart-sound (PCG) playback test ---
cfg.pcg.dir       = fullfile(fileparts(mfilename('fullpath')), 'pcg_test', 'clips');  % made by pcg_test/select_clips.py (PhysioNet + PASCAL-B test split)
cfg.pcg.hpf       = 20;                 % Hz, 4th-order Butterworth high-pass, zero-phase (removes DC/baseline the speaker cannot play)
cfg.pcg.fadeDur   = 0.01;               % s raised-cosine fade at clip edges
cfg.pcg.peakDbfs  = -6;                 % common digital peak level of every clip; pcg_level_check 2026-10-09:
                                        % every 6 dB step from -18 to 0 dBFS measured 5.9-6.4 dB, no clipping;
                                        % steth peaks <= -10 dBFS at -6
cfg.pcg.gapDur    = 1.5;                % s silence between clips
cfg.pcg.showCorrection = true;          % figures H4/H5: diagnostic correction with the inverse tone response,
                                        % shown after and separate from the uncorrected result (the correction
                                        % includes the stethoscope's own response, so it is not its performance)
cfg.pcg.levelCheckClips  = [1 2 3 4];   % filename_map rows used by pcg_level_check (PhysioNet N, PASCAL A, PASCAL N, PhysioNet A)
cfg.pcg.levelCheckLevels = [-18 -12 -6];% dBFS peak levels compared by pcg_level_check
cfg.paths.pcg     = fullfile(fileparts(mfilename('fullpath')), 'pcg_test');

% --- Analysis ---
cfg.ana.skipStart   = 0.4;              % s ignored after each tone onset
cfg.ana.skipEnd     = 0.2;              % s ignored before each tone offset
cfg.ana.zeroPad     = 4;                % FFT zero-padding factor
cfg.ana.searchRel   = 0.05;             % peak search +/- 5 % of nominal frequency
cfg.ana.searchMinHz = 3;                % ...but at least +/- 3 Hz
cfg.ana.nHarm       = 5;                % harmonics 2..nHarm used for THD
cfg.ana.thdMaxF     = 20000;            % ignore harmonics above this (Hz)
cfg.ana.normFreq    = 250;              % 0 dB reference frequency for responses
cfg.ana.useReference = false;           % false: ignore reference.wav in analysis and figures
cfg.ana.refMinSnr   = 20;               % dB; reference points below this are not plotted

% --- Thesis signal chain (used to mark plots) ---
cfg.thesis.band  = [25 900];            % Butterworth bandpass / Mel range (Hz)
cfg.thesis.fsDec = 44100/11;            % 4009.09 Hz after decimation
cfg.thesis.showDecimationMarks = false; % draw the 4009 Hz Nyquist line / -0.227 % labelling-error line?
                                        % false: the device streams 44.1 kHz, the app resamples (thesis §3.3.1 variant A)
cfg.thesis.selectedTones = [50 100 200 400 700 1000];

% --- Output ---
cfg.paths.data    = fullfile(fileparts(mfilename('fullpath')), 'data');
cfg.paths.figures = fullfile(fileparts(mfilename('fullpath')), 'figures');
cfg.paths.stim    = fullfile(fileparts(mfilename('fullpath')), 'stimulus');
cfg.fig.width     = 16;                 % cm (A4 single column)
cfg.fig.height    = 9;                  % cm
cfg.fig.font      = 'Times New Roman';
cfg.fig.fontSize  = 10;
cfg.fig.dpi       = 300;
cfg.fig.respYlim  = [-40 30];          % common dB axis of the response figures (A and H1; advisor's review)
end
