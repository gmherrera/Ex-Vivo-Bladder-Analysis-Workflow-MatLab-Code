function data = loadSpike2Batch(fileInput, opts)
% loadSpike2Batch  Load Spike2 Spreadsheet Text files, select channels, compute volume,
% and extract filename metadata (ALL underscore tags) + parsed indicators (FillN, conditions, sec-sec window).
%         Version 1.0
%         Date: July 8, 2026
%         Author: G. Herrera 
%         Co-Author/AI Tool: OpenAI ChatGPT (GPT-5.5)
%         Note: The core workflow was designed by the author and implemented by
%           ChatGPT via prompt engineering. All code was reviewed,
%           modified, and verified by the author.
%         Version History:
%                 1.0 - Initial Release July 8, 2026
%
% INPUTS
%   fileInput : either:
%       1) string/cellstr/char list of full paths to Spike2 TXT/TSV files
%          Example:
%              data = loadSpike2Batch(string({info.file}));
%
%       2) struct array returned by inspectSpike2Txt()
%          Example:
%              info = inspectSpike2Txt();
%              data = loadSpike2Batch(info);
%
%          When an info struct is supplied, the matching inspector record is
%          stored in data(i).meta.importInfo automatically.
%
%   opts      : optional struct with fields:
%       .defaultRate_mL_per_hr (default 1.8)
%       .defaultV0_mL          (default 0.000)
%       .defaultVolumeMode     'ask', 'filling', or 'stable'
%       .keyboardClusterGap_s  (default 30)
%
% OUTPUT
%   data : struct array with fields:
%       .file
%       .time
%       .pressure
%       .nerveHz
%       .keyboard              % raw keyboard/event channel, if present
%       .volume
%       .events.keyboardTimes       % timestamps for collapsed Keyboard event clusters
%       .events.keyboardIdx         % sample indices for collapsed Keyboard event cluster starts
%       .events.keyboardStrokeTimes % timestamps for individual Keyboard rising edges/key strokes
%       .events.keyboardStrokeIdx   % sample indices for individual Keyboard rising edges/key strokes
%       .meta (labels, dt, volume params, filename tags + parsed indicators)
%
% NOTES
% - Volume model can be either:
%     * filling: V(t) = V0 + rate*(t - tStart), where rate is mL/s
%     * stable:  V(t) = constant volume throughout the recording
% - Filename tags are ALL underscore-delimited chunks (stored losslessly, hyphens/dots preserved).
% - Parsed indicators:
%     * FillN from filename tags
%     * Named conditions (Baseline, Indomethacin, Control, etc.)
%     * Optional window "<start>sec-<end>sec" anywhere in filename
%
% Examples:
%   info = inspectSpike2Txt();
%   data = loadSpike2Batch(info);                 % preferred: embeds info in data(i).meta.importInfo
%
%   data = loadSpike2Batch(string({info.file}));  % also supported, but does not embed info

    if nargin < 1 || isempty(fileInput)
        error(['Please pass either file paths or the info struct from inspectSpike2Txt, e.g.\n' ...
               '  info = inspectSpike2Txt();\n' ...
               '  data = loadSpike2Batch(info);\n']);
    end

    importInfo = [];
    if isstruct(fileInput)
        if ~isfield(fileInput, 'file')
            error('When fileInput is a struct, it must contain a .file field, as returned by inspectSpike2Txt().');
        end
        importInfo = fileInput(:);
        filePaths = string({importInfo.file});
    else
        filePaths = string(fileInput);
    end

    if nargin < 2 || isempty(opts)
        opts = struct();
    end

    % Defaults
    if ~isfield(opts,'defaultRate_mL_per_hr'), opts.defaultRate_mL_per_hr = 1.8;   end
    if ~isfield(opts,'defaultV0_mL'),          opts.defaultV0_mL         = 0.000; end
    if ~isfield(opts,'defaultVolumeMode'),     opts.defaultVolumeMode    = 'ask'; end  % 'ask', 'filling', or 'stable'
    if ~isfield(opts,'keyboardClusterGap_s'),  opts.keyboardClusterGap_s = 30;    end  % collapse keystrokes separated by <= this gap into one event

    % Volume workflow:
    %   filling = compute volume as V0 + rate*(t-tStart)
    %   stable  = volume is constant through the file (steady-state/non-filling segment)
    [volumeModePerFile, ratePerFile, V0PerFile] = promptVolumeWorkflow( ...
        filePaths, opts.defaultVolumeMode, opts.defaultRate_mL_per_hr, opts.defaultV0_mL);

    % Condition dictionary (expandable)
    condDict = getConditionDictionary();

    % Cache Hz-column choice for repeated header layouts (ask once, reuse)
    persistent hzChoiceCache
    if isempty(hzChoiceCache)
        hzChoiceCache = containers.Map('KeyType','char','ValueType','char');
    end


    % Load each file
    data = repmat(emptyDataStruct(), numel(filePaths), 1);

    for i = 1:numel(filePaths)
        f = filePaths(i);

        % Read Spike2 export table (tab-delimited; quoted headers preserved)
        T = readtable(f, ...
            'FileType','text', ...
            'Delimiter','\t', ...
            'ReadVariableNames',true, ...
            'VariableNamingRule','preserve');

        headers = T.Properties.VariableNames;

        % ---- Select channels by header labels ----
        timeIdx = find(strcmpi(strtrim(headers), "Time"), 1, 'first');
        if isempty(timeIdx)
            timeIdx = find(contains(lower(headers), "time"), 1, 'first');
        end
        if isempty(timeIdx)
            error('Could not identify Time column in: %s', f);
        end

        [pIdx, pCand] = choosePressure(headers);
        [nIdx, nCand] = chooseNerveHz(headers);
        [kIdx, kCand] = chooseKeyboard(headers);

        if isempty(pIdx)
            error('No pressure channel selected in: %s', f);
        end

        % ---- Hz channel fallback: prompt user if auto-detect fails ----
        if isempty(nIdx)
            % Build a cache key from the headers (excluding Time to avoid weird matches)
            hdr = string(headers);
            hdrNoTime = hdr(~strcmpi(strtrim(hdr), "Time"));
            headerKey = strjoin(hdrNoTime, "|");

            if isKey(hzChoiceCache, char(headerKey))
                chosenName = string(hzChoiceCache(char(headerKey)));
            else
                chosenName = promptSelectHzChannel(hdrNoTime, f);
                if strlength(chosenName) > 0
                    hzChoiceCache(char(headerKey)) = char(chosenName);
                end
            end

            if strlength(chosenName) == 0
                error('No nerve Hz channel selected in: %s', f);
                % Alternative behavior (skip file instead of error):
                % warning('Skipping file (no Hz selected): %s', f);
                % continue
            end

            % Convert chosen header name back to index in original headers list
            nIdx = find(strcmp(string(headers), chosenName), 1, 'first');
            if isempty(nIdx)
                error('Selected Hz channel "%s" not found in headers for: %s', chosenName, f);
            end

            % Update candidates list to include what user picked (nice for recordkeeping)
            nCand = headers(nIdx);
        end



        t = T{:, timeIdx};
        p = T{:, pIdx};
        n = T{:, nIdx};

        % ---- Optional Keyboard/event channel ----
        if ~isempty(kIdx)
            keyboard = T{:, kIdx};
        else
            keyboard = [];
        end

        if numel(t) < 2
            error('Time vector too short in: %s', f);
        end

        dt = t(2) - t(1);

        % ---- Compute or assign volume ----
        t0 = t(1);
        V0 = V0PerFile(i);
        r  = ratePerFile(i); % mL/s
        volumeMode = string(volumeModePerFile(i));

        switch lower(volumeMode)
            case "filling"
                vol = V0 + r .* (t - t0);
                volumeModel = 'V = V0 + rate*(t - tStart)';
            case "stable"
                r = 0;
                vol = repmat(V0, size(t));
                volumeModel = 'Stable volume: V = constant for entire recording';
            otherwise
                error('Unknown volume mode "%s" for file: %s', volumeMode, f);
        end

        % ---- Parse filename metadata (ALL tags + known indicators) ----
        fnameMeta = parseFilenameMetadata(f, condDict);

        % ---- Populate output ----
        d = emptyDataStruct();
        d.file     = char(f);
        d.time     = t;
        d.pressure = p;
        d.nerveHz  = n;
        d.keyboard = keyboard;
        d.volume   = vol;

        % Keyboard event handling:
        % 1) Detect individual keystrokes as rising edges in the Keyboard channel.
        % 2) Collapse nearby keystrokes into event clusters. The experimental
        %    event time is the first keystroke in each cluster.
        d.events = struct();
        if ~isempty(keyboard)
            keyboardVec = double(keyboard(:));
            keyboardOn = isfinite(keyboardVec) & keyboardVec ~= 0;

            strokeIdx = find(keyboardOn & [true; ~keyboardOn(1:end-1)]);
            strokeTimes = t(strokeIdx);
            strokeValues = keyboardVec(strokeIdx);

            if isempty(strokeTimes)
                clusterStartIdx = [];
            else
                gap_s = opts.keyboardClusterGap_s;
                isClusterStart = [true; diff(strokeTimes(:)) > gap_s];
                clusterStartIdx = strokeIdx(isClusterStart);
            end

            d.events.keyboardStrokeIdx = strokeIdx;
            d.events.keyboardStrokeTimes = strokeTimes;
            d.events.keyboardStrokeValues = strokeValues;

            d.events.keyboardIdx = clusterStartIdx;
            d.events.keyboardTimes = t(clusterStartIdx);
            d.events.keyboardValues = keyboardVec(clusterStartIdx);
            d.events.keyboardClusterGap_s = opts.keyboardClusterGap_s;
        else
            d.events.keyboardStrokeIdx = [];
            d.events.keyboardStrokeTimes = [];
            d.events.keyboardStrokeValues = [];

            d.events.keyboardIdx = [];
            d.events.keyboardTimes = [];
            d.events.keyboardValues = [];
            d.events.keyboardClusterGap_s = opts.keyboardClusterGap_s;
        end

        % Channel meta
        d.meta.timeLabel          = headers{timeIdx};
        d.meta.pressureLabel      = headers{pIdx};
        d.meta.nerveHzLabel       = headers{nIdx};
        if ~isempty(kIdx)
            d.meta.keyboardLabel   = headers{kIdx};
        else
            d.meta.keyboardLabel   = '';
        end
        d.meta.pressureCandidates = pCand;
        d.meta.nerveCandidates    = nCand;
        d.meta.keyboardCandidates = kCand;

        % Volume meta
        d.meta.dt_s               = dt;
        d.meta.volumeMode         = char(volumeMode);
        d.meta.fillRate_mL_per_s  = r;
        d.meta.fillRate_mL_per_hr = r * 3600;
        d.meta.initialVolume_mL   = V0;
        d.meta.volumeModel        = volumeModel;

        % Filename meta (lossless tags) + parsed indicators
        d.meta.fileBase           = fnameMeta.fileBase;
        d.meta.fileTags           = fnameMeta.fileTags;          % ALL underscore tags, lossless
        d.meta.conditionTokens    = fnameMeta.conditionTokens;   % ALL tags (per your request)
        d.meta.conditionKey       = fnameMeta.conditionKey;      % derived grouping key from known indicators
        d.meta.parsed             = fnameMeta.parsed;            % nested parsed fields

        % Full import provenance from inspectSpike2Txt(), if supplied.
        % This makes data self-contained so a separate info variable does
        % not have to be saved or kept synchronized.
        if ~isempty(importInfo)
            d.meta.importInfo = importInfo(i);
        end

        data(i) = d;
    end
