classdef ScenarioManager < handle
    % ScenarioManager - wrapper around satelliteScenario for DTN GUI
    %
    % Responsibilities:
    %   - Own the satelliteScenario
    %   - Add/remove satellites and ground stations
    %   - Keep a simple node list (name, type, handle)
    %   - Maintain access objects between all node pairs (for viewer lines)
    %   - Provide lat/lon/alt lookup at a given time
    
    properties
        sc             % satelliteScenario
        nodes          % struct array of nodes
        accesses       % struct array of access objects
        startTime      datetime
        stopTime       datetime
        sampleTime     double
    end
    
    methods
        function obj = ScenarioManager(startTime, stopTime, sampleTime)
            % Constructor
            
            obj.startTime  = startTime;
            obj.stopTime   = stopTime;
            obj.sampleTime = sampleTime;
            
            obj.sc = satelliteScenario(startTime, stopTime, sampleTime);
            obj.nodes    = struct('name',{},'type',{},'handle',{}, ...
                                  'latDeg',{},'lonDeg',{},'altM',{});
            obj.accesses = struct('nodeA',{},'nodeB',{},'handle',{});
        end
        
        function addSatellite(obj, name, altKm, incDeg, raanDeg)
            % addSatellite - create a simple circular LEO satellite
            %
            % altKm: altitude above Earth in km
            % incDeg, raanDeg: inclination and RAAN in degrees
            
            if obj.hasNode(name)
                error('Node with name %s already exists.', name);
            end
            
            Re = 6371e3;            % Earth radius in meters (approx)
            altM = altKm * 1e3;
            sma  = Re + altM;       % semi-major axis
            ecc  = 0;
            argPeri  = 0;
            trueAnom = 0;
            
            sat = satellite(obj.sc, sma, ecc, incDeg, raanDeg, argPeri, trueAnom, ...
                'Name', name);
            
            node.name   = name;
            node.type   = 'sat';
            node.handle = sat;
            node.latDeg = NaN;
            node.lonDeg = NaN;
            node.altM   = altM;
            
            obj.nodes(end+1) = node;
            
            obj.createAccessesForNewNode(name);
        end
        
        function addGroundStation(obj, name, latDeg, lonDeg, altM)
            % addGroundStation - create a groundStation
            %
            % Older MATLAB uses:
            %   groundStation(sc, name, lat, lon, alt)
            
            if obj.hasNode(name)
                error('Node with name %s already exists.', name);
            end
            
            gs = groundStation(obj.sc, ...
                'Name',      name, ...
                'Latitude',  latDeg, ...
                'Longitude', lonDeg, ...
                'Altitude',  altM);
            
            node.name   = name;
            node.type   = 'gs';
            node.handle = gs;
            node.latDeg = latDeg;
            node.lonDeg = lonDeg;
            node.altM   = altM;
            
            obj.nodes(end+1) = node;
            
            obj.createAccessesForNewNode(name);
        end
        
        function removeNode(obj, name)
            % removeNode - delete node and its accesses
            
            idx = obj.findNodeIndex(name);
            if isempty(idx)
                return;
            end
            
            h = obj.nodes(idx).handle;
            try
                delete(h);
            catch
            end
            
            % Remove related access objects
            toDelete = false(1, numel(obj.accesses));
            for k = 1:numel(obj.accesses)
                if strcmp(obj.accesses(k).nodeA, name) || ...
                   strcmp(obj.accesses(k).nodeB, name)
                    toDelete(k) = true;
                    try
                        delete(obj.accesses(k).handle);
                    catch
                    end
                end
            end
            obj.accesses(toDelete) = [];
            
            obj.nodes(idx) = [];
        end
        
        function tf = hasNode(obj, name)
            % hasNode - true if node with this name exists
            names = obj.getNodeNames();
            tf = any(strcmp(names, name));
        end
        
        function names = getNodeNames(obj)
            % getNodeNames - return cell array of node names
            names = {obj.nodes.name};
        end
        
        function idx = findNodeIndex(obj, name)
            % findNodeIndex - return index of node with given name
            idx = [];
            for k = 1:numel(obj.nodes)
                if strcmp(obj.nodes(k).name, name)
                    idx = k;
                    return;
                end
            end
        end
        
        function [latDeg, lonDeg, altM] = getLatLonAlt(obj, name, t)
            % getLatLonAlt - get lat/lon/alt of node at time t
            %
            % For satellites: use states(handle, t, 'CoordinateFrame','geographic')
            % For ground stations: they are fixed, so just return stored lat/lon/alt.
            
            idx = obj.findNodeIndex(name);
            if isempty(idx)
                error('Node %s not found.', name);
            end
            
            node = obj.nodes(idx);
            
            if strcmp(node.type, 'gs')
                % Ground station: constant position, no need to call states
                latDeg = node.latDeg;
                lonDeg = node.lonDeg;
                altM   = node.altM;
            else
                % Satellite: use states with geographic frame
                pos = states(node.handle, t, 'CoordinateFrame', 'geographic');
                pos = squeeze(pos);  % [3 x 1] = [lat; lon; alt]
                
                latDeg = pos(1);
                lonDeg = pos(2);
                altM   = pos(3);
            end
        end

        function [xKm, yKm, zKm] = getXYZ(obj, nodeName, t)
            % getXYZ - ECEF-ish position in km for any node.
            % Satellites: use states(...,'geographic') via getLatLonAlt.
            % Ground stations: use stored lat/lon/alt (fixed).
            
            idx = obj.findNodeIndex(nodeName);
            if isempty(idx)
                error('Node %s not found in ScenarioManager.', nodeName);
            end
            node = obj.nodes(idx);
            
            ReKm = 6371;  % Earth radius in km (approx)
            
            if strcmp(node.type, 'gs')
                % Ground station: fixed geographic coordinates
                latDeg = node.latDeg;
                lonDeg = node.lonDeg;
                altM   = node.altM;
            else
                % Satellite: get geographic coordinates from states()
                [latDeg, lonDeg, altM] = obj.getLatLonAlt(nodeName, t);
            end
            
            rKm  = ReKm + altM/1000;
            latR = deg2rad(latDeg);
            lonR = deg2rad(lonDeg);
            
            xKm = rKm * cos(latR) * cos(lonR);
            yKm = rKm * cos(latR) * sin(lonR);
            zKm = rKm * sin(latR);
        end

    end
    
    methods (Access = private)
        function createAccessesForNewNode(obj, newName)
            % createAccessesForNewNode - create access objects with all
            % existing nodes when a new node is added
            
            idxNew = obj.findNodeIndex(newName);
            if isempty(idxNew)
                return;
            end
            
            newNode = obj.nodes(idxNew);
            
            for k = 1:numel(obj.nodes)
                if k == idxNew
                    continue;
                end
                aName = obj.nodes(k).name;
                bName = newNode.name;
                
                % Avoid duplicates
                if obj.hasAccessBetween(aName, bName)
                    continue;
                end
                
                aHandle = obj.nodes(k).handle;
                bHandle = newNode.handle;
                
                acHandle = access(aHandle, bHandle);
                
                entry.nodeA  = aName;
                entry.nodeB  = bName;
                entry.handle = acHandle;
                
                obj.accesses(end+1) = entry;
            end
        end
        
        function tf = hasAccessBetween(obj, nameA, nameB)
            tf = false;
            for k = 1:numel(obj.accesses)
                a = obj.accesses(k).nodeA;
                b = obj.accesses(k).nodeB;
                if (strcmp(a, nameA) && strcmp(b, nameB)) || ...
                   (strcmp(a, nameB) && strcmp(b, nameA))
                    tf = true;
                    return;
                end
            end
        end
    end
end
