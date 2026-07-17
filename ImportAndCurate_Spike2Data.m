%% ImportAndCurate_Spike2Data.m 
%     Version 1.1
%     Date: July 10, 2026
%     Author: G. Herrera 
%     Co-Author/AI Tool: OpenAI ChatGPT (GPT-5.5)
%     Note: The core workflow was designed by the author and implemented by
%           ChatGPT via prompt engineering. All code was reviewed, modified,
%           and verified by the author.
%           Refer to individual function dependencies for further
%           information
%     Version History:
%           1.1 - July 10, 2026
%                 Added user-defined annotation of keyboard events for
%                 indicating treatment periods in an imported txt data file.
%                 Added new block 7 (label keyboard-event treatment marks).
%                 Updated numbering for following blocks.  Added new helper
%                 functions (getRecordLabel, promptTreatmentEventLabels)
%                 to end of script.
%           1.0 - July 8, 2026
%                 Initial Release
%
% Import and Curate Spike2 Text Exports
% Purpose:
%   Build or append to the canonical afferent nerve data structure from
%   Spike2 Spreadsheet Text exports.
%
% This script is intentionally limited to data import/curation:
%   1) Start a new data structure OR append to an existing one
%   2) Inspect selected Spike2 text files
%   3) Load selected files into MATLAB data records
%   4) Assign treatment/group labels into data(i).meta.groupKey
%   5) Process pressure, nerve, and volume-normalized fields
%   6) Save the curated data structure
%
% This script does NOT run:
%   - TPE analysis
%   - fixed-width binning
%   - equal-N binning
%   - final analysis plotting
%
% Important convention:
%   Group/treatment identity is stored inside each record:
%       data(i).meta.groupKey
%   Do not use or save a separate groupMap for downstream analysis.

clear; clc;

%% ------------------------------------------------------------------------
% 0) Add analysis code folder to MATLAB path
% -------------------------------------------------------------------------
% If this script is in the same folder as the analysis functions, this is enough.
% Otherwise, replace pwd with the folder containing the .m files.
addpath(pwd);

%% ------------------------------------------------------------------------
% 1) Choose workflow mode: new data structure or append to existing data
% -------------------------------------------------------------------------
modeChoice = questdlg( ...
    'What would you like to do?', ...
    'Import/Curation Mode', ...
    'Start new data structure', ...
    'Append to existing data structure', ...
    'Start new data structure');

if isempty(modeChoice)
    error('User cancelled.');
end

isAppend = strcmp(modeChoice, 'Append to existing data structure');

if isAppend
    [matFile, matPath] = uigetfile('*.mat', 'Select existing MAT file containing variable named data');
    if isequal(matFile, 0)
        error('No existing MAT file selected.');
    end

    existingFile = fullfile(matPath, matFile);
    S = load(existingFile, 'data');

    if ~isfield(S, 'data') || ~isstruct(S.data)
        error('Selected MAT file does not contain a struct variable named data.');
    end

    data = S.data(:);
    fprintf('Loaded %d existing records from:\n  %s\n', numel(data), existingFile);
else
    data = struct([]);
    existingFile = '';
    fprintf('Starting a new data structure.\n');
end

%% ------------------------------------------------------------------------
% 2) Inspect new Spike2 text exports
% -------------------------------------------------------------------------
% This opens a file picker and reports the columns selected for time,
% pressure, and nerve Hz. It is read-only and does not load full data.
infoNew = inspectSpike2Txt();

if isempty(infoNew)
    error('No Spike2 text files were selected.');
end

newFilePaths = string({infoNew.file});

