%% ImportAndCurate_Spike2Data.m 
%     Version 1.2
%     Date: September 28, 2026
%     Author: G. Herrera 
%     Co-Author/AI Tool: OpenAI ChatGPT (GPT-5.5)
%     Note: The core workflow was designed by the author and implemented by
%           ChatGPT via prompt engineering. All code was reviewed, modified,
%           and verified by the author.
%           Refer to individual function dependencies for further
%           information
%     Version History:
%           1.2 - September 28, 2026
%                 Added automatic meta.prepID assignment for paired/
%                 repeated-measures experiments. Existing prepID values
%                 are preserved and older records are backfilled when
%                 appending when the ID can be determined from metadata.
%                 Added explicit user designation of reference-condition
%                 records in meta.isReference during curation.
%                 Added Update existing dataset mode for metadata maintenance
%                 without importing or reprocessing raw Spike2 files.
%                 Added preparation-matched reference normalization of the
%                 continuous smoothed nerve signal, stored as
%                 proc.smoothNervePctReferenceMax.
%                 Update Existing Dataset mode now also permits direct
%                 editing/correction of meta.groupKey values.
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
%   5) Assign preparation/reference metadata for paired analyses
%   6) Process pressure, nerve, and volume-normalized fields
%   7) Save the curated data structure
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
% 1) Choose workflow mode
% -------------------------------------------------------------------------
modeChoice = questdlg( ...
    'What would you like to do?', ...
    'Import/Curation Mode', ...
    'Start new data structure', ...
    'Append new files', ...
    'Update existing dataset', ...
    'Start new data structure');

if isempty(modeChoice), error('User cancelled.'); end

isAppend = strcmp(modeChoice,'Append new files');
isUpdate = strcmp(modeChoice,'Update existing dataset');
existingFile = '';

if isAppend || isUpdate
    [matFile,matPath] = uigetfile('*.mat', ...
        'Select existing MAT file containing variable named data');
    if isequal(matFile,0), error('No existing MAT file selected.'); end
    existingFile = fullfile(matPath,matFile);
    S = load(existingFile,'data');
    if ~isfield(S,'data') || ~isstruct(S.data)
        error('Selected MAT file does not contain a struct variable named data.');
    end
    data = S.data(:);
    fprintf('Loaded %d existing records from:\n  %s\n',numel(data),existingFile);
    data = assignPrepIDs(data);   % backfill older datasets
else
    data = struct([]);
    fprintf('Starting a new data structure.\n');
end

if isUpdate
    % Metadata-only maintenance: no raw files are imported or processed.
    newFilePaths = strings(0,1);
    newData = struct([]);
else
    %% 2) Inspect new Spike2 text exports
    infoNew = inspectSpike2Txt();
    if isempty(infoNew), error('No Spike2 text files were selected.'); end
    newFilePaths = string({infoNew.file});

    %% 3) Prevent accidental duplicate imports when appending
    if isAppend && ~isempty(data)
        existingPaths = strings(numel(data),1);
        for i = 1:numel(data)
            if isfield(data(i),'file') && ~isempty(data(i).file)
                existingPaths(i) = string(data(i).file);
            end
        end
        dupMask = ismember(lower(newFilePaths),lower(existingPaths));
        if any(dupMask)
            fprintf('\nDuplicate file(s) already present in data structure:\n');
            disp(newFilePaths(dupMask).');
            keepChoice = questdlg( ...
                'One or more selected files are already in the existing data structure. What should happen?', ...
                'Duplicate files detected','Skip duplicates','Cancel import','Skip duplicates');
            if isempty(keepChoice) || strcmp(keepChoice,'Cancel import')
                error('Import cancelled because duplicate files were detected.');
            end
            newFilePaths = newFilePaths(~dupMask);
        end
    end
    if isempty(newFilePaths)
        error('No new files remain to import after duplicate filtering.');
    end

    fprintf('Preparing to import %d new file(s).\n',numel(newFilePaths));

    %% 4) Load new files into data records
    newData = loadSpike2Batch(newFilePaths);
    newData = newData(:);
    newData = assignPrepIDs(newData);
end

if ~isUpdate
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

end

