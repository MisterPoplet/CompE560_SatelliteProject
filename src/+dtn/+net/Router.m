

classdef (Abstract) Router < handle
    % ROUTER Abstract base class for DTN routing protocols.
    %   The Router is the "Brain" of the node. It decides:
    %   1. Which bundles to forward?
    %   2. Which bundles to delete (if buffer full)?
    %   3. How to handle new contacts?
    
    properties
        ParentNode  % Reference to the owning Node
    end
    
    methods
        function obj = Router(parentNode)
            % ROUTER Constructor
            obj.ParentNode = parentNode;
        end
        
        function update(obj, dt)
            % UPDATE Called every simulation tick.
            %   Override this if the protocol needs periodic maintenance
            %   (e.g., aging routing tables).
        end
        
        function summary = getSummaryVector(obj)
            % GETSUMMARYVECTOR Return list of Bundle IDs currently held.
            %   Used by peers to know what we have.
            if isempty(obj.ParentNode.Buffer)
                summary = {};
            else
                summary = {obj.ParentNode.Buffer.Id};
            end
        end
    end
    
    methods (Abstract)
        % Called when the LinkLayer reports a new connection (LinkUp)
        handleContact(obj, peerId)
        
        % Called when the LinkLayer reports a successful/failed transmission
        handleTransmissionComplete(obj, bundle, success)
        
        % Called when a new bundle is created or received by the Node
        handleBundleReceived(obj, bundle)
    end
end
