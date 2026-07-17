function h = plotBinned2DByGroup(ax, b, varargin)
%PLOTBINNED2DBYGROUP
% Plot grouped 2D binned data with both X and Y error bars.
%         Version 1.0
%         Date: July 9, 2026
%         Author: G. Herrera 
%         Co-Author/AI Tool: OpenAI ChatGPT (GPT-5.5)
%         Note: The core architecture was designed by the author and implemented by
%           ChatGPT via prompt engineering. All code was reviewed,
%           modified, and verified by the author.
%
% Usage:
%   b = bin2DByGroup(data, 'xVar','volumePct', 'yVar','smoothNerveHz');
%   figure; ax = axes;
%   plotBinned2DByGroup(ax, b);
%
% Name-value options:
%   'minReps'       minimum number of replicates required per bin; default = 1
%   'showXError'    true/false; default = true
%   'showYError'    true/false; default = true
%   'showLine'      true/false; default = true
%   'marker'        marker symbol; default = 'o'
%   'lineWidth'     line width; default = 1.5
%   'capSizeFrac'   cap size as fraction of axis range; default = 0.006
%   'title'         plot title; default = ''
%
% Output:
%   h.line(g)       line handle for each group
%   h.xerr, h.yerr  error bar line handles

if nargin < 1 || isempty(ax)
    figure;
    ax = axes;
end

p = inputParser;
p.FunctionName = 'plotBinned2DByGroup';
p.addParameter('minReps', 1, @(x) isscalar(x) && isnumeric(x) && x >= 1);
p.addParameter('showXError', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('showYError', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('showLine', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('marker', 'o', @(s) ischar(s) || isstring(s));
p.addParameter('lineWidth', 1.5, @(x) isscalar(x) && isnumeric(x) && x > 0);
p.addParameter('capSizeFrac', 0.006, @(x) isscalar(x) && isnumeric(x) && x >= 0);
p.addParameter('title', '', @(s) ischar(s) || isstring(s));
p.parse(varargin{:});
opts = p.Results;

holdState = ishold(ax);
hold(ax, 'on');

nGroups = numel(b.groups);
co = get(ax, 'ColorOrder');
nColors = size(co, 1);

h.line = gobjects(nGroups, 1);
h.xerr = gobjects(0);
h.yerr = gobjects(0);

allX = [];
allY = [];
for g = 1:nGroups
    use = b.groups(g).nRepsUsed >= opts.minReps & ...
          isfinite(b.groups(g).xMean) & isfinite(b.groups(g).yMean);
    allX = [allX; b.groups(g).xMean(use)]; 
    allY = [allY; b.groups(g).yMean(use)]; 
end

if isempty(allX) || isempty(allY)
    warning('plotBinned2DByGroup:NoPlottableData', ...
        'No bins met the plotting criteria.');
    return
end

xRange = max(allX) - min(allX);
yRange = max(allY) - min(allY);
if xRange == 0, xRange = 1; end
if yRange == 0, yRange = 1; end

xCapHalfHeight = opts.capSizeFrac * yRange;
yCapHalfWidth  = opts.capSizeFrac * xRange;

for g = 1:nGroups
    C = co(mod(g-1, nColors) + 1, :);

    x = b.groups(g).xMean(:);
    y = b.groups(g).yMean(:);
    xs = b.groups(g).xSd(:);
    ys = b.groups(g).ySd(:);

    use = b.groups(g).nRepsUsed(:) >= opts.minReps & isfinite(x) & isfinite(y);
    x = x(use);
    y = y(use);
    xs = xs(use);
    ys = ys(use);

    if isempty(x)
        continue
    end

    [x, order] = sort(x);
    y = y(order);
    xs = xs(order);
    ys = ys(order);

    if opts.showXError
        for k = 1:numel(x)
            if isfinite(xs(k)) && xs(k) > 0
                h.xerr(end+1,1) = line(ax, [x(k)-xs(k), x(k)+xs(k)], [y(k), y(k)], ...
                    'Color', C, 'LineWidth', max(0.75, opts.lineWidth * 0.75), ...
                    'HandleVisibility', 'off'); 

                if opts.capSizeFrac > 0
                    h.xerr(end+1,1) = line(ax, [x(k)-xs(k), x(k)-xs(k)], ...
                        [y(k)-xCapHalfHeight, y(k)+xCapHalfHeight], ...
                        'Color', C, 'LineWidth', max(0.75, opts.lineWidth * 0.75), ...
                        'HandleVisibility', 'off'); 
                    h.xerr(end+1,1) = line(ax, [x(k)+xs(k), x(k)+xs(k)], ...
                        [y(k)-xCapHalfHeight, y(k)+xCapHalfHeight], ...
                        'Color', C, 'LineWidth', max(0.75, opts.lineWidth * 0.75), ...
                        'HandleVisibility', 'off'); 
                end
            end
        end
    end

    if opts.showYError
        for k = 1:numel(x)
            if isfinite(ys(k)) && ys(k) > 0
                h.yerr(end+1,1) = line(ax, [x(k), x(k)], [y(k)-ys(k), y(k)+ys(k)], ...
                    'Color', C, 'LineWidth', max(0.75, opts.lineWidth * 0.75), ...
                    'HandleVisibility', 'off'); 

                if opts.capSizeFrac > 0
                    h.yerr(end+1,1) = line(ax, [x(k)-yCapHalfWidth, x(k)+yCapHalfWidth], ...
                        [y(k)-ys(k), y(k)-ys(k)], ...
                        'Color', C, 'LineWidth', max(0.75, opts.lineWidth * 0.75), ...
                        'HandleVisibility', 'off'); 
                    h.yerr(end+1,1) = line(ax, [x(k)-yCapHalfWidth, x(k)+yCapHalfWidth], ...
                        [y(k)+ys(k), y(k)+ys(k)], ...
                        'Color', C, 'LineWidth', max(0.75, opts.lineWidth * 0.75), ...
                        'HandleVisibility', 'off'); 
                end
            end
        end
    end

    if opts.showLine
        lineStyle = '-';
    else
        lineStyle = 'none';
    end

    h.line(g) = plot(ax, x, y, ...
        'LineStyle', lineStyle, ...
        'Marker', char(opts.marker), ...
        'Color', C, ...
        'MarkerFaceColor', C, ...
        'LineWidth', opts.lineWidth, ...
        'DisplayName', char(b.groups(g).groupKey));
end

xlabel(ax, b.xLabel, 'Interpreter', 'none');
ylabel(ax, b.yLabel, 'Interpreter', 'none');

if strlength(string(opts.title)) > 0
    title(ax, char(opts.title), 'Interpreter', 'none');
end

legend(ax, 'show', 'Interpreter', 'none', 'Location', 'best');
box(ax, 'on');

if ~holdState
    hold(ax, 'off');
end

end
