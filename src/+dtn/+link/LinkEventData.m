

classdef (ConstructOnLoad) LinkEventData < event.EventData
    properties
        PeerId
    end
    
    methods
        function data = LinkEventData(peerId)
            data.PeerId = peerId;
        end
    end
end
