

classdef Bundle
    % BUNDLE Represents a data packet in the Delay Tolerant Network.
    %   A bundle is the fundamental unit of data exchange. It carries
    %   metadata (ID, source, dest) and payload information (size).
    
    properties
        Id          % Unique Identifier (string)
        Source      % Source Node ID (integer)
        Dest        % Destination Node ID (integer)
        Size        % Size in bytes (integer)
        CreationTime % Simulation time when created (seconds)
        Ttl         % Time To Live (seconds)
        
        % Optional: Custody tracking
        CustodyNode % ID of current custodian
    end
    
    methods
        function obj = Bundle(id, src, dest, size, time, ttl)
            % BUNDLE Constructor
            %   b = Bundle(id, src, dest, size, time, ttl) creates a new bundle.
            
            if nargin > 0
                obj.Id = id;
                obj.Source = src;
                obj.Dest = dest;
                obj.Size = size;
                obj.CreationTime = time;
                obj.Ttl = ttl;
                obj.CustodyNode = src; % Initially, source has custody
            end
        end
        
        function expired = isExpired(obj, currentTime)
            % ISEXPIRED Check if the bundle has exceeded its TTL.
            %   expired = b.isExpired(currentTime) returns true if dead.
            
            age = currentTime - obj.CreationTime;
            expired = age > obj.Ttl;
        end
        
        function s = toString(obj)
            % TOSTRING String representation for debugging
            s = sprintf('Bundle[%s]: %d -> %d (Size: %d, Age: %.1f)', ...
                obj.Id, obj.Source, obj.Dest, obj.Size, 0); % Age calc requires time, omitted here
        end
    end
end
