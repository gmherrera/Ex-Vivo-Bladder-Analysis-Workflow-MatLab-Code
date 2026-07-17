function h = plotRawPrepOverlaySparklines(data, varargin)
%PLOTRAWPREPOVERLAYSPARKLINES
% Plot raw-data sparklines with treatment groups overlaid for each preparation.
%         Version 1.0
%         Date: July 9, 2026
%         Author: G. Herrera 
%         Co-Author/AI Tool: OpenAI ChatGPT (GPT-5.5)
%         Note: The core architecture was designed by the author and implemented by
%           ChatGPT via prompt engineering. All code was reviewed,
%           modified, and verified by the author.
%
% Creates one sparkline axis per preparation. Within each axis, all
% treatment/condition records belonging to that preparation are
% superimposed.
%
% All sparklines are scaled to the same X and Y limits by default so shapes
% and amplitudes are directly comparable.
%
% Recommended usage with explicit prep identifier:
%   figure;
%   plotRawPrepOverlaySparklines(data, ...
%       'prepPath','meta.prepID', ...
%       'groupPath','meta.groupKey', ...
%       'xPath','volume', ...
%       'yPath','proc.smoothNerveMovMean10s', ...
%       'showScaleBar',true, ...
%       'xScaleBarValue',0.1, ...
%       'yScaleBarValue',5);
%
% If you do not yet have a prepID field, pair by order within each group:
%   figure;
%   plotRawPrepOverlaySparklines(data, ...
%       'pairingMode','byOrder', ...
%       'xVar','volumeML', ...
%       'yVar','smoothNerveHz', ...
%       'showScaleBar',true, ...
%       'xScaleBarValue',0.1, ...
%       'yScaleBarValue',5);
%
% Supported variable aliases:
%   'volumeML'        -> data(i).volume
%   'volumePct'       -> data(i).proc.volumePercent
%   'pressure'        -> data(i).pressureSmooth
%   'smoothNerveHz'   -> data(i).proc.smoothNerveMovMean10s
%   'smoothNervePct'  -> data(i).proc.smoothNervePctMax
%
% Name-value options:
%   'xPath'                 field path for X data; default = 'volume'
%   'yPath'                 field path for Y data; default = 'proc.smoothNerveMovMean10s'
%   'xVar'                  alias for X data; overrides xPath if supplied
%   'yVar'                  alias for Y data; overrides yPath if supplied
%   'groupPath'             default = 'meta.groupKey'
%   'prepPath'              default = ''
%   'pairingMode'           'prepPath' or 'byOrder'; default = 'prepPath'
%   'sameAxes'              true/false; default = true
%   'xLim'                  explicit shared X limits; default = []
%   'yLim'                  explicit shared Y limits; default = []
%   'showAxes'              true/false; default = false
%   'showPrepLabels'        true/false; default = true
%   'prepLabelMode'         'prepID', 'index', 'file', or 'none'; default = 'prepID'
%   'lineWidth'             default = 1.1
%   'normalizeXWithinTrace' true/false; default = false
%   'normalizeYWithinTrace' true/false; default = false
%   'thinToNPoints'         default = 1000; set [] to plot all points
%   'title'                 optional figure title; default = ''
%
% Scale bar options:
%   'showScaleBar'          true/false; default = false
%   'xScaleBarValue'        X scale bar length in X-axis units; default = []
%   'yScaleBarValue'        Y scale bar length in Y-axis units; default = []
%   'scaleBarLocation'      'southeast','southwest','northeast','northwest'; default = 'southeast'
%   'scaleBarRow'           row index where scale bar appears; default = last row
%   'scaleBarColor'         RGB color; default = [0 0 0]
%   'scaleBarLineWidth'     default = 1.5
%   'showScaleBarLabels'    true/false; default = true
%   'xScaleBarLabel'        custom X label; default uses value + x label
%   'yScaleBarLabel'        custom Y label; default uses value + y label
%
% Output:
%   h.fig
%   h.tiled
%   h.ax
%   h.line
%   h.scaleBar
%   h.prepIDs
%   h.groupKeys

