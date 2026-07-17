function out = bin2DByGroup(data, varargin)
%BIN2DBYGROUP
% General grouped 2D binning for paired X/Y data vectors.
%         Version 1.0
%         Date: July 9, 2026
%         Author: G. Herrera 
%         Co-Author/AI Tool: OpenAI ChatGPT (GPT-5.5)
%         Note: The core architecture was designed by the author and implemented by
%           ChatGPT via prompt engineering. All code was reviewed,
%           modified, and verified by the author.
%
% Bins by the X variable, then calculates both X and Y summary statistics
% within each X bin. Each replicate is binned first; group means and SDs are
% then calculated across replicate-level binned means.
%
% Example:
%   b = bin2DByGroup(data, ...
%       'xPath', 'proc.volumePercent', ...
%       'yPath', 'proc.smoothNerveMovMean10s');
%
%   figure; ax = axes;
%   plotBinned2DByGroup(ax, b);
%
% Supported variable aliases:
%   'volumeML'        -> data(i).volume
%   'volumePct'       -> data(i).proc.volumePercent
%   'pressure'        -> data(i).pressureSmooth
%   'smoothNerveHz'   -> data(i).proc.smoothNerveMovMean10s
%   'smoothNervePct'  -> data(i).proc.smoothNervePctMax
%
% Name-value options:
%   'xPath'           field path for X data
%   'yPath'           field path for Y data
%   'xVar'            alias for X data
%   'yVar'            alias for Y data
%   'xEdges'          explicit X-bin edges
%   'xBinWidth'       X-bin width; inferred from xVar/xPath if omitted
%   'xMin'            lower edge; inferred from data if omitted
%   'xMax'            upper edge; inferred from data if omitted
%   'minNPerBin'      minimum samples/bin/replicate; default = 1
%   'groupPath'       default = 'meta.groupKey'
%   'clampX0100'      clamp X to [0 100] for percent axes; default inferred
%
% Output:
%   out.edges, out.centers
%   out.rep(i).xMean/.xSd/.yMean/.ySd/.n
%   out.meta(i).groupKey/.file
%   out.groups(g).groupKey/.xMean/.xSd/.yMean/.ySd/.nRepsUsed
%   out.xLabel, out.yLabel, out.opts

if numel(varargin) == 1 && isstruct(varargin{1})
    varargin = namedStructToVarargin(varargin{1});
end

