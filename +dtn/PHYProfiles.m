classdef PHYProfiles
    % PHYProfiles - return PHY parameter sets for satellite links
    %
    % Each profile includes:
    %   dataRate_bps  - nominal data rate
    %   discovery_s   - neighbor discovery / handshake overhead
    %   handshake_s   - initial handshake before data
    %   ber           - bit error rate (placeholder for link errors)
    %   maxRangeKm    - max link range; beyond this, no communication
    
    methods (Static)
        function profile = getProfile(mode)
            % Returns a struct with basic PHY parameters
            
            switch mode
                case 'SBand'
                    profile.name          = 'SBand';
                    profile.dataRate_bps  = 1e6;     % ~1 Mbps
                    profile.discovery_s   = 5;       % seconds
                    profile.handshake_s   = 1;       % seconds
                    profile.ber           = 1e-5;
                    profile.maxRangeKm    = 4000;    % LEO-LEO / LEO-GS scale
                    
                case 'KaBand'
                    profile.name          = 'KaBand';
                    profile.dataRate_bps  = 100e6;   % ~100 Mbps
                    profile.discovery_s   = 8;       % more overhead for pointing, etc.
                    profile.handshake_s   = 2;
                    profile.ber           = 5e-6;
                    profile.maxRangeKm    = 3500;    % slightly tighter, pointing-limited
                    
                case 'SatelliteRF'
                    profile.name          = 'SatelliteRF';
                    profile.dataRate_bps  = 10e6;    % generic moderate rate
                    profile.discovery_s   = 6;
                    profile.handshake_s   = 1.5;
                    profile.ber           = 1e-4;
                    profile.maxRangeKm    = 5000;    % very generous general RF
                    
                otherwise
                    error('Unknown PHY mode: %s', mode);
            end
        end
    end
end
