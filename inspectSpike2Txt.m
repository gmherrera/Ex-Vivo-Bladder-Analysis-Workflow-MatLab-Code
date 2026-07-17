function info = inspectSpike2Txt(filePaths, opts)
% inspectSpike2Txt  Read-only inspector for Spike2 "Spreadsheet Text" exports.
%         Version 1.0
%         Date: July 8, 2026
%         Author: G. Herrera 
%         Co-Author/AI Tool: OpenAI ChatGPT (GPT-5.5)
%         Note: The core architecture was designed by the author and implemented by
%           ChatGPT via prompt engineering. All code was reviewed,
%           modified, and verified by the author.
%
% WHAT IT DOES (read-only):
% - Reads ONLY the header line + a few initial data rows for sanity checks.
% - Identifies candidate columns for:
%     * Time
%     * Pressure (prefers memory-channel corrected pressure when it matches a raw pressure label)
%     * Nerve rate (Hz-like channel; excludes raw neurogram)
% - Reports what it *would* choose for downstream analysis.
%
% USAGE:
%   info = inspectSpike2Txt();                         % interactive picker (multi-directory)
%   info = inspectSpike2Txt("C:\data\file1.txt");      % single file
%   info = inspectSpike2Txt(["f1.txt","f2.txt"]);      % many files
%
% OUTPUT:
%   info(i) is a struct with fields:
%     .file
%     .headers (cellstr, original labels)
%     .nCols
%     .timeIdx, .dt, .t0, .t1
%     .pressureCandidates, .pressureIdx, .pressureLabel
%     .nerveCandidates, .nerveIdx, .nerveLabel
%     .warnings (cellstr)
%
% NOTE:
% - This function does NOT load full data or compute volume.

% -------- File selection (multi-directory accumulate + remembers last dir) --------
if nargin < 1 || isempty(filePaths)

    % Use MATLAB preferences to persist last-used directory between sessions
    prefGroup = 'AfferentNerveAnalysis';
    prefName  = 'LastSpike2TxtDir';

    if ispref(prefGroup, prefName)
        lastDir = getpref(prefGroup, prefName);
        if ~isfolder(lastDir)
            lastDir = pwd;
        end
    else
        lastDir = pwd;
    end

    allFiles = string.empty;

    while true
        % Seed uigetfile with lastDir by passing a file pattern path
        startPath = fullfile(lastDir, '*.txt');

        [fn, fp] = uigetfile( ...
            {'*.txt;*.tsv','Spike2 text (*.txt, *.tsv)'; '*.*','All files'}, ...
            'Select Spike2 Spreadsheet Text file(s)', ...
            startPath, ...
            'MultiSelect','on');

        if isequal(fn,0)
            break
        end

        % Update lastDir based on where the user just selected files
        lastDir = fp;
        setpref(prefGroup, prefName, lastDir);

        if ischar(fn)
            fn = {fn};
        end

        newFiles = string(fullfile(fp, fn(:)));
        allFiles = [allFiles; newFiles]; %#ok<AGROW>

        choice = questdlg( ...
            'Add files from another directory?', ...
            'Continue file selection', ...
            'Yes','No','No');

        if strcmp(choice,'No')
            break
        end
    end

    if isempty(allFiles)
        info = struct([]);
        return
    end

    filePaths = allFiles;
else
    filePaths = string(filePaths);
