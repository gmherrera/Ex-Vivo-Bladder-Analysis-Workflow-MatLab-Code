function TPEanalysisGUI(data)
%TPEANALYSISGUI  GUI wrapper for transient pressure event (TPE) analysis.
%
%         Version 1.0
%         Date: July 9, 2026
%         Author: G. Herrera 
%         Co-Author/AI Tool: OpenAI ChatGPT (GPT-5.5)
%         Note: The core architecture was designed by the author and implemented by
%           ChatGPT via prompt engineering. All code was reviewed,
%           modified, and verified by the author. Refer to dependent
%           functions for further information.
%
% Usage:
%   TPEanalysisGUI(data)
%   TPEanalysisGUI()          % then use File > Open data structure...
%
% Requires on MATLAB path:
%   detectTPEs.m
%
% Optional on MATLAB path:
%   summarizeTPEbyGroup.m     % if absent, this GUI uses its internal summary table
%   plotTPEdetectionQC.m      % if absent, this GUI uses its internal QC plot
%
% This GUI lets you load/select experiments, set TPE detection parameters,
% run TPE detection on selected records, preview detections, summarize by
% meta.groupKey, export tables, and save the updated data structure.
%
% Results are stored in:
%   data(i).events.pressureTPE

    if nargin < 1
        data = struct([]);
    end

    if ~isempty(data) && ~isstruct(data)
        error('Input must be a data struct array, or call TPEanalysisGUI() and load a .mat file.');
    end

    dataFile = "";
    lastSummary = table();
    lastRepTable = table();

    % ---------------- UI layout ----------------
    fig = uifigure('Name','TPE Analysis GUI', 'Position',[90 90 1320 760]);

    % Menus
    mFile = uimenu(fig,'Text','File');
    uimenu(mFile,'Text','Open data structure...','MenuSelectedFcn',@openDataFile);
    uimenu(mFile,'Text','Save updated data as...','MenuSelectedFcn',@saveDataAs);
    uimenu(mFile,'Text','Export replicate table...','MenuSelectedFcn',@exportReplicateTable);
    uimenu(mFile,'Text','Export group summary...','MenuSelectedFcn',@exportSummaryTable);
    uimenu(mFile,'Text','Close','MenuSelectedFcn',@(~,~)close(fig));

    gl = uigridlayout(fig,[2 2]);
    gl.RowHeight = {'1x', 42};
    gl.ColumnWidth = {'1.25x','1x'};
    gl.Padding = [10 10 10 10];
    gl.RowSpacing = 8;
    gl.ColumnSpacing = 10;

    leftPanel = uipanel(gl, 'Title','Experiments in loaded data');
    leftPanel.Layout.Row = 1;
    leftPanel.Layout.Column = 1;

    lp = uigridlayout(leftPanel,[2 1]);
    lp.RowHeight = {'1x', 36};
    lp.ColumnWidth = {'1x'};

    tbl = uitable(lp, 'Data', buildExperimentTable(data));
    tbl.ColumnEditable = getEditableColumns(tbl.Data);
    tbl.ColumnName = tbl.Data.Properties.VariableNames;
    tbl.Layout.Row = 1;

    btnGrid = uigridlayout(lp,[1 6]);
    btnGrid.Layout.Row = 2;
    btnGrid.ColumnWidth = {'1x','1x','1.2x','1x','1x','1x'};

    uibutton(btnGrid,'Text','Select all','ButtonPushedFcn',@(~,~)setUseAll(true));
    uibutton(btnGrid,'Text','Select none','ButtonPushedFcn',@(~,~)setUseAll(false));
    uibutton(btnGrid,'Text','Only selected group','ButtonPushedFcn',@selectCurrentGroup);
    uibutton(btnGrid,'Text','Untested only','ButtonPushedFcn',@selectUntestedOnly);
    uibutton(btnGrid,'Text','Exclude stable','ButtonPushedFcn',@excludeStable);
    uibutton(btnGrid,'Text','Refresh','ButtonPushedFcn',@refreshTable);

    rightPanel = uipanel(gl, 'Title','TPE options');
    rightPanel.Layout.Row = 1;
    rightPanel.Layout.Column = 2;

    rp = uigridlayout(rightPanel,[1 1]);
    tabs = uitabgroup(rp);

    tabDetect  = uitab(tabs,'Title','Detect TPEs');
    tabQC      = uitab(tabs,'Title','Preview / QC');
    tabSummary = uitab(tabs,'Title','Summary / Export');

    % Detection tab
    dgl = uigridlayout(tabDetect,[14 2]);
    dgl.RowHeight = repmat({32},1,14);
    dgl.ColumnWidth = {210,'1x'};
    dgl.Padding = [12 12 12 12];

    uilabel(dgl,'Text','Min peak prominence (mmHg)');
    minProm = uieditfield(dgl,'numeric','Value',0.05,'Limits',[0 Inf]);

    uilabel(dgl,'Text','Max peak width (s)');
    maxWidthS = uieditfield(dgl,'numeric','Value',30,'Limits',[0 Inf]);

    uilabel(dgl,'Text','Max peak width samples');
    maxWidthSamples = uieditfield(dgl,'text','Value','','Tooltip','Optional. Leave blank to use max peak width in seconds.');

    uilabel(dgl,'Text','Min peak distance (s)');
    minDistanceS = uieditfield(dgl,'text','Value','','Tooltip','Optional. Useful if double-peaks are detected.');

    uilabel(dgl,'Text','Start fraction of trace');
    startFrac = uieditfield(dgl,'numeric','Value',0.11,'Limits',[0 1]);

    uilabel(dgl,'Text','End fraction of trace');
    endFrac = uieditfield(dgl,'numeric','Value',0.98,'Limits',[0 1]);

    uilabel(dgl,'Text','Sample rate override (Hz)');
    fsHz = uieditfield(dgl,'text','Value','','Tooltip','Optional. Leave blank to infer from data(i).time.');

    uilabel(dgl,'Text','Store baseline-subtracted trace');
    storeBaseSub = uicheckbox(dgl,'Value',true,'Text','Store in events.pressureTPE.pressureBaseSub');

    uilabel(dgl,'Text','Verbose command-window output');
    verboseOpt = uicheckbox(dgl,'Value',true,'Text','Print detection progress');

    uilabel(dgl,'Text','Output data variable');
    outDataName = uieditfield(dgl,'text','Value','data');

    uilabel(dgl,'Text','Summary variable');
    outSummaryName = uieditfield(dgl,'text','Value','tpeSummary');

    uibutton(dgl,'Text','Run TPE detection','ButtonPushedFcn',@runDetection);
    uibutton(dgl,'Text','Run + QC selected','ButtonPushedFcn',@runDetectionAndQC);

    uibutton(dgl,'Text','Assign data to workspace','ButtonPushedFcn',@assignDataToWorkspace);
    uibutton(dgl,'Text','Save updated data as...','ButtonPushedFcn',@saveDataAs);

    % QC tab
    qgl = uigridlayout(tabQC,[9 2]);
    qgl.RowHeight = repmat({32},1,9);
    qgl.ColumnWidth = {210,'1x'};
    qgl.Padding = [12 12 12 12];

    uilabel(qgl,'Text','QC plot source');
    qcSource = uidropdown(qgl,'Items',{'Selected table rows','Single table index'},'Value','Selected table rows');

    uilabel(qgl,'Text','Single table index');
    qcIndex = uieditfield(qgl,'numeric','Value',1,'Limits',[1 Inf]);

    uilabel(qgl,'Text','Max points/file');
    qcThin = uieditfield(qgl,'numeric','Value',3000,'Limits',[100 Inf]);

    uilabel(qgl,'Text','Show baseline');
    qcShowBaseline = uicheckbox(qgl,'Value',true,'Text','Overlay pressure baseline');

    uilabel(qgl,'Text','Show analysis window');
    qcShowWindow = uicheckbox(qgl,'Value',true,'Text','Shade start/end window');

    uibutton(qgl,'Text','Plot TPE QC','ButtonPushedFcn',@plotQC);
    uibutton(qgl,'Text','Plot built-in QC function','ButtonPushedFcn',@plotExternalQC);

    % Summary tab
    sgl = uigridlayout(tabSummary,[8 2]);
    sgl.RowHeight = repmat({32},1,8);
    sgl.ColumnWidth = {210,'1x'};
    sgl.Padding = [12 12 12 12];

    uilabel(sgl,'Text','Group by');
    summaryGroupPath = uidropdown(sgl,'Items',{'meta.groupKey','meta.conditionKey'},'Value','meta.groupKey');

    uibutton(sgl,'Text','Build replicate table','ButtonPushedFcn',@buildRepTableCallback);
    uibutton(sgl,'Text','Build group summary','ButtonPushedFcn',@buildSummaryCallback);
    uibutton(sgl,'Text','Show replicate table','ButtonPushedFcn',@showReplicateTable);
    uibutton(sgl,'Text','Show group summary','ButtonPushedFcn',@showSummaryTable);
    uibutton(sgl,'Text','Export replicate table...','ButtonPushedFcn',@exportReplicateTable);
    uibutton(sgl,'Text','Export group summary...','ButtonPushedFcn',@exportSummaryTable);
    uibutton(sgl,'Text','Assign summary to workspace','ButtonPushedFcn',@assignSummaryToWorkspace);

    status = uilabel(gl,'Text','Ready. Load or provide a curated data structure, select experiments, set TPE options, then run.', ...
        'HorizontalAlignment','left');
    status.Layout.Row = 2;
    status.Layout.Column = [1 2];

    refreshTable();

    % ---------------- Callbacks ----------------
    function openDataFile(~,~)
        [fn, fp] = uigetfile('*.mat','Open curated data structure');
        if isequal(fn,0), return; end
        S = load(fullfile(fp,fn));
        if isfield(S,'data') && isstruct(S.data)
            data = S.data;
        else
            names = fieldnames(S);
            isStructArray = false(size(names));
            for k = 1:numel(names)
                isStructArray(k) = isstruct(S.(names{k})) && numel(S.(names{k})) >= 1;
            end
            idx = find(isStructArray,1,'first');
            if isempty(idx)
                uialert(fig,'No struct array named data, or any usable struct array, was found in this .mat file.','No data found');
                return
            end
            data = S.(names{idx});
        end
        dataFile = string(fullfile(fp,fn));
        refreshTable();
        status.Text = sprintf('Loaded %d records from %s', numel(data), dataFile);
    end

    function saveDataAs(~,~)
        if isempty(data)
            uialert(fig,'No data loaded.','No data');
            return
        end
        [fn, fp] = uiputfile('*.mat','Save updated data as','ExperimentData_with_TPEs.mat');
        if isequal(fn,0), return; end
        summary = lastSummary; %#ok<NASGU>
        replicateTable = lastRepTable; %#ok<NASGU>
        save(fullfile(fp,fn),'data','summary','replicateTable','-v7.3');
        dataFile = string(fullfile(fp,fn));
        status.Text = sprintf('Saved updated data to %s', dataFile);
    end

    function setUseAll(tf)
        T2 = tbl.Data;
        if isempty(T2), return; end
        T2.Use(:) = tf;
        tbl.Data = T2;
        updateStatus();
    end

    function selectCurrentGroup(~,~)
        T2 = tbl.Data;
        if isempty(T2), return; end
        groups = unique(string(T2.Group),'stable');
        groups = groups(strlength(groups)>0);
        if isempty(groups)
            uialert(fig,'No groups found.','No groups');
            return
        end
        [idx, ok] = listdlg('PromptString','Select group to keep:', ...
            'SelectionMode','single','ListString',cellstr(groups));
        if ~ok, return; end
        T2.Use = string(T2.Group) == groups(idx);
        tbl.Data = T2;
        updateStatus();
    end

    function selectUntestedOnly(~,~)
        T2 = tbl.Data;
        if isempty(T2), return; end
        T2.Use = ~logical(T2.HasTPE);
        tbl.Data = T2;
        updateStatus();
    end

    function excludeStable(~,~)
        T2 = tbl.Data;
        if isempty(T2), return; end
        isStable = strcmpi(string(T2.VolumeMode),'stable');
        T2.Use(isStable) = false;
        tbl.Data = T2;
        updateStatus();
    end

    function refreshTable(~,~)
        Tnew = buildExperimentTable(data);
        tbl.Data = Tnew;
        tbl.ColumnName = Tnew.Properties.VariableNames;
        tbl.ColumnEditable = getEditableColumns(Tnew);
        updateStatus();
    end

    function updateStatus()
        T2 = tbl.Data;
        if isempty(T2) || height(T2)==0
            status.Text = 'No data loaded. Use File > Open data structure... or call TPEanalysisGUI(data).';
            return
        end
        nSel = sum(T2.Use);
        nDone = sum(T2.HasTPE);
        g = unique(string(T2.Group(T2.Use)),'stable');
        status.Text = sprintf('Selected experiments: %d / %d. Records with TPEs: %d. Groups: %s', ...
            nSel, height(T2), nDone, strjoin(g, ', '));
    end

    function idx = selectedIndices()
        T2 = tbl.Data;
        idx = find(T2.Use);
        if isempty(idx)
            error('No experiments selected.');
        end
    end

    function opts = getOptsFromUI()
        if endFrac.Value <= startFrac.Value
            error('End fraction must be greater than start fraction.');
        end
        opts = struct();
        opts.minPeakProm_mmHg = minProm.Value;
        opts.maxPeakWidth_s = maxWidthS.Value;
        opts.startFrac = startFrac.Value;
        opts.endFrac = endFrac.Value;
        opts.storeBaseSub = logical(storeBaseSub.Value);
        opts.verbose = logical(verboseOpt.Value);

        v = str2double(strtrim(maxWidthSamples.Value));
        if isfinite(v) && v > 0
            opts.maxPeakWidth_samples = round(v);
        else
            opts.maxPeakWidth_samples = [];
        end

        v = str2double(strtrim(minDistanceS.Value));
        if isfinite(v) && v > 0
            opts.minPeakDistance_s = v;
        else
            opts.minPeakDistance_s = [];
        end

        v = str2double(strtrim(fsHz.Value));
        if isfinite(v) && v > 0
            opts.fs_Hz = v;
        else
            opts.fs_Hz = [];
        end
    end

    function runDetection(~,~)
        try
            if isempty(data), error('No data loaded.'); end
            idx = selectedIndices();
            opts = getOptsFromUI();
            dsel = data(idx);
            dsel = detectTPEs(dsel, opts);

            % Make sure the parent struct array can accept detected events.
            % MATLAB struct assignment requires compatible top-level fields.
            if ~isfield(data,'events')
                [data.events] = deal(struct());
            end

            for k = 1:numel(idx)
                data(idx(k)) = dsel(k);
            end
            refreshTable();
            lastRepTable = buildTPEReplicateTable(data, char(summaryGroupPath.Value));
            lastSummary = buildTPESummaryTable(lastRepTable);
            assignin('base', char(outDataName.Value), data);
            assignin('base', char(outSummaryName.Value), lastSummary);
            status.Text = sprintf('TPE detection complete for %d selected records. Updated data assigned to "%s".', numel(idx), outDataName.Value);
        catch ME
            uialert(fig, ME.message, 'TPE detection error');
        end
    end

    function runDetectionAndQC(~,~)
        runDetection();
        plotQC();
    end

    function assignDataToWorkspace(~,~)
        if isempty(data), return; end
        assignin('base', char(outDataName.Value), data);
        status.Text = sprintf('Updated data assigned to workspace variable "%s".', outDataName.Value);
    end

    function assignSummaryToWorkspace(~,~)
        if isempty(lastSummary)
            lastRepTable = buildTPEReplicateTable(data, char(summaryGroupPath.Value));
            lastSummary = buildTPESummaryTable(lastRepTable);
        end
        assignin('base', char(outSummaryName.Value), lastSummary);
        assignin('base', 'tpeReplicateTable', lastRepTable);
        status.Text = sprintf('Summary assigned to "%s" and replicate table assigned to "tpeReplicateTable".', outSummaryName.Value);
    end

    function plotQC(~,~)
        try
            if isempty(data), error('No data loaded.'); end
            if strcmp(qcSource.Value,'Single table index')
                idx = round(qcIndex.Value);
                if idx < 1 || idx > numel(data)
                    error('Single table index is outside the data range.');
                end
            else
                idx = selectedIndices();
            end
            plotTPEQCInternal(data(idx), round(qcThin.Value), logical(qcShowBaseline.Value), logical(qcShowWindow.Value));
        catch ME
            uialert(fig, ME.message, 'TPE QC error');
        end
    end

    function plotExternalQC(~,~)
        try
            if isempty(data), error('No data loaded.'); end
            idx = selectedIndices();
            dsel = data(idx);
            if exist('plotTPEdetectionQC','file') == 2
                plotTPEdetectionQC(dsel);
            else
                plotTPEQCInternal(dsel, round(qcThin.Value), logical(qcShowBaseline.Value), logical(qcShowWindow.Value));
            end
        catch ME
            uialert(fig, ME.message, 'External QC error');
        end
    end

    function buildRepTableCallback(~,~)
        try
            lastRepTable = buildTPEReplicateTable(data, char(summaryGroupPath.Value));
            assignin('base','tpeReplicateTable',lastRepTable);
            status.Text = 'Replicate-level TPE table built and assigned to workspace variable "tpeReplicateTable".';
        catch ME
            uialert(fig, ME.message, 'Replicate table error');
        end
    end

    function buildSummaryCallback(~,~)
        try
            lastRepTable = buildTPEReplicateTable(data, char(summaryGroupPath.Value));
            lastSummary = buildTPESummaryTable(lastRepTable);
            assignin('base', char(outSummaryName.Value), lastSummary);
            status.Text = sprintf('Group summary built and assigned to workspace variable "%s".', outSummaryName.Value);
        catch ME
            uialert(fig, ME.message, 'Summary error');
        end
    end

    function showReplicateTable(~,~)
        if isempty(lastRepTable)
            lastRepTable = buildTPEReplicateTable(data, char(summaryGroupPath.Value));
        end
        f2 = uifigure('Name','TPE replicate table','Position',[150 150 1050 500]);
        uitable(f2,'Data',lastRepTable,'Position',[10 10 1030 480]);
    end

    function showSummaryTable(~,~)
        if isempty(lastSummary)
            lastRepTable = buildTPEReplicateTable(data, char(summaryGroupPath.Value));
            lastSummary = buildTPESummaryTable(lastRepTable);
        end
        f2 = uifigure('Name','TPE group summary','Position',[170 170 1050 500]);
        uitable(f2,'Data',lastSummary,'Position',[10 10 1030 480]);
    end

    function exportReplicateTable(~,~)
        try
            if isempty(lastRepTable)
                lastRepTable = buildTPEReplicateTable(data, char(summaryGroupPath.Value));
            end
            writeTablePrompt(lastRepTable, 'TPE_replicate_table.csv');
        catch ME
            uialert(fig, ME.message, 'Export replicate table error');
        end
    end

    function exportSummaryTable(~,~)
        try
            if isempty(lastSummary)
                lastRepTable = buildTPEReplicateTable(data, char(summaryGroupPath.Value));
                lastSummary = buildTPESummaryTable(lastRepTable);
            end
            writeTablePrompt(lastSummary, 'TPE_group_summary.csv');
        catch ME
            uialert(fig, ME.message, 'Export summary error');
        end
    end

    function writeTablePrompt(Twrite, defaultName)
        if isempty(Twrite)
            error('Table is empty.');
        end
        [fn, fp] = uiputfile({'*.csv','CSV file (*.csv)';'*.xlsx','Excel workbook (*.xlsx)'}, ...
            'Export table', defaultName);
        if isequal(fn,0), return; end
        outPath = fullfile(fp,fn);
        writetable(Twrite, outPath);
        status.Text = sprintf('Exported table to %s', outPath);
    end
