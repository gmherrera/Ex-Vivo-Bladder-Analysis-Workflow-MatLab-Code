function rawTracePlottingGUI
%RAWTRACEPLOTTINGGUI Interactive raw-trace plotting application.
%
%         Version 1.0
%         Date: September 4, 2026
%         Author: G. Herrera 
%         Co-Author/AI Tool: OpenAI ChatGPT (GPT-5.5)
%         Note: The core workflow was designed by the author and implemented by
%           ChatGPT via prompt engineering. All code was reviewed,
%           modified, and verified by the author.
% Usage:
%   rawTracePlottingGUI
%
% Purpose:
%   Opens a curated Ex-Vivo Analysis Workflow MAT dataset, displays its
%   records and user-defined experimental groups, and creates raw overlay
%   sparkline plots through plotRawPrepOverlaySparklines.m.
%
% The GUI does NOT require a variable named "data" in the base workspace.
% The dataset is loaded and retained internally by the application.
%
% Expected curated data structure (minimum):
%   data(i).time
%   data(i).pressure
%   data(i).nerveHz
%   data(i).volume
%   data(i).meta
%
% Common processed fields used by plotting:
%   data(i).proc.pressureSmooth
%   data(i).proc.volumePercent
%   data(i).proc.smoothNerveMovMean10s
%   data(i).proc.smoothNervePctMax
%
% User-defined group labels are read from:
%   data(i).meta.groupKey
%
% Requirements:
%   plotRawPrepOverlaySparklines.m must be on the MATLAB path.
%
% MATLAB: developed for R2024b or newer.

    % ---------------- Application state ----------------
    data = struct([]);
    datasetPath = "";
    n = 0;
    groupKeys = strings(0,1);
    fileNames = strings(0,1);
    dates = strings(0,1);
    prepIDs = strings(0,1);
    uGroups = strings(0,1);
    groupSummary = strings(0,1);

    prefGroup = 'AfferentNerveAnalysis';
    prefName  = 'LastCuratedDatasetDir';

    % ---------------- GUI ----------------
    fig = uifigure( ...
        'Name', 'Raw Trace Plotting', ...
        'Position', [80 80 1280 800]);

    gl = uigridlayout(fig, [5 3]);
    gl.RowHeight = {42, 38, 250, '1x', 46};
    gl.ColumnWidth = {290, '1x', 350};
    gl.Padding = [10 10 10 10];
    gl.RowSpacing = 8;
    gl.ColumnSpacing = 8;

    % Header
    titleLbl = uilabel(gl, ...
        'Text', 'Raw Trace Plotting', ...
        'FontWeight', 'bold', ...
        'FontSize', 17);
    titleLbl.Layout.Row = 1;
    titleLbl.Layout.Column = 1;

    datasetLbl = uilabel(gl, ...
        'Text', 'Dataset: No dataset loaded', ...
        'FontSize', 12);
    datasetLbl.Layout.Row = 1;
    datasetLbl.Layout.Column = 2;

    fileBtnPanel = uipanel(gl, 'BorderType', 'none');
    fileBtnPanel.Layout.Row = 1;
    fileBtnPanel.Layout.Column = 3;
    fileBtnGL = uigridlayout(fileBtnPanel, [1 3]);
    fileBtnGL.ColumnWidth = {'1x','1x','1x'};
    fileBtnGL.Padding = [0 0 0 0];

    openBtn = uibutton(fileBtnGL, ...
        'Text', 'Open Dataset...', ...
        'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) openDataset());
    reloadBtn = uibutton(fileBtnGL, ...
        'Text', 'Reload', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) reloadDataset());
    closeBtn = uibutton(fileBtnGL, ...
        'Text', 'Close Dataset', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) closeDataset());

    summaryLbl = uilabel(gl, ...
        'Text', 'Open a curated MAT dataset to begin.', ...
        'FontAngle', 'italic');
    summaryLbl.Layout.Row = 2;
    summaryLbl.Layout.Column = [1 3];

    % Group list panel
    groupPanel = uipanel(gl, 'Title', 'Experimental groups (meta.groupKey)');
    groupPanel.Layout.Row = [3 4];
    groupPanel.Layout.Column = 1;
    groupGL = uigridlayout(groupPanel, [3 1]);
    groupGL.RowHeight = {'1x', 34, 34};
    groupGL.Padding = [8 8 8 8];

    groupList = uilistbox(groupGL, ...
        'Items', {}, ...
        'Multiselect', 'on', ...
        'Enable', 'off');

    selectAllGroupsBtn = uibutton(groupGL, ...
        'Text', 'Select all groups', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) selectAllGroups());
    clearGroupsBtn = uibutton(groupGL, ...
        'Text', 'Clear group selection', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) clearGroupSelection());

    % Record table
    tbl = uitable(gl);
    tbl.Layout.Row = [3 4];
    tbl.Layout.Column = 2;
    tbl.ColumnEditable = [true false false false false];
    tbl.ColumnName = {'Use', 'Index', 'GroupKey', 'Date/FileTag', 'File'};
    tbl.ColumnWidth = {50, 55, 160, 120, 'auto'};
    tbl.Data = emptyRecordTable();
    tbl.Enable = 'off';
    tbl.CellEditCallback = @(~,~) updateStatus();

    % Options panel
    optPanel = uipanel(gl, 'Title', 'Plot options');
    optPanel.Layout.Row = [3 4];
    optPanel.Layout.Column = 3;
    optGL = uigridlayout(optPanel, [22 2]);
    optGL.RowHeight = repmat({30}, 1, 22);
    optGL.ColumnWidth = {130, '1x'};
    optGL.Padding = [8 8 8 8];

    uilabel(optGL, 'Text', 'X variable');
    xDrop = uidropdown(optGL, ...
        'Items', {'volumeML','volumePct','pressure','time','custom path'}, ...
        'Value', 'volumeML', ...
        'Enable', 'off', ...
        'ValueChangedFcn', @(~,~) updateTimeOptions());

    uilabel(optGL, 'Text', 'Y variable');
    yDrop = uidropdown(optGL, ...
        'Items', {'smoothNerveHz','smoothNervePct','pressure','rawNerveHz','custom path'}, ...
        'Value', 'smoothNerveHz', ...
        'Enable', 'off');

    uilabel(optGL, 'Text', 'Custom X path');
    xPathEdit = uieditfield(optGL, 'text', ...
        'Value', 'volume', ...
        'Enable', 'off');

    uilabel(optGL, 'Text', 'Custom Y path');
    yPathEdit = uieditfield(optGL, 'text', ...
        'Value', 'proc.smoothNerveMovMean10s', ...
        'Enable', 'off');

    uilabel(optGL, 'Text', 'Pairing mode');
    pairingDrop = uidropdown(optGL, ...
        'Items', {'byOrder','prepPath'}, ...
        'Value', 'byOrder', ...
        'Enable', 'off');

    uilabel(optGL, 'Text', 'Prep path');
    prepPathEdit = uieditfield(optGL, 'text', ...
        'Value', 'meta.prepID', ...
        'Enable', 'off');

    sameAxesCB = uicheckbox(optGL, 'Text', 'Same axes', 'Value', true, 'Enable', 'off');
    sameAxesCB.Layout.Column = [1 2];

    showAxesCB = uicheckbox(optGL, 'Text', 'Show axes', 'Value', false, 'Enable', 'off');
    showAxesCB.Layout.Column = [1 2];

    showLabelsCB = uicheckbox(optGL, 'Text', 'Show prep labels', 'Value', true, 'Enable', 'off');
    showLabelsCB.Layout.Column = [1 2];

    shiftTimeCB = uicheckbox(optGL, ...
        'Text', 'TIME: Shift start time to zero', ...
        'Value', false, ...
        'Enable', 'off');
    shiftTimeCB.Layout.Column = [1 2];

    treatmentCB = uicheckbox(optGL, ...
        'Text', 'TIME: Include treatment markers', ...
        'Value', false, ...
        'Enable', 'off');
    treatmentCB.Layout.Column = [1 2];

    scaleBarCB = uicheckbox(optGL, 'Text', 'Show scale bar', 'Value', false, 'Enable', 'off');
    scaleBarCB.Layout.Column = [1 2];

    uilabel(optGL, 'Text', 'X scale bar');
    xScaleEdit = uieditfield(optGL, 'numeric', ...
        'Value', 0.1, 'Limits', [0 Inf], 'Enable', 'off');

    uilabel(optGL, 'Text', 'Y scale bar');
    yScaleEdit = uieditfield(optGL, 'numeric', ...
        'Value', 5, 'Limits', [0 Inf], 'Enable', 'off');

    thinCB = uicheckbox(optGL, ...
        'Text', 'Thin to 1000 points/trace', ...
        'Value', true, ...
        'Enable', 'off');
    thinCB.Layout.Column = [1 2];

    % Bottom row
    statusLbl = uilabel(gl, 'Text', 'No dataset loaded.');
    statusLbl.Layout.Row = 5;
    statusLbl.Layout.Column = 1;

    applyGroupBtn = uibutton(gl, ...
        'Text', 'Apply selected groups to table', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) applySelectedGroups());
    applyGroupBtn.Layout.Row = 5;
    applyGroupBtn.Layout.Column = 2;

    btnPanel = uipanel(gl, 'BorderType', 'none');
    btnPanel.Layout.Row = 5;
    btnPanel.Layout.Column = 3;
    btnGL = uigridlayout(btnPanel, [1 2]);
    btnGL.ColumnWidth = {'1x','1x'};
    btnGL.Padding = [0 0 0 0];

    previewBtn = uibutton(btnGL, ...
        'Text', 'Preview selected', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) previewSelected());
    plotBtn = uibutton(btnGL, ...
        'Text', 'Create plot', ...
        'FontWeight', 'bold', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) createPlot());

    % ---------------- Nested callbacks ----------------
    function openDataset()
        startDir = pwd;
        if ispref(prefGroup, prefName)
            tmp = getpref(prefGroup, prefName);
            if isfolder(tmp)
                startDir = tmp;
            end
        end

        [fn, fp] = uigetfile( ...
            {'*.mat','MATLAB curated dataset (*.mat)'; '*.*','All files'}, ...
            'Open Curated Ex-Vivo Dataset', ...
            fullfile(startDir, '*.mat'));

        if isequal(fn,0)
            return
        end

        setpref(prefGroup, prefName, fp);
        loadDatasetFile(fullfile(fp, fn));
    end

    function reloadDataset()
        if strlength(datasetPath) == 0 || ~isfile(datasetPath)
            uialert(fig, 'The currently loaded dataset file could not be found.', ...
                'Reload failed');
            return
        end
        loadDatasetFile(datasetPath);
    end

    function closeDataset()
        data = struct([]);
        datasetPath = "";
        n = 0;
        groupKeys = strings(0,1);
        fileNames = strings(0,1);
        dates = strings(0,1);
        prepIDs = strings(0,1);
        uGroups = strings(0,1);
        groupSummary = strings(0,1);

        datasetLbl.Text = 'Dataset: No dataset loaded';
        summaryLbl.Text = 'Open a curated MAT dataset to begin.';
        tbl.Data = emptyRecordTable();
        groupList.Items = {};
        groupList.Value = {};
        statusLbl.Text = 'No dataset loaded.';
        setAnalysisControlsEnabled(false);
        reloadBtn.Enable = 'off';
        closeBtn.Enable = 'off';
    end

    function loadDatasetFile(fullName)
        try
            S = load(fullName);
            [candidate, varName] = findCuratedDataVariable(S);
            validateCuratedData(candidate);
        catch ME
            uialert(fig, sprintf('Could not open this curated dataset:\n\n%s', ME.message), ...
                'Dataset load failed');
            return
        end

        data = candidate;
        datasetPath = string(fullName);
        n = numel(data);

        groupKeys = strings(n,1);
        fileNames = strings(n,1);
        dates = strings(n,1);
        prepIDs = strings(n,1);

        for ii = 1:n
            groupKeys(ii) = getStringFieldOrDefault(data(ii), 'meta.groupKey', "Ungrouped");
            if strlength(groupKeys(ii)) == 0
                groupKeys(ii) = "Ungrouped";
            end
            fileNames(ii) = getFileName(data(ii));
            dates(ii) = inferDateString(data(ii));
            prepIDs(ii) = getStringFieldOrDefault(data(ii), 'meta.prepID', "");
        end

        uGroups = unique(groupKeys, 'stable');
        groupSummary = strings(numel(uGroups),1);
        for gg = 1:numel(uGroups)
            groupSummary(gg) = sprintf('%s  (n = %d)', ...
                uGroups(gg), sum(groupKeys == uGroups(gg)));
        end

        [~, shortName, ext] = fileparts(fullName);
        datasetLbl.Text = sprintf('Dataset: %s%s', shortName, ext);
        summaryLbl.Text = sprintf('%d records | %d experimental groups | MAT variable: %s', ...
            n, numel(uGroups), varName);

        tbl.Data = makeTableData(true(n,1));
        groupList.Items = cellstr(groupSummary);
        groupList.Value = cellstr(groupSummary);

        setAnalysisControlsEnabled(true);
        reloadBtn.Enable = 'on';
        closeBtn.Enable = 'on';
        updateTimeOptions();
        updateStatus();
    end

    function [candidate, varName] = findCuratedDataVariable(S)
        if isfield(S, 'data') && looksLikeCuratedData(S.data)
            candidate = S.data;
            varName = 'data';
            return
        end

        names = fieldnames(S);
        matches = strings(0,1);
        values = {};
        for kk = 1:numel(names)
            v = S.(names{kk});
            if looksLikeCuratedData(v)
                matches(end+1,1) = string(names{kk}); %#ok<AGROW>
                values{end+1,1} = v; %#ok<AGROW>
            end
        end

        if isempty(matches)
            error(['No recognizable curated dataset was found in this MAT file. ' ...
                'Expected a non-empty struct array containing time, pressure, volume, and meta fields.']);
        elseif numel(matches) == 1
            candidate = values{1};
            varName = char(matches(1));
        else
            [idx, ok] = listdlg( ...
                'PromptString', 'More than one possible curated dataset was found. Select one:', ...
                'SelectionMode', 'single', ...
                'ListString', cellstr(matches), ...
                'Name', 'Select Dataset Variable', ...
                'ListSize', [420 220]);
            if ~ok || isempty(idx)
                error('Dataset selection was cancelled.');
            end
            candidate = values{idx};
            varName = char(matches(idx));
        end
    end

    function tf = looksLikeCuratedData(v)
        tf = isstruct(v) && ~isempty(v) && ...
            isfield(v, 'time') && ...
            isfield(v, 'pressure') && ...
            isfield(v, 'volume') && ...
            isfield(v, 'meta');
    end

    function validateCuratedData(d)
        if ~looksLikeCuratedData(d)
            error('Selected variable is not a recognizable curated dataset.');
        end

        required = {'time','pressure','volume','meta'};
        for rr = 1:numel(required)
            if ~isfield(d, required{rr})
                error('Dataset is missing required field "%s".', required{rr});
            end
        end

        % nerveHz is required for several Y-variable options but a dataset can
        % still be useful for pressure-only plotting. Warn later if selected.
        if ~isfield(d, 'nerveHz')
            warning('rawTracePlottingGUI:MissingNerveHz', ...
                'Dataset does not contain nerveHz. Nerve plotting options will fail if selected.');
        end
    end

    function setAnalysisControlsEnabled(tf)
        if tf
            state = 'on';
        else
            state = 'off';
        end
        groupList.Enable = state;
        selectAllGroupsBtn.Enable = state;
        clearGroupsBtn.Enable = state;
        tbl.Enable = state;
        xDrop.Enable = state;
        yDrop.Enable = state;
        xPathEdit.Enable = state;
        yPathEdit.Enable = state;
        pairingDrop.Enable = state;
        prepPathEdit.Enable = state;
        sameAxesCB.Enable = state;
        showAxesCB.Enable = state;
        showLabelsCB.Enable = state;
        scaleBarCB.Enable = state;
        xScaleEdit.Enable = state;
        yScaleEdit.Enable = state;
        thinCB.Enable = state;
        applyGroupBtn.Enable = state;
        previewBtn.Enable = state;
        plotBtn.Enable = state;

        if ~tf
            shiftTimeCB.Enable = 'off';
            treatmentCB.Enable = 'off';
        end
    end

    function T = emptyRecordTable()
        T = table(false(0,1), zeros(0,1), strings(0,1), strings(0,1), strings(0,1), ...
            'VariableNames', {'Use','Index','GroupKey','Date_FileTag','File'});
    end

    function T = makeTableData(useMask)
        T = table(logical(useMask(:)), (1:n)', groupKeys, dates, fileNames, ...
            'VariableNames', {'Use','Index','GroupKey','Date_FileTag','File'});
    end

    function selectAllGroups()
        groupList.Value = cellstr(groupSummary);
    end

    function clearGroupSelection()
        groupList.Value = {};
    end

    function applySelectedGroups()
        selected = string(groupList.Value);
        selectedKeys = strings(0,1);
        for kk = 1:numel(selected)
            selectedKeys(end+1,1) = extractBeforeCountText(selected(kk)); %#ok<AGROW>
        end
        useMask = ismember(groupKeys, selectedKeys);
        tbl.Data = makeTableData(useMask);
        updateStatus();
    end

    function previewSelected()
        idx = getSelectedIndices();
        if isempty(idx)
            uialert(fig, 'No records are selected.', 'Nothing to preview');
            return
        end

        ug = unique(groupKeys(idx), 'stable');
        msg = sprintf('Selected %d of %d records.\n\nGroups:\n%s', ...
            numel(idx), n, strjoin(cellstr(ug), newline));
        uialert(fig, msg, 'Selected records');
    end

    function createPlot()
        idx = getSelectedIndices();
        if isempty(idx)
            uialert(fig, 'No records are selected.', 'Nothing to plot');
            return
        end

        if exist('plotRawPrepOverlaySparklines', 'file') ~= 2
            uialert(fig, ...
                'plotRawPrepOverlaySparklines.m is not on the MATLAB path.', ...
                'Missing plotting function');
            return
        end

        selectedData = data(idx);
        doTimeX = strcmpi(string(xDrop.Value), "time");
        doShiftTime = doTimeX && logical(shiftTimeCB.Value);
        doTreatmentMarkers = doTimeX && logical(treatmentCB.Value);

        if doShiftTime
            selectedData = shiftSelectedTimeToZero(selectedData);
        end

        args = {'groupPath', 'meta.groupKey', ...
                'pairingMode', char(pairingDrop.Value), ...
                'sameAxes', logical(sameAxesCB.Value), ...
                'showAxes', logical(showAxesCB.Value), ...
                'showPrepLabels', logical(showLabelsCB.Value), ...
                'prepLabelMode', 'index', ...
                'title', makePlotTitle(idx)};

        % X variable handling. Explicit canonical field paths are used where
        % needed so this GUI does not depend on legacy top-level aliases.
        switch char(xDrop.Value)
            case 'custom path'
                args = [args, {'xPath', char(xPathEdit.Value)}]; %#ok<AGROW>
            case 'time'
                args = [args, {'xPath', 'time'}]; %#ok<AGROW>
            case 'pressure'
                args = [args, {'xPath', 'proc.pressureSmooth'}]; %#ok<AGROW>
            otherwise
                args = [args, {'xVar', char(xDrop.Value)}]; %#ok<AGROW>
        end

        % Y variable handling.
        switch char(yDrop.Value)
            case 'custom path'
                args = [args, {'yPath', char(yPathEdit.Value)}]; %#ok<AGROW>
            case 'rawNerveHz'
                args = [args, {'yPath', 'nerveHz'}]; %#ok<AGROW>
            case 'pressure'
                args = [args, {'yPath', 'proc.pressureSmooth'}]; %#ok<AGROW>
            otherwise
                args = [args, {'yVar', char(yDrop.Value)}]; %#ok<AGROW>
        end

        if strcmp(pairingDrop.Value, 'prepPath')
            args = [args, {'prepPath', char(prepPathEdit.Value)}]; %#ok<AGROW>
        end

        if scaleBarCB.Value
            args = [args, {'showScaleBar', true, ...
                           'xScaleBarValue', xScaleEdit.Value, ...
                           'yScaleBarValue', yScaleEdit.Value}]; %#ok<AGROW>
        end

        if thinCB.Value
            args = [args, {'thinToNPoints', 1000}]; %#ok<AGROW>
        else
            args = [args, {'thinToNPoints', []}]; %#ok<AGROW>
        end

        try
            figure;
            h = plotRawPrepOverlaySparklines(selectedData, args{:});
            if logical(showLabelsCB.Value)
                reinforceSparklinePrepLabels(h);
            end
            if doTreatmentMarkers
                addTreatmentMarkersToSparklineAxes(h, selectedData);
            end
        catch ME
            uialert(fig, ME.message, 'Plot failed');
        end
    end

    function updateTimeOptions()
        hasData = ~isempty(data);
        isTimeX = hasData && strcmpi(string(xDrop.Value), "time");
        if isTimeX
            shiftTimeCB.Enable = 'on';
            treatmentCB.Enable = 'on';
        else
            shiftTimeCB.Enable = 'off';
            treatmentCB.Enable = 'off';
        end
    end

    function idx = getSelectedIndices()
        if isempty(data)
            idx = [];
            return
        end
        T = tbl.Data;
        if istable(T)
            useMask = logical(T.Use);
        else
            useMask = logical(cell2mat(T(:,1)));
        end
        idx = find(useMask);
    end

    function updateStatus()
        if isempty(data)
            statusLbl.Text = 'No dataset loaded.';
            return
        end
        idx = getSelectedIndices();
        statusLbl.Text = sprintf('%d of %d records selected.', numel(idx), n);
    end

    function ttl = makePlotTitle(idx)
        ug = unique(groupKeys(idx), 'stable');
        ttl = sprintf('Raw overlay sparklines: %s', strjoin(cellstr(ug), ', '));
    end
