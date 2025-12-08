classdef DTNSimulator < handle
    % DTNSimulator - core DTN scenario engine (no UI)
    %
    % Runs a single scenario:
    %   - store-carry-forward bundles
    %   - Epidemic / PRoPHET-like / Spray-and-Wait routing
    %   - PHY-based range limit + Earth occlusion (LOS)
    %   - TTL per bundle (measured from releaseTime)
    %   - Per-bundle release times and per-bundle src/dst
    %   - Simulation start offset
    %   - Logs all forwarding, deliveries, expiries, and unfinished bundles
    
    properties
        % Scenario config
        srcName        char      % global label only (may be 'mixed')
        dstName        char
        numBundles     double
        routing        char      % 'Epidemic' | 'PRoPHET' | 'SprayAndWait'
        phyMode        char      % 'SBand' | 'KaBand' | 'SatelliteRF'
        startTime      datetime
        horizonMinutes double    % total duration (minutes) from startTime
        stepSeconds    double    % step size (seconds)
        ttlMinutes     double    % TTL (minutes, 0 => disabled)
        realTimeSpeed  double    % playback speed (x real time; 0 => as fast as possible)
        packetSizeBytes double   % bundle size (bytes)
        
        simStartOffsetMinutes       double   % when DTN sim starts (min from startTime)
        bundleReleaseOffsetsMinutes double   % per-bundle release offsets (min from startTime)
        bundleSrcNames              cell     % 1xN cell array of sources
        bundleDstNames              cell     % 1xN cell array of destinations
        
        stopRequested  logical = false
        
        % State
        bundles        struct = struct('id',{}, 'src',{}, 'dst',{}, ...
                                       'holders',{}, 'delivered',{}, ...
                                       'deliveredTime',{}, 'numHops',{}, ...
                                       'expired',{}, 'expiredTime',{}, ...
                                       'releaseTime',{}, 'born',{}, ...
                                       'maxCopies',{}, 'copiesUsed',{});
        logLines       cell   = {}
        logCallback                    % optional GUI callback (function handle or [])
    end
    
    methods
        function obj = DTNSimulator(cfg)
            % cfg is a struct with fields:
            %   srcName, dstName, numBundles, routing, phyMode,
            %   startTime, horizonMinutes, stepSeconds, realTimeSpeed,
            %   ttlMinutes, packetSizeBytes,
            %   bundleReleaseOffsetsMinutes, bundleSrcNames, bundleDstNames,
            %   simStartOffsetMinutes
            
            if isfield(cfg, 'srcName')
                obj.srcName = cfg.srcName;
            else
                obj.srcName = 'mixed';
            end
            if isfield(cfg, 'dstName')
                obj.dstName = cfg.dstName;
            else
                obj.dstName = 'mixed';
            end
            
            obj.numBundles      = cfg.numBundles;
            obj.routing         = cfg.routing;
            obj.phyMode         = cfg.phyMode;
            obj.startTime       = cfg.startTime;
            obj.horizonMinutes  = cfg.horizonMinutes;
            obj.stepSeconds     = cfg.stepSeconds;
            obj.ttlMinutes      = cfg.ttlMinutes;
            obj.realTimeSpeed   = cfg.realTimeSpeed;
            obj.packetSizeBytes = cfg.packetSizeBytes;
            
            if isfield(cfg, 'simStartOffsetMinutes')
                obj.simStartOffsetMinutes = cfg.simStartOffsetMinutes;
            else
                obj.simStartOffsetMinutes = 0;
            end
            
            if isfield(cfg, 'bundleReleaseOffsetsMinutes')
                obj.bundleReleaseOffsetsMinutes = cfg.bundleReleaseOffsetsMinutes(:).';
            else
                obj.bundleReleaseOffsetsMinutes = 0;
            end
            
            if isfield(cfg, 'bundleSrcNames')
                obj.bundleSrcNames = cfg.bundleSrcNames;
            else
                obj.bundleSrcNames = repmat({obj.srcName}, 1, obj.numBundles);
            end
            
            if isfield(cfg, 'bundleDstNames')
                obj.bundleDstNames = cfg.bundleDstNames;
            else
                obj.bundleDstNames = repmat({obj.dstName}, 1, obj.numBundles);
            end
            
            obj.logLines    = {};
            obj.logCallback = [];
        end
        
        function requestStop(obj)
            % requestStop - ask the simulator to stop at the next step
            obj.stopRequested = true;
        end
        
        function [bundles, logLines] = run(obj, scenarioManager, viewer)
            % run - execute the scenario using the given ScenarioManager
            %
            % Inputs:
            %   scenarioManager - dtn.ScenarioManager
            %   viewer          - satelliteScenarioViewer handle (or [])
            %
            % Outputs:
            %   bundles   - final bundle array
            %   logLines  - cell array of log strings

            % Reset stop flag at the beginning of every run
            obj.stopRequested = false;
            
            nodes     = scenarioManager.nodes;
            nodeNames = {nodes.name};
            nNodes    = numel(nodes);
            
            % Map node names to indices
            nameToIdx = containers.Map();
            for i = 1:nNodes
                nameToIdx(nodeNames{i}) = i;
            end
            
            % Prepare bundle release offsets
            if numel(obj.bundleReleaseOffsetsMinutes) == 1
                offsetsMin = repmat(obj.bundleReleaseOffsetsMinutes, 1, obj.numBundles);
            else
                offsetsMin = obj.bundleReleaseOffsetsMinutes;
                if numel(offsetsMin) < obj.numBundles
                    last = offsetsMin(end);
                    offsetsMin(end+1:obj.numBundles) = last;
                elseif numel(offsetsMin) > obj.numBundles
                    offsetsMin = offsetsMin(1:obj.numBundles);
                end
            end
            
            % Initialize bundles
            proto = struct('id',0, 'src','', 'dst','', ...
                           'holders',{{}}, 'delivered',false, ...
                           'deliveredTime',NaT, 'numHops',0, ...
                           'expired',false, 'expiredTime',NaT, ...
                           'releaseTime',NaT, 'born',false, ...
                           'maxCopies',0, 'copiesUsed',0);
            obj.bundles = repmat(proto, 1, obj.numBundles);
            for b = 1:obj.numBundles
                srcName = char(obj.bundleSrcNames{b});
                dstName = char(obj.bundleDstNames{b});
                
                if ~isKey(nameToIdx, srcName)
                    error('Bundle %d source node "%s" not found.', b, srcName);
                end
                if ~isKey(nameToIdx, dstName)
                    error('Bundle %d destination node "%s" not found.', b, dstName);
                end
                
                bd               = proto;
                bd.id            = b;
                bd.src           = srcName;
                bd.dst           = dstName;
                bd.holders       = {};  % empty until release
                bd.delivered     = false;
                bd.deliveredTime = NaT;
                bd.numHops       = 0;
                bd.expired       = false;
                bd.expiredTime   = NaT;
                bd.releaseTime   = obj.startTime + minutes(offsetsMin(b));
                bd.born          = false;
                
                % Spray-and-Wait copy limits (simplified L-copies version)
                if strcmp(obj.routing, 'SprayAndWait')
                    bd.maxCopies  = 8;   % total distinct nodes that can ever hold this bundle
                    bd.copiesUsed = 0;   % will set to 1 at birth when src gets copy
                else
                    bd.maxCopies  = 0;   % 0 => unlimited (Epidemic / PRoPHET)
                    bd.copiesUsed = 0;
                end
                
                obj.bundles(b) = bd;
            end
            
            profile = dtn.PHYProfiles.getProfile(obj.phyMode);
            
            obj.appendLog(sprintf('--- Scenario start: bundle-specific src/dst, bundles=%d, routing=%s, PHY=%s ---', ...
                obj.numBundles, obj.routing, profile.name));
            obj.appendLog('[INFO] Scenario running: use Scenario tab playback speed; avoid satellite viewer play/pause/arrow controls during run.');
            
            if ~ismember(obj.routing, {'Epidemic','PRoPHET','SprayAndWait'})
                obj.appendLog(sprintf('NOTE: routing "%s" not recognized; using Epidemic-like behavior.', ...
                    obj.routing));
            end
            
            % Effective time span for DTN sim (in seconds) after simStartOffset
            totalSeconds = obj.horizonMinutes * 60 - obj.simStartOffsetMinutes * 60;
            if totalSeconds <= 0
                obj.appendLog('WARNING: Horizon minutes <= simStartOffsetMinutes; nothing to simulate.');
                bundles  = obj.bundles;
                logLines = obj.logLines;
                return;
            end
            
            nSteps = floor(totalSeconds / obj.stepSeconds);
            if nSteps < 1
                nSteps = 1;
            end
            
            % TTL in seconds (0 => TTL disabled)
            ttlSec = obj.ttlMinutes * 60;
            useTTL = ttlSec > 0;
            
            % Rendering decimation for higher speeds
            renderInterval = 1;
            if obj.realTimeSpeed > 20
                renderInterval = 5;
            end
            if obj.realTimeSpeed > 50
                renderInterval = 20;
            end
            if obj.realTimeSpeed > 100
                renderInterval = 50;
            end
            
            simStartOffsetSec = obj.simStartOffsetMinutes * 60;
            simEndTime = obj.startTime + minutes(obj.horizonMinutes);
            
            % Main time-stepped loop
            for step = 1:nSteps
                t = obj.startTime + seconds(simStartOffsetSec + (step-1)*obj.stepSeconds);
                
                % Compute node positions / adjacency
                [x, y, z] = obj.computeNodeXYZ(scenarioManager, nodeNames, t);
                
                connected = false(nNodes, nNodes);
                for i = 1:nNodes
                    for j = i+1:nNodes
                        p1 = [x(i) y(i) z(i)];
                        p2 = [x(j) y(j) z(j)];
                        dKm = norm(p1 - p2);
                        
                        % Earth occlusion
                        if ~obj.hasLOSFromXYZ(p1, p2)
                            continue;
                        end
                        
                        % PHY range
                        if dKm <= profile.maxRangeKm
                            connected(i,j) = true;
                            connected(j,i) = true;
                        end
                    end
                end
                
                % Forward bundles
                allDone = true;  % assume done until we see active/pending ones
                
                for b = 1:numel(obj.bundles)
                    bd = obj.bundles(b);
                    
                    % If releaseTime is after sim end, this bundle will never be simulated;
                    % treat it as "done" for early-stop purposes (logged later).
                    if bd.releaseTime > simEndTime
                        obj.bundles(b) = bd;
                        continue;
                    end
                    
                    % Not yet born?
                    if ~bd.born
                        if t < bd.releaseTime
                            % Waiting to be born; scenario not done yet
                            allDone = false;
                            obj.bundles(b) = bd;
                            continue;
                        end
                        
                        % Birth moment
                        bd.born    = true;
                        bd.holders = {bd.src};
                        if bd.maxCopies > 0 && bd.copiesUsed == 0
                            % Source now holds one copy
                            bd.copiesUsed = 1;
                        end
                        obj.appendLog(sprintf('t=%s: bundle %d RELEASED at %s (dst=%s)', ...
                            datestr(t, 'dd-mmm-yyyy HH:MM:SS.FFF'), ...
                            bd.id, bd.src, bd.dst));
                    end
                    
                    % Now bd.born==true
                    if bd.delivered || bd.expired
                        % Already finished; leave allDone as is (could be false from others)
                        obj.bundles(b) = bd;
                        continue;
                    end
                    
                    % At this point, bundle is active; scenario not done
                    allDone = false;
                    
                    % TTL check relative to releaseTime
                    if useTTL
                        ageSec = seconds(t - bd.releaseTime);
                        if ageSec > ttlSec
                            bd.expired     = true;
                            bd.expiredTime = t;
                            obj.appendLog(sprintf('t=%s: bundle %d EXPIRED (TTL=%.1f s)', ...
                                datestr(t, 'dd-mmm-yyyy HH:MM:SS.FFF'), ...
                                bd.id, ttlSec));
                            obj.bundles(b) = bd;
                            continue;
                        end
                    end
                    
                    holders    = bd.holders;
                    newHolders = holders;
                    
                    % --- Routing behavior ---
                    routeMode = obj.routing;
                    if ~ismember(routeMode, {'Epidemic','PRoPHET','SprayAndWait'})
                        routeMode = 'Epidemic';  % fallback
                    end
                    
                    % For PRoPHET/Spray, we need distances to this bundle's destination
                    idxDst = nameToIdx(bd.dst);
                    dstPos = [x(idxDst) y(idxDst) z(idxDst)];
                    distToDstKm = zeros(1, nNodes);
                    for i = 1:nNodes
                        distToDstKm(i) = norm([x(i) y(i) z(i)] - dstPos);
                    end
                    
                    switch routeMode
                        case 'Epidemic'
                            % Flood to all neighbors that don't yet hold the bundle
                            for hIdx = 1:numel(holders)
                                hName = holders{hIdx};
                                i = nameToIdx(hName);
                                
                                for j = 1:nNodes
                                    if ~connected(i,j)
                                        continue;
                                    end
                                    neighName = nodeNames{j};
                                    
                                    if any(strcmp(newHolders, neighName))
                                        continue;
                                    end
                                    
                                    newHolders{end+1} = neighName; %#ok<AGROW>
                                    bd.numHops = bd.numHops + 1;
                                    obj.appendLog(sprintf('t=%s: bundle %d forwarded %s -> %s', ...
                                        datestr(t, 'dd-mmm-yyyy HH:MM:SS.FFF'), ...
                                        bd.id, hName, neighName));
                                end
                            end
                            
                        case 'PRoPHET'
                            % Simplified PRoPHET:
                            % For each holder, forward only to ONE neighbor (the closest
                            % to dst) that is closer to dst than the holder and doesn't
                            % already have the bundle.
                            for hIdx = 1:numel(holders)
                                hName = holders{hIdx};
                                i = nameToIdx(hName);
                                
                                dHolder = distToDstKm(i);
                                bestJ   = [];
                                bestD   = Inf;
                                
                                for j = 1:nNodes
                                    if ~connected(i,j)
                                        continue;
                                    end
                                    neighName = nodeNames{j};
                                    
                                    if any(strcmp(newHolders, neighName))
                                        continue;
                                    end
                                    
                                    dNeigh = distToDstKm(j);
                                    
                                    % Only neighbors strictly closer to dst
                                    if dNeigh < dHolder && dNeigh < bestD
                                        bestD = dNeigh;
                                        bestJ = j;
                                    end
                                end
                                
                                if ~isempty(bestJ)
                                    neighName = nodeNames{bestJ};
                                    newHolders{end+1} = neighName; %#ok<AGROW>
                                    bd.numHops = bd.numHops + 1;
                                    obj.appendLog(sprintf('t=%s: bundle %d forwarded %s -> %s (PRoPHET-like)', ...
                                        datestr(t, 'dd-mmm-yyyy HH:MM:SS.FFF'), ...
                                        bd.id, hName, neighName));
                                end
                            end
                            
                        case 'SprayAndWait'
                            % Simplified L-copies Spray-and-Wait:
                            % - total distinct nodes that can ever have this bundle = maxCopies
                            % - each new node consumes one copy from the budget
                            if bd.maxCopies <= 0
                                % Fallback: behave like Epidemic if not configured
                                for hIdx = 1:numel(holders)
                                    hName = holders{hIdx};
                                    i = nameToIdx(hName);
                                    
                                    for j = 1:nNodes
                                        if ~connected(i,j)
                                            continue;
                                        end
                                        neighName = nodeNames{j};
                                        
                                        if any(strcmp(newHolders, neighName))
                                            continue;
                                        end
                                        
                                        newHolders{end+1} = neighName; %#ok<AGROW>
                                        bd.numHops = bd.numHops + 1;
                                        obj.appendLog(sprintf('t=%s: bundle %d forwarded %s -> %s (Spray fallback)', ...
                                            datestr(t, 'dd-mmm-yyyy HH:MM:SS.FFF'), ...
                                            bd.id, hName, neighName));
                                    end
                                end
                            else
                                % Limited copies:
                                % For each holder, forward to ONE neighbor that is closer
                                % to dst, and only while copiesUsed < maxCopies.
                                for hIdx = 1:numel(holders)
                                    hName = holders{hIdx};
                                    i = nameToIdx(hName);
                                    
                                    % If we've already exhausted the copy budget, stop.
                                    if bd.copiesUsed >= bd.maxCopies
                                        break;
                                    end
                                    
                                    dHolder = distToDstKm(i);
                                    bestJ   = [];
                                    bestD   = Inf;
                                    
                                    for j = 1:nNodes
                                        if ~connected(i,j)
                                            continue;
                                        end
                                        neighName = nodeNames{j};
                                        
                                        if any(strcmp(newHolders, neighName))
                                            continue;
                                        end
                                        
                                        dNeigh = distToDstKm(j);
                                        if dNeigh < dHolder && dNeigh < bestD
                                            bestD = dNeigh;
                                            bestJ = j;
                                        end
                                    end
                                    
                                    if ~isempty(bestJ) && bd.copiesUsed < bd.maxCopies
                                        neighName = nodeNames{bestJ};
                                        newHolders{end+1} = neighName; %#ok<AGROW>
                                        bd.numHops   = bd.numHops + 1;
                                        bd.copiesUsed = bd.copiesUsed + 1;
                                        
                                        obj.appendLog(sprintf('t=%s: bundle %d forwarded %s -> %s (Spray-and-Wait, copy %d/%d)', ...
                                            datestr(t, 'dd-mmm-yyyy HH:MM:SS.FFF'), ...
                                            bd.id, hName, neighName, ...
                                            bd.copiesUsed, bd.maxCopies));
                                    end
                                end
                            end
                    end
                    
                    bd.holders = unique(newHolders);
                    
                    % Check delivery to per-bundle destination
                    if any(strcmp(bd.holders, bd.dst))
                        if ~bd.delivered
                            bd.delivered     = true;
                            bd.deliveredTime = t;
                            obj.appendLog(sprintf('t=%s: bundle %d DELIVERED at %s', ...
                                datestr(t, 'dd-mmm-yyyy HH:MM:SS.FFF'), ...
                                bd.id, bd.dst));
                        end
                    end
                    
                    obj.bundles(b) = bd;
                end
                
                % Update viewer & draw only every renderInterval steps
                doRender = (mod(step-1, renderInterval) == 0);
                if ~isempty(viewer) && isvalid(viewer) && doRender
                    try
                        viewer.CurrentTime = t;
                    catch
                    end
                end
                if doRender
                    drawnow limitrate;
                end
                
                % Real-time playback: pause according to speed factor
                if obj.realTimeSpeed > 0
                    pause(obj.stepSeconds / obj.realTimeSpeed);
                else
                    % 0 => run as fast as possible; tiny pause to keep GUI responsive
                    pause(0);
                end
                
                % Stop early if all bundles are done
                if allDone
                    break;
                end
                
                % Stop early if user requested
                if obj.stopRequested
                    obj.appendLog('--- Scenario stopped by user ---');
                    break;
                end
            end
            
            % Summary
            deliveredMask  = [obj.bundles.delivered];
            deliveredCount = sum(deliveredMask);
            
            obj.appendLog(sprintf('--- Scenario end: %d/%d bundles delivered ---', ...
                deliveredCount, numel(obj.bundles)));
            
            % PHY-based per-hop delay (one-way) for bundles
            profile     = dtn.PHYProfiles.getProfile(obj.phyMode);
            packetBits  = obj.packetSizeBytes * 8;
            hopDelay_s  = packetBits / profile.dataRate_bps + profile.handshakeOverhead_s;
            
            simEndTime = obj.startTime + minutes(obj.horizonMinutes);
            ttlSec  = obj.ttlMinutes * 60;
            useTTL  = ttlSec > 0;
            
            % Per-bundle delay summary
            for b = 1:numel(obj.bundles)
                bd = obj.bundles(b);
                if bd.delivered
                    % Delay measured from releaseTime
                    baseDelay_s   = seconds(bd.deliveredTime - bd.releaseTime);
                    protoDelay_s  = bd.numHops * hopDelay_s;
                    totalDelay_s  = baseDelay_s + protoDelay_s;
                    obj.appendLog(sprintf(['Bundle %d delivery delay: %.6f s ' ...
                                           '(path=%.3f s, PHY-extra=%.6f s, hops=%d, PHY=%s, ' ...
                                           'release=%s, delivered=%s, src=%s, dst=%s)'], ...
                        bd.id, totalDelay_s, baseDelay_s, ...
                        protoDelay_s, bd.numHops, profile.name, ...
                        datestr(bd.releaseTime), datestr(bd.deliveredTime), ...
                        bd.src, bd.dst));
                elseif bd.expired && useTTL
                    obj.appendLog(sprintf(['Bundle %d expired due to TTL (%.1f s) ' ...
                                           'before delivery (release=%s, expired=%s, src=%s, dst=%s).'], ...
                        bd.id, ttlSec, ...
                        datestr(bd.releaseTime), datestr(bd.expiredTime), ...
                        bd.src, bd.dst));
                else
                    % Not delivered and not TTL-expired by horizon
                    if bd.releaseTime > simEndTime
                        obj.appendLog(sprintf(['Bundle %d NOT simulated: release time %s ' ...
                                               'is after simulation end %s (src=%s, dst=%s).'], ...
                            bd.id, datestr(bd.releaseTime), datestr(simEndTime), ...
                            bd.src, bd.dst));
                    else
                        obj.appendLog(sprintf(['Bundle %d NOT delivered within horizon ' ...
                                               '(release=%s, sim end=%s, src=%s, dst=%s).'], ...
                            bd.id, datestr(bd.releaseTime), datestr(simEndTime), ...
                            bd.src, bd.dst));
                    end
                end
            end
            
            bundles  = obj.bundles;
            logLines = obj.logLines;
        end
    end
    
    methods (Access = private)
        function [x, y, z] = computeNodeXYZ(obj, scenarioManager, nodeNames, t)
            % computeNodeXYZ - get node positions for distance calculations
            % Uses ScenarioManager.getXYZ() so geometry matches ping + viewer.
            
            nNodes = numel(nodeNames);
            x = zeros(1, nNodes);
            y = zeros(1, nNodes);
            z = zeros(1, nNodes);
            
            for i = 1:nNodes
                [x(i), y(i), z(i)] = scenarioManager.getXYZ(nodeNames{i}, t);
            end
        end
        
        function tf = hasLOSFromXYZ(obj, p1Km, p2Km)
            % hasLOSFromXYZ - geometric line-of-sight test vs Earth sphere
            % Slightly smaller radius to align better with access() horizon
            ReKm = 6350;
            d    = p2Km - p1Km;
            r1   = p1Km;
            
            a = dot(d,d);
            b = 2*dot(r1,d);
            c = dot(r1,r1) - ReKm^2;
            
            disc = b^2 - 4*a*c;
            if disc <= 0
                tf = true;
                return;
            end
            
            s1 = (-b - sqrt(disc)) / (2*a);
            s2 = (-b + sqrt(disc)) / (2*a);
            
            if (s1 >= 0 && s1 <= 1) || (s2 >= 0 && s2 <= 1)
                tf = false;
            else
                tf = true;
            end
        end
        
        function appendLog(obj, msg)
            % Store in internal log
            obj.logLines{end+1} = msg;
            
            % Stream to GUI if callback is set
            if ~isempty(obj.logCallback)
                try
                    obj.logCallback(msg);
                catch
                    % ignore GUI errors so sim can keep running
                end
            end
        end
    end
end