%% ------------------------------------------------------------------------
% 6) Designate reference-condition records
% -------------------------------------------------------------------------
% Reference identity is explicit metadata and is NOT inferred from group
% names. For each preparation affected by this import, the dialog shows both
% existing and newly imported records. Check every record that belongs to the
% reference/control condition. For example, a preparation may legitimately
% have both a stable reference record and a filling reference record.
%
% Stored as:
%       data(i).meta.isReference = true/false
%
% Downstream filling analyses can then select the reference record using:
%       same meta.prepID + meta.isReference == true + volumeMode == filling

if isUpdate
    data = assignReferenceRecordsExistingUI(data);
else
    [data, newData] = assignReferenceRecordsUI(data,newData,isAppend);
end

if ~isUpdate
%% ------------------------------------------------------------------------
% 7) Process only the new records
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
% 8) Label keyboard-event treatment marks
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




end

%% ------------------------------------------------------------------------
% 9) Append or initialize final curated data structure
% -------------------------------------------------------------------------
if isUpdate
    % Existing data were edited in place.
elseif isAppend
    data = [data(:); newData(:)];
else
    data = newData(:);
end

%% ------------------------------------------------------------------------
% 10) Calculate nerve activity as percent of matched reference maximum
% -------------------------------------------------------------------------
% For each preparation:
%   1) Find exactly one reference FILLING record:
%          same meta.prepID
%          meta.isReference == true
%          meta.volumeMode == 'filling'
%   2) Calculate the denominator as the maximum of that reference record's
%      10-second moving-mean smoothed nerve signal.
%   3) Normalize every sample of proc.nerveSmooth in every record belonging
%      to that preparation:
%
%      smoothNervePctReferenceMax =
%          100 * proc.nerveSmooth / referenceMax10sMovMean
%
% The numerator is the continuous smoothed nerve signal, NOT the 10-second
% moving mean. Therefore values above 100% are valid.
%
% This step is run for Start New, Append, and Update Existing workflows.

[data, refNormSummary] = calculateReferenceNormalizedNerve(data);

%% ------------------------------------------------------------------------
% 11) Curation summary
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

allPrepIDs = strings(numel(data), 1);
for i = 1:numel(data)
    if isfield(data(i), 'meta') && isfield(data(i).meta, 'prepID')
        allPrepIDs(i) = string(data(i).meta.prepID);
    end
end

missingPrep = strlength(allPrepIDs) == 0;
if any(missingPrep)
    warning('%d record(s) do not have meta.prepID. These records cannot be used for paired/reference normalization until a prepID is assigned.', sum(missingPrep));
else
    fprintf('Preparations identified: %d\n', numel(unique(allPrepIDs, 'stable')));
end

allReference = false(numel(data),1);
for i = 1:numel(data)
    if isfield(data(i),'meta') && isfield(data(i).meta,'isReference')
        allReference(i) = logical(data(i).meta.isReference);
    end
end
fprintf('Reference-condition records designated: %d\n', sum(allReference));

fprintf('Reference-normalized nerve signal calculated for %d record(s) across %d preparation(s).\n', ...
    refNormSummary.nRecordsCalculated, refNormSummary.nPrepsCalculated);
if refNormSummary.nPrepsSkipped > 0
    fprintf('Reference normalization skipped for %d preparation(s); see warnings above.\n', ...
        refNormSummary.nPrepsSkipped);
end

%% ------------------------------------------------------------------------
% 12) Save curated data structure
% -------------------------------------------------------------------------
defaultName = 'CuratedAfferentNerveData.mat';

if (isAppend || isUpdate) && ~isempty(existingFile)
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
    importCurationInfo.metadataUpdateOnly = isUpdate;

    save(saveFullPath, 'data', 'importCurationInfo', '-v7.3');
    fprintf('\nSaved curated data structure to:\n  %s\n', saveFullPath);
    fprintf('\nImport Complete.\n');

    % Successful save: Clear all variables from workspace.
    clearvars;

end




%% Helper functions:

