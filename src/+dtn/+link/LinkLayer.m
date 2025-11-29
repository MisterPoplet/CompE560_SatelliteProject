

classdef LinkLayer < handle
    % LINKLAYER Manages neighbor discovery and reliable transmission.
    %   - Discovery: Checks distances to other nodes.
    %   - Association: Simulates handshake overhead.
    %   - ARQ: Stop-and-Wait protocol with BER errors.
    
    properties
        ParentNode      % Reference to the owning Node
        Phy             % Reference to the PhyLayer
        
        % Neighbor Table: Map of NodeID -> ConnectionState
        % State: 'DISCONNECTED', 'HANDSHAKING', 'CONNECTED'
        Neighbors
        
        % ARQ State
        IsTransmitting  % Boolean
        CurrentTxBundle % The bundle currently being sent
        TxTimer         % Timer for transmission delay
        
        % Parameters
        BitErrorRate    % Probability of bit error (e.g., 1e-6)
    end
    
    events
        LinkUp          % Triggered when a neighbor becomes CONNECTED
        LinkDown        % Triggered when a neighbor goes out of range
        TransmissionComplete % Triggered when ARQ finishes (Success or Fail)
    end
    
    methods
        function obj = LinkLayer(parentNode, phy)
            % LINKLAYER Constructor
            obj.ParentNode = parentNode;
            obj.Phy = phy;
            obj.Neighbors = containers.Map('KeyType', 'double', 'ValueType', 'any');
            obj.IsTransmitting = false;
            obj.BitErrorRate = 1e-6; % Default BER
        end
        
        function update(obj, dt, allNodes)
            % UPDATE Check connectivity and progress transmissions.
            
            % 1. Discovery & Maintenance
            myPos = obj.ParentNode.Position;
            
            for i = 1:length(allNodes)
                other = allNodes(i);
                if other.Id == obj.ParentNode.Id, continue; end
                
                dist = norm(myPos - other.Position);
                
                % Check if in range
                if dist <= obj.Phy.Range
                    obj.handleInRange(other, dt);
                else
                    obj.handleOutOfRange(other);
                end
            end
            
            % 2. Transmission Progress
            if obj.IsTransmitting
                obj.TxTimer = obj.TxTimer - dt;
                if obj.TxTimer <= 0
                    obj.finishTransmission();
                end
            end
        end
        
        function handleInRange(obj, other, dt)
            % HANDLEINRANGE Manage state transitions when node is close.
            
            if ~isKey(obj.Neighbors, other.Id)
                % New neighbor found! Start Handshake.
                state = struct('Status', 'HANDSHAKING', 'Timer', obj.Phy.HandshakeTime);
                obj.Neighbors(other.Id) = state;
                % fprintf('Node %s found %s. Starting Handshake...\n', obj.ParentNode.Name, other.Name);
                
            else
                state = obj.Neighbors(other.Id);
                if strcmp(state.Status, 'HANDSHAKING')
                    state.Timer = state.Timer - dt;
                    if state.Timer <= 0
                        state.Status = 'CONNECTED';
                        notify(obj, 'LinkUp', dtn.link.LinkEventData(other.Id));
                        fprintf('Node %s <-> %s CONNECTED\n', obj.ParentNode.Name, other.Name);
                    end
                    obj.Neighbors(other.Id) = state; % Update struct in Map
                end
            end
        end
        
        function handleOutOfRange(obj, other)
            % HANDLEOUTOFRANGE Reset state if node leaves.
            if isKey(obj.Neighbors, other.Id)
                state = obj.Neighbors(other.Id);
                if strcmp(state.Status, 'CONNECTED')
                    notify(obj, 'LinkDown', dtn.link.LinkEventData(other.Id));
                    fprintf('Node %s <-> %s DISCONNECTED\n', obj.ParentNode.Name, other.Name);
                end
                remove(obj.Neighbors, other.Id);
            end
        end
        
        function success = sendBundle(obj, bundle, nextHopId)
            % SENDBUNDLE Start transmitting a bundle.
            %   Returns false if link is busy or down.
            
            if obj.IsTransmitting
                success = false; return;
            end
            
            if ~isKey(obj.Neighbors, nextHopId) || ...
               ~strcmp(obj.Neighbors(nextHopId).Status, 'CONNECTED')
                success = false; return;
            end
            
            % Calculate Transmission Delay = Size / Rate
            delay = (bundle.Size * 8) / (obj.Phy.DataRate * 8); % Bytes/Bytes
            
            obj.IsTransmitting = true;
            obj.CurrentTxBundle = bundle;
            obj.TxTimer = delay;
            success = true;
        end
        
        function finishTransmission(obj)
            % FINISHTRANSMISSION Check for errors and notify.
            
            % Simulate Errors
            % Probability of success = (1 - BER) ^ Bits
            bits = obj.CurrentTxBundle.Size * 8;
            probSuccess = (1 - obj.BitErrorRate) ^ bits;
            
            if rand() <= probSuccess
                % Success!
                % In a real sim, we would call otherNode.receiveBundle() here
                % For now, we just fire an event
                notify(obj, 'TransmissionComplete', ...
                    dtn.link.TransmissionEventData(obj.CurrentTxBundle, true));
            else
                % Failed (CRC Error)
                notify(obj, 'TransmissionComplete', ...
                    dtn.link.TransmissionEventData(obj.CurrentTxBundle, false));
                fprintf('Node %s transmission FAILED (BER)\n', obj.ParentNode.Name);
            end
            
            obj.IsTransmitting = false;
            obj.CurrentTxBundle = [];
        end
    end
end
