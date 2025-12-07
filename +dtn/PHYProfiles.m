classdef PHYProfiles
    % PHYProfiles - simple physical layer profiles for DTN sim
    %
    % Fields returned by getProfile(name):
    %   name                 - profile name
    %   maxRangeKm           - maximum link range
    %   dataRate_bps         - nominal data rate (bits per second)
    %   handshakeOverhead_s  - per-direction handshake / MAC overhead (sec)

    methods (Static)
        function profile = getProfile(name)
            switch name
                case 'SBand'
                    profile.name                = 'SBand';
                    profile.maxRangeKm          = 4000;      % LEO-ish
                    profile.dataRate_bps        = 1e6;       % 1 Mbps
                    profile.handshakeOverhead_s = 0.050;     % 50 ms

                case 'KaBand'
                    profile.name                = 'KaBand';
                    profile.maxRangeKm          = 3000;
                    profile.dataRate_bps        = 1e8;       % 100 Mbps
                    profile.handshakeOverhead_s = 0.010;     % 10 ms

                case 'SatelliteRF'
                    profile.name                = 'SatelliteRF';
                    profile.maxRangeKm          = 3000;
                    profile.dataRate_bps        = 1e7;       % 10 Mbps
                    profile.handshakeOverhead_s = 0.020;     % 20 ms

                otherwise
                    error('Unknown PHY profile "%s".', name);
            end
        end
    end
end
