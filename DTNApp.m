classdef DTNApp < handle
    % DTNApp - GUI for Delay Tolerant Network Satellite Simulator
    %
    % Left side:
    %   - Tabs:
    %       * Nodes & Ping: add/remove nodes, manual pings, reset, open viewer
    %       * Settings: PHY + basic DTN configuration
    %       * Scenario: define "SAT-A -> SAT-B, N bundles, routing, PHY"
    %
    % Right side:
    %   - Logs panel (always visible): shows scenario logs + ping logs,
    %     with a Clear button.
    
    properties
        % Core objects
        scenarioManager   dtn.ScenarioManager
        dtnConfig         dtn.DTNConfig
        
        % satelliteScenarioViewer handle (optional)
        viewer            % satelliteScenarioViewer object
        
        % GUI figure & layout
        fig               matlab.ui.Figure
        tabGroup          matlab.ui.container.TabGroup
        tabNodes          matlab.ui.container.Tab
        tabSettings       matlab.ui.container.Tab
        tabScenario       matlab.ui.container.Tab
        
        % Logs panel (always visible)
        logsPanel         matlab.ui.container.Panel
        logTextArea       matlab.ui.control.TextArea
        clearLogButton    matlab.ui.control.Button
        
        % Nodes & Ping tab controls
        openViewerButton  matlab.ui.control.Button
        
        nodesTable        matlab.ui.control.Table
        
        nodeTypeDropDown  matlab.ui.control.DropDown
        nodeNameField     matlab.ui.control.EditField
        
        % Satellite add controls
        satAltField       matlab.ui.control.NumericEditField
        satIncField       matlab.ui.control.NumericEditField
        satRAANField      matlab.ui.control.NumericEditField
        
        % Ground station add controls
        gsLatField        matlab.ui.control.NumericEditField
        gsLonField        matlab.ui.control.NumericEditField
        gsAltField        matlab.ui.control.NumericEditField
        
        addNodeButton     matlab.ui.control.Button
        removeNodeButton  matlab.ui.control.Button
        
        pingFromDropDown  matlab.ui.control.DropDown
        pingToDropDown    matlab.ui.control.DropDown
        pingButton        matlab.ui.control.Button
        
        resetButton       matlab.ui.control.Button
        
        % Settings tab controls
        phyModeDropDown   matlab.ui.control.DropDown
        packetSizeField   matlab.ui.control.NumericEditField
        routingDropDown   matlab.ui.control.DropDown
        ttlField          matlab.ui.control.NumericEditField
        
        % Scenario tab controls
        scenarioSrcDropDown     matlab.ui.control.DropDown
        scenarioDstDropDown     matlab.ui.control.DropDown
        scenarioNumBundlesField matlab.ui.control.NumericEditField
        scenarioRoutingDropDown matlab.ui.control.DropDown
        scenarioPHYDropDown     matlab.ui.control.DropDown
        scenarioSpeedField      matlab.ui.control.NumericEditField
        runScenarioButton       matlab.ui.control.Button
    end
    
    properties
        % Log lines for the Logs panel
        logLines      cell = {}
    end
    
    methods
        function app = DTNApp()
            % Constructor: create scenario, config, and GUI
            
            startTime  = datetime(2025,1,1,0,0,0);
            stopTime   = startTime + days(1);
            sampleTime = 60; % seconds
            
            app.scenarioManager = dtn.ScenarioManager(startTime, stopTime, sampleTime);
            app.dtnConfig       = dtn.DTNConfig();
            app.viewer          = [];  % no viewer yet
            
            app.createUI();
            app.postInitSetup();
        end
        
        function delete(app)
            % Destructor: clean up
            if ~isempty(app.viewer) && isvalid(app.viewer)
                try
                    delete(app.viewer);
                catch
                end
            end
            
            if isvalid(app.fig)
                delete(app.fig);
            end
        end
    end
    
    methods (Access = private)
        
        function createUI(app)
            % Create the main window and layout
            
            app.fig = uifigure('Name', 'DTN Satellite GUI', ...
                'Position', [100 100 1200 700]);
            
            % Layout: left = tabs, right = logs panel
            figPos = app.fig.Position;
            figW   = figPos(3);
            figH   = figPos(4);
            margin = 20;
            logsW  = 350;
            
            % Logs panel (always visible on the right)
            app.logsPanel = uipanel(app.fig, ...
                'Title', 'Logs', ...
                'Position', [figW - logsW - margin, margin, logsW, figH - 2*margin]);
            app.createLogsPanelUI();
            
            % Tab group on the left (fixed width)
            tabW = figW - logsW - 3*margin;
            app.tabGroup = uitabgroup(app.fig, ...
                'Position', [margin, margin, tabW, figH - 2*margin]);
            
            % Tabs
            app.tabNodes    = uitab(app.tabGroup, 'Title', 'Nodes & Ping');
            app.tabSettings = uitab(app.tabGroup, 'Title', 'Settings');
            app.tabScenario = uitab(app.tabGroup, 'Title', 'Scenario');
            
            app.createNodesTabUI();
            app.createSettingsTabUI();
            app.createScenarioTabUI();
        end
        
        function createLogsPanelUI(app)
            % Logs panel: text area + clear button
            
            panelPos = app.logsPanel.Position;
            panelW   = panelPos(3);
            panelH   = panelPos(4);
            
            app.logTextArea = uitextarea(app.logsPanel, ...
                'Position', [10 50 panelW - 20 panelH - 60], ...
                'Editable', 'off');
            
            app.clearLogButton = uibutton(app.logsPanel, 'push', ...
                'Text', 'Clear Log', ...
                'Position', [10 10 100 30], ...
                'ButtonPushedFcn', @(src,evt) app.onClearLogButton());
            
            app.logLines = {};
            app.updateLogText();
        end
        
        function createNodesTabUI(app)
            % UI elements for Nodes & Ping tab
            
            % Open satellite viewer
            app.openViewerButton = uibutton(app.tabNodes, 'push', ...
                'Text', 'Open Satellite Viewer', ...
                'Position', [25 660 180 30], ...
                'ButtonPushedFcn', @(src,evt) app.onOpenViewerButton());
            
            % Controls panel (static size)
            panel = uipanel(app.tabNodes, ...
                'Title', 'Nodes & Ping Controls', ...
                'Position', [20 20 760 620]);
            
            % Node table
            app.nodesTable = uitable(panel, ...
                'Position', [10 330 540 260], ...
                'ColumnName', {'Type','Name','Lat (deg)','Lon (deg)','Alt (km)'}, ...
                'ColumnEditable', [false false false false false], ...
                'Data', {});
            
            % Add node controls
            uilabel(panel, 'Position', [10 300 100 20], 'Text', 'Node type:');
            app.nodeTypeDropDown = uidropdown(panel, ...
                'Position', [90 300 120 22], ...
                'Items', {'Satellite','Ground Station'});
            
            uilabel(panel, 'Position', [230 300 50 20], 'Text', 'Name:');
            app.nodeNameField = uieditfield(panel, 'text', ...
                'Position', [280 300 190 22], ...
                'Value', 'Node1');
            
            % Satellite-specific
            uilabel(panel, 'Position', [10 270 100 20], ...
                'Text', 'Sat Alt (km):');
            app.satAltField = uieditfield(panel, 'numeric', ...
                'Position', [110 270 80 22], ...
                'Value', 500);
            
            uilabel(panel, 'Position', [210 270 90 20], ...
                'Text', 'Incl (deg):');
            app.satIncField = uieditfield(panel, 'numeric', ...
                'Position', [290 270 80 22], ...
                'Value', 53);
            
            uilabel(panel, 'Position', [380 270 90 20], ...
                'Text', 'RAAN (deg):');
            app.satRAANField = uieditfield(panel, 'numeric', ...
                'Position', [380 250 80 22], ...
                'Value', 0);
            
            % Ground station-specific
            uilabel(panel, 'Position', [10 230 90 20], ...
                'Text', 'GS Lat (deg):');
            app.gsLatField = uieditfield(panel, 'numeric', ...
                'Position', [110 230 80 22], ...
                'Value', 32.774);
            
            uilabel(panel, 'Position', [210 230 90 20], ...
                'Text', 'GS Lon (deg):');
            app.gsLonField = uieditfield(panel, 'numeric', ...
                'Position', [290 230 80 22], ...
                'Value', -117.07);
            
            uilabel(panel, 'Position', [380 230 90 20], ...
                'Text', 'GS Alt (m):');
            app.gsAltField = uieditfield(panel, 'numeric', ...
                'Position', [380 210 80 22], ...
                'Value', 0);
            
            % Add / Remove buttons
            app.addNodeButton = uibutton(panel, 'push', ...
                'Text', 'Add Node', ...
                'Position', [10 180 150 30], ...
                'ButtonPushedFcn', @(src,evt) app.onAddNodeButton());
            
            app.removeNodeButton = uibutton(panel, 'push', ...
                'Text', 'Remove Selected Node', ...
                'Position', [180 180 200 30], ...
                'ButtonPushedFcn', @(src,evt) app.onRemoveNodeButton());
            
            % Ping controls
            uilabel(panel, 'Position', [10 135 80 20], 'Text', 'Ping From:');
            app.pingFromDropDown = uidropdown(panel, ...
                'Position', [90 135 180 22], ...
                'Items', {}, ...
                'ItemsData', {});
            
            uilabel(panel, 'Position', [10 105 80 20], 'Text', 'Ping To:');
            app.pingToDropDown = uidropdown(panel, ...
                'Position', [90 105 180 22], ...
                'Items', {}, ...
                'ItemsData', {});
            
            app.pingButton = uibutton(panel, 'push', ...
                'Text', 'Ping', ...
                'Position', [290 115 80 30], ...
                'ButtonPushedFcn', @(src,evt) app.onPingButton());
            
            % Reset Simulation
            app.resetButton = uibutton(panel, 'push', ...
                'Text', 'Reset Simulation', ...
                'Position', [10 50 200 30], ...
                'ButtonPushedFcn', @(src,evt) app.onResetButton());
        end
        
        function createSettingsTabUI(app)
            % UI for settings tab
            
            panel = uipanel(app.tabSettings, ...
                'Title', 'PHY & DTN Settings', ...
                'Position', [20 20 760 620]);
            
            % PHY mode
            uilabel(panel, 'Position', [20 560 80 20], 'Text', 'PHY Mode:');
            app.phyModeDropDown = uidropdown(panel, ...
                'Position', [100 560 150 22], ...
                'Items', {'SBand','KaBand','SatelliteRF'}, ...
                'Value', app.dtnConfig.phyMode);
            app.phyModeDropDown.ValueChangedFcn = @(src,evt) app.onPHYModeChanged();
            
            % Packet size
            uilabel(panel, 'Position', [20 520 100 20], 'Text', 'Packet size (B):');
            app.packetSizeField = uieditfield(panel, 'numeric', ...
                'Position', [130 520 100 22], ...
                'Value', app.dtnConfig.packetSizeBytes);
            app.packetSizeField.ValueChangedFcn = @(src,evt) app.onPacketSizeChanged();
            
            % Routing
            uilabel(panel, 'Position', [20 480 80 20], 'Text', 'Routing:');
            app.routingDropDown = uidropdown(panel, ...
                'Position', [100 480 150 22], ...
                'Items', {'Epidemic','PRoPHET','SprayAndWait'}, ...
                'Value', app.dtnConfig.routingMode);
            app.routingDropDown.ValueChangedFcn = @(src,evt) app.onRoutingChanged();
            
            % TTL
            uilabel(panel, 'Position', [20 440 100 20], 'Text', 'TTL (min):');
            app.ttlField = uieditfield(panel, 'numeric', ...
                'Position', [130 440 100 22], ...
                'Value', app.dtnConfig.ttlMinutes);
            app.ttlField.ValueChangedFcn = @(src,evt) app.onTTLChanged();
        end
        
        function createScenarioTabUI(app)
            % Scenario setup: define source, dest, bundles, routing, PHY
            
            panel = uipanel(app.tabScenario, ...
                'Title', 'Scenario Setup', ...
                'Position', [20 20 760 620]);
            
            uilabel(panel, 'Position', [20 560 120 20], 'Text', 'Source node:');
            app.scenarioSrcDropDown = uidropdown(panel, ...
                'Position', [140 560 200 22], ...
                'Items', {});
            
            uilabel(panel, 'Position', [20 520 120 20], 'Text', 'Destination node:');
            app.scenarioDstDropDown = uidropdown(panel, ...
                'Position', [140 520 200 22], ...
                'Items', {});
            
            uilabel(panel, 'Position', [20 480 120 20], 'Text', '# Bundles:');
            app.scenarioNumBundlesField = uieditfield(panel, 'numeric', ...
                'Position', [140 480 100 22], ...
                'Value', 3, 'Limits', [1 Inf]);
            
            uilabel(panel, 'Position', [20 440 120 20], 'Text', 'Routing:');
            app.scenarioRoutingDropDown = uidropdown(panel, ...
                'Position', [140 440 200 22], ...
                'Items', {'Epidemic','PRoPHET','SprayAndWait'}, ...
                'Value', 'Epidemic');
            
            uilabel(panel, 'Position', [20 400 120 20], 'Text', 'PHY:');
            app.scenarioPHYDropDown = uidropdown(panel, ...
                'Position', [140 400 200 22], ...
                'Items', {'SBand','KaBand','SatelliteRF'}, ...
                'Value', app.dtnConfig.phyMode);
            
            % Playback speed (x real time)
            uilabel(panel, 'Position', [20 360 200 20], ...
                'Text', 'Playback speed (x real time):');
            app.scenarioSpeedField = uieditfield(panel, 'numeric', ...
                'Position', [220 360 80 22], ...
                'Value', 5, ...
                'Limits', [0 Inf]);   % 0 = run as fast as possible
            
            app.runScenarioButton = uibutton(panel, 'push', ...
                'Text', 'Run Scenario', ...
                'Position', [20 320 150 30], ...
                'ButtonPushedFcn', @(src,evt) app.onRunScenarioButton());
            
            uilabel(panel, 'Position', [20 280 500 40], ...
                'Text', sprintf(['Example: Source = SAT-4, Dest = SAT-9, Bundles = 3.\n' ...
                                 'Routing will be simulated with store-carry-forward (Epidemic for now).']));
        end
        
        function postInitSetup(app)
            % Spawn 12 satellites in a ring + one ground station
            
            app.logLines = {};
            app.updateLogText();
            
            % new empty scenario
            app.scenarioManager.nodes    = struct('name',{},'type',{},'handle',{}, ...
                                                  'latDeg',{},'lonDeg',{},'altM',{});
            app.scenarioManager.accesses = struct('nodeA',{},'nodeB',{},'handle',{});
            
            % 12 LEO sats in one plane with different RAANs
            N = 12;
            altKm = 500;
            incDeg = 53;
            for k = 1:N
                name = sprintf('SAT-%d', k);
                raan = (k-1) * (360/N);
                app.scenarioManager.addSatellite(name, altKm, incDeg, raan);
            end
            
            % Ground station at SDSU-ish
            app.scenarioManager.addGroundStation('GS-1', 32.774, -117.07, 0);
            
            app.updateNodeTable();
            app.updatePingDropdowns();
            app.updateScenarioNodeDropdowns();
        end
        
        %% Log helpers
        
        function updateLogText(app)
            if isempty(app.logLines)
                app.logTextArea.Value = {''};
            else
                app.logTextArea.Value = app.logLines;
            end
        end
        
        function onClearLogButton(app)
            app.logLines = {};
            app.updateLogText();
        end

        function appendLogFromSim(app, msg)
            % Called by DTNSimulator via logCallback while the sim runs
            app.logLines{end+1} = msg;
            app.updateLogText();
        end
        
        %% Callbacks
        
        function onOpenViewerButton(app)
            % Open (or reuse) the fancy satelliteScenarioViewer window
            
            if isempty(app.viewer) || ~isvalid(app.viewer)
                app.viewer = satelliteScenarioViewer(app.scenarioManager.sc);
            end
        end
        
        function onAddNodeButton(app)
            nodeType = app.nodeTypeDropDown.Value;
            name     = strtrim(app.nodeNameField.Value);
            if isempty(name)
                uialert(app.fig, 'Node name cannot be empty.', 'Error');
                return;
            end
            
            if app.scenarioManager.hasNode(name)
                uialert(app.fig, 'Node with this name already exists.', 'Error');
                return;
            end
            
            try
                switch nodeType
                    case 'Satellite'
                        altKm = app.satAltField.Value;
                        inc   = app.satIncField.Value;
                        raan  = app.satRAANField.Value;
                        app.scenarioManager.addSatellite(name, altKm, inc, raan);
                    case 'Ground Station'
                        lat  = app.gsLatField.Value;
                        lon  = app.gsLonField.Value;
                        altM = app.gsAltField.Value;
                        app.scenarioManager.addGroundStation(name, lat, lon, altM);
                end
            catch ME
                uialert(app.fig, sprintf('Error adding node:\n%s', ME.message), 'Error');
                return;
            end
            
            app.updateNodeTable();
            app.updatePingDropdowns();
            app.updateScenarioNodeDropdowns();
        end
        
        function onRemoveNodeButton(app)
            idx = app.nodesTable.Selection;
            if isempty(idx)
                uialert(app.fig, 'Select a row in the node table to remove.', 'Info');
                return;
            end
            row = idx(1);
            data = app.nodesTable.Data;
            name = data{row,2};
            
            app.scenarioManager.removeNode(name);
            app.updateNodeTable();
            app.updatePingDropdowns();
            app.updateScenarioNodeDropdowns();
        end
        
        function onPingButton(app)
            fromName = app.pingFromDropDown.Value;
            toName   = app.pingToDropDown.Value;
            
            if isempty(fromName) || isempty(toName)
                uialert(app.fig, 'Select both From and To nodes.', 'Info');
                return;
            end
            if strcmp(fromName, toName)
                uialert(app.fig, 'From and To cannot be the same node.', 'Info');
                return;
            end
            
            % Use viewer time if open, else scenario start time
            t = app.scenarioManager.startTime;
            if ~isempty(app.viewer) && isvalid(app.viewer)
                try
                    t = app.viewer.CurrentTime;
                catch
                end
            end
            
            % Get positions directly via states() so we match the viewer
            [x1, y1, z1] = app.scenarioManager.getXYZ(fromName, t);
            [x2, y2, z2] = app.scenarioManager.getXYZ(toName, t);
            
            p1 = [x1 y1 z1];
            p2 = [x2 y2 z2];
            
            % First: line-of-sight test (Earth occlusion)
            if ~app.hasLOSFromXYZ(p1, p2)
                msg = sprintf('Cannot communicate: no line-of-sight (Earth occlusion).\nRange would be %.1f km.', ...
                    norm(p1-p2));
                uialert(app.fig, msg, 'No LOS');
                entry = sprintf('[PING FAIL] %s -> %s at %s, NO LOS (approx range %.1f km)', ...
                    fromName, toName, datestr(t), norm(p1-p2));
                app.logLines{end+1} = entry;
                app.updateLogText();
                return;
            end
            
            % Range check vs PHY
            dKm = norm(p1 - p2);
            profile = dtn.PHYProfiles.getProfile(app.dtnConfig.phyMode);
            if dKm > profile.maxRangeKm
                msg = sprintf(['Cannot communicate: range %.1f km exceeds max range %.2f km ' ...
                               'for PHY mode %s.'], ...
                               dKm, profile.maxRangeKm, profile.name);
                uialert(app.fig, msg, 'Out of Range');
                entry = sprintf('[PING FAIL] %s -> %s at %s, range=%.1f km > %.1f km (PHY=%s)', ...
                    fromName, toName, datestr(t), dKm, profile.maxRangeKm, profile.name);
                app.logLines{end+1} = entry;
                app.updateLogText();
                return;
            end
            
            % RTT model:
            %   RTT = 2 * propagation + 2 * serialization + 2 * handshake
            dM  = dKm * 1e3;
            c   = 3e8; % speed of light m/s
            prop_s = 2 * dM / c;    % there & back
            
            packetBits = app.dtnConfig.packetSizeBytes * 8;
            txOneWay_s = packetBits / profile.dataRate_bps;
            
            handshake_s = profile.handshakeOverhead_s;
            
            rtt_s  = prop_s + 2*txOneWay_s + 2*handshake_s;
            rtt_ms = rtt_s * 1e3;
            
            msg = sprintf(['Ping %s -> %s at %s\nRange: %.1f km\n' ...
                           'RTT: %.3f ms (prop=%.3f ms, PHY=%.3f ms, handshake=%.3f ms)'], ...
                fromName, toName, datestr(t), dKm, ...
                rtt_ms, prop_s*1e3, 2*txOneWay_s*1e3, 2*handshake_s*1e3);
            uialert(app.fig, msg, 'Ping Result');
            
            % Log successful ping
            entry = sprintf(['[PING] %s -> %s at %s, range=%.1f km, RTT=%.3f ms ' ...
                             '(PHY=%s, pkt=%d B)'], ...
                fromName, toName, datestr(t), dKm, rtt_ms, ...
                profile.name, app.dtnConfig.packetSizeBytes);
            app.logLines{end+1} = entry;
            app.updateLogText();
        end
        
        function tf = hasLOSFromXYZ(app, p1Km, p2Km)
            % hasLOSFromXYZ - geometric line-of-sight test vs Earth sphere
            ReKm = 6371;
            d = p2Km - p1Km;
            r1 = p1Km;
            
            a = dot(d,d);
            b = 2*dot(r1,d);
            c = dot(r1,r1) - ReKm^2;
            
            disc = b^2 - 4*a*c;
            if disc <= 0
                tf = true;
                return;
            end
            
            s1 = (-b - sqrt(disc)) / (2*a);
            s2 = (-b + sqrt(disc)) / (2*a);
            
            if (s1 >= 0 && s1 <= 1) || (s2 >= 0 && s2 <= 1)
                tf = false;
            else
                tf = true;
            end
        end
        
        function onResetButton(app)
            % Reset simulation: new scenario, same time window, default nodes
            
            % Close viewer (tied to old scenario)
            if ~isempty(app.viewer) && isvalid(app.viewer)
                try
                    delete(app.viewer);
                catch
                end
            end
            app.viewer = [];
            
            % New scenario
            startTime  = app.scenarioManager.startTime;
            stopTime   = app.scenarioManager.stopTime;
            sampleTime = app.scenarioManager.sampleTime;
            app.scenarioManager = dtn.ScenarioManager(startTime, stopTime, sampleTime);
            
            app.postInitSetup();
        end
        
        function onPHYModeChanged(app)
            app.dtnConfig.phyMode = app.phyModeDropDown.Value;
        end
        
        function onPacketSizeChanged(app)
            app.dtnConfig.packetSizeBytes = app.packetSizeField.Value;
        end
        
        function onRoutingChanged(app)
            app.dtnConfig.routingMode = app.routingDropDown.Value;
        end
        
        function onTTLChanged(app)
            app.dtnConfig.ttlMinutes = app.ttlField.Value;
        end
        
        function onRunScenarioButton(app)
            % Run DTN scenario: uses DTNSimulator
            
            srcName  = app.scenarioSrcDropDown.Value;
            dstName  = app.scenarioDstDropDown.Value;
            nBundles = app.scenarioNumBundlesField.Value;
            routing  = app.scenarioRoutingDropDown.Value;
            phyMode  = app.scenarioPHYDropDown.Value;
            
            if isempty(srcName) || isempty(dstName)
                uialert(app.fig, 'Select both source and destination.', 'Info');
                return;
            end
            if strcmp(srcName, dstName)
                uialert(app.fig, 'Source and destination must be different.', 'Info');
                return;
            end
            
            cfg.srcName        = srcName;
            cfg.dstName        = dstName;
            cfg.numBundles     = nBundles;
            cfg.routing        = routing;
            cfg.phyMode        = phyMode;
            cfg.startTime      = app.scenarioManager.startTime;
            
            % Simulation horizon + resolution
            cfg.horizonMinutes = 60;    % simulate 1 hour (adjust as needed)
            cfg.stepSeconds    = 1;     % 1-second simulation steps
            
            % Real-time playback speed (0 => run as fast as possible)
            cfg.realTimeSpeed  = app.scenarioSpeedField.Value;
            
            cfg.ttlMinutes     = app.dtnConfig.ttlMinutes;
            cfg.packetSizeBytes = app.dtnConfig.packetSizeBytes;
            
            % Create simulator
            sim = dtn.DTNSimulator(cfg);
            
            % Clear log and stream messages live from simulator
            app.logLines = {};
            app.updateLogText();
            sim.logCallback = @(msg) app.appendLogFromSim(msg);
            
            % Run simulation (logs will appear as it runs)
            sim.run(app.scenarioManager, app.viewer);
        end

        
        %% Helper updates
        
        function updateNodeTable(app)
            nodes = app.scenarioManager.nodes;
            n = numel(nodes);
            data = cell(n,5);
            for k = 1:n
                nd = nodes(k);
                data{k,1} = nd.type;
                data{k,2} = nd.name;
                data{k,3} = nd.latDeg;
                data{k,4} = nd.lonDeg;
                data{k,5} = nd.altM / 1000; % km
            end
            app.nodesTable.Data = data;
        end
        
        function updatePingDropdowns(app)
            names = app.scenarioManager.getNodeNames();
            if isempty(names)
                app.pingFromDropDown.Items = {};
                app.pingToDropDown.Items   = {};
            else
                app.pingFromDropDown.Items = names;
                app.pingToDropDown.Items   = names;
                app.pingFromDropDown.Value = names{1};
                app.pingToDropDown.Value   = names{min(2,numel(names))};
            end
        end
        
        function updateScenarioNodeDropdowns(app)
            names = app.scenarioManager.getNodeNames();
            if isempty(names)
                app.scenarioSrcDropDown.Items = {};
                app.scenarioDstDropDown.Items = {};
            else
                app.scenarioSrcDropDown.Items = names;
                app.scenarioDstDropDown.Items = names;
                app.scenarioSrcDropDown.Value = names{1};
                app.scenarioDstDropDown.Value = names{min(2,numel(names))};
            end
        end
    end
end
