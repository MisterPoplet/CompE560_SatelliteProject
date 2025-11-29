

classdef PhyLayer < handle
    % PHYLAYER Handles the physical transmission details.
    %   Manages the wireless technology (Satellite Links), data rates, and
    %   contact capacity calculations.
    
    properties
        TechType    % 'S-Band' or 'Ka-Band'
        DataRate    % Bytes per second
        Range       % Max communication range (km)
        HandshakeTime % Time overhead to establish link (seconds)
    end
    
    methods
        function obj = PhyLayer(type)
            % PHYLAYER Constructor
            %   Configures the PHY based on the requested type.
            
            obj.TechType = type;
            switch type
                case 'S-Band'
                    % Low rate, robust, omni-directional
                    % Replaces BLE (Low rate, longer discovery)
                    % 1 Mbps ~ 125,000 Bytes/s
                    obj.DataRate = 125000; 
                    obj.Range = 1000;        % 1000 km
                    obj.HandshakeTime = 5.0; % Acquisition overhead
                case 'Ka-Band'
                    % High rate, directional
                    % Replaces Wi-Fi Direct (High rate, short discovery)
                    % 100 Mbps ~ 12,500,000 Bytes/s
                    obj.DataRate = 12500000; 
                    obj.Range = 5000;        % 5000 km
                    obj.HandshakeTime = 2.0; % Pointing acquisition
                otherwise
                    error('Unknown PHY Type: %s', type);
            end
        end
        
        function capacity = calculateCapacity(obj, contactDuration)
            % CALCULATECAPACITY Total bytes that can be sent in a contact.
            %   Formula: Rate * (Window - Handshake)
            
            effectiveTime = contactDuration - obj.HandshakeTime;
            if effectiveTime <= 0
                capacity = 0;
            else
                capacity = floor(obj.DataRate * effectiveTime);
            end
        end
    end
end