%% ------------------------------------------------------------------------
% 3) Prevent accidental duplicate imports when appending
% -------------------------------------------------------------------------
if isAppend && ~isempty(data)
    existingPaths = strings(numel(data), 1);
    for i = 1:numel(data)
        if isfield(data(i), 'file') && ~isempty(data(i).file)
            existingPaths(i) = string(data(i).file);
        else
            existingPaths(i) = "";
        end
    end

    dupMask = ismember(lower(newFilePaths), lower(existingPaths));

    if any(dupMask)
        fprintf('\nDuplicate file(s) already present in data structure:\n');
        disp(newFilePaths(dupMask).');

        keepChoice = questdlg( ...
            'One or more selected files are already in the existing data structure. What should happen?', ...
            'Duplicate files detected', ...
            'Skip duplicates', ...
            'Cancel import', ...
            'Skip duplicates');

        if isempty(keepChoice) || strcmp(keepChoice, 'Cancel import')
            error('Import cancelled because duplicate files were detected.');
        end

        newFilePaths = newFilePaths(~dupMask);
    end
end

if isempty(newFilePaths)
    error('No new files remain to import after duplicate filtering.');
end

fprintf('Preparing to import %d new file(s).\n', numel(newFilePaths));

%% ------------------------------------------------------------------------
% 4) Load new files into data records
% -------------------------------------------------------------------------
% loadSpike2Batch imports the selected Spike2 text files, chooses pressure
% and nerve Hz channels, computes volume from filling rate and initial volume,
% and stores file/channel metadata in data(i).meta.
%
% You will be prompted for filling rate and initial volume.
newData = loadSpike2Batch(newFilePaths);
newData = newData(:);

%% ------------------------------------------------------------------------
% 5) Assign or confirm treatment/group labels for the new records
% -------------------------------------------------------------------------
% assignExperimentalGroupsUI should store the user-defined group name in:
%       newData(i).meta.groupKey
%
% If your local copy still returns [data, groupMap], update that function or
% ignore the second output. This workflow intentionally does not use groupMap.
newData = assignExperimentalGroupsUI(newData);

% Safety check: every new record must have meta.groupKey.
for i = 1:numel(newData)
    if ~isfield(newData(i), 'meta') || ~isstruct(newData(i).meta)
        newData(i).meta = struct();
    end

    missingGroupKey = ~isfield(newData(i).meta, 'groupKey') || ...
                      strlength(string(newData(i).meta.groupKey)) == 0;

    if missingGroupKey
        if isfield(newData(i).meta, 'conditionKey') && strlength(string(newData(i).meta.conditionKey)) > 0
            newData(i).meta.groupKey = string(newData(i).meta.conditionKey);
            warning('New record %d was missing meta.groupKey. Used meta.conditionKey instead.', i);
        else
            answer = inputdlg( ...
                sprintf('Enter group/treatment label for new record %d:\n%s', i, newData(i).file), ...
                'Missing group label', ...
                [1 80], ...
                {'Ungrouped'});

            if isempty(answer)
                error('Group label entry cancelled.');
            end

            newData(i).meta.groupKey = string(strtrim(answer{1}));
        end
    end
end

%% ------------------------------------------------------------------------
% 6) Process only the new records
% -------------------------------------------------------------------------
% processSpike2Batch adds data(i).proc fields, including:
%   proc.pressureSmooth
%   proc.pressureBaseline
%   proc.pressurePeak
%   proc.nerveSmooth
%   proc.nerveBaseline
%   proc.nervePeak
%   proc.volumeMax_mL
%   proc.volumePercent
%   proc.smoothNerveMovMean10s
%   proc.smoothNervePctMax

newData = processSpike2Batch(newData);

% Optional custom processing parameters:
% procOpts = struct('medWindow', 75, ...
%                   'meanWindow', 250, ...
%                   'lambda', 5e10, ...
%                   'sym', 0.01, ...
%                   'normalizeVolume', true);
% newData = processSpike2Batch(newData, procOpts);

%% ------------------------------------------------------------------------
% 7) Label keyboard-event treatment marks
% -------------------------------------------------------------------------
% Spike2 Keyboard marks were imported by loadSpike2Batch and collapsed into
% event clusters. Ask the user to assign a treatment label to each event.
%
% Labels are stored in:
%   newData(i).events.treatment.times
%   newData(i).events.treatment.labels
%   newData(i).events.treatment.source
%
% This format is used by the sparkline and treatment-overlay plotting tools.