function [data, summary] = calculateReferenceNormalizedNerve(data)
%CALCULATEREFERENCENORMALIZEDNERVE Normalize nerveSmooth to matched reference.
%
% For each prepID, exactly one reference filling record is required. The
% denominator is max(proc.smoothNerveMovMean10s) from that record. Every
% sample of proc.nerveSmooth in every record from the same preparation is
% divided by that denominator and multiplied by 100.
%
% Outputs stored in each successfully normalized record:
%   proc.smoothNervePctReferenceMax
%   proc.smoothNerveReferenceMax10sMovMean   (scalar denominator)
%
% Existing values are cleared first so stale normalization cannot survive a
% metadata change that makes a preparation invalid.

    summary = struct( ...
        'nPrepsCalculated', 0, ...
        'nPrepsSkipped', 0, ...
        'nRecordsCalculated', 0);

    if isempty(data)
        return
    end

    % Clear prior values first. This is important in Update mode if the user
    % changes which record is designated as the reference.
    for i = 1:numel(data)
        if ~isfield(data(i),'proc') || ~isstruct(data(i).proc)
            data(i).proc = struct();
        end
        data(i).proc.smoothNervePctReferenceMax = [];
        data(i).proc.smoothNerveReferenceMax10sMovMean = [];
    end

    prepIDs = strings(numel(data),1);
    for i = 1:numel(data)
        if isfield(data(i),'meta') && isstruct(data(i).meta) && ...
                isfield(data(i).meta,'prepID')
            prepIDs(i) = strtrim(string(data(i).meta.prepID));
        end
    end

    validPrepIDs = unique(prepIDs(strlength(prepIDs) > 0),'stable');

    for p = 1:numel(validPrepIDs)
        thisPrep = validPrepIDs(p);
        prepMask = prepIDs == thisPrep;
        prepIdx = find(prepMask);

        refFillIdx = [];
        for k = prepIdx(:).'
            isRef = false;
            volMode = "";

            if isfield(data(k),'meta') && isstruct(data(k).meta)
                if isfield(data(k).meta,'isReference') && ...
                        ~isempty(data(k).meta.isReference)
                    isRef = logical(data(k).meta.isReference);
                end
                if isfield(data(k).meta,'volumeMode')
                    volMode = strtrim(string(data(k).meta.volumeMode));
                end
            end

            if isRef && strcmpi(volMode,'filling')
                refFillIdx(end+1) = k; %#ok<AGROW>
            end
        end

        if isempty(refFillIdx)
            warning(['Reference normalization skipped for prepID "%s": ' ...
                'no record is marked isReference=true with volumeMode="filling".'], ...
                thisPrep);
            summary.nPrepsSkipped = summary.nPrepsSkipped + 1;
            continue
        elseif numel(refFillIdx) > 1
            warning(['Reference normalization skipped for prepID "%s": ' ...
                '%d reference filling records were found; exactly one is required.'], ...
                thisPrep, numel(refFillIdx));
            summary.nPrepsSkipped = summary.nPrepsSkipped + 1;
            continue
        end

        r = refFillIdx(1);

        if ~isfield(data(r),'proc') || ...
                ~isfield(data(r).proc,'smoothNerveMovMean10s') || ...
                isempty(data(r).proc.smoothNerveMovMean10s)
            warning(['Reference normalization skipped for prepID "%s": ' ...
                'the reference filling record has no proc.smoothNerveMovMean10s.'], ...
                thisPrep);
            summary.nPrepsSkipped = summary.nPrepsSkipped + 1;
            continue
        end

        refMov = data(r).proc.smoothNerveMovMean10s;
        referenceMax = max(refMov,[],'omitnan');

        if isempty(referenceMax) || ~isscalar(referenceMax) || ...
                ~isfinite(referenceMax) || referenceMax <= 0
            warning(['Reference normalization skipped for prepID "%s": ' ...
                'reference 10-second moving-mean maximum is invalid (%g).'], ...
                thisPrep, referenceMax);
            summary.nPrepsSkipped = summary.nPrepsSkipped + 1;
            continue
        end

        nThisPrep = 0;
        for k = prepIdx(:).'
            if ~isfield(data(k),'proc') || ...
                    ~isfield(data(k).proc,'nerveSmooth') || ...
                    isempty(data(k).proc.nerveSmooth)
                continue
            end

            data(k).proc.smoothNervePctReferenceMax = ...
                100 .* data(k).proc.nerveSmooth ./ referenceMax;
            data(k).proc.smoothNerveReferenceMax10sMovMean = referenceMax;
            nThisPrep = nThisPrep + 1;
        end

        if nThisPrep == 0
            warning(['Reference denominator was found for prepID "%s", but no ' ...
                'records in that preparation contained proc.nerveSmooth.'], thisPrep);
            summary.nPrepsSkipped = summary.nPrepsSkipped + 1;
        else
            summary.nPrepsCalculated = summary.nPrepsCalculated + 1;
            summary.nRecordsCalculated = summary.nRecordsCalculated + nThisPrep;
        end
    end

    % Explicit warning for records that cannot be associated with a prep.
    missingPrep = find(strlength(prepIDs) == 0);
    if ~isempty(missingPrep)
        warning(['Reference normalization could not be calculated for %d record(s) ' ...
            'because meta.prepID is missing.'], numel(missingPrep));
    end
