% run_visual_test.m
% A script to verify the DTN Simulation and GUI.

% 1. Setup Path
addpath('src');

% 2. Configure Simulation
config.Duration = 600; % Run for 10 minutes
config.TimeStep = 1.0; % 1 second steps
sim = dtn.core.Simulation(config);

% 3. Create Nodes
% Sat 1: Low Earth Orbit (LEO), 7000km radius
mob1 = dtn.core.SimpleOrbitMobility(7000, 5400, 0, 0); 
sat1 = dtn.core.Node(1, 'Sat-1', 'Satellite', 1e6, 'S-Band', 'Epidemic', mob1, sim);

% Sat 2: LEO, same orbit, behind Sat 1
mob2 = dtn.core.SimpleOrbitMobility(7000, 5400, -0.2, 0); % -0.2 rad phase lag
sat2 = dtn.core.Node(2, 'Sat-2', 'Satellite', 1e6, 'S-Band', 'Epidemic', mob2, sim);

% Sat 3: Polar Orbit (90 deg inclination)
mob3 = dtn.core.SimpleOrbitMobility(7000, 5400, 0, pi/2);
sat3 = dtn.core.Node(3, 'Sat-3', 'Satellite', 1e6, 'S-Band', 'Epidemic', mob3, sim);

% Ground Station: Fixed on Earth surface
% For now, use a static position (Mobility with 0 speed)
mobGS = dtn.core.SimpleOrbitMobility(6371, 1e9, 0, 0); % Effectively static
gs1 = dtn.core.Node(4, 'GS-SanDiego', 'GroundStation', 1e9, 'S-Band', 'Epidemic', mobGS, sim);

% 4. Add to Simulation
sim.addNode(sat1);
sim.addNode(sat2);
sim.addNode(sat3);
sim.addNode(gs1);

% 5. Initialize GUI
gui = dtn.gui.GlobeView(sim);

% 6. Run Loop
fprintf('Starting Visual Test... Close the figure to stop.\n');
while sim.Time < sim.Duration
    if ~isvalid(gui.Figure)
        break; % Stop if user closes window
    end
    
    sim.step(sim.TimeStep);
    pause(0.05); % Slow down slightly for visualization
end

fprintf('Test Complete.\n');
