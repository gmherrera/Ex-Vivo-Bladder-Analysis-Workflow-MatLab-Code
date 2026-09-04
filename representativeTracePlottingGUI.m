function representativeTracePlottingGUI
%REPRESENTATIVETRACEPLOTTINGGUI Publication-style representative trace plots.
%         Version 1.0
%         Date: September 4, 2026
%         Author: G. Herrera 
%         Co-Author/AI Tool: OpenAI ChatGPT (GPT-5.5)
%         Note: The core workflow was designed by the author and implemented by
%           ChatGPT via prompt engineering. All code was reviewed,
%           modified, and verified by the author.
%
% Usage:
%   representativeTracePlottingGUI
%
% Opens a curated Ex-Vivo Analysis Workflow MAT dataset, allows records to
% be selected, and creates publication/grant-ready representative trace
% figures in one of two layouts:
%
%   1) Time mode (3 stacked traces)
%        Volume   vs Time
%        Pressure vs Time
%        Nerve    vs Time
%
%   2) Volume mode (2 stacked traces)
%        Pressure vs Volume
%        Nerve    vs Volume
%
% By default, each selected record is plotted in its own figure. If
% 'Overlay traces' is selected, all selected records are plotted together
% in one figure, using a consistent color for each record across axes.
%
% Expected curated data structure:
%   data(i).time
%   data(i).pressure
%   data(i).nerveHz
%   data(i).volume
%   data(i).meta
%
% Common processed fields:
%   data(i).proc.pressureSmooth
%   data(i).proc.nerveSmooth
%   data(i).proc.smoothNerveMovMean10s
%   data(i).proc.volumePercent
%
% Group labels are read from:
%   data(i).meta.groupKey
%
% MATLAB: developed for R2024b or newer.

    % ================= Application state =================
    data = struct([]);
    datasetPath = "";
    n = 0;
    groupKeys = strings(0,1);
    fileNames = strings(0,1);
    dates = strings(0,1);
    uGroups = strings(0,1);
    groupSummary = strings(0,1);

    prefGroup = 'AfferentNerveAnalysis';
    prefName  = 'LastCuratedDatasetDir';

    % ================= GUI =================
    fig = uifigure( ...
        'Name', 'Representative Trace Plotting', ...
        'Position', [70 70 1340 820]);

    gl = uigridlayout(fig, [5 3]);
    gl.RowHeight = {42, 38, 250, '1x', 46};
    gl.ColumnWidth = {290, '1x', 380};
    gl.Padding = [10 10 10 10];
    gl.RowSpacing = 8;
    gl.ColumnSpacing = 8;

    % ----- Header -----
    titleLbl = uilabel(gl, ...
        'Text', 'Representative Trace Plotting', ...
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

    % ----- Group list -----
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

    % ----- Record table -----
    tbl = uitable(gl);
    tbl.Layout.Row = [3 4];
    tbl.Layout.Column = 2;
    tbl.ColumnEditable = [true false false false false];
    tbl.ColumnName = {'Use', 'Index', 'GroupKey', 'Date/FileTag', 'File'};
    tbl.ColumnWidth = {50, 55, 160, 120, 'auto'};
    tbl.Data = emptyRecordTable();
    tbl.Enable = 'off';
    tbl.CellEditCallback = @(~,~) updateStatus();

    % ----- Options -----
    optPanel = uipanel(gl, 'Title', 'Representative trace options', 'Scrollable', 'on');
    optPanel.Layout.Row = [3 4];
    optPanel.Layout.Column = 3;

    optGL = uigridlayout(optPanel, [19 2]);
    optGL.RowHeight = repmat({30}, 1, 19);
    optGL.ColumnWidth = {155, '1x'};
    optGL.Padding = [8 8 8 8];

    uilabel(optGL, 'Text', 'Plot layout');
    layoutDrop = uidropdown(optGL, ...
        'Items', { ...
            'Time: Volume + Pressure + Nerve', ...
            'Volume: Pressure + Nerve'}, ...
        'Value', 'Time: Volume + Pressure + Nerve', ...
        'Enable', 'off', ...
        'ValueChangedFcn', @(~,~) updateOptionAvailability());

    overlayCB = uicheckbox(optGL, ...
        'Text', 'Overlay selected traces in one figure', ...
        'Value', false, ...
        'Enable', 'off', ...
        'FontWeight', 'bold', ...
        'ValueChangedFcn', @(~,~) updateOverlayNote());
    overlayCB.Layout.Column = [1 2];

    uilabel(optGL, 'Text', 'Pressure signal');
    pressureDrop = uidropdown(optGL, ...
        'Items', { ...
            'Smoothed pressure', ...
            'Raw pressure'}, ...
        'Value', 'Smoothed pressure', ...
        'Enable', 'off');

    uilabel(optGL, 'Text', 'Nerve signal');
    nerveDrop = uidropdown(optGL, ...
        'Items', { ...
            '10 s moving mean', ...
            'Processed smooth nerve', ...
            'Raw nerve Hz'}, ...
        'Value', '10 s moving mean', ...
        'Enable', 'off');

    uilabel(optGL, 'Text', 'Time units');
    timeUnitsDrop = uidropdown(optGL, ...
        'Items', {'Seconds','Minutes'}, ...
        'Value', 'Seconds', ...
        'Enable', 'off');

    shiftTimeCB = uicheckbox(optGL, ...
        'Text', 'Shift time to start at zero', ...
        'Value', true, ...
        'Enable', 'off');
    shiftTimeCB.Layout.Column = [1 2];

    uilabel(optGL, 'Text', 'Volume axis');
    volumeUnitsDrop = uidropdown(optGL, ...
        'Items', {'mL','% max volume'}, ...
        'Value', 'mL', ...
        'Enable', 'off');

    showTitleCB = uicheckbox(optGL, ...
        'Text', 'Show figure title', ...
        'Value', false, ...
        'Enable', 'off');
    showTitleCB.Layout.Column = [1 2];

    showGroupCB = uicheckbox(optGL, ...
        'Text', 'Include group in title', ...
        'Value', true, ...
        'Enable', 'off');
    showGroupCB.Layout.Column = [1 2];

    uilabel(optGL, 'Text', 'Line width');
    lineWidthEdit = uieditfield(optGL, 'numeric', ...
        'Value', 1.25, ...
        'Limits', [0.25 6], ...
        'Enable', 'off');

    linkAxesCB = uicheckbox(optGL, ...
        'Text', 'Link X axes', ...
        'Value', true, ...
        'Enable', 'off');
    linkAxesCB.Layout.Column = [1 2];

    boxAxesCB = uicheckbox(optGL, ...
        'Text', 'Box axes', ...
        'Value', false, ...
        'Enable', 'off');
    boxAxesCB.Layout.Column = [1 2];

    thinCB = uicheckbox(optGL, ...
        'Text', 'Thin very long traces for display', ...
        'Value', false, ...
        'Enable', 'off');
    thinCB.Layout.Column = [1 2];

    uilabel(optGL, 'Text', 'Maximum plot points');
    maxPointsEdit = uieditfield(optGL, 'numeric', ...
        'Value', 10000, ...
        'Limits', [500 Inf], ...
        'RoundFractionalValues', 'on', ...
        'Enable', 'off');

    noteLbl = uilabel(optGL, ...
        'Text', 'Each selected record creates one figure.', ...
        'FontAngle', 'italic');
    noteLbl.Layout.Column = [1 2];

    % ----- Bottom row -----
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
        'Text', 'Create figure(s)', ...
        'FontWeight', 'bold', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) createFigures());

    updateOptionAvailability();

    % ================================================================
    % Nested callbacks
    % ================================================================
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
        loadDataset(fullfile(fp, fn));
    end

    function reloadDataset()
        if strlength(datasetPath) == 0 || ~isfile(datasetPath)
            uialert(fig, 'The current dataset file cannot be found.', 'Reload failed');
            return
        end
        loadDataset(datasetPath);
    end

    function closeDataset()
        data = struct([]);
        datasetPath = "";
        n = 0;
        groupKeys = strings(0,1);
        fileNames = strings(0,1);
        dates = strings(0,1);
        uGroups = strings(0,1);
        groupSummary = strings(0,1);

        datasetLbl.Text = 'Dataset: No dataset loaded';
        summaryLbl.Text = 'Open a curated MAT dataset to begin.';
        groupList.Items = {};
        groupList.Value = {};
        tbl.Data = emptyRecordTable();
        statusLbl.Text = 'No dataset loaded.';

        setControlsEnabled(false);
        reloadBtn.Enable = 'off';
        closeBtn.Enable = 'off';
    end

    function loadDataset(pathIn)
        try
            S = load(pathIn);
            candidate = identifyCuratedDataset(S);
            validateCuratedDataset(candidate);
        catch ME
            uialert(fig, ME.message, 'Could not open dataset');
            return
        end

        data = candidate;
        datasetPath = string(pathIn);
        n = numel(data);

        groupKeys = strings(n,1);
        fileNames = strings(n,1);
        dates = strings(n,1);

        for i = 1:n
            groupKeys(i) = getStringFieldOrDefault(data(i), 'meta.groupKey', "Ungrouped");
            if strlength(groupKeys(i)) == 0
                groupKeys(i) = "Ungrouped";
            end
            fileNames(i) = getFileName(data(i));
            dates(i) = inferDateString(data(i));
        end

        uGroups = unique(groupKeys, 'stable');
        groupSummary = strings(numel(uGroups),1);
        for g = 1:numel(uGroups)
            groupSummary(g) = sprintf('%s  (n = %d)', uGroups(g), sum(groupKeys == uGroups(g)));
        end

        [~, displayName, ext] = fileparts(char(datasetPath));
        datasetLbl.Text = sprintf('Dataset: %s%s', displayName, ext);
        summaryLbl.Text = sprintf('%d records | %d experimental groups', n, numel(uGroups));

        groupList.Items = cellstr(groupSummary);
        groupList.Value = cellstr(groupSummary);
        tbl.Data = makeTableData(true(n,1));

        setControlsEnabled(true);
        reloadBtn.Enable = 'on';
        closeBtn.Enable = 'on';
        updateStatus();
        updateOptionAvailability();
    end

    function setControlsEnabled(tf)
        if tf, state = 'on'; else, state = 'off'; end

        groupList.Enable = state;
        selectAllGroupsBtn.Enable = state;
        clearGroupsBtn.Enable = state;
        tbl.Enable = state;
        layoutDrop.Enable = state;
        pressureDrop.Enable = state;
        nerveDrop.Enable = state;
        timeUnitsDrop.Enable = state;
        shiftTimeCB.Enable = state;
        volumeUnitsDrop.Enable = state;
        showTitleCB.Enable = state;
        showGroupCB.Enable = state;
        lineWidthEdit.Enable = state;
        linkAxesCB.Enable = state;
        boxAxesCB.Enable = state;
        overlayCB.Enable = state;
        thinCB.Enable = state;
        maxPointsEdit.Enable = state;
        applyGroupBtn.Enable = state;
        previewBtn.Enable = state;
        plotBtn.Enable = state;
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
        for k = 1:numel(selected)
            selectedKeys(end+1,1) = extractBeforeCountText(selected(k)); %#ok<AGROW>
        end
        useMask = ismember(groupKeys, selectedKeys);
        tbl.Data = makeTableData(useMask);
        updateStatus();
    end

    function previewSelected()
        idx = getSelectedIndices();
        if isempty(idx)
            uialert(fig, 'No records are selected.', 'Nothing selected');
            return
        end

        if logical(overlayCB.Value)
            plotModeText = 'Selected records will be overlaid in one figure.';
        else
            plotModeText = 'One figure will be created per selected record.';
        end
        groupsText = strjoin(cellstr(unique(groupKeys(idx), 'stable')), newline);
        msg = sprintf('Selected %d of %d records.\n\nGroups:\n%s\n\n%s', ...
            numel(idx), n, groupsText, plotModeText);
        uialert(fig, msg, 'Selected records');
    end

    function updateStatus()
        idx = getSelectedIndices();
        statusLbl.Text = sprintf('%d of %d records selected.', numel(idx), n);
    end

    function updateOptionAvailability()
        hasData = ~isempty(data);
        isTimeMode = strcmp(layoutDrop.Value, 'Time: Volume + Pressure + Nerve');

        if hasData && isTimeMode
            timeUnitsDrop.Enable = 'on';
            shiftTimeCB.Enable = 'on';
        else
            timeUnitsDrop.Enable = 'off';
            shiftTimeCB.Enable = 'off';
        end

        if hasData
            volumeUnitsDrop.Enable = 'on';
            maxPointsEdit.Enable = 'on';
        end
    end


    function updateOverlayNote()
        if logical(overlayCB.Value)
            noteLbl.Text = 'Selected records will be overlaid in one figure.';
            plotBtn.Text = 'Create overlay figure';
        else
            noteLbl.Text = 'Each selected record creates one figure.';
            plotBtn.Text = 'Create figure(s)';
        end
    end

    function createFigures()
        idx = getSelectedIndices();
        if isempty(idx)
            uialert(fig, 'No records are selected.', 'Nothing to plot');
            return
        end

        if logical(overlayCB.Value)
            try
                createOverlayFigure(idx);
            catch ME
                uialert(fig, ME.message, 'Overlay plot failed');
            end
            return
        end

        problems = strings(0,1);

        for kk = 1:numel(idx)
            r = idx(kk);
            try
                createRepresentativeFigure(data(r), r, groupKeys(r));
            catch ME
                problems(end+1,1) = sprintf('Record %d: %s', r, ME.message); %#ok<AGROW>
            end
        end

        if ~isempty(problems)
            uialert(fig, strjoin(cellstr(problems), newline), 'Some figures could not be created');
        end
    end

    function createOverlayFigure(idx)
        isTimeMode = strcmp(layoutDrop.Value, 'Time: Volume + Pressure + Nerve');
        nSel = numel(idx);

        % Use one color per selected record and keep that color consistent
        % across all axes so the condition identity is visually stable.
        co = get(groot, 'defaultAxesColorOrder');
        nColors = size(co,1);
        C = zeros(nSel,3);
        for kk = 1:nSel
            C(kk,:) = co(mod(kk-1,nColors)+1,:);
        end

        legendLabels = makeOverlayLegendLabels(idx);

        if isTimeMode
            f = figure('Name', 'Representative trace overlay', 'Color', 'w');
            t = tiledlayout(f, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
            ax1 = nexttile(t,1); hold(ax1,'on');
            ax2 = nexttile(t,2); hold(ax2,'on');
            ax3 = nexttile(t,3); hold(ax3,'on');

            hLeg = gobjects(nSel,1);
            for kk = 1:nSel
                r = idx(kk);
                d = data(r);
                pressure = getPressureSignal(d, pressureDrop.Value);
                nerve = getNerveSignal(d, nerveDrop.Value);
                volume = getVolumeSignal(d, volumeUnitsDrop.Value);
                x = d.time(:);

                if logical(shiftTimeCB.Value)
                    x = x - x(1);
                end
                if strcmp(timeUnitsDrop.Value, 'Minutes')
                    x = x / 60;
                end

                validateSameLength(x, volume, pressure, nerve);
                [x, volume, pressure, nerve] = maybeThin(x, volume, pressure, nerve);

                hLeg(kk) = plot(ax1, x, volume, 'LineWidth', lineWidthEdit.Value, ...
                    'Color', C(kk,:), 'DisplayName', legendLabels{kk});
                plot(ax2, x, pressure, 'LineWidth', lineWidthEdit.Value, 'Color', C(kk,:));
                plot(ax3, x, nerve, 'LineWidth', lineWidthEdit.Value, 'Color', C(kk,:));
            end

            ylabel(ax1, volumeYLabel());
            ylabel(ax2, 'Pressure (mmHg)');
            ylabel(ax3, nerveYLabel());
            if strcmp(timeUnitsDrop.Value, 'Minutes')
                xlabel(ax3, 'Time (min)');
            else
                xlabel(ax3, 'Time (s)');
            end

            stylePublicationAxes(ax1); stylePublicationAxes(ax2); stylePublicationAxes(ax3);
            legend(ax1, hLeg, legendLabels, 'Interpreter', 'none', 'Location', 'best');

            if logical(linkAxesCB.Value)
                linkaxes([ax1 ax2 ax3], 'x');
            end

        else
            f = figure('Name', 'Representative trace overlay', 'Color', 'w');
            t = tiledlayout(f, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
            ax1 = nexttile(t,1); hold(ax1,'on');
            ax2 = nexttile(t,2); hold(ax2,'on');

            hLeg = gobjects(nSel,1);
            for kk = 1:nSel
                r = idx(kk);
                d = data(r);
                pressure = getPressureSignal(d, pressureDrop.Value);
                nerve = getNerveSignal(d, nerveDrop.Value);
                volume = getVolumeSignal(d, volumeUnitsDrop.Value);

                validateSameLength(volume, pressure, nerve);
                [volume, pressure, nerve] = maybeThin(volume, pressure, nerve);

                hLeg(kk) = plot(ax1, volume, pressure, 'LineWidth', lineWidthEdit.Value, ...
                    'Color', C(kk,:), 'DisplayName', legendLabels{kk});
                plot(ax2, volume, nerve, 'LineWidth', lineWidthEdit.Value, 'Color', C(kk,:));
            end

            ylabel(ax1, 'Pressure (mmHg)');
            ylabel(ax2, nerveYLabel());
            xlabel(ax2, volumeXLabel());
            stylePublicationAxes(ax1); stylePublicationAxes(ax2);
            legend(ax1, hLeg, legendLabels, 'Interpreter', 'none', 'Location', 'best');

            if logical(linkAxesCB.Value)
                linkaxes([ax1 ax2], 'x');
            end
        end

        if logical(showTitleCB.Value)
            title(t, makeOverlayTitle(idx), 'Interpreter', 'none');
        end
    end

    function labels = makeOverlayLegendLabels(idx)
        labels = cell(numel(idx),1);
        selGroups = groupKeys(idx);
        for kk = 1:numel(idx)
            g = selGroups(kk);
            if sum(selGroups == g) > 1
                labels{kk} = sprintf('%s (record %d)', g, idx(kk));
            else
                labels{kk} = char(g);
            end
        end
    end

    function ttl = makeOverlayTitle(idx)
        ug = unique(groupKeys(idx), 'stable');
        if logical(showGroupCB.Value)
            ttl = sprintf('Overlay: %s', strjoin(cellstr(ug), ', '));
        else
            ttl = sprintf('Overlay of %d selected records', numel(idx));
        end
    end

    function createRepresentativeFigure(d, recordIndex, groupKey)
        pressure = getPressureSignal(d, pressureDrop.Value);
        nerve = getNerveSignal(d, nerveDrop.Value);

        isTimeMode = strcmp(layoutDrop.Value, 'Time: Volume + Pressure + Nerve');

        if isTimeMode
            x = d.time(:);
            volume = getVolumeSignal(d, volumeUnitsDrop.Value);

            if logical(shiftTimeCB.Value)
                x = x - x(1);
            end

            if strcmp(timeUnitsDrop.Value, 'Minutes')
                x = x / 60;
                xLabelText = 'Time (min)';
            else
                xLabelText = 'Time (s)';
            end

            validateSameLength(x, volume, pressure, nerve);
            [x, volume, pressure, nerve] = maybeThin(x, volume, pressure, nerve);

            f = figure('Name', sprintf('Representative trace - record %d', recordIndex), ...
                'Color', 'w');
            t = tiledlayout(f, 3, 1, ...
                'TileSpacing', 'compact', ...
                'Padding', 'compact');

            ax1 = nexttile(t,1);
            plot(ax1, x, volume, 'LineWidth', lineWidthEdit.Value);
            ylabel(ax1, volumeYLabel());
            stylePublicationAxes(ax1);

            ax2 = nexttile(t,2);
            plot(ax2, x, pressure, 'LineWidth', lineWidthEdit.Value);
            ylabel(ax2, 'Pressure (mmHg)');
            stylePublicationAxes(ax2);

            ax3 = nexttile(t,3);
            plot(ax3, x, nerve, 'LineWidth', lineWidthEdit.Value);
            ylabel(ax3, nerveYLabel());
            xlabel(ax3, xLabelText);
            stylePublicationAxes(ax3);

            if logical(linkAxesCB.Value)
                linkaxes([ax1 ax2 ax3], 'x');
            end

            if logical(showTitleCB.Value)
                title(t, makeFigureTitle(d, recordIndex, groupKey), 'Interpreter', 'none');
            end

        else
            volume = getVolumeSignal(d, volumeUnitsDrop.Value);
            validateSameLength(volume, pressure, nerve);
            [volume, pressure, nerve] = maybeThin(volume, pressure, nerve);

            f = figure('Name', sprintf('Representative trace - record %d', recordIndex), ...
                'Color', 'w');
            t = tiledlayout(f, 2, 1, ...
                'TileSpacing', 'compact', ...
                'Padding', 'compact');

            ax1 = nexttile(t,1);
            plot(ax1, volume, pressure, 'LineWidth', lineWidthEdit.Value);
            ylabel(ax1, 'Pressure (mmHg)');
            stylePublicationAxes(ax1);

            ax2 = nexttile(t,2);
            plot(ax2, volume, nerve, 'LineWidth', lineWidthEdit.Value);
            ylabel(ax2, nerveYLabel());
            xlabel(ax2, volumeXLabel());
            stylePublicationAxes(ax2);

            if logical(linkAxesCB.Value)
                linkaxes([ax1 ax2], 'x');
            end

            if logical(showTitleCB.Value)
                title(t, makeFigureTitle(d, recordIndex, groupKey), 'Interpreter', 'none');
            end
        end
    end

    function stylePublicationAxes(ax)
        ax.FontName = 'Arial';
        ax.FontSize = 10;
        ax.LineWidth = 1;
        ax.TickDir = 'out';
        ax.Box = ternary(logical(boxAxesCB.Value), 'on', 'off');
        ax.Layer = 'top';
    end

    function p = getPressureSignal(d, mode)
        switch mode
            case 'Raw pressure'
                requireField(d, 'pressure');
                p = d.pressure(:);
            otherwise
                if isfield(d, 'proc') && isstruct(d.proc) && ...
                        isfield(d.proc, 'pressureSmooth') && ~isempty(d.proc.pressureSmooth)
                    p = d.proc.pressureSmooth(:);
                elseif isfield(d, 'pressure') && ~isempty(d.pressure)
                    p = d.pressure(:);
                else
                    error('No pressure signal is available.');
                end
        end
    end

    function y = getNerveSignal(d, mode)
        switch mode
            case 'Raw nerve Hz'
                requireField(d, 'nerveHz');
                y = d.nerveHz(:);

            case 'Processed smooth nerve'
                if isfield(d, 'proc') && isstruct(d.proc) && ...
                        isfield(d.proc, 'nerveSmooth') && ~isempty(d.proc.nerveSmooth)
                    y = d.proc.nerveSmooth(:);
                else
                    error('proc.nerveSmooth is not available for this record.');
                end

            otherwise % 10 s moving mean
                if isfield(d, 'proc') && isstruct(d.proc) && ...
                        isfield(d.proc, 'smoothNerveMovMean10s') && ~isempty(d.proc.smoothNerveMovMean10s)
                    y = d.proc.smoothNerveMovMean10s(:);
                elseif isfield(d, 'proc') && isstruct(d.proc) && ...
                        isfield(d.proc, 'nerveSmooth') && ~isempty(d.proc.nerveSmooth)
                    y = d.proc.nerveSmooth(:);
                elseif isfield(d, 'nerveHz') && ~isempty(d.nerveHz)
                    y = d.nerveHz(:);
                else
                    error('No nerve signal is available.');
                end
        end
    end

    function v = getVolumeSignal(d, unitsMode)
        switch unitsMode
            case '% max volume'
                if isfield(d, 'proc') && isstruct(d.proc) && ...
                        isfield(d.proc, 'volumePercent') && ~isempty(d.proc.volumePercent)
                    v = d.proc.volumePercent(:);
                else
                    error('proc.volumePercent is not available for this record.');
                end
            otherwise
                requireField(d, 'volume');
                v = d.volume(:);
        end
    end

    function txt = volumeYLabel()
        if strcmp(volumeUnitsDrop.Value, '% max volume')
            txt = 'Volume (% max)';
        else
            txt = 'Volume (mL)';
        end
    end

    function txt = volumeXLabel()
        txt = volumeYLabel();
    end

    function txt = nerveYLabel()
        switch nerveDrop.Value
            case 'Raw nerve Hz'
                txt = 'Nerve activity (Hz)';
            case 'Processed smooth nerve'
                txt = 'Nerve activity (Hz)';
            otherwise
                txt = 'Nerve activity (Hz)';
        end
    end

    function ttl = makeFigureTitle(d, recordIndex, groupKey)
        fName = getFileName(d);
        if logical(showGroupCB.Value)
            ttl = sprintf('%s | %s', groupKey, fName);
        else
            ttl = sprintf('Record %d | %s', recordIndex, fName);
        end
    end

    function varargout = maybeThin(varargin)
        varargout = varargin;
        if ~logical(thinCB.Value)
            return
        end

        nPts = numel(varargin{1});
        maxPts = max(500, round(maxPointsEdit.Value));
        if nPts <= maxPts
            return
        end

        idxKeep = unique(round(linspace(1, nPts, maxPts)));
        for q = 1:numel(varargin)
            xq = varargin{q};
            varargout{q} = xq(idxKeep);
        end
    end

    function T = makeTableData(useMask)
        T = table(logical(useMask(:)), (1:n)', groupKeys, dates, fileNames, ...
            'VariableNames', {'Use','Index','GroupKey','Date_FileTag','File'});
    end

    function idx = getSelectedIndices()
        if isempty(tbl.Data)
            idx = [];
            return
        end
        T = tbl.Data;
        if istable(T)
            idx = find(logical(T.Use));
        else
            idx = find(logical(cell2mat(T(:,1))));
        end
    end
end

% =====================================================================
% Local helper functions
% =====================================================================
function T = emptyRecordTable()
T = table(false(0,1), zeros(0,1), strings(0,1), strings(0,1), strings(0,1), ...
    'VariableNames', {'Use','Index','GroupKey','Date_FileTag','File'});
end

function data = identifyCuratedDataset(S)
% Prefer a variable named data, then search for a struct array that resembles
% the canonical curated dataset.
if isfield(S, 'data') && isstruct(S.data) && ~isempty(S.data)
    data = S.data;
    return
end

names = fieldnames(S);
for k = 1:numel(names)
    candidate = S.(names{k});
    if isstruct(candidate) && ~isempty(candidate) && ...
            isfield(candidate, 'time') && ...
            isfield(candidate, 'pressure') && ...
            isfield(candidate, 'nerveHz') && ...
            isfield(candidate, 'volume') && ...
            isfield(candidate, 'meta')
        data = candidate;
        return
    end
end

error('representativeTracePlottingGUI:NoCuratedData', ...
    ['The MAT file does not contain a recognizable curated dataset. ' ...
     'Expected a struct array with time, pressure, nerveHz, volume, and meta fields.']);
end

function validateCuratedDataset(data)
if ~isstruct(data) || isempty(data)
    error('Curated dataset must be a non-empty struct array.');
end
required = {'time','pressure','nerveHz','volume','meta'};
for k = 1:numel(required)
    if ~isfield(data, required{k})
        error('Curated dataset is missing required field "%s".', required{k});
    end
end
end

function requireField(S, fieldName)
if ~isfield(S, fieldName) || isempty(S.(fieldName))
    error('Required field "%s" is missing or empty.', fieldName);
end
end

function validateSameLength(varargin)
n = cellfun(@numel, varargin);
if any(n ~= n(1))
    error('Selected signals do not have matching lengths.');
end
end

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

function out = ternary(tf, a, b)
if tf
    out = a;
else
    out = b;
end
end