end

function data = assignPrepIDs(data)
%ASSIGNPREPIDS Populate data(i).meta.prepID from existing file metadata.
%
% The canonical Spike2 file tag (for example, 260917001) identifies the
% experimental preparation. All records generated from that preparation
% receive the same prepID. Existing non-empty prepID values are preserved.

    for i = 1:numel(data)
        if ~isfield(data(i), 'meta') || ~isstruct(data(i).meta)
            data(i).meta = struct();
        end

        % Preserve an explicitly assigned preparation ID.
        if isfield(data(i).meta, 'prepID') && ...
                strlength(strtrim(string(data(i).meta.prepID))) > 0
            data(i).meta.prepID = string(strtrim(string(data(i).meta.prepID)));
            continue
        end

        prepID = "";

        % Preferred source: first parsed file tag from loadSpike2Batch.
        if isfield(data(i).meta, 'fileTags') && ~isempty(data(i).meta.fileTags)
            tags = string(data(i).meta.fileTags);
            if ~isempty(tags)
                prepID = strtrim(tags(1));
            end
        end

        % Conservative fallback: extract a leading 9-digit Spike2 tag from
        % fileBase/file name. Do not invent an ID if no such tag is found.
        if strlength(prepID) == 0
            sourceText = "";
            if isfield(data(i).meta, 'fileBase') && ...
                    strlength(string(data(i).meta.fileBase)) > 0
                sourceText = string(data(i).meta.fileBase);
            elseif isfield(data(i), 'file') && ~isempty(data(i).file)
                [~, nm, ~] = fileparts(char(data(i).file));
                sourceText = string(nm);
            end

            if strlength(sourceText) > 0
                tok = regexp(char(sourceText), '^(\d{9})', 'tokens', 'once');
                if ~isempty(tok)
                    prepID = string(tok{1});
                end
            end
        end

        data(i).meta.prepID = prepID;

        if strlength(prepID) == 0
            warning('Could not determine meta.prepID for record %d: %s', ...
                i, getRecordLabel(data(i), i));
        end
    end
end

