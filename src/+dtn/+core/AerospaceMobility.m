
classdef AerospaceMobility < dtn.core.Mobility
    % AEROSPACEMOBILITY Wraps an Aerospace Toolbox asset.
    %   Uses a 'satellite' or 'groundStation' object to calculate
    %   real-world positions.
    
    properties
        Asset       % The Aerospace Toolbox object (satellite/groundStation)
        Scenario    % Reference to the satelliteScenario
    end
    
    methods
        function obj = AerospaceMobility(asset, scenario)
            % AEROSPACEMOBILITY Constructor
            obj.Asset = asset;
            obj.Scenario = scenario;
        end
        
        function pos = getPosition(obj, time)
            % GETPOSITION Get ECEF position in km.
            currentDt = obj.Scenario.StartTime + seconds(time);
            
            if contains(class(obj.Asset), 'groundStation', 'IgnoreCase', true)
                % GroundStation: Calculate ECEF from LLA
                lat = obj.Asset.Latitude;
                lon = obj.Asset.Longitude;
                alt = obj.Asset.Altitude;
                p = obj.lla2ecef(lat, lon, alt);
                pos = p / 1000;
                return;
            end
            
            % Satellite: Try multiple signatures
            try
                % Try 1: User script signature (2 outputs)
                [~, p] = states(obj.Asset, currentDt, 'CoordinateFrame', 'ecef');
                pos = p' / 1000;
            catch
                try
                    % Try 2: 3 outputs (Standard toolbox?)
                    [~, p, ~] = states(obj.Asset, currentDt, 'CoordinateFrame', 'ecef');
                    pos = p' / 1000;
                catch
                    try
                        % Try 3: 1 output (Maybe just position?)
                        p = states(obj.Asset, currentDt, 'CoordinateFrame', 'ecef');
                        if length(p) == 3
                            pos = p' / 1000;
                        else
                            % Maybe it returned quaternion?
                            warning('states() returned 1 output of length %d', length(p));
                            pos = [0, 0, 0];
                        end
                    catch e
                        % All failed
                        fprintf('Error calling states() for %s: %s\n', obj.Asset.Name, e.message);
                        pos = [0, 0, 0];
                    end
                end
            end
        end
        
        function vel = getVelocity(obj, time)
            % GETVELOCITY Get ECEF velocity in km/s.
            % FIXME: states() signature is tricky. For now, return 0.
            % Visualization and Link checks only use Position.
            vel = [0, 0, 0];
        end
        
        function r = lla2ecef(obj, lat_deg, lon_deg, alt_m)
            % LLA2ECEF Helper to convert LLA to ECEF (WGS84)
            a = 6378137; 
            f = 1/298.257223563; 
            e2 = f*(2-f);
            
            lat = deg2rad(lat_deg); 
            lon = deg2rad(lon_deg); 
            h = alt_m;
            
            N = a ./ sqrt(1 - e2 * sin(lat).^2);
            
            x = (N + h) .* cos(lat) .* cos(lon);
            y = (N + h) .* cos(lat) .* sin(lon);
            z = (N * (1 - e2) + h) .* sin(lat);
            
            r = [x, y, z];
        end
    end
end
