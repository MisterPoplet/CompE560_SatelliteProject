classdef DTNConfig < handle
    % DTNConfig - holds DTN configuration selected in the GUI
    
    properties
        % PHY mode: 'SBand' | 'KaBand' | 'SatelliteRF'
        phyMode          char   = 'SatelliteRF'
        
        % Bundle / packet config
        packetSizeBytes  double = 1024
        
        % Routing: 'Epidemic' | 'PRoPHET' | 'SprayAndWait'
        routingMode      char   = 'Epidemic'
        
        % TTL in minutes (for later experiments)
        ttlMinutes       double = 120
    end
    
    methods
        function obj = DTNConfig()
            % default config already set via property defaults
        end
    end
end