end

% =====================================================================
% Dialog helper
% =====================================================================

function [modePerFile, ratePerFile, V0PerFile] = promptVolumeWorkflow(filePaths, defaultMode, defaultRate_mL_per_hr, defaultV0_mL)
% Prompt for volume handling. Supports true filling cycles and stable-volume files.
%
% modePerFile is string array: "filling" or "stable".
% ratePerFile is mL/s. For stable files, rate = 0.
% V0PerFile is initial/constant volume in mL.

    nFiles = numel(filePaths);

    defaultMode = lower(string(defaultMode));
    if defaultMode == "constant"
        defaultMode = "stable";
    end

    validModes = ["ask","filling","stable"];
    if ~any(defaultMode == validModes)
        error('opts.defaultVolumeMode must be ''ask'', ''filling'', or ''stable''.');
    end

    modePerFile = strings(nFiles,1);
    ratePerFile = nan(nFiles,1);
    V0PerFile   = nan(nFiles,1);

    if defaultMode == "filling" || defaultMode == "stable"
        modeChoice = defaultMode;
        sameMode = true;
    else
        scope = questdlg( ...
            'How should volume be handled for the selected file(s)?', ...
            'Volume workflow', ...
            'All files are filling cycles', ...
            'All files are stable volume', ...
            'Choose per file', ...
            'All files are filling cycles');

        if isempty(scope)
            error('User cancelled.');
        end

        switch scope
            case 'All files are filling cycles'
                modeChoice = "filling";
                sameMode = true;
            case 'All files are stable volume'
                modeChoice = "stable";
                sameMode = true;
            otherwise
                modeChoice = "";
                sameMode = false;
        end
    end

    if sameMode
        modePerFile(:) = modeChoice;

        switch modeChoice
            case "filling"
                [rate_mL_per_s, V0_mL] = promptVolumeParams( ...
                    'Global filling-cycle volume settings', ...
                    defaultRate_mL_per_hr, defaultV0_mL);
                ratePerFile(:) = rate_mL_per_s;
                V0PerFile(:)   = V0_mL;

            case "stable"
                Vstable_mL = promptStableVolume( ...
                    'Global stable-volume setting', defaultV0_mL);
                ratePerFile(:) = 0;
                V0PerFile(:)   = Vstable_mL;
        end

    else
        for i = 1:nFiles
            modeChoice = promptVolumeModeForFile(i, nFiles, filePaths(i));
            modePerFile(i) = modeChoice;

            switch modeChoice
                case "filling"
                    titleStr = sprintf('Filling-cycle volume settings (%d/%d): %s', i, nFiles, filePaths(i));
                    [ratePerFile(i), V0PerFile(i)] = promptVolumeParams( ...
                        titleStr, defaultRate_mL_per_hr, defaultV0_mL);

                case "stable"
                    titleStr = sprintf('Stable-volume setting (%d/%d): %s', i, nFiles, filePaths(i));
                    V0PerFile(i) = promptStableVolume(titleStr, defaultV0_mL);
                    ratePerFile(i) = 0;
            end
        end
    end
