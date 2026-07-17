function binningAnalysisGUI(data)
%BINNINGANALYSISGUI  GUI wrapper for grouped 2D binning functions.
%     Version 1.0
%     Date: July 8, 2026
%     Author: G. Herrera 
%     Co-Author/AI Tool: OpenAI ChatGPT (GPT-5.5)
%     Note: The core workflow, architecture and GUI Layout were designed by
%           the author and implemented by ChatGPT via prompt engineering.
%           All code was reviewed, modified, and verified by the author.
%           Refer to individual function dependencies for further
%           information.
%
%
% Usage:
%   binningAnalysisGUI          % launch, then load a curated MAT file
%   binningAnalysisGUI(data)    % optional backward-compatible direct input
%
% Requires these functions on MATLAB path:
%   bin2DByGroup.m
%   bin2DByGroup_equalN.m
%   plotBinned2DByGroup.m
%
% The GUI lets you select experiments, choose X/Y variables, choose grouping,
% run fixed-width or equal-N binning, plot results, and export the binned
% output to the MATLAB base workspace as binOut.

    % The GUI can launch without an input. A curated MAT file containing a
    % struct variable named "data" can then be loaded from the File menu.
    if nargin < 1 || isempty(data)
        data = struct([]);
    elseif ~isstruct(data)
        error('Optional input data must be a struct array.');
    end

    loadedFile = "";

    % ---------------- Variable aliases ----------------
    varLabels = { ...
        'Pressure raw', ...
        'Pressure smooth', ...
        'Pressure baseline', ...
        'Pressure peak envelope', ...
        'Volume mL', ...
        'Volume percent', ...
        'Nerve raw Hz', ...
        'Nerve smooth', ...
        'Nerve 10 s movmean', ...
        'Nerve percent max'};

    varPaths = containers.Map(varLabels, { ...
        'pressure', ...
        'proc.pressureSmooth', ...
        'proc.pressureBaseline', ...
        'proc.pressurePeak', ...
        'volume', ...
        'proc.volumePercent', ...
        'nerveHz', ...
        'proc.nerveSmooth', ...
        'proc.smoothNerveMovMean10s', ...
        'proc.smoothNervePctMax'});

    groupLabels = {'User group: meta.groupKey', 'Auto condition: meta.conditionKey'};
    groupPaths  = containers.Map(groupLabels, {'meta.groupKey','meta.conditionKey'});

    % ---------------- Table data ----------------
    T = buildExperimentTable(data);

    % ---------------- UI layout ----------------
    fig = uifigure('Name','Binning Analysis GUI', 'Position',[100 100 1250 720]);

    % File menu
    fileMenu = uimenu(fig, 'Text', 'File');
    uimenu(fileMenu, 'Text', 'Open Curated Dataset...', ...
        'MenuSelectedFcn', @openDataset);
    uimenu(fileMenu, 'Text', 'Close', ...
        'Separator', 'on', ...
        'MenuSelectedFcn', @(~,~) delete(fig));

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

    tbl = uitable(lp, 'Data', T);
    tbl.ColumnEditable = [true false false false false false false false false];
    tbl.ColumnName = T.Properties.VariableNames;
    tbl.Layout.Row = 1;

    btnGrid = uigridlayout(lp,[1 5]);
    btnGrid.Layout.Row = 2;
    btnGrid.ColumnWidth = {'1x','1x','1x','1x','1x'};

    uibutton(btnGrid,'Text','Select all','ButtonPushedFcn',@(~,~)setUseAll(true));
    uibutton(btnGrid,'Text','Select none','ButtonPushedFcn',@(~,~)setUseAll(false));
    uibutton(btnGrid,'Text','Only selected group','ButtonPushedFcn',@selectCurrentGroup);
    uibutton(btnGrid,'Text','Exclude stable','ButtonPushedFcn',@excludeStable);
    uibutton(btnGrid,'Text','Refresh table','ButtonPushedFcn',@refreshTable);

    rightPanel = uipanel(gl, 'Title','Binning options');
    rightPanel.Layout.Row = 1;
    rightPanel.Layout.Column = 2;

    rp = uigridlayout(rightPanel,[1 1]);
    tabs = uitabgroup(rp);

    tabFixed = uitab(tabs,'Title','Fixed-width binning');
    tabEqual = uitab(tabs,'Title','Equal-N binning');
    tabQC    = uitab(tabs,'Title','Preview / QC');

    % Fixed-width tab
    fgl = uigridlayout(tabFixed,[12 2]);
    fgl.RowHeight = repmat({32},1,12);
    fgl.ColumnWidth = {170,'1x'};
    fgl.Padding = [12 12 12 12];

    uilabel(fgl,'Text','X variable');
    fixedX = uidropdown(fgl,'Items',varLabels,'Value','Pressure smooth');

    uilabel(fgl,'Text','Y variable');
    fixedY = uidropdown(fgl,'Items',varLabels,'Value','Nerve 10 s movmean');

    uilabel(fgl,'Text','Group by');
    fixedGroup = uidropdown(fgl,'Items',groupLabels,'Value','User group: meta.groupKey');

    uilabel(fgl,'Text','X bin width');
    fixedBinWidth = uieditfield(fgl,'numeric','Value',2);

    uilabel(fgl,'Text','X min (blank = auto)');
    fixedXMin = uieditfield(fgl,'text','Value','');

    uilabel(fgl,'Text','X max (blank = auto)');
    fixedXMax = uieditfield(fgl,'text','Value','');

    uilabel(fgl,'Text','Min samples/bin');
    fixedMinN = uieditfield(fgl,'numeric','Value',1,'Limits',[1 Inf]);

    uilabel(fgl,'Text','Clamp X to 0-100');
    fixedClamp = uicheckbox(fgl,'Value',false,'Text','Use for percent axes');

    uilabel(fgl,'Text','Output variable');
    outNameFixed = uieditfield(fgl,'text','Value','binOut');

    uibutton(fgl,'Text','Run fixed binning','ButtonPushedFcn',@runFixed);
    uibutton(fgl,'Text','Run + plot','ButtonPushedFcn',@runFixedPlot);

    % Equal-N tab
    egl = uigridlayout(tabEqual,[10 2]);
    egl.RowHeight = repmat({32},1,10);
    egl.ColumnWidth = {170,'1x'};
    egl.Padding = [12 12 12 12];

    uilabel(egl,'Text','X variable');
    equalX = uidropdown(egl,'Items',varLabels,'Value','Pressure smooth');

    uilabel(egl,'Text','Y variable');
    equalY = uidropdown(egl,'Items',varLabels,'Value','Nerve 10 s movmean');

    uilabel(egl,'Text','Group by');
    equalGroup = uidropdown(egl,'Items',groupLabels,'Value','User group: meta.groupKey');

    uilabel(egl,'Text','Number of bins');
    equalNBins = uieditfield(egl,'numeric','Value',12,'Limits',[1 Inf]);

    uilabel(egl,'Text','Min samples/bin');
    equalMinN = uieditfield(egl,'numeric','Value',1,'Limits',[1 Inf]);

    uilabel(egl,'Text','Clamp X to 0-100');
    equalClamp = uicheckbox(egl,'Value',false,'Text','Use for percent axes');

    uilabel(egl,'Text','Output variable');
    outNameEqual = uieditfield(egl,'text','Value','binOut');

    uibutton(egl,'Text','Run equal-N binning','ButtonPushedFcn',@runEqual);
    uibutton(egl,'Text','Run + plot','ButtonPushedFcn',@runEqualPlot);

    % QC tab
    qgl = uigridlayout(tabQC,[8 2]);
    qgl.RowHeight = repmat({32},1,8);
    qgl.ColumnWidth = {170,'1x'};
    qgl.Padding = [12 12 12 12];

    uilabel(qgl,'Text','QC X variable');
    qcX = uidropdown(qgl,'Items',varLabels,'Value','Pressure smooth');
    uilabel(qgl,'Text','QC Y variable');
    qcY = uidropdown(qgl,'Items',varLabels,'Value','Nerve 10 s movmean');
    uilabel(qgl,'Text','Max points/file');
    qcThin = uieditfield(qgl,'numeric','Value',1500,'Limits',[100 Inf]);
    uibutton(qgl,'Text','Plot selected raw traces','ButtonPushedFcn',@plotQC);
    uibutton(qgl,'Text','Group counts table','ButtonPushedFcn',@showGroupCounts);

    % Bottom status panel
    status = uilabel(gl,'Text','Ready. Select experiments, choose binning options, then run.', ...
        'HorizontalAlignment','left');
    status.Layout.Row = 2;
    status.Layout.Column = [1 2];

    lastOut = [];

    % ---------------- Callbacks ----------------
    function openDataset(~,~)
        [matFile, matPath] = uigetfile( ...
            {'*.mat','MAT-files (*.mat)'}, ...
            'Select curated MAT file containing variable named data');

        if isequal(matFile,0)
            return
        end

        fullName = fullfile(matPath, matFile);

        try
            S = load(fullName, 'data');
        catch ME
            uialert(fig, ME.message, 'Dataset load error');
            return
        end

        if ~isfield(S,'data') || ~isstruct(S.data) || isempty(S.data)
            uialert(fig, ...
                'The selected MAT file does not contain a non-empty struct variable named data.', ...
                'Invalid curated dataset');
            return
        end

        data = S.data(:);
        loadedFile = string(fullName);
        lastOut = [];

        tbl.Data = buildExperimentTable(data);
        updateStatus();
        fig.Name = sprintf('Binning Analysis GUI - %s', matFile);
    end

    function setUseAll(tf)
        T2 = tbl.Data;
        T2.Use(:) = tf;
        tbl.Data = T2;
        updateStatus();
    end

    function selectCurrentGroup(~,~)
        T2 = tbl.Data;
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

    function excludeStable(~,~)
        T2 = tbl.Data;
        isStable = strcmpi(string(T2.VolumeMode),'stable');
        T2.Use(isStable) = false;
        tbl.Data = T2;
        updateStatus();
    end

    function refreshTable(~,~)
        tbl.Data = buildExperimentTable(data);
        updateStatus();
    end

    function updateStatus()
        T2 = tbl.Data;

        if isempty(data) || height(T2) == 0
            status.Text = 'No dataset loaded. Use File > Open Curated Dataset...';
            return
        end

        nSel = sum(T2.Use);
        g = unique(string(T2.Group(T2.Use)),'stable');
        groupText = strjoin(g, ', ');
        if strlength(groupText) == 0
            groupText = "none";
        end

        if strlength(loadedFile) > 0
            [~, loadedName, loadedExt] = fileparts(char(loadedFile));
            fileText = string(loadedName) + string(loadedExt);
            status.Text = sprintf('Loaded: %s | Selected experiments: %d / %d | Groups: %s', ...
                fileText, nSel, height(T2), groupText);
        else
            status.Text = sprintf('Selected experiments: %d / %d. Groups: %s', ...
                nSel, height(T2), groupText);
        end
    end

    function dsel = selectedData()
        if isempty(data)
            error('No curated dataset is loaded. Use File > Open Curated Dataset...');
        end
        T2 = tbl.Data;
        idx = find(T2.Use);
        if isempty(idx)
            error('No experiments selected.');
        end
        dsel = data(idx);
    end

    function runFixed(~,~)
        try
            lastOut = doFixed();
            assignin('base', char(outNameFixed.Value), lastOut);
            status.Text = sprintf('Fixed-width binning complete. Output assigned to workspace variable "%s".', outNameFixed.Value);
        catch ME
            uialert(fig, ME.message, 'Fixed-width binning error');
        end
    end

    function runFixedPlot(~,~)
        runFixed();
        if ~isempty(lastOut)
            figure('Name','Fixed-width binned result');
            ax = axes;
            plotBinned2DByGroup(ax,lastOut);
        end
    end

    function out = doFixed()
        dsel = selectedData();
        args = { ...
            'xPath', varPaths(fixedX.Value), ...
            'yPath', varPaths(fixedY.Value), ...
            'groupPath', groupPaths(fixedGroup.Value), ...
            'xBinWidth', fixedBinWidth.Value, ...
            'minNPerBin', fixedMinN.Value};

        xmin = str2double(strtrim(fixedXMin.Value));
        xmax = str2double(strtrim(fixedXMax.Value));
        if isfinite(xmin), args = [args, {'xMin', xmin}]; end %#ok<AGROW>
        if isfinite(xmax), args = [args, {'xMax', xmax}]; end %#ok<AGROW>
        args = [args, {'clampX0100', logical(fixedClamp.Value)}];

        out = bin2DByGroup(dsel, args{:});
    end

    function runEqual(~,~)
        try
            lastOut = doEqual();
            assignin('base', char(outNameEqual.Value), lastOut);
            status.Text = sprintf('Equal-N binning complete. Output assigned to workspace variable "%s".', outNameEqual.Value);
        catch ME
            uialert(fig, ME.message, 'Equal-N binning error');
        end
    end

    function runEqualPlot(~,~)
        runEqual();
        if ~isempty(lastOut)
            figure('Name','Equal-N binned result');
            ax = axes;
            plotBinned2DByGroup(ax,lastOut);
        end
    end

    function out = doEqual()
        dsel = selectedData();
        out = bin2DByGroup_equalN(dsel, ...
            'xPath', varPaths(equalX.Value), ...
            'yPath', varPaths(equalY.Value), ...
            'groupPath', groupPaths(equalGroup.Value), ...
            'nBins', equalNBins.Value, ...
            'minNPerBin', equalMinN.Value, ...
            'clampX0100', logical(equalClamp.Value));
    end

    function plotQC(~,~)
        try
            dsel = selectedData();
            xp = varPaths(qcX.Value);
            yp = varPaths(qcY.Value);
            maxPts = round(qcThin.Value);

            figure('Name','QC raw selected traces');
            ax = axes;
            hold(ax,'on');
            for ii = 1:numel(dsel)
                x = getByPath(dsel(ii), xp);
                y = getByPath(dsel(ii), yp);
                x = x(:); y = y(:);
                keep = isfinite(x) & isfinite(y);
                x = x(keep); y = y(keep);
                if isempty(x), continue; end
                step = max(1, ceil(numel(x)/maxPts));
                plot(ax, x(1:step:end), y(1:step:end), 'DisplayName', getShortLabel(dsel(ii)));
            end
            xlabel(ax, qcX.Value, 'Interpreter','none');
            ylabel(ax, qcY.Value, 'Interpreter','none');
            title(ax, 'Selected raw traces', 'Interpreter','none');
            legend(ax,'show','Interpreter','none','Location','best');
            box(ax,'on');
        catch ME
            uialert(fig, ME.message, 'QC plot error');
        end
    end

    function showGroupCounts(~,~)
        T2 = tbl.Data;
        Tsel = T2(T2.Use,:);
        if isempty(Tsel)
            uialert(fig,'No experiments selected.','No selection');
            return
        end
        [G,gNames] = findgroups(string(Tsel.Group));
        counts = splitapply(@numel, Tsel.Index, G);
        countTable = table(gNames, counts, 'VariableNames', {'Group','N'});
        assignin('base','binningGroupCounts',countTable);
        f2 = uifigure('Name','Selected group counts','Position',[200 200 520 360]);
        uitable(f2,'Data',countTable,'Position',[10 10 500 340]);
    end

    updateStatus();