p = inputParser;
p.FunctionName = 'plotRawPrepOverlaySparklines';
p.addParameter('xPath', 'volume', @(s) ischar(s) || isstring(s));
p.addParameter('yPath', 'proc.smoothNerveMovMean10s', @(s) ischar(s) || isstring(s));
p.addParameter('xVar', '', @(s) ischar(s) || isstring(s));
p.addParameter('yVar', '', @(s) ischar(s) || isstring(s));
p.addParameter('groupPath', 'meta.groupKey', @(s) ischar(s) || isstring(s));
p.addParameter('prepPath', '', @(s) ischar(s) || isstring(s));
p.addParameter('pairingMode', 'prepPath', @(s) ischar(s) || isstring(s));
p.addParameter('sameAxes', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('xLim', [], @(x) isempty(x) || (isnumeric(x) && numel(x)==2));
p.addParameter('yLim', [], @(x) isempty(x) || (isnumeric(x) && numel(x)==2));
p.addParameter('showAxes', false, @(x) islogical(x) || isnumeric(x));
p.addParameter('showPrepLabels', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('prepLabelMode', 'prepID', @(s) ischar(s) || isstring(s));
p.addParameter('lineWidth', 1.1, @(x) isscalar(x) && isnumeric(x) && x > 0);
p.addParameter('normalizeXWithinTrace', false, @(x) islogical(x) || isnumeric(x));
p.addParameter('normalizeYWithinTrace', false, @(x) islogical(x) || isnumeric(x));
p.addParameter('thinToNPoints', 1000, @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x >= 2));
p.addParameter('title', '', @(s) ischar(s) || isstring(s));

p.addParameter('showScaleBar', false, @(x) islogical(x) || isnumeric(x));
p.addParameter('xScaleBarValue', [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x > 0));
p.addParameter('yScaleBarValue', [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x > 0));
p.addParameter('scaleBarLocation', 'southeast', @(s) ischar(s) || isstring(s));
p.addParameter('scaleBarRow', [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x >= 1));
p.addParameter('scaleBarColor', [0 0 0], @(x) isnumeric(x) && numel(x)==3);
p.addParameter('scaleBarLineWidth', 1.5, @(x) isscalar(x) && isnumeric(x) && x > 0);
p.addParameter('showScaleBarLabels', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('xScaleBarLabel', '', @(s) ischar(s) || isstring(s));
p.addParameter('yScaleBarLabel', '', @(s) ischar(s) || isstring(s));

p.parse(varargin{:});
opts = p.Results;

opts.xPath = char(opts.xPath);
opts.yPath = char(opts.yPath);
opts.xVar = char(opts.xVar);
opts.yVar = char(opts.yVar);
opts.groupPath = char(opts.groupPath);
opts.prepPath = char(opts.prepPath);
opts.pairingMode = lower(char(opts.pairingMode));
opts.scaleBarLocation = lower(char(opts.scaleBarLocation));

[xPath, xLabel] = resolveVar(opts.xVar, opts.xPath, 'x');
[yPath, yLabel] = resolveVar(opts.yVar, opts.yPath, 'y');

nRec = numel(data);
if nRec == 0
    error('plotRawPrepOverlaySparklines:NoData', 'Input data is empty.');
end

% Treatment/group labels.
groupKeys = strings(nRec,1);
for i = 1:nRec
    groupKeys(i) = getStringFieldOrDefault(data(i), opts.groupPath, "Ungrouped");
end
uGroups = unique(groupKeys, 'stable');

% Preparation labels.
if isempty(opts.prepPath) || strcmpi(opts.pairingMode, 'byorder')
    prepIDs = inferPrepIDsByOrder(groupKeys);
else
    prepIDs = strings(nRec,1);
    for i = 1:nRec
        prepIDs(i) = getStringFieldOrDefault(data(i), opts.prepPath, "Prep_" + string(i));
    end
end

uPrep = unique(prepIDs, 'stable');
nPrep = numel(uPrep);

% Pull traces and global limits.
traceXY = cell(nRec, 2);
allX = [];
allY = [];

for i = 1:nRec
    x = getByPath(data(i), xPath);
    y = getByPath(data(i), yPath);

    x = x(:);
    y = y(:);

    if numel(x) ~= numel(y)
        error('plotRawPrepOverlaySparklines:SizeMismatch', ...
            'Record %d: %s (%d) and %s (%d) sizes do not match.', ...
            i, xPath, numel(x), yPath, numel(y));
    end

    keep = isfinite(x) & isfinite(y);
    x = x(keep);
    y = y(keep);

    if ~isempty(opts.thinToNPoints) && numel(x) > opts.thinToNPoints
        idx = unique(round(linspace(1, numel(x), opts.thinToNPoints)));
        x = x(idx);
        y = y(idx);
    end

    if opts.normalizeXWithinTrace
        x = normalize01(x);
    end

    if opts.normalizeYWithinTrace
        y = normalize01(y);
    end

    traceXY{i,1} = x;
    traceXY{i,2} = y;

    allX = [allX; x(:)]; %#ok<AGROW>
    allY = [allY; y(:)]; %#ok<AGROW>
end

if isempty(allX) || isempty(allY)
    error('plotRawPrepOverlaySparklines:NoFiniteData', ...
        'No finite X/Y data found.');
end

if ~isempty(opts.xLim)
    sharedXLim = opts.xLim(:).';
else
    sharedXLim = paddedLimits(allX, 0.03);
end

if ~isempty(opts.yLim)
    sharedYLim = opts.yLim(:).';
else
    sharedYLim = paddedLimits(allY, 0.08);
end

% Plot.
fig = gcf;
t = tiledlayout(fig, nPrep, 1, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

if strlength(string(opts.title)) > 0
    title(t, string(opts.title), 'Interpreter', 'none');
end

co = get(groot, 'defaultAxesColorOrder');
nColors = size(co,1);

ax = gobjects(nPrep,1);
lineHandles = gobjects(nRec,1);

for pIdx = 1:nPrep
    ax(pIdx) = nexttile(t, pIdx);
    hold(ax(pIdx), 'on');

    thisPrep = uPrep(pIdx);
    recIdx = find(prepIDs == thisPrep);

    for r = recIdx(:).'
        gIdx = find(uGroups == groupKeys(r), 1, 'first');
        C = co(mod(gIdx-1, nColors)+1, :);

        x = traceXY{r,1};
        y = traceXY{r,2};

        if isempty(x) || isempty(y)
            continue
        end

        lineHandles(r) = plot(ax(pIdx), x, y, ...
            'LineStyle', '-', ...
            'Color', C, ...
            'LineWidth', opts.lineWidth, ...
            'DisplayName', char(groupKeys(r)));
    end

    if opts.sameAxes
        xlim(ax(pIdx), sharedXLim);
        ylim(ax(pIdx), sharedYLim);
    else
        localX = [];
        localY = [];
        for r = recIdx(:).'
            localX = [localX; traceXY{r,1}(:)]; %#ok<AGROW>
            localY = [localY; traceXY{r,2}(:)]; %#ok<AGROW>
        end
        if ~isempty(localX), xlim(ax(pIdx), paddedLimits(localX, 0.03)); end
        if ~isempty(localY), ylim(ax(pIdx), paddedLimits(localY, 0.08)); end
    end

    box(ax(pIdx), 'off');

    if ~opts.showAxes
        ax(pIdx).XColor = 'none';
        ax(pIdx).YColor = 'none';
        ax(pIdx).XTick = [];
        ax(pIdx).YTick = [];
    else
        if pIdx < nPrep
            ax(pIdx).XTickLabel = [];
        end
    end

    if opts.showPrepLabels
        labelText = makePrepLabel(thisPrep, pIdx, recIdx, data, opts.prepLabelMode);
        text(ax(pIdx), -0.02, 0.5, labelText, ...
            'Units', 'normalized', ...
            'HorizontalAlignment', 'right', ...
            'VerticalAlignment', 'middle', ...
            'Interpreter', 'none', ...
            'FontSize', 8, ...
            'Color', [0.2 0.2 0.2]);
    end
end

% Legend: one representative line per group.
legendLines = gobjects(numel(uGroups),1);
legendLabels = cell(numel(uGroups),1);
for g = 1:numel(uGroups)
    r = find(groupKeys == uGroups(g), 1, 'first');
    if ~isempty(r) && isgraphics(lineHandles(r))
        legendLines(g) = lineHandles(r);
        legendLabels{g} = char(uGroups(g));
    end
end
validLegend = isgraphics(legendLines);
if any(validLegend)
    legend(ax(1), legendLines(validLegend), legendLabels(validLegend), ...
        'Interpreter', 'none', 'Location', 'best');
end

scaleBarHandles = struct('xLine',gobjects(0), 'yLine',gobjects(0), ...
                         'xText',gobjects(0), 'yText',gobjects(0));

if opts.showScaleBar
    if isempty(opts.scaleBarRow)
        scaleBarRow = nPrep;
    else
        scaleBarRow = min(max(1, round(opts.scaleBarRow)), nPrep);
    end

    scaleBarHandles = addScaleBar(ax(scaleBarRow), opts, xLabel, yLabel);
end

if opts.showAxes
    xlabel(ax(end), xLabel, 'Interpreter', 'none');
    ylabel(t, yLabel, 'Interpreter', 'none');
end

h.fig = fig;
h.tiled = t;
h.ax = ax;
h.line = lineHandles;
h.scaleBar = scaleBarHandles;
h.prepIDs = prepIDs;
h.groupKeys = groupKeys;
h.uniquePrepIDs = uPrep;
h.uniqueGroupKeys = uGroups;
h.xPath = xPath;
h.yPath = yPath;
h.sharedXLim = sharedXLim;
h.sharedYLim = sharedYLim;

end

function sb = addScaleBar(ax, opts, xLabel, yLabel)
xl = xlim(ax);
yl = ylim(ax);

xRange = diff(xl);
yRange = diff(yl);

if isempty(opts.xScaleBarValue)
    xVal = niceScaleValue(xRange * 0.2);
else
    xVal = opts.xScaleBarValue;
end

if isempty(opts.yScaleBarValue)
    yVal = niceScaleValue(yRange * 0.2);
else
    yVal = opts.yScaleBarValue;
end

marginX = 0.08 * xRange;
marginY = 0.12 * yRange;

switch opts.scaleBarLocation
    case 'southwest'
        x0 = xl(1) + marginX;
        y0 = yl(1) + marginY;
        xDir = 1; yDir = 1;
        hAlign = 'center';
    case 'northwest'
        x0 = xl(1) + marginX;
        y0 = yl(2) - marginY;
        xDir = 1; yDir = -1;
        hAlign = 'center';
    case 'northeast'
        x0 = xl(2) - marginX;
        y0 = yl(2) - marginY;
        xDir = -1; yDir = -1;
        hAlign = 'center';
    otherwise % southeast
        x0 = xl(2) - marginX;
        y0 = yl(1) + marginY;
        xDir = -1; yDir = 1;
        hAlign = 'center';
end

x1 = x0 + xDir * xVal;
y1 = y0 + yDir * yVal;

C = opts.scaleBarColor(:).';

sb.xLine = line(ax, [x0 x1], [y0 y0], ...
    'Color', C, ...
    'LineWidth', opts.scaleBarLineWidth, ...
    'Clipping', 'off', ...
    'HandleVisibility', 'off');

sb.yLine = line(ax, [x0 x0], [y0 y1], ...
    'Color', C, ...
    'LineWidth', opts.scaleBarLineWidth, ...
    'Clipping', 'off', ...
    'HandleVisibility', 'off');

sb.xText = gobjects(0);
sb.yText = gobjects(0);

if opts.showScaleBarLabels
    if strlength(string(opts.xScaleBarLabel)) > 0
        xText = string(opts.xScaleBarLabel);
    else
        xText = string(formatNumber(xVal)) + " " + stripUnitsFromLabel(xLabel);
    end

    if strlength(string(opts.yScaleBarLabel)) > 0
        yText = string(opts.yScaleBarLabel);
    else
        yText = string(formatNumber(yVal)) + " " + stripUnitsFromLabel(yLabel);
    end

    textYOffset = 0.04 * yRange;
    textXOffset = 0.025 * xRange;

    sb.xText = text(ax, mean([x0 x1]), y0 - sign(yDir)*textYOffset, xText, ...
        'HorizontalAlignment', hAlign, ...
        'VerticalAlignment', 'middle', ...
        'Interpreter', 'none', ...
        'FontSize', 8, ...
        'Color', C, ...
        'Clipping', 'off');

    sb.yText = text(ax, x0 - sign(xDir)*textXOffset, mean([y0 y1]), yText, ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'Rotation', 90, ...
        'Interpreter', 'none', ...
        'FontSize', 8, ...
        'Color', C, ...
        'Clipping', 'off');
end
end

function v = niceScaleValue(v)
if ~isfinite(v) || v <= 0
    v = 1;
    return
end
pow10 = 10^floor(log10(v));
mant = v / pow10;
if mant < 1.5
    niceMant = 1;
elseif mant < 3.5
    niceMant = 2;
elseif mant < 7.5
    niceMant = 5;
else
    niceMant = 10;
end
v = niceMant * pow10;
end

function s = stripUnitsFromLabel(label)
label = char(label);
tokens = regexp(label, '\((.*?)\)', 'tokens');
if ~isempty(tokens)
    s = string(tokens{end}{1});
else
    s = string(label);
end
end

function s = formatNumber(v)
if abs(v) >= 100 || abs(v) < 0.01
    s = sprintf('%.3g', v);
elseif abs(v) >= 10
    s = sprintf('%.2g', v);
else
    s = sprintf('%.2g', v);
end
end

function prepIDs = inferPrepIDsByOrder(groupKeys)
uGroups = unique(groupKeys, 'stable');
prepIDs = strings(numel(groupKeys),1);

for g = 1:numel(uGroups)
    idx = find(groupKeys == uGroups(g));
    for k = 1:numel(idx)
        prepIDs(idx(k)) = "Prep_" + string(k);
    end
end
end

function [pathStr, label] = resolveVar(varName, pathStr, axisName)
varName = char(varName);
pathStr = char(pathStr);

if ~isempty(varName)
    key = lower(strtrim(varName));

    switch key
        case {'volumeml','volume_ml','volume','ml'}
            pathStr = 'volume';
            label = 'Volume (mL)';

        case {'volumepct','volume_pct','volumepctmax','volume_pctmax','pctvolume','percentvolume','volumemaxpct'}
            pathStr = 'proc.volumePercent';
            label = 'Volume (% Max Capacity)';

        case {'pressure','pressuremmhg','pressure_mmhg'}
            pathStr = 'pressureSmooth';
            label = 'Pressure (mmHg)';

        case {'smoothnervehz','nervehz','smooth_nerve_hz'}
            pathStr = 'proc.smoothNerveMovMean10s';
            label = 'Smoothed Nerve Activity (Hz)';

        case {'smoothnervepct','smoothnervepctmax','nervepct','nervepctmax','smooth_nerve_pct'}
            pathStr = 'proc.smoothNervePctMax';
            label = 'Smoothed Nerve Activity (% Max)';

        otherwise
            error('plotRawPrepOverlaySparklines:UnknownVarAlias', ...
                'Unknown %sVar alias "%s". Use xPath/yPath for custom fields.', axisName, varName);
    end
else
    label = labelFromPath(pathStr);
end
end

function label = labelFromPath(pathStr)
switch char(pathStr)
    case 'volume'
        label = 'Volume (mL)';
    case 'proc.volumePercent'
        label = 'Volume (% Max Capacity)';
    case 'pressureSmooth'
        label = 'Pressure (mmHg)';
    case 'proc.smoothNerveMovMean10s'
        label = 'Smoothed Nerve Activity (Hz)';
    case 'proc.smoothNervePctMax'
        label = 'Smoothed Nerve Activity (% Max)';
    otherwise
        label = strrep(char(pathStr), '_', '\_');
end
end

function val = getByPath(S, pathStr)
parts = strsplit(char(pathStr), '.');
val = S;

for p = 1:numel(parts)
    f = parts{p};
    if ~isstruct(val) || ~isfield(val, f)
        error('plotRawPrepOverlaySparklines:MissingField', ...
            'Missing field path "%s" at "%s".', pathStr, f);
    end
    val = val.(f);
end
end

function s = getStringFieldOrDefault(S, pathStr, defaultValue)
try
    val = getByPath(S, pathStr);
    s = string(val);
    if strlength(s) == 0
        s = defaultValue;
    end
catch
    s = defaultValue;
end
end

function z = normalize01(z)
z = z(:);
mn = min(z, [], 'omitnan');
mx = max(z, [], 'omitnan');

if ~isfinite(mn) || ~isfinite(mx) || mx == mn
    z = zeros(size(z));
else
    z = (z - mn) ./ (mx - mn);
end
end

function lim = paddedLimits(v, frac)
v = v(isfinite(v));

if isempty(v)
    lim = [0 1];
    return
end

mn = min(v);
mx = max(v);

if mn == mx
    pad = max(abs(mn), 1) * frac;
else
    pad = (mx - mn) * frac;
end

lim = [mn - pad, mx + pad];
end

function labelText = makePrepLabel(prepID, prepIdx, recIdx, data, mode)
mode = lower(char(mode));

switch mode
    case 'none'
        labelText = "";

    case 'index'
        labelText = "Prep " + string(prepIdx);

    case 'file'
        r = recIdx(1);
        if isfield(data(r), 'file') && strlength(string(data(r).file)) > 0
            [~, name, ext] = fileparts(char(data(r).file));
            labelText = string([name ext]);
        else
            labelText = "Prep " + string(prepIdx);
        end

    otherwise
        labelText = string(prepID);
end
end