end

function modeChoice = promptVolumeModeForFile(i, nFiles, filePath)
% Ask whether one file is a filling cycle or a stable-volume segment.

    msg = sprintf(['Volume mode for file %d/%d:\n\n%s\n\n' ...
                   'Choose "Filling cycle" if volume changes during this file.\n' ...
                   'Choose "Stable volume" for steady-state/non-filling segments.'], ...
                   i, nFiles, filePath);

    choice = questdlg(msg, ...
        'Volume mode', ...
        'Filling cycle', 'Stable volume', 'Filling cycle');

    if isempty(choice)
        error('User cancelled.');
    end

    if strcmp(choice, 'Filling cycle')
        modeChoice = "filling";
    else
        modeChoice = "stable";
    end
end

function Vstable_mL = promptStableVolume(titleStr, defaultV_mL)
% Prompt for the constant volume assigned to a stable/non-filling segment.

    prompt = {sprintf('Constant/stable volume (mL) [default %.4g]:', defaultV_mL)};
    def = {num2str(defaultV_mL)};

    answ = inputdlg(prompt, titleStr, [1 65], def);
    if isempty(answ)
        error('User cancelled.');
    end

    Vstable_mL = str2double(answ{1});
    if ~isfinite(Vstable_mL)
        error('Invalid stable volume: must be numeric (mL).');
    end