end

% =====================================================================
% Helper functions
% =====================================================================
function editable = getEditableColumns(T)
    if isempty(T) || width(T)==0
        editable = [];
    else
        editable = false(1,width(T));
        editable(1) = true;
    end
end

function T = buildExperimentTable(data)
    if isempty(data)
        T = table(false(0,1), zeros(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), false(0,1), zeros(0,1), strings(0,1), ...
            'VariableNames', {'Use','Index','Group','Condition','VolumeMode','FileBase','HasTPE','NumTPEs','Treatments'});
        return
    end

    n = numel(data);
    Use = true(n,1);
    Index = (1:n).';
    Group = strings(n,1);
    Condition = strings(n,1);
    VolumeMode = strings(n,1);
    FileBase = strings(n,1);
    HasTPE = false(n,1);
    NumTPEs = zeros(n,1);
    Treatments = strings(n,1);

    for i = 1:n
        if isfield(data(i),'meta')
            m = data(i).meta;
            if isfield(m,'groupKey') && strlength(string(m.groupKey)) > 0
                Group(i) = string(m.groupKey);
            else
                Group(i) = "Unassigned";
            end
            if isfield(m,'conditionKey'), Condition(i) = string(m.conditionKey); end
            if isfield(m,'volumeMode'), VolumeMode(i) = string(m.volumeMode); end
            if isfield(m,'fileBase'), FileBase(i) = string(m.fileBase); end
        end

        if isfield(data(i),'events') && isstruct(data(i).events) && ...
                isfield(data(i).events,'pressureTPE') && isstruct(data(i).events.pressureTPE)
            HasTPE(i) = true;
            ev = data(i).events.pressureTPE;
            if isfield(ev,'numTPEs') && isfinite(ev.numTPEs)
                NumTPEs(i) = ev.numTPEs;
            elseif isfield(ev,'pks')
                NumTPEs(i) = numel(ev.pks);
            end
        end

        if isfield(data(i),'events') && isstruct(data(i).events) && ...
                isfield(data(i).events,'treatment') && isstruct(data(i).events.treatment) && ...
                isfield(data(i).events.treatment,'labels')
            Treatments(i) = strjoin(string(data(i).events.treatment.labels(:)), ' | ');
        end
    end

    T = table(Use, Index, Group, Condition, VolumeMode, FileBase, HasTPE, NumTPEs, Treatments);
