function dict = getConditionDictionary()
% getConditionDictionary  Returns condition dictionary (defaults + user customizations).
%
%         Version 1.0
%         Date: July 10, 2026
%         Author: G. Herrera 
%         Co-Author/AI Tool: OpenAI ChatGPT (GPT-5.5)
%         Note: The core architecture was designed by the author and implemented by
%           ChatGPT via prompt engineering. All code was reviewed,
%           modified, and verified by the author.
%
% Stores user customizations in:
%   fullfile(prefdir, 'AfferentNerveAnalysis_ConditionDict.mat')

    prefFile = fullfile(prefdir, 'AfferentNerveAnalysis_ConditionDict.mat');

    dict = defaultConditionDictionary();

    % Merge user dictionary if it exists
    if isfile(prefFile)
        S = load(prefFile, 'userDict');
        if isfield(S,'userDict') && isstruct(S.userDict)
            dict = mergeConditionDict(dict, S.userDict);
        end
    end
end

% ----------------- DEFAULTS (edit once, rarely) -----------------

function dict = defaultConditionDictionary()
% Default canonical labels and synonyms (your current set).

    dict = struct();

    dict.canonical = { ...
        'Control', ...
        'Indomethacin', ...
        'GSK10nMBath', ...
        'GSK100nMBath', ...
        'GSK100nMBathLumen', ...
        'Diltiazem50uM', ...
        'Diltiazem100uM', ...
        'Thapsigargin100nM', ...
        'Thapsigargin1uM' ...
    };

    dict.synonyms = struct();

    dict.synonyms.Control = { ...
        'control','ctrl','vehicle','veh', ...
        'baseline','base','bl' ...
    };

    dict.synonyms.Indomethacin = { ...
        'indomethacin','indom','indo' ...
    };

    dict.synonyms.GSK10nMBath = { ...
        'gsk10nmbath','gsk 10nmbath','gsk 10 nm bath','gsk10nm bath', ...
        'gsk10nm','gsk10 nm','gsk 10 nm' ...
    };

    dict.synonyms.GSK100nMBath = { ...
        'gsk100nmbath','gsk 100nmbath','gsk 100 nm bath','gsk100nm bath', ...
        'gsk100nm','gsk100 nm','gsk 100 nm' ...
    };

    dict.synonyms.GSK100nMBathLumen = { ...
        'gsk100nmbathlumen','gsk 100nmbathlumen', ...
        'gsk100nmlumen','gsk100 nm lumen','gsk 100 nm lumen', ...
        'gsk100nmbath lumen','gsk100nm bath lumen' ...
    };

    dict.synonyms.Diltiazem50uM = { ...
        'diltiazem50um','diltiazem 50um','diltiazem 50 um', ...
        'dilt50um','dilt 50um','dilt 50 um' ...
    };

    dict.synonyms.Diltiazem100uM = { ...
        'diltiazem100um','diltiazem 100um','diltiazem 100 um', ...
        'dilt100um','dilt 100um','dilt 100 um' ...
    };

    dict.synonyms.Thapsigargin100nM = { ...
        'thapsigargin100nm','thapsigargin 100nm','thapsigargin 100 nm', ...
        'thapsi100nm','thapsi 100nm','thapsi 100 nm' ...
    };

    dict.synonyms.Thapsigargin1uM = { ...
        'thapsigargin1um','thapsigargin 1um','thapsigargin 1 um', ...
        'thapsi1um','thapsi 1um','thapsi 1 um' ...
    };

    % Allow embedded matching for everything by default
    dict.allowEmbedded = dict.canonical;
end

% ----------------- MERGE HELPERS -----------------

function out = mergeConditionDict(base, extra)
% Merge extra dict into base dict, dedupe canonical list and synonyms.

    out = base;

    if isfield(extra,'canonical') && ~isempty(extra.canonical)
        out.canonical = unique([out.canonical(:); extra.canonical(:)], 'stable')';
    end

    if ~isfield(out,'synonyms') || ~isstruct(out.synonyms)
        out.synonyms = struct();
    end

    if isfield(extra,'synonyms') && isstruct(extra.synonyms)
        extraFields = fieldnames(extra.synonyms);
        for k = 1:numel(extraFields)
            label = extraFields{k};
            syns  = extra.synonyms.(label);
            if ~iscell(syns), syns = cellstr(syns); end

            if isfield(out.synonyms, label)
                out.synonyms.(label) = unique([out.synonyms.(label)(:); syns(:)], 'stable')';
            else
                out.synonyms.(label) = syns(:)';
            end
        end
    end

    if isfield(extra,'allowEmbedded')
        out.allowEmbedded = unique([out.allowEmbedded(:); extra.allowEmbedded(:)], 'stable')';
    end
end