end


function [rate_mL_per_s, V0_mL] = promptVolumeParams(titleStr, defaultRate_mL_per_hr, defaultV0_mL)
% Prompts for fill rate (mL/hr) and initial volume (mL).
% Returns fill rate in mL/s (internal units) and V0 in mL.

    prompt = { ...
        sprintf('Fill rate (mL/hr) [default %.4g]:', defaultRate_mL_per_hr), ...
        sprintf('Initial volume V0 (mL) [default %.4g]:', defaultV0_mL) ...
    };
    def = {num2str(defaultRate_mL_per_hr), num2str(defaultV0_mL)};

    answ = inputdlg(prompt, titleStr, [1 65], def);
    if isempty(answ)
        error('User cancelled.');
    end

    rate_mL_per_hr = str2double(answ{1});
    V0_mL          = str2double(answ{2});

    if ~isfinite(rate_mL_per_hr) || rate_mL_per_hr < 0
        error('Invalid fill rate: must be a nonnegative number (mL/hr).');
    end
    if ~isfinite(V0_mL)
        error('Invalid initial volume: must be numeric (mL).');
    end

    rate_mL_per_s = rate_mL_per_hr / 3600;
end

% =====================================================================
% Output struct helper
% =====================================================================

function d = emptyDataStruct()
    d = struct( ...
        'file','', ...
        'time',[], ...
        'pressure',[], ...
        'nerveHz',[], ...
        'keyboard',[], ...
        'volume',[], ...
        'events',struct(), ...
        'meta',struct());