end

% =====================================================================
% Helper functions
% =====================================================================
function val = getStringFieldOrDefault(S, pathStr, defaultVal)
    try
        val = getByPath(S, pathStr);
        if iscell(val), val = val{1}; end
        val = string(val);
        if isempty(val) || ismissing(val) || strlength(val) == 0
            val = string(defaultVal);
        end
    catch
        val = string(defaultVal);
    end
end

function val = getByPath(S, pathStr)
    parts = strsplit(char(pathStr), '.');
    val = S;
    for p = 1:numel(parts)
        f = parts{p};
        if ~isstruct(val) || ~isfield(val, f)
            error('Missing field path "%s" at "%s".', pathStr, f);
        end
        val = val.(f);
    end
end

function fname = getFileName(d)
    if isfield(d, 'file') && ~isempty(d.file)
        [~, name, ext] = fileparts(char(d.file));
        fname = string([name ext]);
    else
        fname = "";
    end
end

function dstr = inferDateString(d)
    dstr = "";

    % Preferred: first fileTag, since date information has been stored there
    % in this workflow.
    try
        ft = d.meta.fileTags;
        if iscell(ft)
            if ~isempty(ft), dstr = string(ft{1}); end
        elseif isstring(ft) || ischar(ft)
            ft = string(ft);
            if ~isempty(ft), dstr = ft(1); end
        end
    catch
        dstr = "";
    end

    % Fallback: extract a leading 6- or 8-digit date-like token from filename.
    if strlength(dstr) == 0 && isfield(d, 'file')
        [~, name, ~] = fileparts(char(d.file));
        tok = regexp(name, '^\d{6,8}', 'match', 'once');
        if ~isempty(tok)
            dstr = string(tok);
        end
    end