end


    % -------- Options --------
    if nargin < 2 || isempty(opts)
        opts = struct();
    end

    if ~isfield(opts,'nSampleLines'), opts.nSampleLines = 5; end

    info = repmat(emptyInfoStruct(), numel(filePaths), 1);

    % -------- Main loop --------
    for i = 1:numel(filePaths)
        f = filePaths(i);
        s = emptyInfoStruct();
        s.file = char(f);

        warnings = {};

        % ---- Read header + a few lines ----
        fid = fopen(f, 'r');
        if fid < 0
            warnings{end+1} = "Could not open file."; %#ok<AGROW>
            s.warnings = cellstr(warnings);
            info(i) = s;
            continue
        end

        headerLine = fgetl(fid);
        if ~ischar(headerLine)
            fclose(fid);
            warnings{end+1} = "File appears empty (no header line)."; %#ok<AGROW>
            s.warnings = cellstr(warnings);
            info(i) = s;
            continue
        end

        headers = parseHeaderLine(headerLine);
        s.headers = headers;
        s.nCols = numel(headers);

        % Sample a few data lines to estimate dt without loading whole file
        tVals = nan(opts.nSampleLines,1);
        nRead = 0;
        for k = 1:opts.nSampleLines
            ln = fgetl(fid);
            if ~ischar(ln), break; end
            parts = split(ln, sprintf('\t'));
            if numel(parts) >= 1
                nRead = nRead + 1;
                tVals(nRead) = str2double(parts{1});
            end
        end
        fclose(fid);

        % ---- Time column detection ----
        timeIdx = find(strcmpi(strtrim(headers), "Time"), 1, 'first');
        if isempty(timeIdx)
            timeIdx = find(contains(lower(headers), "time"), 1, 'first');
        end
        s.timeIdx = timeIdx;

        if isempty(timeIdx)
            warnings{end+1} = "Could not confidently identify the Time column."; %#ok<AGROW>
        else
            if nRead >= 2 && all(isfinite(tVals(1:2)))
                s.t0 = tVals(1);
                s.t1 = tVals(2);
                s.dt = tVals(2) - tVals(1);
                if s.dt <= 0
                    warnings{end+1} = "Estimated dt <= 0 from first two rows; check time ordering."; %#ok<AGROW>
                end
            else
                warnings{end+1} = "Insufficient numeric time rows to estimate dt."; %#ok<AGROW>
            end
        end

        % ---- Pressure selection ----
        [pressureIdx, pressureCandidates] = choosePressure(headers);
        s.pressureIdx = pressureIdx;
        s.pressureCandidates = pressureCandidates;
        if ~isempty(pressureIdx)
            s.pressureLabel = headers{pressureIdx};
        else
            warnings{end+1} = "No pressure channel selected (no candidates matched)."; %#ok<AGROW>
        end

        % ---- Nerve rate (Hz) selection ----
        [nerveIdx, nerveCandidates] = chooseNerveHz(headers);
        s.nerveIdx = nerveIdx;
        s.nerveCandidates = nerveCandidates;
        if ~isempty(nerveIdx)
            s.nerveLabel = headers{nerveIdx};
        else
            warnings{end+1} = "No nerve Hz channel selected (no candidates matched)."; %#ok<AGROW>
        end

        % ---- Print a concise report to Command Window ----
        fprintf('\n=== Spike2 Inspector: %s ===\n', s.file);
        fprintf('Columns (%d):\n', s.nCols);
        fprintf('  %s\n', strjoin(string(headers), " | "));

        if ~isempty(s.timeIdx)
            fprintf('Time: idx %d ("%s")', s.timeIdx, headers{s.timeIdx});
            if isfinite(s.dt)
                fprintf('  dt=%.6g s  (t0=%.6g, t1=%.6g)\n', s.dt, s.t0, s.t1);
            else
                fprintf('\n');
            end
        end

        fprintf('Pressure candidates: %s\n', strjoin(string(s.pressureCandidates), " | "));
        if ~isempty(s.pressureIdx)
            fprintf('Chosen Pressure: idx %d ("%s")\n', s.pressureIdx, s.pressureLabel);
        end

        fprintf('NerveHz candidates: %s\n', strjoin(string(s.nerveCandidates), " | "));
        if ~isempty(s.nerveIdx)
            fprintf('Chosen NerveHz: idx %d ("%s")\n', s.nerveIdx, s.nerveLabel);
        end

        if ~isempty(warnings)
            fprintf('Warnings:\n');
            for w = 1:numel(warnings)
                fprintf('  - %s\n', warnings{w});
            end
        end

        s.warnings = cellstr(warnings);
        info(i) = s;
    end
end

% ---------------- Helpers (must be in same file) ----------------

function s = emptyInfoStruct()
    s = struct( ...
        'file','', ...
        'headers',{{}}, ...
        'nCols',0, ...
        'timeIdx',[], ...
        'dt',NaN, ...
        't0',NaN, ...
        't1',NaN, ...
        'pressureCandidates',{{}}, ...
        'pressureIdx',[], ...
        'pressureLabel','', ...
        'nerveCandidates',{{}}, ...
        'nerveIdx',[], ...
        'nerveLabel','', ...
        'warnings',{{}} );
end

function headers = parseHeaderLine(headerLine)
    raw = split(string(headerLine), sprintf('\t'));
    headers = cell(size(raw));
    for j = 1:numel(raw)
        x = strtrim(raw(j));
        x = strip(x, '"');          % remove leading/trailing double-quotes
        headers{j} = char(x);
    end
end

function [chosenIdx, candidates] = choosePressure(headers)
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

    % Partition into memory vs non-memory (Spike2 "m#" convention)
    isMem = ~cellfun(@isempty, regexp(headers(candIdx), '^m\d+\s', 'once'));
    memIdx = candIdx(isMem);
    rawIdx = candIdx(~isMem);

    % If both exist, prefer a memory channel whose "base" matches a raw channel base.
    if ~isempty(memIdx) && ~isempty(rawIdx)
        memBases = arrayfun(@(ii) pressureBase(headers{ii}), memIdx, 'UniformOutput', false);
        rawBases = arrayfun(@(ii) pressureBase(headers{ii}), rawIdx, 'UniformOutput', false);

        for m = 1:numel(memIdx)
            if any(strcmpi(memBases{m}, rawBases))
                chosenIdx = memIdx(m);
                return
            end
        end
        % No base match: do not blindly pick memory channel.
    end

    % Score candidates by token strength, with a modest memory bonus.
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
    x = string(strtrim(label));
    x = regexprep(x, '^m?\d+\s*', ''); % remove m?digits + optional whitespace
    b = char(strtrim(x));
end

function [chosenIdx, candidates] = chooseNerveHz(headers)
    hLower = lower(string(headers));

    % Exclude raw neurogram explicitly
    isExcluded = contains(hLower,"neuro") | contains(hLower,"neurogram");

    % Include likely processed-rate tokens
    includeTok = ["freq","m freq","hz","rate","nw"];
    isCandidate = false(size(hLower));
    for t = includeTok
        isCandidate = isCandidate | contains(hLower, t);
    end

    % Exclude non-signal channels
    isCandidate = isCandidate & ~contains(hLower,"keyboard") & ~contains(hLower,"event");
    isCandidate = isCandidate & ~isExcluded;

    candIdx = find(isCandidate);
    candidates = headers(candIdx);

    if isempty(candIdx)
        chosenIdx = [];
        return
    end

    % Score: prefer freq/hz over nw when both exist
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