function data = assignReferenceRecordsExistingUI(data)
% Review/reference-designate all records in an existing curated dataset.
    for i = 1:numel(data)
        if ~isfield(data(i),'meta') || ~isstruct(data(i).meta)
            data(i).meta = struct();
        end
        if ~isfield(data(i).meta,'isReference') || isempty(data(i).meta.isReference)
            data(i).meta.isReference = false;
        else
            data(i).meta.isReference = logical(data(i).meta.isReference);
        end
    end

    n = numel(data);
    Reference = false(n,1); PrepID = strings(n,1);
    Group = strings(n,1); VolumeMode = strings(n,1);
    File = strings(n,1); RecordIndex = (1:n).';

    for i = 1:n
        Reference(i) = data(i).meta.isReference;
        PrepID(i) = getMetaString(data(i),'prepID');
        Group(i) = getMetaString(data(i),'groupKey');
        VolumeMode(i) = getMetaString(data(i),'volumeMode');
        File(i) = string(getRecordLabel(data(i),i));
    end

    T = table(Reference,PrepID,Group,VolumeMode,File,RecordIndex);
    fig = uifigure('Name','Update Curated Dataset Metadata', ...
        'Position',[120 80 1050 680],'WindowStyle','modal');
    gl = uigridlayout(fig,[3 1]);
    gl.RowHeight = {90,'1x',44}; gl.Padding = [12 12 12 12];

    msg = uilabel(gl,'WordWrap','on','Text', ...
        ['Review all records. Use Reference? to designate records belonging to the ' ...
         'reference/control condition. Edit Group to correct or standardize meta.groupKey ' ...
         'designators (for example, DILT versus Dilt). Reference status is explicit metadata ' ...
         'and is not inferred from the group name.']);
    msg.Layout.Row = 1;

    tbl = uitable(gl,'Data',T);
    tbl.Layout.Row = 2;
    % Reference? and Group are editable; other columns remain read-only.
    tbl.ColumnEditable = [true false true false false false];
    tbl.ColumnName = {'Reference?','PrepID','Group','Volume mode','File','Record index'};
    tbl.ColumnWidth = {85,120,200,100,410,80};

    bg = uigridlayout(gl,[1 3]); bg.Layout.Row = 3;
    bg.ColumnWidth = {'1x',110,110};
    uilabel(bg,'Text','');
    uibutton(bg,'Text','Cancel','ButtonPushedFcn',@cancelDialog);
    uibutton(bg,'Text','OK','ButtonPushedFcn',@acceptDialog);

    accepted = false; uiwait(fig);
    if ~accepted, error('Metadata update was cancelled.'); end

    function acceptDialog(~,~)
        Tout = tbl.Data;
        for r = 1:height(Tout)
            ii = Tout.RecordIndex(r);
            data(ii).meta.isReference = logical(Tout.Reference(r));

            % Save the edited groupKey, trimming only accidental whitespace.
            newGroup = strtrim(string(Tout.Group(r)));
            if ismissing(newGroup)
                newGroup = "";
            end
            data(ii).meta.groupKey = char(newGroup);
        end
        accepted = true; uiresume(fig); delete(fig);
    end
    function cancelDialog(~,~)
        accepted = false; uiresume(fig); delete(fig);
    end
end

