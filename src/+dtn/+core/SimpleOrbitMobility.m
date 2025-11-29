

classdef SimpleOrbitMobility < dtn.core.Mobility
    % SIMPLEORBITMOBILITY Moves a node in a circle.
    %   Used for testing the GUI.
    
    properties
        Radius  % km
        Speed   % rad/s
        Phase   % Initial angle (radians)
        Inclination % radians (rotation around X axis)
    end
    
    methods
        function obj = SimpleOrbitMobility(radius, period, phase, inclination)
            % SIMPLEORBITMOBILITY Constructor
            %   radius: km
            %   period: seconds for one orbit
            %   phase: initial angle
            %   inclination: tilt
            
            obj.Radius = radius;
            obj.Speed = (2 * pi) / period;
            obj.Phase = phase;
            obj.Inclination = inclination;
        end
        
        function pos = getPosition(obj, time)
            % GETPOSITION Calculate [x, y, z]
            theta = obj.Speed * time + obj.Phase;
            
            % Flat orbit in XY plane
            x = obj.Radius * cos(theta);
            y = obj.Radius * sin(theta);
            z = 0;
            
            % Apply Inclination (Rotate around X)
            % y_new = y*cos(inc) - z*sin(inc)
            % z_new = y*sin(inc) + z*cos(inc)
            y_new = y * cos(obj.Inclination);
            z_new = y * sin(obj.Inclination);
            
            pos = [x, y_new, z_new];
        end
        
        function vel = getVelocity(obj, time)
            % GETVELOCITY Not needed for simple viz
            vel = [0, 0, 0];
        end
    end
end