end

% =====================================================================
% Helpers
% =====================================================================
function T = buildExperimentTable(data)
    n = numel(data);
    Use = true(n,1);
    Index = (1:n).';
    Date = strings(n,1);
    DateTag = strings(n,1);
    Group = strings(n,1);
    Condition = strings(n,1);
    VolumeMode = strings(n,1);
    Treatments = strings(n,1);
    FileBase = strings(n,1);

    for i = 1:n
        if isfield(data(i),'meta')
            m = data(i).meta;
            if isfield(m,'fileTags') && ~isempty(m.fileTags)
                DateTag(i) = string(m.fileTags{1});
                Date(i) = parseDateTag(DateTag(i));
            else
                DateTag(i) = "";
                Date(i) = "";
            end
            if isfield(m,'groupKey'), Group(i) = string(m.groupKey); else, Group(i) = "Unassigned"; end
            if isfield(m,'conditionKey'), Condition(i) = string(m.conditionKey); end
            if isfield(m,'volumeMode'), VolumeMode(i) = string(m.volumeMode); end
            if isfield(m,'fileBase'), FileBase(i) = string(m.fileBase); end
        end

        if isfield(data(i),'events') && isfield(data(i).events,'treatment') && ...
                isfield(data(i).events.treatment,'labels')
            Treatments(i) = strjoin(string(data(i).events.treatment.labels(:)), ' | ');
        end
    end

    T = table(Use, Index, Date, DateTag, Group, Condition, VolumeMode, Treatments, FileBase);
end

function s = parseDateTag(tag)
    tag = string(tag);
    s = tag;
    % Expected format like 260423001: YYMMDD###
    if strlength(tag) >= 6
        six = extractBefore(tag, 7);
        if all(isstrprop(char(six),'digit'))
            yy = str2double(extractBetween(six,1,2));
            mm = str2double(extractBetween(six,3,4));
            dd = str2double(extractBetween(six,5,6));
            if isfinite(yy) && isfinite(mm) && isfinite(dd) && mm>=1 && mm<=12 && dd>=1 && dd<=31
                yr = 2000 + yy;
                try
                    s = string(datetime(yr,mm,dd,'Format','yyyy-MM-dd'));
                catch
                    s = tag;
                end
            end
        end
    end
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

function lbl = getShortLabel(d)
    if isfield(d,'meta') && isfield(d.meta,'groupKey')
        g = string(d.meta.groupKey);
    else
        g = "Group";
    end
    if isfield(d,'meta') && isfield(d.meta,'fileTags') && ~isempty(d.meta.fileTags)
        tag = string(d.meta.fileTags{1});
    else
        tag = "";
    end
    lbl = char(g + " " + tag);
end
