function data = processSpike2Batch(data, opts)
% processSpike2Batch  Smooth + baseline/peak-envelope fits for pressure and nerve Hz,
% and compute max volume + optional volume normalization (% of max).
%         Version 1.0
%         Date: July 8, 2026
%         Author: G. Herrera 
%         Co-Author/AI Tool: OpenAI ChatGPT (GPT-5.5)
%         Note: The core workflow was designed by the author and implemented by
%           ChatGPT via prompt engineering. All code was reviewed,
%           modified, and verified by the author.
%
%
% INPUT
%   data : struct array from loadSpike2Batch with fields:
%          .time, .pressure, .nerveHz, .volume, .meta (incl conditionKey/fileTags/etc.)
%   opts : optional struct with fields (defaults shown):
%       .medWindow        = 50      % points for movmedian
%       .meanWindow       = 200     % points for movmean
%       .lambda           = 5e10    % baseline() lambda
%       .sym              = 0.01    % baseline() p (asymmetry)
%       .doPressure       = true
%       .doNerve          = true
%       .normalizeVolume  = true    % compute volumePercent = 100*(v/vMax)
%       .verbose          = true
%
% OUTPUT
%   data : same struct array, with new field .proc containing:
%       .pressureSmooth
%       .pressureBaseline
%       .pressurePeak
%       .nerveSmooth
%       .nerveBaseline
%       .nervePeak
%       .volumeMax_mL
%       .volumePercent (if normalizeVolume = true)
%       .params (windows + baseline params)
%
% Notes
% - "Peak" is computed by flipping around the max of the smoothed signal:
%       flip = max(smooth) - smooth
%       flipBase = baseline(flip, lambda, sym)
%       peak = max(smooth) - flipBase
%
% - No trimming is performed. Filename "sec-sec" notes are treated as provenance only.

    if nargin < 2 || isempty(opts), opts = struct(); end

    % Defaults
    opts = setDefault(opts, 'medWindow', 50);
    opts = setDefault(opts, 'meanWindow', 200);
    opts = setDefault(opts, 'lambda', 5e10);
    opts = setDefault(opts, 'sym', 0.01);
    opts = setDefault(opts, 'doPressure', true);
    opts = setDefault(opts, 'doNerve', true);
    opts = setDefault(opts, 'normalizeVolume', true);
    opts = setDefault(opts, 'verbose', true);

    % Quick checks
    if ~exist('baseline', 'file')
        error('baseline.m not found on the MATLAB path. Add your project folder to the path.');
    end
    if ~isstruct(data) || isempty(data)
        error('Input "data" must be a non-empty struct array from loadSpike2Batch.');
    end

    % Ensure windows are valid positive integers
    medWindow  = max(1, round(opts.medWindow));
    meanWindow = max(1, round(opts.meanWindow));

    for i = 1:numel(data)

        if opts.verbose
            ck = "";
            if isfield(data(i),'meta') && isfield(data(i).meta,'conditionKey')
                ck = " [" + string(data(i).meta.conditionKey) + "]";
            end
            fprintf('Processing %d/%d: %s%s\n', i, numel(data), string(data(i).file), ck);
        end

        % Initialize proc struct
        proc = struct();
        proc.params = struct( ...
            'medWindow', medWindow, ...
            'meanWindow', meanWindow, ...
            'lambda', opts.lambda, ...
            'sym', opts.sym, ...
            'algorithm', 'smooth: movmedian->movmean; baseline: asym. least squares (Eilers/Boelens); peak via flip' );

        % ---- Volume summary + optional normalization ----
        if isfield(data(i),'volume') && ~isempty(data(i).volume)
            v = data(i).volume;
            vMax = max(v, [], 'omitnan');   % max volume achieved in this recording

            if isfinite(vMax) && vMax > 0
                proc.volumeMax_mL = vMax;

                if opts.normalizeVolume
                    proc.volumePercent = 100 * (v ./ vMax);
                end
            else
                proc.volumeMax_mL = NaN;
                if opts.normalizeVolume
                    proc.volumePercent = nan(size(v));
                end
            end
        else
            proc.volumeMax_mL = NaN;
            if opts.normalizeVolume
                proc.volumePercent = [];
            end
        end

        % ---- Pressure processing ----
        if opts.doPressure
            y = data(i).pressure;

            ySmooth = movmean(movmedian(y, medWindow, 'omitnan'), meanWindow, 'omitnan');
            yBase   = baseline(ySmooth, opts.lambda, opts.sym);

            yMax = max(ySmooth, [], 'omitnan');
            yFlip = yMax - ySmooth;
            yFlipBase = baseline(yFlip, opts.lambda, opts.sym);
            yPeak = yMax - yFlipBase;

            proc.pressureSmooth   = ySmooth;
            proc.pressureBaseline = yBase;
            proc.pressurePeak     = yPeak;
        end

        % ---- Nerve Hz processing ----
        if opts.doNerve
            y = data(i).nerveHz;

            ySmooth = movmean(movmedian(y, medWindow, 'omitnan'), meanWindow, 'omitnan');
            yBase   = baseline(ySmooth, opts.lambda, opts.sym);

            yMax = max(ySmooth, [], 'omitnan');
            yFlip = yMax - ySmooth;
            yFlipBase = baseline(yFlip, opts.lambda, opts.sym);
            yPeak = yMax - yFlipBase;

            proc.nerveSmooth   = ySmooth;
            proc.nerveBaseline = yBase;
            proc.nervePeak     = yPeak;

            % Normalize smooth nerve to % of max(10 s moving mean) ----
            % Requires data(i).time in seconds
            if isfield(data(i),'time') && ~isempty(data(i).time)
                t = data(i).time(:);
                sn = ySmooth(:);  % smoothNerve

                if numel(t) ~= numel(sn)
                    error('processSpike2Batch:SizeMismatch', ...
                        'Rep %d: time (%d) and nerveSmooth (%d) sizes do not match.', ...
                        i, numel(t), numel(sn));
                end

                keep = isfinite(t) & isfinite(sn);
                if sum(keep) < 5
                    proc.smoothNerveMovMean10s    = nan(size(sn));
                    proc.smoothNerveMax10sMovMean = NaN;
                    proc.smoothNervePctMax        = nan(size(sn));
                else
                    dt = median(diff(t(keep)), 'omitnan');
                    if ~isfinite(dt) || dt <= 0
                        error('processSpike2Batch:BadTime', ...
                            'Rep %d: invalid time base; cannot compute 10 s moving window.', i);
                    end

                    winSec  = 10;
                    winSamp = max(1, round(winSec / dt));

                    snMov = movmean(sn, winSamp, 'omitnan');
                    snMax = max(snMov(keep), [], 'omitnan');

                    if ~isfinite(snMax) || snMax <= 0
                        snPct = nan(size(sn));
                    else
                        snPct = (sn ./ snMax) * 100;
                    end

                    proc.smoothNerveMovMean10s    = snMov;
                    proc.smoothNerveMax10sMovMean = snMax;
                    proc.smoothNervePctMax        = snPct;
                end
            else
                proc.smoothNerveMovMean10s    = [];
                proc.smoothNerveMax10sMovMean = NaN;
                proc.smoothNervePctMax        = [];
            end
        end


        % Attach processed results
        data(i).proc = proc;
    end
end

% ---------------- helpers ----------------

function opts = setDefault(opts, name, value)
if ~isfield(opts, name) || isempty(opts.(name))
    opts.(name) = value;
end
end