end

function repT = buildTPEReplicateTable(data, groupPath)
    if isempty(data)
        repT = table();
        return
    end

    rows = struct('Index',{},'Group',{},'FileBase',{},'HasTPE',{},'NumTPEs',{}, ...
        'RecordDuration_min',{},'ContFreqTotal_perMin',{},'MeanPeak_mmHg',{}, ...
        'MeanProminence_mmHg',{},'MeanWidth_s',{},'MeanICI_s',{}, ...
        'MeanContPerMin',{},'MeanTPEbasePressure_mmHg',{}, ...
        'MeanTPEvolume_mL',{},'MeanTPEvolumePercent',{});

    for i = 1:numel(data)
        r = struct();
        r.Index = i;
        r.Group = getStringByPathOrDefault(data(i), groupPath, "Unassigned");
        if strlength(r.Group)==0, r.Group = "Unassigned"; end
        r.FileBase = getStringByPathOrDefault(data(i), 'meta.fileBase', "");
        r.HasTPE = false;
        r.NumTPEs = NaN;
        r.RecordDuration_min = NaN;
        r.ContFreqTotal_perMin = NaN;
        r.MeanPeak_mmHg = NaN;
        r.MeanProminence_mmHg = NaN;
        r.MeanWidth_s = NaN;
        r.MeanICI_s = NaN;
        r.MeanContPerMin = NaN;
        r.MeanTPEbasePressure_mmHg = NaN;
        r.MeanTPEvolume_mL = NaN;
        r.MeanTPEvolumePercent = NaN;

        if isfield(data(i),'events') && isstruct(data(i).events) && ...
                isfield(data(i).events,'pressureTPE') && isstruct(data(i).events.pressureTPE)
            ev = data(i).events.pressureTPE;
            r.HasTPE = true;
            r.NumTPEs = getNumericFieldOrDefault(ev,'numTPEs',numel(getFieldOrDefault(ev,'pks',[])));
            r.RecordDuration_min = getNumericFieldOrDefault(ev,'recordDur_min',NaN);
            r.ContFreqTotal_perMin = getNumericFieldOrDefault(ev,'contFreqTotal_perMin',NaN);
            r.MeanPeak_mmHg = getNumericFieldOrDefault(ev,'meanPks',NaN);
            r.MeanProminence_mmHg = getNumericFieldOrDefault(ev,'meanProm',NaN);
            r.MeanWidth_s = getNumericFieldOrDefault(ev,'meanWidth_s',NaN);
            r.MeanICI_s = getNumericFieldOrDefault(ev,'meanIntConInt_s',NaN);
            r.MeanContPerMin = getNumericFieldOrDefault(ev,'meanContPerMin',NaN);
            r.MeanTPEbasePressure_mmHg = getNumericFieldOrDefault(ev,'meanTPEbasePressure',NaN);
            r.MeanTPEvolume_mL = mean(getFieldOrDefault(ev,'tpeVolume_mL',NaN),'omitnan');
            r.MeanTPEvolumePercent = mean(getFieldOrDefault(ev,'tpeVolumePercent',NaN),'omitnan');
        end

        rows(end+1) = r; %#ok<AGROW>
    end

    repT = struct2table(rows);
