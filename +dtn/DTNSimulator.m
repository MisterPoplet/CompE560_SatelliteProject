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
        horizonMinutes double    % total duration
        stepMinutes    double    % step size
        ttlMinutes     double    % TTL (unused for now, but stored)
        
        % State
        bundles        struct = struct('id',{}, 'src',{}, 'dst',{}, ...
                                       'holders',{}, 'delivered',{}, ...
                                       'deliveredTime',{});
        logLines       cell   = {}
    end
    
    methods
        function obj = DTNSimulator(cfg)
            % cfg is a struct with fields:
            %   srcName, dstName, numBundles, routing, phyMode,
            %   startTime, horizonMinutes, stepMinutes, ttlMinutes
            
            obj.srcName        = cfg.srcName;
            obj.dstName        = cfg.dstName;
            obj.numBundles     = cfg.numBundles;
            obj.routing        = cfg.routing;
            obj.phyMode        = cfg.phyMode;
            obj.startTime      = cfg.startTime;
            obj.horizonMinutes = cfg.horizonMinutes;
            obj.stepMinutes    = cfg.stepMinutes;
            obj.ttlMinutes     = cfg.ttlMinutes;
            
            obj.logLines = {};
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
            
            % Initialize bundles
            obj.bundles = struct('id',{}, 'src',{}, 'dst',{}, ...
                                 'holders',{}, 'delivered',{}, ...
                                 'deliveredTime',{});
            for b = 1:obj.numBundles
                bd.id           = b;
                bd.src          = obj.srcName;
                bd.dst          = obj.dstName;
                bd.holders      = {obj.srcName};
                bd.delivered    = false;
                bd.deliveredTime = NaT;
                obj.bundles(end+1) = bd;
            end
            
            profile = dtn.PHYProfiles.getProfile(obj.phyMode);
            
            obj.appendLog(sprintf('--- Scenario start: %s -> %s, bundles=%d, routing=%s, PHY=%s ---', ...
                obj.srcName, obj.dstName, obj.numBundles, obj.routing, profile.name));
            
            if ~strcmp(obj.routing, 'Epidemic')
                obj.appendLog(sprintf('NOTE: routing "%s" not yet implemented; using Epidemic behavior.', ...
                    obj.routing));
            end
            
            nSteps = floor(obj.horizonMinutes / obj.stepMinutes);
            if nSteps < 1
                nSteps = 1;
            end
            
            % Main time-stepped loop
            for step = 1:nSteps
                t = obj.startTime + minutes((step-1)*obj.stepMinutes);
                
                % Move viewer time, if provided
                if ~isempty(viewer) && isvalid(viewer)
                    try
                        viewer.CurrentTime = t;
                    catch
                    end
                end
                
                % Compute node positions / adjacency
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
                            
                            % Epidemic-like forward (only from original holders this step)
                            newHolders{end+1} = neighName; %#ok<AGROW>
                            obj.appendLog(sprintf('t=%s: bundle %d forwarded %s -> %s', ...
                                datestr(t), obj.bundles(b).id, hName, neighName));
                        end
                    end
                    
                    obj.bundles(b).holders = unique(newHolders);
                    
                    % Check delivery
                    if any(strcmp(obj.bundles(b).holders, obj.dstName))
                        if ~obj.bundles(b).delivered
                            obj.bundles(b).delivered     = true;
                            obj.bundles(b).deliveredTime = t;
                            obj.appendLog(sprintf('t=%s: bundle %d DELIVERED at %s', ...
                                datestr(t), obj.bundles(b).id, obj.dstName));
                        end
                    end
                end
                
                drawnow;  % let viewer refresh
                
                if allDelivered
                    break;
                end
            end
            
            deliveredCount = sum([obj.bundles.delivered]);
            obj.appendLog(sprintf('--- Scenario end: %d/%d bundles delivered ---', ...
                deliveredCount, numel(obj.bundles)));
            
            bundles  = obj.bundles;
            logLines = obj.logLines;
        end
    end
    
    methods (Access = private)
        function [x, y, z] = computeNodeXYZ(obj, scenarioManager, nodeNames, t)
            % computeNodeXYZ - get node positions for distance calculations
            %
            % Satellites: use states(handle, t) to get inertial/ECEF position (m).
            % Ground stations: use stored lat/lon/alt and convert to ECEF-ish.
            
            nNodes = numel(nodeNames);
            x = zeros(1, nNodes);
            y = zeros(1, nNodes);
            z = zeros(1, nNodes);
            
            ReKm = 6371;  % Earth radius in km (approx)
            
            for i = 1:nNodes
                idx = scenarioManager.findNodeIndex(nodeNames{i});
                if isempty(idx)
                    error('Node %s not found in ScenarioManager.', nodeNames{i});
                end
                node = scenarioManager.nodes(idx);
                
                if strcmp(node.type, 'gs')
                    % Ground station: use stored geographic coords
                    latDeg = node.latDeg;
                    lonDeg = node.lonDeg;
                    altM   = node.altM;
                    
                    latRad = deg2rad(latDeg);
                    lonRad = deg2rad(lonDeg);
                    rKm    = ReKm + altM/1000;
                    
                    x(i) = rKm * cos(latRad) * cos(lonRad);
                    y(i) = rKm * cos(latRad) * sin(lonRad);
                    z(i) = rKm * sin(latRad);
                else
                    % Satellite: use states(handle, t) -> position in meters
                    pos = states(node.handle, t);  % [3 x 1 x 1] or [3 x 1]
                    pos = squeeze(pos);            % [3 x 1]
                    
                    x(i) = pos(1) / 1000;  % m -> km
                    y(i) = pos(2) / 1000;
                    z(i) = pos(3) / 1000;
                end
            end
        end
        
        function tf = hasLOSFromXYZ(obj, p1Km, p2Km)
            % hasLOSFromXYZ - geometric line-of-sight test vs Earth sphere
            ReKm = 6371;
            d = p2Km - p1Km;
            r1 = p1Km;
            
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
            obj.logLines{end+1} = msg;
        end
    end
end
