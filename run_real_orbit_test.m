% run_real_orbit_test.m
% Test DTN Simulation with Real Aerospace Toolbox Orbits

addpath('src');

%% 1. Setup Scenario
startTime = datetime(2025, 11, 10, 12, 0, 0, 'TimeZone', 'UTC');
stopTime  = datetime(2025, 11, 10, 13, 0, 0, 'TimeZone', 'UTC'); % 1 hour run
sampleTime = 10; % 10 seconds step for speed

sc = satelliteScenario(startTime, stopTime, sampleTime);

%% 2. Create Satellites (Walker Delta Constellation subset)
% Altitude ~500km
Re = 6378137; 
a = Re + 500e3; 
inc = 53; 

% Sat 1
sat1_asset = satellite(sc, a, 0, inc, 0, 0, 0, 'Name', 'Sat-1');
% Sat 2 (Same plane, different anomaly)
sat2_asset = satellite(sc, a, 0, inc, 0, 0, 20, 'Name', 'Sat-2');
% Sat 3 (Different plane)
sat3_asset = satellite(sc, a, 0, inc, 30, 0, 0, 'Name', 'Sat-3');

% Ground Station (San Diego)
gs_asset = groundStation(sc, 32.7157, -117.1611, 'Name', 'GS-SanDiego');

%% 3. Setup DTN Simulation
config.Duration = seconds(stopTime - startTime);
config.TimeStep = sampleTime;
sim = dtn.core.Simulation(config);

%% 4. Wrap in DTN Nodes
% Sat 1
mob1 = dtn.core.AerospaceMobility(sat1_asset, sc);
node1 = dtn.core.Node(1, 'Sat-1', 'Satellite', 1e6, 'S-Band', 'Epidemic', mob1, sim);
sim.addNode(node1);

% Sat 2
mob2 = dtn.core.AerospaceMobility(sat2_asset, sc);
node2 = dtn.core.Node(2, 'Sat-2', 'Satellite', 1e6, 'S-Band', 'Epidemic', mob2, sim);
sim.addNode(node2);

% Sat 3
mob3 = dtn.core.AerospaceMobility(sat3_asset, sc);
node3 = dtn.core.Node(3, 'Sat-3', 'Satellite', 1e6, 'S-Band', 'Epidemic', mob3, sim);
sim.addNode(node3);

% GS
mobGS = dtn.core.AerospaceMobility(gs_asset, sc);
nodeGS = dtn.core.Node(4, 'GS-SD', 'GroundStation', 1e9, 'S-Band', 'Epidemic', mobGS, sim);
sim.addNode(nodeGS);

%% 5. Run Visualization
gui = dtn.gui.GlobeView(sim);

fprintf('Starting Real Orbit Test... Close figure to stop.\n');
while sim.Time < sim.Duration
    if ~isvalid(gui.Figure), break; end
    
    sim.step(sim.TimeStep);
    pause(0.01); 
end
fprintf('Test Complete.\n');
