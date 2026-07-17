function [data, groupMap] = assignExperimentalGroupsUI(data, opts)
% assignExperimentalGroupsUI
% UI to map detected condition keys -> user-defined group labels.
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
% Writes: data(i).meta.groupKey

    if nargin < 2 || isempty(opts), opts = struct(); end
    opts = setDefault(opts,'title','Assign Experimental Groups');
    opts = setDefault(opts,'defaultGroupMode','sameAsCondition'); % or 'blank'
    opts = setDefault(opts,'saveMapPath','');

    if ~isstruct(data) || isempty(data)
        error('Input "data" must be a non-empty struct array.');
    end

    % ---- Extract per-record fields safely ----
    n = numel(data);
    recID   = strings(n,1);
    fileStr = strings(n,1);
    condKey = strings(n,1);

    for i = 1:n
        recID(i)   = string(getRecID(data(i), i));
        fileStr(i) = string(getFilePath(data(i)));
        condKey(i) = string(getConditionKey(data(i)));
        if strlength(condKey(i)) == 0
            condKey(i) = "Unlabeled";
        end
    end

    % Default group assignments
    switch lower(string(opts.defaultGroupMode))
        case "blank"
            groupAssign = repmat("", n, 1);
        otherwise
            groupAssign = condKey;
    end

    % Pre-load existing groupKey if present
    for i = 1:n
        if isfield(data(i),'meta') && isfield(data(i).meta,'groupKey') && ~isempty(data(i).meta.groupKey)
            groupAssign(i) = string(data(i).meta.groupKey);
        end
    end

    % Table shown in UI
    T = table(recID, fileStr, condKey, groupAssign, ...
        'VariableNames', {'RecID','File','DetectedCondition','Group'});

    uConds = unique(condKey, 'stable');

    % ---- UI ----
    fig = uifigure('Name', opts.title, 'Color','w', 'Position', [100 100 1200 650]);

    gl = uigridlayout(fig, [2 1]);
    gl.RowHeight = {'1x', 140};
    gl.Padding = [10 10 10 10];
    gl.RowSpacing = 10;

    uit = uitable(gl);
    uit.Data = T;
    uit.ColumnEditable = [false false false true];
    uit.ColumnName = {'RecID','File','DetectedCondition','Group'};
    uit.ColumnWidth = {120, 520, 260, 220};
    uit.RowName = [];
    uit.Layout.Row = 1;

    pnl = uipanel(gl, 'Title','Bulk assignment (optional)', 'BackgroundColor','w');
    pnl.Layout.Row = 2;

    cg = uigridlayout(pnl, [3 6]);
    cg.RowHeight = {28, 28, '1x'};
    cg.ColumnWidth = {170, '1x', 140, '1x', 140, 140};
    cg.Padding = [10 10 10 10];
    cg.RowSpacing = 8;
    cg.ColumnSpacing = 10;

    lblCond = uilabel(cg, 'Text','Detected condition:', 'FontWeight','bold');
    lblCond.Layout.Row = 1; lblCond.Layout.Column = 1;

    ddCond = uidropdown(cg, 'Items', cellstr(uConds), 'Value', char(uConds(1)));
    ddCond.Layout.Row = 1; ddCond.Layout.Column = 2;

    lblGroup = uilabel(cg, 'Text','Assign group label:', 'FontWeight','bold');
    lblGroup.Layout.Row = 1; lblGroup.Layout.Column = 3;

    efGroup = uieditfield(cg, 'text', 'Value', '');
    efGroup.Layout.Row = 1; efGroup.Layout.Column = 4;

    btnApplyAll = uibutton(cg, 'Text','Apply to ALL matches', 'ButtonPushedFcn', @onApplyAll);
    btnApplyAll.Layout.Row = 1; btnApplyAll.Layout.Column = 5;

    btnApplySel = uibutton(cg, 'Text','Apply to selected rows', 'ButtonPushedFcn', @onApplySelected);
    btnApplySel.Layout.Row = 1; btnApplySel.Layout.Column = 6;

    hint = uitextarea(cg, ...
        'Value', { ...
            'Edit the Group column directly, or use bulk assignment above.', ...
            'Example: map "GSK100nMBath" and "GSK100nMBath|GSK100nMBathLumen" to "GSK100nM".', ...
            'Click OK to write data(i).meta.groupKey for all rows.'}, ...
        'Editable','off', 'BackgroundColor','w');
    hint.Layout.Row = 2; hint.Layout.Column = [1 6];

    btnOK = uibutton(cg, 'Text','OK', 'ButtonPushedFcn', @onOK);
    btnOK.Layout.Row = 3; btnOK.Layout.Column = 5;

    btnCancel = uibutton(cg, 'Text','Cancel', 'ButtonPushedFcn', @onCancel);
    btnCancel.Layout.Row = 3; btnCancel.Layout.Column = 6;

    % ---- State shared across callbacks ----
    didCancel = false;
    Tfinal = T; % will be overwritten on OK

    % Wait for user
    uiwait(fig);

    % If user closed the window manually, treat as cancel
    if ~isvalid(fig)
        didCancel = true;
    else
        delete(fig); % safe cleanup after uiwait ends
    end

    if didCancel
        groupMap = buildGroupMapFromTable(Tfinal);
        return;
    end

    % Write back
    for i = 1:n
        if ~isfield(data(i),'meta') || ~isstruct(data(i).meta)
            data(i).meta = struct();
        end
        data(i).meta.groupKey = string(Tfinal.Group(i));
    end

    groupMap = buildGroupMapFromTable(Tfinal);

    if ~isempty(opts.saveMapPath)
        try
            save(opts.saveMapPath, 'groupMap');
        catch ME
            warning('Could not save groupMap to "%s": %s', opts.saveMapPath, ME.message);
        end
    end

    % ------------ callbacks ------------
    function onApplyAll(~,~)
        Tcur = uit.Data;
        targetCond = string(ddCond.Value);
        newGroup = string(strtrim(efGroup.Value));

        if strlength(newGroup)==0
            uialert(fig, 'Enter a group label to apply.', 'Missing group');
            return;
        end

        mask = string(Tcur.DetectedCondition) == targetCond;
        if ~any(mask)
            uialert(fig, 'No rows match the selected detected condition.', 'No matches');
            return;
        end

        Tcur.Group(mask) = newGroup;
        uit.Data = Tcur;
    end

    function onApplySelected(~,~)
        Tcur = uit.Data;
        newGroup = string(strtrim(efGroup.Value));
        if strlength(newGroup)==0
            uialert(fig, 'Enter a group label to apply.', 'Missing group');
            return;
        end

        sel = uit.Selection;
        if isempty(sel)
            uialert(fig, 'Select one or more rows in the table first.', 'No selection');
            return;
        end

        selRows = unique(sel(:,1));
        Tcur.Group(selRows) = newGroup;
        uit.Data = Tcur;
    end

    function onOK(~,~)
        % Cache final data BEFORE closing UI
        Tfinal = uit.Data;
        didCancel = false;
        uiresume(fig);
    end

    function onCancel(~,~)
        % Cache current state but mark as cancel
        Tfinal = uit.Data;
        didCancel = true;
        uiresume(fig);
    end
