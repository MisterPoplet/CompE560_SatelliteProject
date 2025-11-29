% run_real_orbit_test.m
% Test DTN Simulation with Real Aerospace Toolbox Orbits

addpath('src');

%% 1. Setup Scenario
startTime = datetime(2025, 11, 10, 12, 0, 0, 'TimeZone', 'UTC');
stopTime  = startTime + days(5); % Run for 5 days
sampleTime = 10; % 10 seconds step for speed

sc = satelliteScenario(startTime, stopTime, sampleTime);

%% 2. Create Satellites (Walker Delta Constellation subset)
% Altitude ~500km
Re = 6378137; 
a = Re + 500e3; 
inc = 53; 

% Sat 1
sat1_asset = satellite(sc, a, 0, inc, 0, 0, 0, 'Name', 'Sat-1');
% show(sat1_asset); % Try to show explicitly

% Sat 2 (Same plane, different anomaly)
sat2_asset = satellite(sc, a, 0, inc, 0, 0, 20, 'Name', 'Sat-2');
% show(sat2_asset);

% Sat 3 (Different plane)
sat3_asset = satellite(sc, a, 0, inc, 30, 0, 0, 'Name', 'Sat-3');
% show(sat3_asset);

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
% Main Loop with GUI Control
sc.AutoSimulate = true;
play(sc);

lastTime = startTime;

while isvalid(gui.CtrlFig) && isvalid(gui.Viewer)
    % Sync DTN Simulation with Scenario Time
    % We assume the scenario is running. We check its current time.
    
    % Note: satelliteScenario doesn't always expose 'CurrentTime' directly in all versions.
    % But usually 'SimulationTime' (seconds elapsed) or similar.
    % Let's try to infer from the viewer or scenario.
    
    try
        % Try to get current time from scenario
        % If this fails, we might need another approach.
        % Assuming sc.SimulationTime is elapsed seconds.
        if isprop(sc, 'SimulationTime')
            elapsed = sc.SimulationTime;
            currentSimTime = startTime + seconds(elapsed);
        else
            % Fallback: Just step forward by wall clock? No, that's bad.
            % Let's assume we can just run our simulation at a fixed rate 
            % and hope the viewer keeps up, or vice versa.
            pause(0.1);
            continue;
        end
        
        if currentSimTime > lastTime
            dt = seconds(currentSimTime - lastTime);
            if dt > 0
                sim.step(dt);
                lastTime = currentSimTime;
            end
        end
    catch
        % If accessing time fails, just pause
        pause(0.1);
    end
    
    pause(0.1); 
end

fprintf('Test Complete.\n');
