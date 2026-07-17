function data = detectTPEs(data, opts)
% detectTPEs  Detect transient pressure events (TPEs) using findpeaks on baseline-subtracted pressure.
%         Version 1.0
%         Date: July 9, 2026
%         Author: G. Herrera 
%         Co-Author/AI Tool: OpenAI ChatGPT (GPT-5.5)
%         Note: The core architecture was designed by the author and implemented by
%           ChatGPT via prompt engineering. All code was reviewed,
%           modified, and verified by the author.
%
% Workflow:
%   pressureBaseSub = pressureSmooth - pressureBaseline
%   analyze only between startFrac and endFrac of the trace
%   findpeaks with MinPeakProminence and MaxPeakWidth
%   compute inter-contraction interval, contractions/min, total frequency
%   store peak metrics + baseline pressure and volume at TPE locations
%
% Requires fields from processSpike2Batch:
%   data(i).proc.pressureSmooth
%   data(i).proc.pressureBaseline
%   data(i).volume
%   data(i).proc.volumePercent
%   data(i).time
%
% opts defaults:
%   .minPeakProm_mmHg = 0.10
%   .maxPeakWidth_s   = 30        % 1000 samples at 100 Hz equivalent
%   .maxPeakWidth_samples = []    % optional override
%   .startFrac = 0.11
%   .endFrac   = 0.98
%   .minPeakDistance_s = []       % optional (helpful if double-peaks occur)
%   .fs_Hz = []                   % if empty, inferred per file from time
%   .storeBaseSub = true
%   .verbose = true

    if nargin < 2 || isempty(opts), opts = struct(); end
    opts = setDefault(opts,'minPeakProm_mmHg',0.10);
    opts = setDefault(opts,'maxPeakWidth_s',30);
    opts = setDefault(opts,'maxPeakWidth_samples',[]);
    opts = setDefault(opts,'startFrac',0.11);
    opts = setDefault(opts,'endFrac',0.98);
    opts = setDefault(opts,'minPeakDistance_s',[]);
    opts = setDefault(opts,'fs_Hz',[]);
    opts = setDefault(opts,'storeBaseSub',true);
    opts = setDefault(opts,'verbose',true);

    if ~isstruct(data) || isempty(data)
        error('Input "data" must be a non-empty struct array.');
    end

    for i = 1:numel(data)

        % --- Validate required fields ---
        requireField(data(i),'time', i);
        requireField(data(i),'volume', i);
        requireProcField(data(i),'pressureSmooth', i);
        requireProcField(data(i),'pressureBaseline', i);

        % volumePercent is optional but requested in your outputs; handle if missing
        hasVolPct = isfield(data(i),'proc') && isfield(data(i).proc,'volumePercent') && ~isempty(data(i).proc.volumePercent);

        t = data(i).time(:);
        pSmooth = data(i).proc.pressureSmooth(:);
        pBase   = data(i).proc.pressureBaseline(:);
        vol     = data(i).volume(:);

        if numel(pSmooth) ~= numel(pBase) || numel(pSmooth) ~= numel(t) || numel(pSmooth) ~= numel(vol)
            error('Length mismatch in file %d: time/pressureSmooth/pressureBaseline/volume must be same length.', i);
        end

        % --- Sample rate ---
        if isempty(opts.fs_Hz)
            dt = median(diff(t), 'omitnan');
            if ~isfinite(dt) || dt <= 0
                error('Could not infer sample rate from time for file %d.', i);
            end
            fs = 1/dt;
        else
            fs = opts.fs_Hz;
        end

        % --- Baseline-subtracted pressure ---
        pBaseSub = pSmooth - pBase;

        % --- Analysis window indices (global indices in full trace) ---
        n = numel(pSmooth);
        startIdx = max(1, floor(opts.startFrac * n));
        endIdx   = min(n, ceil(opts.endFrac * n));

        if endIdx <= startIdx
            error('Invalid analysis window for file %d: startIdx=%d endIdx=%d', i, startIdx, endIdx);
        end

        % Subvector for detection
        x = pBaseSub(startIdx:endIdx);

        % --- findpeaks parameter conversion ---
        if ~isempty(opts.maxPeakWidth_samples)
            maxW = max(1, round(opts.maxPeakWidth_samples));
        else
            maxW = max(1, round(opts.maxPeakWidth_s * fs));
        end

        fpArgs = {'MinPeakProminence', opts.minPeakProm_mmHg, ...
                  'MaxPeakWidth', maxW};

        if ~isempty(opts.minPeakDistance_s)
            minD = max(1, round(opts.minPeakDistance_s * fs));
            fpArgs = [fpArgs, {'MinPeakDistance', minD}];
        end

        % --- Peak detection (locs are relative to x; convert to global) ---
        [pks, locsRel, widthsSamp, proms] = findpeaks(x, fpArgs{:});

        locs = locsRel + (startIdx - 1); % global indices into full trace

        % --- Inter-contraction interval and frequency metrics ---
        % intervals in seconds based on fs
        intConInt_s = diff(locs) / fs;

        % contractions per minute between successive peaks
        contPerMin = (1 ./ intConInt_s) * 60;

        numTPEs = numel(pks);  % matches your prior definition
        recordDur_min = (t(endIdx) - t(startIdx)) / 60;

        if isfinite(recordDur_min) && recordDur_min > 0
            contFreqTotal = numTPEs / recordDur_min;
        else
            contFreqTotal = NaN;
        end

        % --- Baseline pressure & volume at each TPE location ---
        tpeBasePressure = pBase(locs);
        tpeVolume = vol(locs);

        if hasVolPct
            tpeVolumeNormalized = data(i).proc.volumePercent(locs);
        else
            tpeVolumeNormalized = [];
        end

        % --- Package results ---
        ev = struct();

        ev.params = struct( ...
            'minPeakProm_mmHg', opts.minPeakProm_mmHg, ...
            'maxPeakWidth_s', opts.maxPeakWidth_s, ...
            'maxPeakWidth_samples', maxW, ...
            'startFrac', opts.startFrac, ...
            'endFrac', opts.endFrac, ...
            'startAnalysisIdx', startIdx, ...
            'endAnalysisIdx', endIdx, ...
            'fs_Hz', fs);

        if opts.storeBaseSub
            ev.pressureBaseSub = pBaseSub;
        end

        % Raw outputs
        ev.pks = pks;
        ev.locs = locs;
        ev.prominences = proms;
        ev.widths_samples = widthsSamp;
        ev.widths_s = widthsSamp / fs;

        % Summary stats
        ev.meanPks = mean(pks, 'omitnan');
        ev.meanProm = mean(proms, 'omitnan');
        ev.meanWidth_samples = mean(widthsSamp, 'omitnan');
        ev.meanWidth_s = mean(widthsSamp / fs, 'omitnan');
        ev.meanTPEbasePressure = mean(tpeBasePressure, 'omitnan');

        % Interval / frequency outputs
        ev.intConInt_s = intConInt_s;
        ev.meanIntConInt_s = mean(intConInt_s, 'omitnan');

        ev.contPerMin = contPerMin;
        ev.meanContPerMin = mean(contPerMin, 'omitnan');

        ev.numTPEs = numTPEs;
        ev.recordDur_min = recordDur_min;
        ev.contFreqTotal_perMin = contFreqTotal;

        % Values at TPEs
        ev.tpeBasePressure = tpeBasePressure;
        ev.tpeVolume_mL = tpeVolume;
        ev.tpeVolumePercent = tpeVolumeNormalized;

        % Times at peaks
        ev.tpeTime_s = t(locs);

        % Attach back to data
        if ~isfield(data(i),'events') || ~isstruct(data(i).events)
            data(i).events = struct();
        end
        data(i).events.pressureTPE = ev;

        if opts.verbose
            lbl = "";
            if isfield(data(i),'meta') && isfield(data(i).meta,'conditionKey')
                lbl = " [" + string(data(i).meta.conditionKey) + "]";
            end
            fprintf('TPEs %d/%d: found %d peaks%s\n', i, numel(data), numel(pks), lbl);
        end
    end
end

% ---------------- helpers ----------------

function opts = setDefault(opts, name, value)
    if ~isfield(opts, name) || isempty(opts.(name))
        opts.(name) = value;
    end
end

function requireField(d, field, i)
    if ~isfield(d, field) || isempty(d.(field))
        error('Missing data(%d).%s.', i, field);
    end
end

function requireProcField(d, field, i)
    if ~isfield(d,'proc') || ~isfield(d.proc, field) || isempty(d.proc.(field))
        error('Missing data(%d).proc.%s. Run processSpike2Batch first.', i, field);
    end
end
