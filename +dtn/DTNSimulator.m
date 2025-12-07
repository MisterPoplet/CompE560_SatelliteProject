classdef DTNSimulator < handle
    % DTNSimulator - core DTN scenario engine (no UI)
    %
    % Runs a single scenario:
    %   - store-carry-forward bundles
    %   - Epidemic-style forwarding (for now)
    %   - PHY-based range limit + Earth occlusion (LOS)
    %   - logs all forwarding and deliveries
    
    properties
        % Scenario config
        srcName        char
        dstName        char
        numBundles     double
        routing        char      % 'Epidemic' | 'PRoPHET' | 'SprayAndWait'
        phyMode        char      % 'SBand' | 'KaBand' | 'SatelliteRF'
        startTime      datetime
        horizonMinutes double    % total duration (minutes)
        stepSeconds    double    % step size (seconds)
        ttlMinutes     double    % TTL (unused for now, but stored)
        realTimeSpeed  double    % playback speed (x real time; 0 => as fast as possible)
        packetSizeBytes double   % bundle size (bytes)
        
        % State
        bundles        struct = struct('id',{}, 'src',{}, 'dst',{}, ...
                                       'holders',{}, 'delivered',{}, ...
                                       'deliveredTime',{}, 'numHops',{});
        logLines       cell   = {}
        logCallback                    % optional GUI callback (function handle or [])
    end
    
    methods
        function obj = DTNSimulator(cfg)
            % cfg is a struct with fields:
            %   srcName, dstName, numBundles, routing, phyMode,
            %   startTime, horizonMinutes, stepSeconds, realTimeSpeed,
            %   ttlMinutes, packetSizeBytes
            
            obj.srcName        = cfg.srcName;
            obj.dstName        = cfg.dstName;
            obj.numBundles     = cfg.numBundles;
            obj.routing        = cfg.routing;
            obj.phyMode        = cfg.phyMode;
            obj.startTime      = cfg.startTime;
            obj.horizonMinutes = cfg.horizonMinutes;
            obj.stepSeconds    = cfg.stepSeconds;
            obj.ttlMinutes     = cfg.ttlMinutes;
            obj.realTimeSpeed  = cfg.realTimeSpeed;
            obj.packetSizeBytes = cfg.packetSizeBytes;
            
            obj.logLines    = {};
            obj.logCallback = [];
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
            
            nodes     = scenarioManager.nodes;
            nodeNames = {nodes.name};
            nNodes    = numel(nodes);
            
            % Map node names to indices
            nameToIdx = containers.Map();
            for i = 1:nNodes
                nameToIdx(nodeNames{i}) = i;
            end
            
            % Lookup indices for src/dst
            if ~isKey(nameToIdx, obj.srcName)
                error('Source node %s not found.', obj.srcName);
            end
            if ~isKey(nameToIdx, obj.dstName)
                error('Destination node %s not found.', obj.dstName);
            end
            
            % Initialize bundles (preallocate with final struct shape)
            proto = struct('id',0, 'src','', 'dst','', ...
                           'holders',{{}}, 'delivered',false, ...
                           'deliveredTime',NaT, 'numHops',0);
            obj.bundles = repmat(proto, 1, obj.numBundles);
            for b = 1:obj.numBundles
                obj.bundles(b).id            = b;
                obj.bundles(b).src           = obj.srcName;
                obj.bundles(b).dst           = obj.dstName;
                obj.bundles(b).holders       = {obj.srcName};
                obj.bundles(b).delivered     = false;
                obj.bundles(b).deliveredTime = NaT;
                obj.bundles(b).numHops       = 0;
            end
            
            profile = dtn.PHYProfiles.getProfile(obj.phyMode);
            
            obj.appendLog(sprintf('--- Scenario start: %s -> %s, bundles=%d, routing=%s, PHY=%s ---', ...
                obj.srcName, obj.dstName, obj.numBundles, obj.routing, profile.name));
            
            if ~strcmp(obj.routing, 'Epidemic')
                obj.appendLog(sprintf('NOTE: routing "%s" not yet implemented; using Epidemic behavior.', ...
                    obj.routing));
            end
            
            totalSeconds = obj.horizonMinutes * 60;
            nSteps = floor(totalSeconds / obj.stepSeconds);
            if nSteps < 1
                nSteps = 1;
            end
            
            % Main time-stepped loop
            for step = 1:nSteps
                t = obj.startTime + seconds((step-1)*obj.stepSeconds);
                
                % Move viewer time, if provided
                if ~isempty(viewer) && isvalid(viewer)
                    try
                        viewer.CurrentTime = t;
                    catch
                    end
                end
                
                % Compute node positions / adjacency using states() for all nodes
                [x, y, z] = obj.computeNodeXYZ(scenarioManager, nodeNames, t);
                
                % Connectivity matrix based on PHY range AND LOS
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
                allDelivered = true;
                for b = 1:numel(obj.bundles)
                    if obj.bundles(b).delivered
                        continue;
                    end
                    allDelivered = false;
                    
                    holders    = obj.bundles(b).holders;
                    newHolders = holders;
                    
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
                            
                            % Epidemic-like forward
                            newHolders{end+1} = neighName; %#ok<AGROW>
                            obj.bundles(b).numHops = obj.bundles(b).numHops + 1;
                            obj.appendLog(sprintf('t=%s: bundle %d forwarded %s -> %s', ...
                                datestr(t, 'dd-mmm-yyyy HH:MM:SS.FFF'), ...
                                obj.bundles(b).id, hName, neighName));
                        end
                    end
                    
                    obj.bundles(b).holders = unique(newHolders);
                    
                    % Check delivery
                    if any(strcmp(obj.bundles(b).holders, obj.dstName))
                        if ~obj.bundles(b).delivered
                            obj.bundles(b).delivered     = true;
                            obj.bundles(b).deliveredTime = t;
                            obj.appendLog(sprintf('t=%s: bundle %d DELIVERED at %s', ...
                                datestr(t, 'dd-mmm-yyyy HH:MM:SS.FFF'), ...
                                obj.bundles(b).id, obj.dstName));
                        end
                    end
                end
                
                drawnow;  % let viewer refresh
                
                % Real-time playback: pause according to speed factor
                if obj.realTimeSpeed > 0
                    pause(obj.stepSeconds / obj.realTimeSpeed);
                end
                
                if allDelivered
                    break;
                end
            end
            
            deliveredCount = sum([obj.bundles.delivered]);
            obj.appendLog(sprintf('--- Scenario end: %d/%d bundles delivered ---', ...
                deliveredCount, numel(obj.bundles)));
            
            % PHY-based per-hop delay (one-way) for bundles
            packetBits = obj.packetSizeBytes * 8;
            hopDelay_s = packetBits / profile.dataRate_bps + profile.handshakeOverhead_s;
            
            % Per-bundle delay summary (relative to scenario start)
            for b = 1:numel(obj.bundles)
                if obj.bundles(b).delivered
                    baseDelay_s   = seconds(obj.bundles(b).deliveredTime - obj.startTime);
                    protoDelay_s  = obj.bundles(b).numHops * hopDelay_s;
                    totalDelay_s  = baseDelay_s + protoDelay_s;
                    obj.appendLog(sprintf(['Bundle %d delivery delay: %.6f s ' ...
                                           '(path=%.3f s, PHY-extra=%.6f s, hops=%d, PHY=%s)'], ...
                        obj.bundles(b).id, totalDelay_s, baseDelay_s, ...
                        protoDelay_s, obj.bundles(b).numHops, profile.name));
                else
                    obj.appendLog(sprintf('Bundle %d NOT delivered within horizon.', ...
                        obj.bundles(b).id));
                end
            end
            
            bundles  = obj.bundles;
            logLines = obj.logLines;
        end
    end
    
    methods (Access = private)
        function [x, y, z] = computeNodeXYZ(obj, scenarioManager, nodeNames, t)
            % computeNodeXYZ - get node positions for distance calculations
            %
            % Uses ScenarioManager.getXYZ() so geometry matches ping and
            % the satellite viewer (for sats; GS are spherical Earth).
            
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
            ReKm = 6350;              % spherical Earth radius
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