end

function key = extractBeforeCountText(s)
    s = string(s);
    parts = split(s, "  (n = ");
    key = parts(1);
end

function dataOut = shiftSelectedTimeToZero(dataIn)
% Shift each selected record so data(i).time starts at zero. Also shift
% treatment event times, when present, so markers remain aligned.
    dataOut = dataIn;
    for i = 1:numel(dataOut)
        if isfield(dataOut(i), 'time') && ~isempty(dataOut(i).time)
            t0 = dataOut(i).time(1);
            dataOut(i).time = dataOut(i).time - t0;

            if isfield(dataOut(i), 'events') && isstruct(dataOut(i).events) && ...
                    isfield(dataOut(i).events, 'treatment') && isstruct(dataOut(i).events.treatment) && ...
                    isfield(dataOut(i).events.treatment, 'times') && ~isempty(dataOut(i).events.treatment.times)
                dataOut(i).events.treatment.times = dataOut(i).events.treatment.times - t0;
            end
        end
    end
end


function addTreatmentMarkersToSparklineAxes(h, data)
% Add cumulative treatment marker bars above each sparkline axis using:
%   data(i).events.treatment.times
%   data(i).events.treatment.labels
%
% CUMULATIVE MARKER RULE:
%   Each treatment line begins at its treatment start time and extends to the
%   end of that preparation trace, not merely to the next treatment.
%
% Labels are placed just above their own treatment lines whenever possible.

    if ~isfield(h, 'ax') || ~isfield(h, 'prepIDs') || ~isfield(h, 'uniquePrepIDs')
        return
    end

    ax = h.ax;
    prepIDs = string(h.prepIDs);
    uPrep = string(h.uniquePrepIDs);

    for p = 1:numel(uPrep)
        if p > numel(ax) || ~isgraphics(ax(p))
            continue
        end

        recIdx = find(prepIDs == uPrep(p));
        markers = collectTreatmentMarkers(data, recIdx);
        if isempty(markers.times)
            continue
        end

        thisAx = ax(p);
        hold(thisAx, 'on');

        % Determine the actual end of this preparation's plotted time trace.
        % This is more robust than using the current x-axis limit because the
        % axis may contain padding or shared limits that extend beyond the
        % plotted data. Treatment bars should run to the end of the trace.
        traceXEnd = getPrepTimeTraceEnd(data, recIdx);
        xl = xlim(thisAx);
        if ~isfinite(traceXEnd)
            traceXEnd = xl(2);
        end
        traceXEnd = min(traceXEnd, xl(2));

        yl0 = ylim(thisAx);
        yr0 = yl0(2) - yl0(1);
        if ~isfinite(yr0) || yr0 <= 0
            yr0 = 1;
        end

        [timesSorted, order] = sort(markers.times(:));
        labelsSorted = markers.labels(order);

        % Keep only marker starts that occur within the visible/plotted trace.
        keep = isfinite(timesSorted) & timesSorted >= xl(1) & timesSorted <= traceXEnd;
        timesSorted = timesSorted(keep);
        labelsSorted = labelsSorted(keep);

        if isempty(timesSorted)
            continue
        end

        % Remove duplicate treatment starts/labels that can occur if more
        % than one selected record contributes the same marker to one row.
        [timesSorted, labelsSorted] = uniqueTreatmentMarkers(timesSorted, labelsSorted);
        nTreat = numel(timesSorted);

        % Expand the y-range enough for stacked cumulative bars plus labels.
        % The trace remains in the lower part of the axis; treatment markers
        % live in the added headroom.
        headroomFrac = max(0.24, 0.12 + 0.10*nTreat);
        newYMax = yl0(2) + headroomFrac * yr0;
        ylim(thisAx, [yl0(1), newYMax]);

        yl = ylim(thisAx);
        yr = yl(2) - yl(1);
        if ~isfinite(yr) || yr <= 0
            yr = 1;
        end

        % Put the first treatment closest to the top. Subsequent treatments
        % are drawn on progressively lower rows. Labels are above each line.
        topPad   = 0.035 * yr;
        rowStep  = 0.078 * yr;
        labelGap = 0.010 * yr;

        xRange = diff(xl);
        if ~isfinite(xRange) || xRange <= 0
            xRange = 1;
        end
        labelNudge = 0.003 * xRange;

        for k = 1:nTreat
            x1 = max(timesSorted(k), xl(1));
            x2 = traceXEnd;

            % Skip degenerate cases where a treatment occurs at/after the end.
            if ~isfinite(x1) || ~isfinite(x2) || x2 <= x1
                continue
            end

            yBar  = yl(2) - topPad - rowStep*(k-1);
            yText = yBar + labelGap;

            % Cumulative treatment line: start time -> end of trace.
            line(thisAx, [x1 x2], [yBar yBar], ...
                'Color', [0 0 0], ...
                'LineWidth', 1.2, ...
                'Clipping', 'off', ...
                'HandleVisibility', 'off');

            % Put the label above the line. Nudge slightly right so the text
            % does not sit directly on the line start, but keep it anchored to
            % the treatment onset as much as possible.
            xText = min(x1 + labelNudge, x2);
            text(thisAx, xText, yText, char(labelsSorted(k)), ...
                'Interpreter', 'none', ...
                'FontSize', 8, ...
                'VerticalAlignment', 'bottom', ...
                'HorizontalAlignment', 'left', ...
                'Clipping', 'off', ...
                'HandleVisibility', 'off');
        end
    end