end

function summaryT = buildTPESummaryTable(repT)
    if isempty(repT) || height(repT)==0
        summaryT = table();
        return
    end

    use = repT.HasTPE & isfinite(repT.NumTPEs);
    repT = repT(use,:);
    if isempty(repT) || height(repT)==0
        summaryT = table();
        return
    end

    [G, groupNames] = findgroups(string(repT.Group));
    nReps = splitapply(@numel, repT.Index, G);

    vars = {'NumTPEs','ContFreqTotal_perMin','MeanPeak_mmHg','MeanProminence_mmHg', ...
        'MeanWidth_s','MeanICI_s','MeanContPerMin','MeanTPEbasePressure_mmHg', ...
        'MeanTPEvolume_mL','MeanTPEvolumePercent'};

    summaryT = table(groupNames, nReps, 'VariableNames', {'Group','N'});

    for v = 1:numel(vars)
        x = repT.(vars{v});
        m = splitapply(@(z)mean(z,'omitnan'), x, G);
        s = splitapply(@(z)std(z,0,'omitnan'), x, G);
        summaryT.([vars{v} '_Mean']) = m;
        summaryT.([vars{v} '_SD']) = s;
    end
end

function plotTPEQCInternal(data, maxPts, showBaseline, showWindow)
    if isempty(data)
        error('No data selected.');
    end

    n = numel(data);
    nCols = min(3, n);
    nRows = ceil(n/nCols);

    figure('Name','TPE detection QC');
    tl = tiledlayout(nRows,nCols,'TileSpacing','compact','Padding','compact');

    for i = 1:n
        ax = nexttile(tl);
        if ~isfield(data(i),'time') || ~isfield(data(i),'proc') || ...
                ~isfield(data(i).proc,'pressureSmooth') || ~isfield(data(i).proc,'pressureBaseline')
            title(ax, sprintf('Record %d missing processed pressure', i));
            continue
        end

        t = data(i).time(:);
        pSmooth = data(i).proc.pressureSmooth(:);
        pBase = data(i).proc.pressureBaseline(:);
        pBaseSub = pSmooth - pBase;

        step = max(1, ceil(numel(t)/maxPts));
        plot(ax, t(1:step:end), pBaseSub(1:step:end), 'DisplayName','Pressure base-sub');
        hold(ax,'on');

        if showBaseline
            plot(ax, t(1:step:end), zeros(size(t(1:step:end))), '--', 'HandleVisibility','off');
        end

        ev = [];
        if isfield(data(i),'events') && isstruct(data(i).events) && ...
                isfield(data(i).events,'pressureTPE') && isstruct(data(i).events.pressureTPE)
            ev = data(i).events.pressureTPE;
        end

        if ~isempty(ev)
            if showWindow && isfield(ev,'params') && isfield(ev.params,'startAnalysisIdx') && isfield(ev.params,'endAnalysisIdx')
                si = ev.params.startAnalysisIdx;
                ei = ev.params.endAnalysisIdx;
                if si >= 1 && ei <= numel(t) && ei > si
                    yl = ylim(ax);
                    patch(ax, [t(si) t(ei) t(ei) t(si)], [yl(1) yl(1) yl(2) yl(2)], ...
                        [0.9 0.9 0.9], 'FaceAlpha',0.25, 'EdgeColor','none', 'HandleVisibility','off');
                    uistack(findobj(ax,'Type','line'),'top');
                end
            end

            if isfield(ev,'locs') && ~isempty(ev.locs)
                locs = ev.locs(:);
                locs = locs(locs>=1 & locs<=numel(t));
                plot(ax, t(locs), pBaseSub(locs), 'rv', 'MarkerFaceColor','r', ...
                    'DisplayName','Detected TPE');
            end
        end

        xlabel(ax,'Time (s)');
        ylabel(ax,'Pressure - baseline (mmHg)');
        title(ax, getShortTitle(data(i)), 'Interpreter','none');
        box(ax,'on');
    end