for i = 1:numel(newData)

    % Make sure the events structure exists.
    if ~isfield(newData(i), 'events') || ~isstruct(newData(i).events)
        newData(i).events = struct();
    end

    % Retrieve collapsed keyboard-event times.
    if isfield(newData(i).events, 'keyboardTimes') && ...
            ~isempty(newData(i).events.keyboardTimes)

        eventTimes = newData(i).events.keyboardTimes(:);
        nEvents = numel(eventTimes);

        % Build one prompt for each keyboard-event cluster.
        prompts = cell(nEvents, 1);
        defaults = cell(nEvents, 1);

        for k = 1:nEvents
            prompts{k} = sprintf( ...
                'Label for keyboard event %d at %.2f s:', ...
                k, eventTimes(k));

            defaults{k} = sprintf('Treatment %d', k);
        end

        fileLabel = getRecordLabel(newData(i), i);

        answers = promptTreatmentEventLabels( ...
            newData(i), ...
            eventTimes, ...
            defaults);

        if isempty(answers)
            error('Treatment-event labeling was cancelled for record %d.', i);
        end

        labels = string(strtrim(answers(:)));

        % Do not allow empty treatment labels.
        emptyLabel = strlength(labels) == 0;
        if any(emptyLabel)
            labels(emptyLabel) = "Unlabeled event";
        end

        % Save in the standard treatment-event structure.
        newData(i).events.treatment = struct();
        newData(i).events.treatment.times = eventTimes;
        newData(i).events.treatment.labels = labels;
        newData(i).events.treatment.source = 'keyboard';

        % Preserve links back to the imported keyboard events.
        if isfield(newData(i).events, 'keyboardIdx')
            newData(i).events.treatment.keyboardIdx = ...
                newData(i).events.keyboardIdx(:);
        end

        if isfield(newData(i).events, 'keyboardClusterGap_s')
            newData(i).events.treatment.keyboardClusterGap_s = ...
                newData(i).events.keyboardClusterGap_s;
        end

        fprintf('Labeled %d keyboard treatment event(s) for record %d.\n', ...
            nEvents, i);

    else
        % Record explicitly that no keyboard treatment marks were present.
        newData(i).events.treatment = struct( ...
            'times', zeros(0,1), ...
            'labels', strings(0,1), ...
            'source', 'keyboard');

        fprintf('No keyboard treatment events found for record %d.\n', i);
    end
end




%% ------------------------------------------------------------------------
% 8) Append or initialize final curated data structure
% -------------------------------------------------------------------------
if isAppend
    data = [data(:); newData(:)];
else
    data = newData(:);
end

%% ------------------------------------------------------------------------
% 9) Curation summary
% -------------------------------------------------------------------------
fprintf('\nCurated data structure now contains %d total record(s).\n', numel(data));

allGroups = strings(numel(data), 1);
for i = 1:numel(data)
    if isfield(data(i), 'meta') && isfield(data(i).meta, 'groupKey')
        allGroups(i) = string(data(i).meta.groupKey);
    else
        allGroups(i) = "<missing groupKey>";
    end
end

uniqueGroups = unique(allGroups, 'stable');
fprintf('\nGroup counts:\n');
for g = 1:numel(uniqueGroups)
    fprintf('  %s: %d\n', uniqueGroups(g), sum(allGroups == uniqueGroups(g)));
end

%% ------------------------------------------------------------------------
% 10) Save curated data structure
% -------------------------------------------------------------------------
defaultName = 'CuratedAfferentNerveData.mat';

if isAppend && ~isempty(existingFile)
    [saveFile, savePath] = uiputfile('*.mat', 'Save updated curated data structure as', existingFile);
else
    [saveFile, savePath] = uiputfile('*.mat', 'Save curated data structure as', defaultName);
end

if isequal(saveFile, 0)
    warning('Save cancelled. The curated data structure remains in the workspace as variable data.');
