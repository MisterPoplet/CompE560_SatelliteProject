

classdef (Abstract) Mobility < handle
    % MOBILITY Abstract base class for node movement.
    %   This class defines the interface that the Node uses to find out
    %   where it is. We can have different subclasses:
    %   1. KeplerianMobility (Uses Aerospace Toolbox or simple math)
    %   2. CsvMobility (Reads positions from a file)
    %   3. StaticMobility (For ground stations that don't move)
    
    methods (Abstract)
        % Returns the [x, y, z] position in km at a given time (seconds)
        pos = getPosition(obj, time)
        
        % Returns the [vx, vy, vz] velocity in km/s at a given time
        vel = getVelocity(obj, time)
    end
    
    methods
        function dist = getDistance(obj, otherMobility, time)
            % GETDISTANCE Calculate distance to another mobility object
            p1 = obj.getPosition(time);
            p2 = otherMobility.getPosition(time);
            dist = norm(p1 - p2);
        end
    end
end