end

function titleStr = getShortTitle(d)
    g = getStringByPathOrDefault(d,'meta.groupKey',"Group");
    fb = getStringByPathOrDefault(d,'meta.fileBase',"");
    if strlength(fb) > 35
        fb = extractBefore(fb,36) + "...";
    end
    titleStr = char(g + " | " + fb);
end

function val = getByPath(S, pathStr)
    parts = strsplit(char(pathStr), '.');
    val = S;
    for p = 1:numel(parts)
        f = parts{p};
        if ~isstruct(val) || ~isfield(val, f)
            error('Missing field path "%s" at "%s".', char(pathStr), f);
        end
        val = val.(f);
    end
end

function s = getStringByPathOrDefault(S, pathStr, defaultVal)
    try
        v = getByPath(S, pathStr);
        s = string(v);
        if isempty(s), s = string(defaultVal); end
        s = s(1);
    catch
        s = string(defaultVal);
    end
end

function v = getNumericFieldOrDefault(S, fieldName, defaultVal)
    if isfield(S,fieldName) && ~isempty(S.(fieldName))
        v = S.(fieldName);
        if numel(v) > 1
            v = mean(v,'omitnan');
        end
    else
        v = defaultVal;
    end
end

function v = getFieldOrDefault(S, fieldName, defaultVal)
    if isfield(S,fieldName) && ~isempty(S.(fieldName))
        v = S.(fieldName);
    else
        v = defaultVal;
    end
end