end

% =====================================================================
% Channel selection logic (ported from inspector)
% =====================================================================

function [chosenIdx, candidates] = choosePressure(headers)
% Choose pressure channel:
% - Identify "pressure-like" candidates by tokens (ip, pressure, intraves, etc.)
% - Exclude volume/frequency/neuro/event/keyboard
% - Prefer memory channel (m# ...) ONLY if its base label matches a raw channel base label
% - Otherwise score by token strength + small memory bonus

    hLower = lower(string(headers));

    includeTok = ["ip","pressure","intraves","intravesical","vesical","pves"];
    excludeTok = ["vol","volume","cap","capacity","flow","rate","freq","hz","neuro","keyboard","event"];

    isCandidate = false(size(hLower));
    for t = includeTok
        isCandidate = isCandidate | contains(hLower, t);
    end
    for t = excludeTok
        isCandidate = isCandidate & ~contains(hLower, t);
    end

    candIdx = find(isCandidate);
    candidates = headers(candIdx);

    if isempty(candIdx)
        chosenIdx = [];
        return
    end

    isMem = ~cellfun(@isempty, regexp(headers(candIdx), '^m\d+\s', 'once'));
    memIdx = candIdx(isMem);
    rawIdx = candIdx(~isMem);

    % Prefer memory channel when base matches a raw channel base
    if ~isempty(memIdx) && ~isempty(rawIdx)
        memBases = arrayfun(@(ii) pressureBase(headers{ii}), memIdx, 'UniformOutput', false);
        rawBases = arrayfun(@(ii) pressureBase(headers{ii}), rawIdx, 'UniformOutput', false);

        for m = 1:numel(memIdx)
            if any(strcmpi(memBases{m}, rawBases))
                chosenIdx = memIdx(m);
                return
            end
        end
    end

    % Score: token priority + modest memory bonus
    priority = ["ip","pressure","intraves","vesical","pves"];
    scores = zeros(size(candIdx));
    for k = 1:numel(candIdx)
        label = lower(string(headers{candIdx(k)}));
        tokScore = 0;
        for p = 1:numel(priority)
            if contains(label, priority(p))
                tokScore = (numel(priority) - p + 1);
                break
            end
        end
        memBonus = 0;
        if ~isempty(regexp(headers{candIdx(k)}, '^m\d+\s', 'once'))
            memBonus = 0.5;
        end
        scores(k) = tokScore + memBonus;
    end

    [~, best] = max(scores);
    chosenIdx = candIdx(best);
end

function b = pressureBase(label)
% Remove leading channel prefix patterns: "m1 " or "2 " etc. Keep remainder.
    x = string(strtrim(label));
    x = regexprep(x, '^m?\d+\s*', '');
    b = char(strtrim(x));
end

function [chosenIdx, candidates] = chooseNerveHz(headers)
% Choose processed nerve Hz channel:
% - Exclude raw neurogram (contains "neuro" or "neurogram")
% - Include tokens: freq, m freq, hz, rate, nw
% - Exclude event/keyboard
% - Prefer freq/hz over nw

    hLower = lower(string(headers));

    isExcluded = contains(hLower,"neuro") | contains(hLower,"neurogram");

    includeTok = ["freq","m freq","hz","rate","nw"];
    isCandidate = false(size(hLower));
    for t = includeTok
        isCandidate = isCandidate | contains(hLower, t);
    end

    isCandidate = isCandidate & ~contains(hLower,"keyboard") & ~contains(hLower,"event");
    isCandidate = isCandidate & ~isExcluded;

    candIdx = find(isCandidate);
    candidates = headers(candIdx);

    if isempty(candIdx)
        chosenIdx = [];
        return
    end

    scores = zeros(size(candIdx));
    for k = 1:numel(candIdx)
        label = hLower(candIdx(k));
        if contains(label,"freq")
            scores(k) = 3;
        elseif contains(label,"hz")
            scores(k) = 2.5;
        elseif contains(label,"rate")
            scores(k) = 2;
        elseif contains(label,"nw")
            scores(k) = 1;
        end
    end
    [~, best] = max(scores);
    chosenIdx = candIdx(best);
end


function [chosenIdx, candidates] = chooseKeyboard(headers)
% Choose optional Spike2 Keyboard/event marker channel.
% Returns [] if no keyboard-like channel is present.

    hLower = lower(string(headers));

    isCandidate = contains(hLower, "keyboard") | ...
                  contains(hLower, "key") | ...
                  contains(hLower, "event");

    candIdx = find(isCandidate);
    candidates = headers(candIdx);

    if isempty(candIdx)
        chosenIdx = [];
        return
    end

    % Prefer an explicit Keyboard label over generic event/key labels.
    scores = zeros(size(candIdx));
    for k = 1:numel(candIdx)
        label = hLower(candIdx(k));
        if contains(label, "keyboard")
            scores(k) = 3;
        elseif contains(label, "key")
            scores(k) = 2;
        elseif contains(label, "event")
            scores(k) = 1;
        end
    end

    [~, best] = max(scores);
    chosenIdx = candIdx(best);
end

% =====================================================================
% Filename metadata extraction (lossless tags) + known-indicator parsing
% =====================================================================

function meta = parseFilenameMetadata(filePath, condDict)
% parseFilenameMetadata
% Extracts ALL underscore-delimited tags from a filename (LOSSLESS),
% then parses known indicators (FillN, named conditions, sec-sec window).
%
% IMPORTANT: Tags are stored exactly as they appear between underscores.
% - Hyphens and dots are preserved (e.g., "120510-001" stays "120510-001").
% - Parsing uses normalized copies so detection remains robust.

    if nargin < 2 || isempty(condDict)
        condDict = defaultConditionDictionary();
    end

    [~, base, ~] = fileparts(char(filePath));
    fileBase = string(base);

    % ---- 1) Extract ALL underscore-delimited tags (preserve exact text) ----
    rawTags = split(fileBase, "_");
    rawTags = rawTags(rawTags ~= ""); % drop empty

    tags = cell(size(rawTags));
    for k = 1:numel(rawTags)
        % Preserve original tag exactly (lossless)
        t = strtrim(string(rawTags(k)));
        tags{k} = char(t);
    end

    % Per your request: conditionTokens includes ALL notes/tags
    conditionTokens = tags;

    % ---- 2) Create normalized copies for parsing only ----
    % Normalize separators to spaces for robust matching in "normAll"
    normAll = lower(strjoin(string(tags), " "));
    normAll = regexprep(normAll, '[_\-\.\(\)\[\]]', ' ');
    normAll = regexprep(normAll, '\s+', ' ');
    normAll = strtrim(normAll);

    % Also normalize each tag for tag-by-tag matching
    normTags = strings(numel(tags),1);
    for k = 1:numel(tags)
        nt = lower(string(tags{k}));
        nt = regexprep(nt, '[_\-\.\(\)\[\]]', ' ');
        nt = regexprep(nt, '\s+', ' ');
        normTags(k) = strtrim(nt);
    end

    % ---- FillN detection ----
    fillLevel = NaN;
    mFill = regexp(normAll, '\bfill\s*(\d+)\b', 'tokens', 'once');
    if ~isempty(mFill)
        fillLevel = str2double(mFill{1});
        if ~isfinite(fillLevel), fillLevel = NaN; end
    end

    % ---- Optional window extraction: "<start>sec-<end>sec" (use ORIGINAL fileBase) ----
    windowStart_s = NaN;
    windowEnd_s   = NaN;
    mWin = regexp(lower(fileBase), '(\d+)\s*sec\s*-\s*(\d+)\s*sec', 'tokens', 'once');
    if ~isempty(mWin) && numel(mWin) == 2
        ws = str2double(mWin{1});
        we = str2double(mWin{2});
        if isfinite(ws) && isfinite(we)
            windowStart_s = ws;
            windowEnd_s   = we;
        end
    end

    % ---- Named condition detection via dictionary ----
    namedConditions = {};
    canon = condDict.canonical;

    for k = 1:numel(canon)
        label = canon{k};
        syns  = lower(string(condDict.synonyms.(label)));

        found = false;

        % Prefer matching within normalized tags (more interpretable)
        for tt = 1:numel(normTags)
            tagStr = normTags(tt);

            % Exact match of whole tag
            if any(strcmp(tagStr, syns))
                found = true;
                break
            end

            % Embedded match for allowEmbedded labels (e.g., "ALSBaseline")
            if ~found && isfield(condDict,'allowEmbedded') && any(strcmpi(label, condDict.allowEmbedded))
                if any(contains(tagStr, syns))
                    found = true;
                    break
                end
            end
        end

        % Fallback: search the whole normalized filename string (rare edge cases)
        if ~found && isfield(condDict,'allowEmbedded') && any(strcmpi(label, condDict.allowEmbedded))
            if any(contains(normAll, syns))
                found = true;
            end
        end

        if found
            namedConditions{end+1} = label; %#ok<AGROW>
        end
    end

    namedConditions = unique(namedConditions, 'stable');

    % ---- 3) Build grouping key from known indicators ONLY ----
    keyParts = strings(0,1);
    if isfinite(fillLevel)
        keyParts(end+1) = "Fill" + string(fillLevel); %#ok<AGROW>
    end
    if ~isempty(namedConditions)
        keyParts = [keyParts; string(namedConditions(:))]; %#ok<AGROW>
    end

    if isempty(keyParts)
        conditionKey = "Unlabeled";
    else
        conditionKey = strjoin(keyParts, " | ");
    end

    % ---- Return ----
    meta = struct();
    meta.fileBase        = fileBase;
    meta.fileTags        = tags;             % ALL underscore tags (lossless)
    meta.conditionTokens = conditionTokens;  % ALL tags (per request)
    meta.conditionKey    = conditionKey;

    meta.parsed = struct();
    meta.parsed.fillLevel        = fillLevel;
    meta.parsed.namedConditions  = namedConditions;
    meta.parsed.windowStart_s    = windowStart_s;
    meta.parsed.windowEnd_s      = windowEnd_s;
end



function hzColName = promptSelectHzChannel(colNames, filePath)
% promptSelectHzChannel
% Ask user to choose which column contains processed nerve frequency (Hz).

msg = sprintf([ ...
    'No nerve Hz channel was auto-detected in:\n\n%s\n\n' ...
    'Select the column containing processed nerve frequency (Hz).\n' ...
    'This may be labeled "M Freq", "Freq", "nw", "rate", or sometimes "unknown".'], ...
    char(filePath));

[idx, ok] = listdlg( ...
    'PromptString', msg, ...
    'SelectionMode', 'single', ...
    'ListString', cellstr(string(colNames)), ...
    'ListSize', [520 260], ...
    'Name', 'Select Nerve Hz Channel');

if ~ok || isempty(idx)
    hzColName = "";
else
    hzColName = string(colNames(idx));
end
end