p = inputParser;
p.FunctionName = 'bin2DByGroup';
p.addParameter('xPath', '', @(s) ischar(s) || isstring(s));
p.addParameter('yPath', '', @(s) ischar(s) || isstring(s));
p.addParameter('xVar', '', @(s) ischar(s) || isstring(s));
p.addParameter('yVar', '', @(s) ischar(s) || isstring(s));
p.addParameter('xEdges', [], @(x) isempty(x) || isnumeric(x));
p.addParameter('xBinWidth', [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x > 0));
p.addParameter('xMin', [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
p.addParameter('xMax', [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
p.addParameter('minNPerBin', 1, @(x) isscalar(x) && isnumeric(x) && x >= 1);
p.addParameter('groupPath', 'meta.groupKey', @(s) ischar(s) || isstring(s));
p.addParameter('clampX0100', [], @(x) isempty(x) || islogical(x));
p.parse(varargin{:});
opts = p.Results;

opts.xPath = char(opts.xPath);
opts.yPath = char(opts.yPath);
opts.xVar  = char(opts.xVar);
opts.yVar  = char(opts.yVar);
opts.groupPath = char(opts.groupPath);

[xPath, xLabel, xDefaultBinWidth, xIsPercent] = resolveVar(opts.xVar, opts.xPath, 'x');
[yPath, yLabel, ~, ~] = resolveVar(opts.yVar, opts.yPath, 'y');
opts.xPath = xPath;
opts.yPath = yPath;

if isempty(opts.xBinWidth)
    opts.xBinWidth = xDefaultBinWidth;
end

if isempty(opts.clampX0100)
    opts.clampX0100 = xIsPercent;
end

nRep = numel(data);

if ~isempty(opts.xEdges)
    edges = opts.xEdges(:).';
else
    allX = [];
    for i = 1:nRep
        x = getByPath(data(i), opts.xPath);
        x = x(:);
        if opts.clampX0100
            x(x < 0) = 0;
            x(x > 100) = 100;
        end
        allX = [allX; x(isfinite(x))]; %#ok<AGROW>
    end

    if isempty(allX)
        error('bin2DByGroup:NoFiniteX', 'No finite X values found for xPath "%s".', opts.xPath);
    end

    if isempty(opts.xMin)
        if opts.clampX0100
            opts.xMin = 0;
        else
            opts.xMin = floor(min(allX) / opts.xBinWidth) * opts.xBinWidth;
        end
    end

    if isempty(opts.xMax)
        if opts.clampX0100
            opts.xMax = 100;
        else
            opts.xMax = ceil(max(allX) / opts.xBinWidth) * opts.xBinWidth;
        end
    end

    edges = opts.xMin:opts.xBinWidth:opts.xMax;

    if numel(edges) < 2 || edges(end) < opts.xMax
        edges = [edges, edges(end) + opts.xBinWidth];
    end
end

centers = (edges(1:end-1) + diff(edges)/2).';
nBins = numel(centers);

emptyRep = struct('xMean',[],'xSd',[],'yMean',[],'ySd',[],'n',[]);
rep = repmat(emptyRep, nRep, 1);
meta = repmat(struct('file',"", 'groupKey', ""), nRep, 1);

for i = 1:nRep
    x = getByPath(data(i), opts.xPath);
    y = getByPath(data(i), opts.yPath);

    x = x(:);
    y = y(:);

    if numel(x) ~= numel(y)
        error('bin2DByGroup:SizeMismatch', ...
            'Rep %d: %s (%d) and %s (%d) sizes do not match.', ...
            i, opts.xPath, numel(x), opts.yPath, numel(y));
    end

    if opts.clampX0100
        x(x < 0) = 0;
        x(x > 100) = 100;
    end

    b = binOneXY(x, y, edges, opts.minNPerBin);

    rep(i).xMean = b.xMean(:);
    rep(i).xSd   = b.xSd(:);
    rep(i).yMean = b.yMean(:);
    rep(i).ySd   = b.ySd(:);
    rep(i).n     = b.n(:);

    if isfield(data(i), 'file')
        meta(i).file = string(data(i).file);
    end

    try
        g = getByPath(data(i), opts.groupPath);
        meta(i).groupKey = string(g);
    catch
        % Primary grouping field is meta.groupKey. If an older dataset only
        % has meta.conditionKey, use it as a legacy fallback rather than
        % silently assigning the record to Ungrouped.
        if isfield(data(i), 'meta') && isfield(data(i).meta, 'groupKey')
            meta(i).groupKey = string(data(i).meta.groupKey);
        elseif isfield(data(i), 'meta') && isfield(data(i).meta, 'conditionKey')
            meta(i).groupKey = string(data(i).meta.conditionKey);
        else
            meta(i).groupKey = "";
        end
    end
end

groupKeys = string({meta.groupKey});
missingGroup = strlength(groupKeys) == 0;
groupKeys(missingGroup) = "Ungrouped";

uGroups = unique(groupKeys, 'stable');
groups = repmat(struct( ...
    'groupKey',"", ...
    'repIdx',[], ...
    'xMean',nan(nBins,1), ...
    'xSd',nan(nBins,1), ...
    'yMean',nan(nBins,1), ...
    'ySd',nan(nBins,1), ...
    'nRepsUsed',zeros(nBins,1)), numel(uGroups), 1);

for g = 1:numel(uGroups)
    idx = find(groupKeys == uGroups(g));

    xMat = nan(nBins, numel(idx));
    yMat = nan(nBins, numel(idx));

    for j = 1:numel(idx)
        r = idx(j);
        xMat(:,j) = rep(r).xMean(:);
        yMat(:,j) = rep(r).yMean(:);
    end

    validBoth = isfinite(xMat) & isfinite(yMat);

    groups(g).groupKey = uGroups(g);
    groups(g).repIdx = idx;
    groups(g).xMean = meanWithOmitnan(xMat, 2);
    groups(g).xSd   = stdWithOmitnan(xMat, 0, 2);
    groups(g).yMean = meanWithOmitnan(yMat, 2);
    groups(g).ySd   = stdWithOmitnan(yMat, 0, 2);
    groups(g).nRepsUsed = sum(validBoth, 2);
end

out.edges = edges;
out.centers = centers;
out.rep = rep;
out.meta = meta;
out.groups = groups;
out.xLabel = xLabel;
out.yLabel = yLabel;
out.opts = opts;

end

function b = binOneXY(x, y, edges, minN)
keep = isfinite(x) & isfinite(y);
x = x(keep);
y = y(keep);

[~,~,binIdx] = histcounts(x, edges);
nBins = numel(edges) - 1;

xMean = nan(nBins,1);
xSd   = nan(nBins,1);
yMean = nan(nBins,1);
ySd   = nan(nBins,1);
n     = zeros(nBins,1);

for k = 1:nBins
    idx = (binIdx == k);
    n(k) = sum(idx);

    if n(k) >= minN
        xMean(k) = meanWithOmitnan(x(idx), 1);
        xSd(k)   = stdWithOmitnan(x(idx), 0, 1);
        yMean(k) = meanWithOmitnan(y(idx), 1);
        ySd(k)   = stdWithOmitnan(y(idx), 0, 1);
    end
end

b.xMean = xMean;
b.xSd   = xSd;
b.yMean = yMean;
b.ySd   = ySd;
b.n     = n;
end

function [pathStr, label, defaultBinWidth, isPercent] = resolveVar(varName, pathStr, axisName)
varName = char(varName);
pathStr = char(pathStr);

isPercent = false;

if ~isempty(varName)
    key = lower(strtrim(varName));

    switch key
        case {'volumeml','volume_ml','volume','ml'}
            pathStr = 'volume';
            label = 'Volume (mL)';
            defaultBinWidth = 0.01;
            isPercent = false;

        case {'volumepct','volume_pct','volumepctmax','volume_pctmax','pctvolume','percentvolume','volumemaxpct'}
            pathStr = 'proc.volumePercent';
            label = 'Volume (% Max Capacity)';
            defaultBinWidth = 2;
            isPercent = true;

        case {'pressure','pressuremmhg','pressure_mmhg'}
            pathStr = 'pressureSmooth';
            label = 'Pressure (mmHg)';
            defaultBinWidth = 2;
            isPercent = false;

        case {'smoothnervehz','nervehz','smooth_nerve_hz'}
            pathStr = 'proc.smoothNerveMovMean10s';
            label = 'Smoothed Nerve Activity (Hz)';
            defaultBinWidth = 1;
            isPercent = false;

        case {'smoothnervepct','smoothnervepctmax','nervepct','nervepctmax','smooth_nerve_pct'}
            pathStr = 'proc.smoothNervePctMax';
            label = 'Smoothed Nerve Activity (% Max)';
            defaultBinWidth = 2;
            isPercent = true;

        otherwise
            error('bin2DByGroup:UnknownVarAlias', ...
                'Unknown %sVar alias "%s". Use xPath/yPath for custom fields.', axisName, varName);
    end

elseif ~isempty(pathStr)
    [label, defaultBinWidth, isPercent] = labelFromPath(pathStr);

else
    error('bin2DByGroup:MissingVariable', ...
        'You must provide either %sVar or %sPath.', axisName, axisName);
end
end

function [label, defaultBinWidth, isPercent] = labelFromPath(pathStr)
switch char(pathStr)
    case 'volume'
        label = 'Volume (mL)';
        defaultBinWidth = 0.01;
        isPercent = false;

    case 'proc.volumePercent'
        label = 'Volume (% Max Capacity)';
        defaultBinWidth = 2;
        isPercent = true;

    case 'pressureSmooth'
        label = 'Pressure (mmHg)';
        defaultBinWidth = 2;
        isPercent = false;

    case 'proc.smoothNerveMovMean10s'
        label = 'Smoothed Nerve Activity (Hz)';
        defaultBinWidth = 1;
        isPercent = false;

    case 'proc.smoothNervePctMax'
        label = 'Smoothed Nerve Activity (% Max)';
        defaultBinWidth = 2;
        isPercent = true;

    otherwise
        label = strrep(char(pathStr), '_', '\_');
        defaultBinWidth = 1;
        isPercent = contains(lower(pathStr), 'percent') || contains(lower(pathStr), 'pct');
end
end

function val = getByPath(S, pathStr)
parts = strsplit(char(pathStr), '.');
val = S;

for p = 1:numel(parts)
    f = parts{p};
    if ~isstruct(val) || ~isfield(val, f)
        error('bin2DByGroup:MissingField', ...
            'Missing field path "%s" at "%s".', pathStr, f);
    end
    val = val.(f);
end
end

function varargin = namedStructToVarargin(S)
names = fieldnames(S);
varargin = cell(1, 2*numel(names));
for i = 1:numel(names)
    varargin{2*i-1} = names{i};
    varargin{2*i} = S.(names{i});
end
end

function m = meanWithOmitnan(x, dim)
if nargin < 2
    dim = 1;
end

try
    m = mean(x, dim, 'omitnan');
catch
    x(~isfinite(x)) = NaN;
    n = sum(~isnan(x), dim);
    x(isnan(x)) = 0;
    m = sum(x, dim) ./ n;
    m(n == 0) = NaN;
end
end

function s = stdWithOmitnan(x, flag, dim)
if nargin < 2 || isempty(flag)
    flag = 0;
end
if nargin < 3
    dim = 1;
end

try
    s = std(x, flag, dim, 'omitnan');
catch
    x(~isfinite(x)) = NaN;
    m = meanWithOmitnan(x, dim);
    n = sum(~isnan(x), dim);

    if dim == 1
        mRep = repmat(m, size(x,1), 1);
    else
        mRep = repmat(m, 1, size(x,2));
    end

    d2 = (x - mRep).^2;
    d2(isnan(d2)) = 0;

    if flag == 0
        denom = max(n - 1, 0);
    else
        denom = n;
    end

    s = sqrt(sum(d2, dim) ./ denom);
    s(denom == 0) = NaN;
end
end
