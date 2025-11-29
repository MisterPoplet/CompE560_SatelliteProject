

classdef Simulation < handle
    % SIMULATION Main container for the DTN simulation.
    %   Holds all nodes, manages time, and runs the main loop.
    
    properties
        Nodes       % Array of dtn.core.Node objects
        Time        % Current simulation time (seconds)
        Duration    % Total duration (seconds)
        TimeStep    % dt (seconds)
        
        % Configuration
        Config
    end
    
    events
        StepComplete % Triggered after each time step (for GUI update)
    end
    
    methods
        function obj = Simulation(config)
            % SIMULATION Constructor
            obj.Config = config;
            obj.Nodes = dtn.core.Node.empty;
            obj.Time = 0;
            obj.Duration = config.Duration;
            obj.TimeStep = config.TimeStep;
        end
        
        function addNode(obj, node)
            % ADDNODE Register a node in the simulation.
            obj.Nodes(end+1) = node;
        end
        
        function node = getNode(obj, id)
            % GETNODE Helper to find a node by ID.
            %   Optimization: In a real large sim, use a Map.
            %   For < 100 nodes, linear search is fine.
            node = [];
            for i = 1:length(obj.Nodes)
                if obj.Nodes(i).Id == id
                    node = obj.Nodes(i);
                    return;
                end
            end
        end
        
        function run(obj)
            % RUN Execute the simulation loop.
            %   NOTE: This is for headless mode.
            %   For GUI mode, the GUI will drive the loop or listen to events.
            
            fprintf('Simulation Started. Duration: %d s\n', obj.Duration);
            
            for t = 0:obj.TimeStep:obj.Duration
                obj.step(obj.TimeStep);
            end
            
            fprintf('Simulation Complete.\n');
        end
        
        function step(obj, dt)
            % STEP Advance the simulation by dt seconds.
            obj.Time = obj.Time + dt;
            
            % Update all nodes
            % Pass 'obj.Nodes' so they can check neighbors
            for i = 1:length(obj.Nodes)
                obj.Nodes(i).update(dt, obj.Time, obj.Nodes);
            end
            
            notify(obj, 'StepComplete');
        end
    end
end
