

classdef Epidemic < dtn.net.Router
    % EPIDEMIC Implements the Epidemic Routing protocol.
    %   Strategy: "Flood". When meeting a peer, send everything I have
    %   that they don't have.
    %   Pros: High delivery ratio, low delay.
    %   Cons: High overhead, buffer contention.
    
    methods
        function obj = Epidemic(node)
            obj = obj@dtn.net.Router(node);
        end
        
        function handleContact(obj, peerId)
            % HANDLECONTACT A new neighbor is connected.
            % 1. Get the peer's summary vector (Magic/Oracle for sim)
            %    In a real sim, we'd look up the peer object.
            %    We assume 'allNodes' is global or accessible via Simulation.
            %    For now, we'll assume the Node has a way to get the peer.
            
            % TODO: We need a way to access the Peer Node object.
            % For this step, we will assume the Simulation passes it or we
            % can find it. Let's assume ParentNode has a method 'getPeer(id)'.
            
            peer = obj.ParentNode.getPeer(peerId);
            if isempty(peer), return; end
            
            peerSummary = peer.Router.getSummaryVector();
            myBundles = obj.ParentNode.Buffer;
            
            % 2. Iterate through my bundles
            for i = 1:length(myBundles)
                bundle = myBundles(i);
                
                % 3. If peer doesn't have it, try to send
                if ~ismember(bundle.Id, peerSummary)
                    % Send it!
                    % Note: LinkLayer.sendBundle is non-blocking but queue is size 1.
                    % In a real implementation, we'd have a queue.
                    % Here, we just try to send the first one we find.
                    
                    success = obj.ParentNode.Link.sendBundle(bundle, peerId);
                    if success
                        fprintf('Epidemic: Node %s forwarding Bundle %s to %s\n', ...
                            obj.ParentNode.Name, bundle.Id, peer.Name);
                        break; % Link is busy now, wait for TransmissionComplete
                    end
                end
            end
        end
        
        function handleTransmissionComplete(obj, bundle, success)
            % HANDLETRANSMISSIONCOMPLETE
            if success
                % Great! Try to send the next one?
                % For simplicity, we'll wait for the next update cycle or
                % trigger a "Flush" method.
                % Re-trigger contact handling for all connected neighbors?
            end
        end
        
        function handleBundleReceived(obj, bundle)
            % HANDLEBUNDLERECEIVED
            % Nothing special to do for Epidemic. Just store it (Node does that).
        end
    end
end