else
    saveFullPath = fullfile(savePath, saveFile);

    importCurationInfo = struct();
    importCurationInfo.savedOn = datetime('now');
    importCurationInfo.mode = modeChoice;
    importCurationInfo.nTotalRecords = numel(data);
    importCurationInfo.nNewRecords = numel(newData);
    importCurationInfo.newFilePaths = newFilePaths(:);

    save(saveFullPath, 'data', 'importCurationInfo', '-v7.3');
    fprintf('\nSaved curated data structure to:\n  %s\n', saveFullPath);
    fprintf('\nImport Complete.\n');

    % Successful save: Clear all variables from workspace.
    clearvars;

end




%% Helper functions:

function lbl = getRecordLabel(d, recordIndex)
% Return a concise file label for treatment-event dialogs.

    if isfield(d, 'meta') && isfield(d.meta, 'fileBase') && ...
            strlength(string(d.meta.fileBase)) > 0
        lbl = char(string(d.meta.fileBase));

    elseif isfield(d, 'file') && ~isempty(d.file)
        [~, name, ext] = fileparts(char(d.file));
        lbl = [name ext];

    else
        lbl = sprintf('Record %d', recordIndex);
    end
end

function answers = promptTreatmentEventLabels(d, eventTimes, defaults)
% Custom dialog for labeling keyboard treatment events.
% Displays the full file path in a wrapped text area.

    nEvents = numel(eventTimes);
    answers = [];

    if isfield(d, 'file') && ~isempty(d.file)
        fullFileName = char(d.file);
    elseif isfield(d, 'meta') && isfield(d.meta, 'fileBase')
        fullFileName = char(string(d.meta.fileBase));
    else
        fullFileName = 'Unknown file';
    end

    figHeight = min(780, 210 + 52*nEvents);
    figWidth  = 760;

    fig = uifigure( ...
        'Name', 'Label Keyboard Treatment Events', ...
        'Position', [200 120 figWidth figHeight], ...
        'WindowStyle', 'modal');

    gl = uigridlayout(fig, [4 1]);
    gl.RowHeight = {28, 70, '1x', 42};
    gl.Padding = [12 12 12 12];
    gl.RowSpacing = 8;

    titleLabel = uilabel(gl, ...
        'Text', 'File being labeled:', ...
        'FontWeight', 'bold');
    titleLabel.Layout.Row = 1;

    fileBox = uitextarea(gl, ...
        'Value', {fullFileName}, ...
        'Editable', 'off', ...
        'WordWrap', 'on');
    fileBox.Layout.Row = 2;

    scrollPanel = uipanel(gl, ...
        'Scrollable', 'on', ...
        'BorderType', 'none');
    scrollPanel.Layout.Row = 3;

    eventGrid = uigridlayout(scrollPanel, [nEvents 2]);
    eventGrid.ColumnWidth = {220, '1x'};
    eventGrid.RowHeight = repmat({34}, 1, nEvents);
    eventGrid.Padding = [4 4 4 4];
    eventGrid.RowSpacing = 6;

    fields = gobjects(nEvents,1);

    for k = 1:nEvents
        uilabel(eventGrid, ...
            'Text', sprintf('Event %d at %.2f s', k, eventTimes(k)));

        fields(k) = uieditfield(eventGrid, ...
            'text', ...
            'Value', defaults{k});
    end

    buttonGrid = uigridlayout(gl, [1 3]);
    buttonGrid.Layout.Row = 4;
    buttonGrid.ColumnWidth = {'1x', 110, 110};

    uilabel(buttonGrid, 'Text', '');

    uibutton(buttonGrid, ...
        'Text', 'Cancel', ...
        'ButtonPushedFcn', @(~,~)cancelDialog());

    uibutton(buttonGrid, ...
        'Text', 'OK', ...
        'ButtonPushedFcn', @(~,~)acceptDialog());

    uiwait(fig);

    function acceptDialog()
        answers = cell(nEvents,1);

        for j = 1:nEvents
            answers{j} = strtrim(fields(j).Value);
        end

        uiresume(fig);
        delete(fig);
    end

    function cancelDialog()
        answers = [];
        uiresume(fig);
        delete(fig);
    end
end

%% End of import/curation script
