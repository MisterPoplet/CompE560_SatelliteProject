

classdef (ConstructOnLoad) TransmissionEventData < event.EventData
    properties
        Bundle
        Success
    end
    
    methods
        function data = TransmissionEventData(bundle, success)
            data.Bundle = bundle;
            data.Success = success;
        end
    end
end
