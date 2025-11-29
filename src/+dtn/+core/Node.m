

classdef Node < handle
    % NODE Represents a Satellite or Ground Station in the network.
    %   This class acts as the central "Agent" that holds all the layers together.
    %   It has a position, a buffer for bundles, and references to its layers.
    
    properties
        Id          % Unique Integer ID
        Name        % Human-readable name (e.g., "Sat-1")
        Type        % 'Satellite' or 'GroundStation'
        
        % State
        Position    % [x, y, z] coordinates (km)
        Time        % Current local time (seconds)
        
        % Layers
        Phy         % dtn.phy.PhyLayer
        Link        % dtn.link.LinkLayer
        Router      % dtn.net.Router (The "Brain")
        Mobility    % dtn.core.Mobility
        
        % Storage
        Buffer      % Array of dtn.core.Bundle objects
        BufferCapacity % Max buffer size in bytes
        CurrentBufferSize % Current usage in bytes
        
        % Simulation Reference (to find peers)
        Sim
    end
    
    events
        PacketReceived % Event triggered when a bundle arrives
        PacketSent     % Event triggered when a bundle leaves
    end
    
    methods
        function obj = Node(id, name, type, capacity, phyType, routingType, mobility, sim)
            % NODE Constructor
            obj.Id = id;
            obj.Name = name;
            obj.Type = type;
            obj.BufferCapacity = capacity;
            obj.CurrentBufferSize = 0;
            obj.Buffer = dtn.core.Bundle.empty;
            obj.Position = [0, 0, 0];
            obj.Sim = sim;
            obj.Mobility = mobility;
            
            % Initialize Layers
            obj.Phy = dtn.phy.PhyLayer(phyType);
            obj.Link = dtn.link.LinkLayer(obj, obj.Phy);
            
            % Initialize Router based on type
            switch routingType
                case 'Epidemic'
                    obj.Router = dtn.routing.Epidemic(obj);
                case 'Prophet'
                    % obj.Router = dtn.routing.Prophet(obj); % TODO
                case 'SprayAndWait'
                    % obj.Router = dtn.routing.SprayAndWait(obj); % TODO
                otherwise
                    warning('Unknown routing type %s, defaulting to Epidemic', routingType);
                    obj.Router = dtn.routing.Epidemic(obj);
            end
            
            % Wire up Link Layer Events to Router
            addlistener(obj.Link, 'LinkUp', @obj.onLinkUp);
            addlistener(obj.Link, 'TransmissionComplete', @obj.onTxComplete);
        end
        
        function update(obj, dt, time, allNodes)
            % UPDATE Main simulation step for this node.
            obj.Time = time;
            
            % 1. Update Position
            if ~isempty(obj.Mobility)
                obj.Position = obj.Mobility.getPosition(time);
            end
            
            % 2. Update Layers
            % Phy doesn't need update usually, but Link does
            obj.Link.update(dt, allNodes);
            obj.Router.update(dt);
            
            % 3. Clean up expired bundles
            obj.cleanupBuffer();
        end
        
        function peer = getPeer(obj, peerId)
            % GETPEER Helper to find another node object by ID.
            peer = obj.Sim.getNode(peerId);
        end
        
        % --- Event Handlers ---
        
        function onLinkUp(obj, ~, eventData)
            % ONLINKUP Called when LinkLayer finds a neighbor.
            obj.Router.handleContact(eventData.PeerId);
        end
        
        function onTxComplete(obj, ~, eventData)
            % ONTXCOMPLETE Called when a transmission finishes.
            obj.Router.handleTransmissionComplete(eventData.Bundle, eventData.Success);
        end
        
        % --- Bundle Handling ---
        
        function success = receiveBundle(obj, bundle)
            % RECEIVEBUNDLE Try to store a bundle in the buffer.
            
            % Check if we already have it (Duplicate Suppression)
            if any(arrayfun(@(b) strcmp(b.Id, bundle.Id), obj.Buffer))
                success = true; % Pretend we took it, but drop duplicate
                return;
            end
            
            if (obj.CurrentBufferSize + bundle.Size) <= obj.BufferCapacity
                obj.Buffer(end+1) = bundle;
                obj.CurrentBufferSize = obj.CurrentBufferSize + bundle.Size;
                success = true;
                notify(obj, 'PacketReceived');
                % Notify Router so it can react (e.g., forward it)
                obj.Router.handleBundleReceived(bundle);
                fprintf('Node %s received bundle %s\n', obj.Name, bundle.Id);
            else
                success = false;
                fprintf('Node %s dropped bundle %s (Buffer Full)\n', obj.Name, bundle.Id);
            end
        end
        
        function cleanupBuffer(obj)
            % CLEANUPBUFFER Remove expired bundles.
            if isempty(obj.Buffer), return; end
            
            expiredMask = arrayfun(@(b) b.isExpired(obj.Time), obj.Buffer);
            if any(expiredMask)
                removedSize = sum([obj.Buffer(expiredMask).Size]);
                obj.CurrentBufferSize = obj.CurrentBufferSize - removedSize;
                obj.Buffer(expiredMask) = [];
                fprintf('Node %s cleaned up %d expired bundles\n', obj.Name, sum(expiredMask));
            end
        end
    end
end