end

function xEnd = getPrepTimeTraceEnd(data, recIdx)
% Return the maximum time value across records contributing to one prep row.
    xEnd = NaN;
    if isempty(recIdx)
        return
    end
    vals = [];
    for ii = recIdx(:)'
        if ii <= numel(data) && isfield(data(ii), 'time') && ~isempty(data(ii).time)
            t = data(ii).time(:);
            vals = [vals; t(isfinite(t))]; %#ok<AGROW>
        end
    end
    if ~isempty(vals)
        xEnd = max(vals);
    end
end

function [timesOut, labelsOut] = uniqueTreatmentMarkers(timesIn, labelsIn)
% Keep the first occurrence of each same-time/same-label treatment marker.
% Rounding avoids duplicates caused by floating-point shifts.
    if isempty(timesIn)
        timesOut = timesIn;
        labelsOut = labelsIn;
        return
    end

    tKey = round(timesIn(:) * 1000) / 1000; % millisecond-level grouping
    labKey = string(labelsIn(:));
    combo = strcat(string(tKey), "__", labKey);
    [~, ia] = unique(combo, 'stable');
    ia = sort(ia);
    timesOut = timesIn(ia);
    labelsOut = labelsIn(ia);
end

function reinforceSparklinePrepLabels(h)
% Make prep labels visible even when the underlying sparkline function places
% labels outside the axes and MATLAB clips/margins hide part of the text.
    if ~isstruct(h) || ~isfield(h, 'ax')
        return
    end

    ax = h.ax;
    for k = 1:numel(ax)
        if ~isgraphics(ax(k))
            continue
        end
        thisAx = ax(k);
        xl = xlim(thisAx);
        yl = ylim(thisAx);
        xr = diff(xl);
        if ~isfinite(xr) || xr <= 0, xr = 1; end
        yr = diff(yl);
        if ~isfinite(yr) || yr <= 0, yr = 1; end

        % Add a small internal label near the left edge of each sparkline.
        labelText = sprintf('rep_%d', k);
        text(thisAx, xl(1) + 0.02*xr, yl(1) + 0.80*yr, labelText, ...
            'Interpreter', 'none', ...
            'FontSize', 10, ...
            'FontWeight', 'bold', ...
            'VerticalAlignment', 'middle', ...
            'HorizontalAlignment', 'left', ...
            'Clipping', 'off', ...
            'HandleVisibility', 'off');
    end
end

function markers = collectTreatmentMarkers(data, recIdx)
    times = [];
    labels = strings(0,1);

    for r = recIdx(:).'
        if r > numel(data)
            continue
        end
        if ~isfield(data(r), 'events') || ~isstruct(data(r).events) || ...
                ~isfield(data(r).events, 'treatment') || ~isstruct(data(r).events.treatment)
            continue
        end

        tr = data(r).events.treatment;
        if ~isfield(tr, 'times') || isempty(tr.times)
            continue
        end

        t = tr.times(:);
        if isfield(tr, 'labels') && ~isempty(tr.labels)
            lab = string(tr.labels(:));
        else
            lab = repmat("Treatment", numel(t), 1);
        end

        % Match label count to time count defensively.
        if numel(lab) < numel(t)
            lab(end+1:numel(t),1) = "Treatment";
        elseif numel(lab) > numel(t)
            lab = lab(1:numel(t));
        end

        times = [times; t]; %#ok<AGROW>
        labels = [labels; lab]; %#ok<AGROW>
    end

    markers.times = times;
    markers.labels = labels;
end