end

% ---------------- helper functions ----------------
function opts = setDefault(opts, name, value)
    if ~isfield(opts, name) || isempty(opts.(name))
        opts.(name) = value;
    end
end

function out = getConditionKey(d)
    out = "";
    if isfield(d,'meta') && isfield(d.meta,'conditionKey') && ~isempty(d.meta.conditionKey)
        out = d.meta.conditionKey;
    end
end

function out = getFilePath(d)
    out = "";
    if isfield(d,'file') && ~isempty(d.file)
        out = d.file; return;
    end
    if isfield(d,'meta') && isfield(d.meta,'file') && ~isempty(d.meta.file)
        out = d.meta.file; return;
    end
    if isfield(d,'meta') && isfield(d.meta,'filePath') && ~isempty(d.meta.filePath)
        out = d.meta.filePath; return;
    end
end

function out = getRecID(d, i)
    out = "rec" + sprintf('%03d', i);
    if isfield(d,'meta') && isfield(d.meta,'fileTags') && ~isempty(d.meta.fileTags)
        out = string(d.meta.fileTags{1});
    elseif isfield(d,'meta') && isfield(d.meta,'dateCode') && ~isempty(d.meta.dateCode)
        out = string(d.meta.dateCode);
    end
end

function groupMap = buildGroupMapFromTable(T)
    det = string(T.DetectedCondition);
    grp = string(T.Group);

    uDet = unique(det, 'stable');
    outGrp = strings(numel(uDet),1);
    nRec = zeros(numel(uDet),1);

    for k = 1:numel(uDet)
        mask = det == uDet(k);
        g = grp(mask);
        g = g(strlength(strtrim(g))>0);
        if isempty(g)
            outGrp(k) = "";
        else
            [ug,~,gi] = unique(g);
            counts = accumarray(gi,1);
            [~,mx] = max(counts);
            outGrp(k) = ug(mx);
        end
        nRec(k) = sum(mask);
    end

    groupMap = table(uDet, outGrp, nRec, 'VariableNames', {'DetectedCondition','AssignedGroup','Nrecords'});
end