function [existingData, newData] = assignReferenceRecordsUI(existingData, newData, isAppend)
%ASSIGNREFERENCERECORDSUI Explicitly designate reference-condition records.
%
% Reference status is never inferred from groupKey text. Missing
% meta.isReference fields default to false. When appending, the dialog shows
% existing records whose prepID matches a newly imported preparation together
% with the new records, so reference status can be reviewed in context.

    % Ensure the field exists everywhere without overwriting prior choices.
    for i = 1:numel(existingData)
        if ~isfield(existingData(i),'meta') || ~isstruct(existingData(i).meta)
            existingData(i).meta = struct();
        end
        if ~isfield(existingData(i).meta,'isReference') || isempty(existingData(i).meta.isReference)
            existingData(i).meta.isReference = false;
        else
            existingData(i).meta.isReference = logical(existingData(i).meta.isReference);
        end
    end

    for i = 1:numel(newData)
        if ~isfield(newData(i),'meta') || ~isstruct(newData(i).meta)
            newData(i).meta = struct();
        end
        if ~isfield(newData(i).meta,'isReference') || isempty(newData(i).meta.isReference)
            newData(i).meta.isReference = false;
        else
            newData(i).meta.isReference = logical(newData(i).meta.isReference);
        end
    end

    newPrepIDs = strings(numel(newData),1);
    for i = 1:numel(newData)
        if isfield(newData(i).meta,'prepID')
            newPrepIDs(i) = string(newData(i).meta.prepID);
        end
    end
    affectedPrepIDs = unique(newPrepIDs(strlength(newPrepIDs)>0),'stable');

    % Build rows: existing records only for affected preparations, plus all
    % newly imported records.
    src = strings(0,1);
    idx = zeros(0,1);
    isRef = false(0,1);
    prepID = strings(0,1);
    groupKey = strings(0,1);
    volumeMode = strings(0,1);
    fileLabel = strings(0,1);

    if isAppend && ~isempty(existingData)
        for i = 1:numel(existingData)
            p = "";
            if isfield(existingData(i).meta,'prepID')
                p = string(existingData(i).meta.prepID);
            end
            if any(p == affectedPrepIDs)
                src(end+1,1) = "Existing"; %#ok<AGROW>
                idx(end+1,1) = i; %#ok<AGROW>
                isRef(end+1,1) = logical(existingData(i).meta.isReference); %#ok<AGROW>
                prepID(end+1,1) = p; %#ok<AGROW>
                groupKey(end+1,1) = getMetaString(existingData(i),'groupKey'); %#ok<AGROW>
                volumeMode(end+1,1) = getMetaString(existingData(i),'volumeMode'); %#ok<AGROW>
                fileLabel(end+1,1) = string(getRecordLabel(existingData(i),i)); %#ok<AGROW>
            end
        end
    end

    for i = 1:numel(newData)
        src(end+1,1) = "New"; %#ok<AGROW>
        idx(end+1,1) = i; %#ok<AGROW>
        isRef(end+1,1) = logical(newData(i).meta.isReference); %#ok<AGROW>
        prepID(end+1,1) = getMetaString(newData(i),'prepID'); %#ok<AGROW>
        groupKey(end+1,1) = getMetaString(newData(i),'groupKey'); %#ok<AGROW>
        volumeMode(end+1,1) = getMetaString(newData(i),'volumeMode'); %#ok<AGROW>
        fileLabel(end+1,1) = string(getRecordLabel(newData(i),i)); %#ok<AGROW>
    end

    if isempty(idx)
        return
    end

    T = table(isRef, prepID, groupKey, volumeMode, src, fileLabel, idx, ...
        'VariableNames', {'Reference','PrepID','Group','VolumeMode','Source','File','RecordIndex'});

    fig = uifigure( ...
        'Name','Designate Reference-Condition Records', ...
        'Position',[120 100 1050 620], ...
        'WindowStyle','modal');

    gl = uigridlayout(fig,[3 1]);
    gl.RowHeight = {82,'1x',44};
    gl.Padding = [12 12 12 12];
    gl.RowSpacing = 8;

    msg = uilabel(gl, ...
        'Text', ['Check every record that belongs to the reference/control condition. ' ...
                 'Reference identity is stored explicitly and is not inferred from the group name. ' ...
                 'A preparation may have more than one reference record when they represent different record types ' ...
                 '(for example, stable and filling).'], ...
        'WordWrap','on');
    msg.Layout.Row = 1;

    tbl = uitable(gl,'Data',T);
    tbl.Layout.Row = 2;
    tbl.ColumnEditable = [true false false false false false false];
    tbl.ColumnName = {'Reference?','PrepID','Group','Volume mode','Source','File','Record index'};
    tbl.ColumnWidth = {85,110,180,100,75,360,80};

    bg = uigridlayout(gl,[1 3]);
    bg.Layout.Row = 3;
    bg.ColumnWidth = {'1x',110,110};
    uilabel(bg,'Text','');
    uibutton(bg,'Text','Cancel','ButtonPushedFcn',@cancelDialog);
    uibutton(bg,'Text','OK','ButtonPushedFcn',@acceptDialog);

    accepted = false;
    uiwait(fig);

    if ~accepted
        error('Reference-record designation was cancelled.');
    end

    function acceptDialog(~,~)
        Tout = tbl.Data;

        for r = 1:height(Tout)
            tf = logical(Tout.Reference(r));
            if Tout.Source(r) == "Existing"
                existingData(Tout.RecordIndex(r)).meta.isReference = tf;
            else
                newData(Tout.RecordIndex(r)).meta.isReference = tf;
            end
        end

        accepted = true;
        uiresume(fig);
        delete(fig);
    end

    function cancelDialog(~,~)
        accepted = false;
        uiresume(fig);
        delete(fig);
    end
end

function s = getMetaString(d, fieldName)
%GETMETASTRING Return a metadata field as a scalar string, or "".
    s = "";
    if isfield(d,'meta') && isstruct(d.meta) && isfield(d.meta,fieldName)
        v = string(d.meta.(fieldName));
        if ~isempty(v)
            s = v(1);
        end
    end
end

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
