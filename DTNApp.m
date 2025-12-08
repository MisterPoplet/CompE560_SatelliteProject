classdef DTNApp < handle
    % DTNApp - GUI for Delay Tolerant Network Satellite Simulator
    %
    % Left side:
    %   - Tabs:
    %       * Nodes & Ping: add/remove nodes, manual pings, reset, open viewer
    %       * Settings & Scenario: PHY + DTN config + scenario timing
    %       * Packets: per-bundle source/destination + release time
    %       * Info: routing & PHY explanations
    %       * Help: how to use the software
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
        tabScenario       matlab.ui.container.Tab   % "Settings & Scenario"
        tabPackets        matlab.ui.container.Tab
        tabInfo           matlab.ui.container.Tab
        tabHelp           matlab.ui.container.Tab
        
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
        
        resetButton       matlab.ui.control.Button   % Nodes tab reset
        
        % Settings & Scenario tab controls
        scenarioRoutingDropDown   matlab.ui.control.DropDown
        scenarioPHYDropDown       matlab.ui.control.DropDown
        scenarioTTLField          matlab.ui.control.NumericEditField
        scenarioPacketSizeField   matlab.ui.control.NumericEditField
        scenarioStartOffsetField  matlab.ui.control.NumericEditField
        scenarioSpeedField        matlab.ui.control.NumericEditField
        runScenarioButton         matlab.ui.control.Button
        stopScenarioButton        matlab.ui.control.Button  % mapped to reset
        
        % Packets tab controls
        packetTable        matlab.ui.control.Table
        addPacketButton    matlab.ui.control.Button
        removePacketButton matlab.ui.control.Button
        
        % Info tab controls
        infoRoutingTextArea matlab.ui.control.TextArea
        infoPHYTextArea     matlab.ui.control.TextArea
        
        % Help tab controls
        helpManualTextArea matlab.ui.control.TextArea
        
        % State flags
        scenarioRunning    logical = false
        viewerOpening      logical = false
        currentSimulator   = []
    end
    
    properties
        % Log lines for the Logs panel
        logLines      cell = {}
    end
    
    methods
        function app = DTNApp()
            % Constructor: create scenario, config, and GUI
            
            startTime  = datetime(2025,1,1,0,0,0);
            stopTime   = startTime + days(1);   % 24h scenario window
            sampleTime = 60;                    % seconds
            
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
        
        function lockUIForScenario(app)
            % lockUIForScenario - disable controls that should not change
            % while a scenario is running
            
            % Nodes & Ping tab
            try
                app.addNodeButton.Enable      = 'off';
                app.removeNodeButton.Enable   = 'off';
                app.nodeNameField.Enable      = 'off';
                app.nodeTypeDropDown.Enable   = 'off';
                app.satAltField.Enable        = 'off';
                app.satIncField.Enable        = 'off';
                app.satRAANField.Enable       = 'off';
                app.gsLatField.Enable         = 'off';
                app.gsLonField.Enable         = 'off';
                app.gsAltField.Enable         = 'off';
                app.pingFromDropDown.Enable   = 'off';
                app.pingToDropDown.Enable     = 'off';
                app.pingButton.Enable         = 'off';
                app.openViewerButton.Enable   = 'off';
                % resetButton remains enabled
            catch
            end
            
            % Settings & Scenario tab
            try
                app.scenarioRoutingDropDown.Enable   = 'off';
                app.scenarioPHYDropDown.Enable       = 'off';
                app.scenarioTTLField.Enable          = 'off';
                app.scenarioPacketSizeField.Enable   = 'off';
                app.scenarioStartOffsetField.Enable  = 'off';
                app.scenarioSpeedField.Enable        = 'off';
            catch
            end
            
            % Packets tab
            try
                app.packetTable.Enable        = 'off';
                app.addPacketButton.Enable    = 'off';
                app.removePacketButton.Enable = 'off';
            catch
            end
            
            % Run is off; Stop/Reset stay usable
            try
                app.runScenarioButton.Enable  = 'off';
                app.stopScenarioButton.Enable = 'on';
                app.resetButton.Enable        = 'on';
            catch
            end
        end
        
        function unlockUIAfterScenario(app)
            % unlockUIForScenario - re-enable controls after reset
            
            % Nodes & Ping tab
            try
                app.addNodeButton.Enable      = 'on';
                app.removeNodeButton.Enable   = 'on';
                app.nodeNameField.Enable      = 'on';
                app.nodeTypeDropDown.Enable   = 'on';
                app.satAltField.Enable        = 'on';
                app.satIncField.Enable        = 'on';
                app.satRAANField.Enable       = 'on';
                app.gsLatField.Enable         = 'on';
                app.gsLonField.Enable         = 'on';
                app.gsAltField.Enable         = 'on';
                app.pingFromDropDown.Enable   = 'on';
                app.pingToDropDown.Enable     = 'on';
                app.pingButton.Enable         = 'on';
                app.openViewerButton.Enable   = 'on';
                app.resetButton.Enable        = 'on';
            catch
            end
            
            % Settings & Scenario tab
            try
                app.scenarioRoutingDropDown.Enable   = 'on';
                app.scenarioPHYDropDown.Enable       = 'on';
                app.scenarioTTLField.Enable          = 'on';
                app.scenarioPacketSizeField.Enable   = 'on';
                app.scenarioStartOffsetField.Enable  = 'on';
                app.scenarioSpeedField.Enable        = 'on';
                app.runScenarioButton.Enable         = 'on';
                app.stopScenarioButton.Enable        = 'on';
            catch
            end
            
            % Packets tab
            try
                app.packetTable.Enable        = 'on';
                app.addPacketButton.Enable    = 'on';
                app.removePacketButton.Enable = 'on';
            catch
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
            app.tabScenario = uitab(app.tabGroup, 'Title', 'Settings & Scenario');
            app.tabPackets  = uitab(app.tabGroup, 'Title', 'Packets');
            app.tabInfo     = uitab(app.tabGroup, 'Title', 'Info');
            app.tabHelp     = uitab(app.tabGroup, 'Title', 'Help');
            
            app.createNodesTabUI();
            app.createScenarioTabUI();
            app.createPacketsTabUI();
            app.createInfoTabUI();
            app.createHelpTabUI();
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
        
        function createScenarioTabUI(app)
            % Settings & Scenario setup (no global src/dst)
            
            panel = uipanel(app.tabScenario, ...
                'Title', 'Settings & Scenario', ...
                'Position', [20 20 760 620]);
            
            y = 560;
            dy = 40;
            
            % Routing
            uilabel(panel, 'Position', [20 y 120 20], 'Text', 'Routing:');
            app.scenarioRoutingDropDown = uidropdown(panel, ...
                'Position', [140 y 200 22], ...
                'Items', {'Epidemic','PRoPHET','SprayAndWait'}, ...
                'Value', 'Epidemic');
            y = y - dy;
            
            % PHY
            uilabel(panel, 'Position', [20 y 120 20], 'Text', 'PHY:');
            app.scenarioPHYDropDown = uidropdown(panel, ...
                'Position', [140 y 200 22], ...
                'Items', {'SBand','KaBand','SatelliteRF'}, ...
                'Value', app.dtnConfig.phyMode);
            y = y - dy;
            
            % TTL
            uilabel(panel, 'Position', [20 y 120 20], 'Text', 'TTL (min):');
            app.scenarioTTLField = uieditfield(panel, 'numeric', ...
                'Position', [140 y 100 22], ...
                'Value', app.dtnConfig.ttlMinutes, ...
                'Limits', [0 Inf]);
            y = y - dy;
            
            % Packet size
            uilabel(panel, 'Position', [20 y 120 20], 'Text', 'Packet size (B):');
            app.scenarioPacketSizeField = uieditfield(panel, 'numeric', ...
                'Position', [140 y 100 22], ...
                'Value', app.dtnConfig.packetSizeBytes, ...
                'Limits', [1 Inf]);
            y = y - dy;
            
            % Simulation start offset
            uilabel(panel, 'Position', [20 y 220 20], ...
                'Text', 'Simulation start offset (min):');
            app.scenarioStartOffsetField = uieditfield(panel, 'numeric', ...
                'Position', [240 y 80 22], ...
                'Value', 0, ...
                'Limits', [0 Inf]);
            y = y - dy;
            
            % Playback speed (x real time)
            uilabel(panel, 'Position', [20 y 220 20], ...
                'Text', 'Playback speed (x real time):');
            app.scenarioSpeedField = uieditfield(panel, 'numeric', ...
                'Position', [240 y 80 22], ...
                'Value', 5, ...
                'Limits', [0 Inf]);   % 0 = run as fast as possible
            y = y - dy;
            
            % Run Scenario button
            app.runScenarioButton = uibutton(panel, 'push', ...
                'Text', 'Run Scenario', ...
                'Position', [20 y 150 30], ...
                'ButtonPushedFcn', @(src,evt) app.onRunScenarioButton());
            
            % Stop scenario mapped to reset (hard reset)
            app.stopScenarioButton = uibutton(panel, 'push', ...
                'Text', 'Reset Simulation', ...
                'Position', [190 y 150 30], ...
                'ButtonPushedFcn', @(src,evt) app.onResetButton());
            
            % Info text
            uilabel(panel, 'Position', [20 y-40 660 40], ...
                'Text', sprintf(['Routing/PHY/TTL/packet size here apply to ALL bundles.\n' ...
                                 'Per-bundle source/destination and release times are set in the Packets tab.']));
        end
        
        function createPacketsTabUI(app)
            % Packets tab: bundle release schedule with per-bundle src/dst
            
            panel = uipanel(app.tabPackets, ...
                'Title', 'Bundle Schedule', ...
                'Position', [20 20 760 620]);
            
            % Table of bundles
            app.packetTable = uitable(panel, ...
                'Position', [10 120 520 480], ...
                'ColumnName', {'Bundle ID','Release offset (min)','Source','Destination'}, ...
                'ColumnEditable', [false true true true], ...
                'Data', {}, ...
                'ColumnFormat', {'numeric','numeric','char','char'});
            
            % Add / Remove packet buttons
            app.addPacketButton = uibutton(panel, 'push', ...
                'Text', 'Add Packet', ...
                'Position', [550 540 200 30], ...
                'ButtonPushedFcn', @(src,evt) app.onAddPacketButton());
            
            app.removePacketButton = uibutton(panel, 'push', ...
                'Text', 'Remove Selected Packet', ...
                'Position', [550 500 200 30], ...
                'ButtonPushedFcn', @(src,evt) app.onRemovePacketButton());
            
            % Hint
            uilabel(panel, 'Position', [10 80 720 40], ...
                'Text', ['Configure per-bundle source/destination and release times (minutes from scenario start).' ...
                         ' Schedule is sorted automatically when you run a scenario.']);
        end
        
        function createInfoTabUI(app)
            % Info tab: routing & PHY descriptions + this GUI's assumptions
            
            panel = uipanel(app.tabInfo, ...
                'Title', 'Routing & PHY Information', ...
                'Position', [20 20 760 620]);
            
            % Routing info
            app.infoRoutingTextArea = uitextarea(panel, ...
                'Position', [10 320 740 280], ...
                'Editable', 'off');
            
            % PHY info
            app.infoPHYTextArea = uitextarea(panel, ...
                'Position', [10 20 740 280], ...
                'Editable', 'off');
            
            app.populateInfoText();
        end
        
        function createHelpTabUI(app)
            % Help tab: manual for the GUI
            
            panel = uipanel(app.tabHelp, ...
                'Title', 'Help & Manual', ...
                'Position', [20 20 760 620]);
            
            app.helpManualTextArea = uitextarea(panel, ...
                'Position', [10 10 740 580], ...
                'Editable', 'off');
            
            app.populateHelpText();
        end
        
        function populateInfoText(app)
            % Populate Info tab with routing + PHY explanations, including GUI assumptions
            
            try
                pSB = dtn.PHYProfiles.getProfile('SBand');
                pKA = dtn.PHYProfiles.getProfile('KaBand');
                pRF = dtn.PHYProfiles.getProfile('SatelliteRF');
            catch
                pSB.maxRangeKm = 2000; pSB.dataRate_bps = 1e6;  pSB.name = 'SBand';
                pKA.maxRangeKm = 3000; pKA.dataRate_bps = 1e8;  pKA.name = 'KaBand';
                pRF.maxRangeKm = 3000; pRF.dataRate_bps = 5e7;  pRF.name = 'SatelliteRF';
            end
            
            routingTxt = {
                'ROUTING PROTOCOLS (DTN bundle layer):'
                ''
                'Epidemic:'
                '  - Flooding: each node forwards bundles to all neighbors that do not have them.'
                '  - Lowest delay, highest overhead (many duplicates).'
                ''
                'PRoPHET:'
                '  - Probabilistic: nodes maintain delivery predictabilities based on encounter history.'
                '  - Forward only to neighbors with higher delivery chance.'
                '  - In this GUI: currently implemented as Epidemic behavior internally, but exposed'
                '    so experiments can vary config and logs.'
                ''
                'Spray-and-Wait:'
                '  - Limit the number of copies per bundle; first "spray" L copies, then "wait".'
                '  - Lower overhead than Epidemic, potentially higher delay.'
                '  - Here: also modeled as Epidemic for now, but the mode is logged.'
                ''
                'Store-Carry-Forward:'
                '  - All routing is on top of store-carry-forward: nodes store bundles locally,'
                '    carry them while moving, and forward on contact.'
                };
            
            app.infoRoutingTextArea.Value = routingTxt;
            
            phyTxt = {
                'PHY PROFILES & ASSUMPTIONS:'
                ''
                sprintf('SBand (model): max range ~%.0f km, data rate ~%.0f bps', pSB.maxRangeKm, pSB.dataRate_bps)
                '  - 2–4 GHz class link, lower data rate, long range.'
                '  - Often used for TT&C or low-rate payloads.'
                ''
                sprintf('KaBand (model): max range ~%.0f km, data rate ~%.0f bps', pKA.maxRangeKm, pKA.dataRate_bps)
                '  - 26–40 GHz class, high data rate, narrower beams.'
                '  - Here we model it as high throughput but with a finite range to keep LEO-style'
                '    connectivity realistic (not a pure physics link budget).'
                ''
                sprintf('SatelliteRF (model): max range ~%.0f km, data rate ~%.0f bps', pRF.maxRangeKm, pRF.dataRate_bps)
                '  - Abstract satellite-satellite RF link for DTN experiments.'
                '  - Long range, moderate rate, not tied to particular band.'
                ''
                'EARTH OCCLUSION:'
                '  - A simple spherical Earth LOS test is used: if the straight line between nodes'
                '    intersects the Earth sphere, the link is blocked.'
                ''
                'LEO vs GEO USE (rough):'
                '  - LEO (~500–2000 km): intermittent ground contacts, good DTN playground.'
                '  - GEO (~35786 km): nearly static view, higher latency; still interesting for DTN'
                '    robustness but less for connectivity gaps.'
                ''
                'These are teaching/experimentation profiles, not full link-budget models.'
                };
            
            app.infoPHYTextArea.Value = phyTxt;
        end
        
        function populateHelpText(app)
            % Populate Help tab with a simple manual
            
            txt = {
                'DTN SATELLITE GUI - HELP & MANUAL'
                ''
                'OVERVIEW'
                '--------'
                'This tool simulates a Delay Tolerant Network (DTN) over a satellite constellation.'
                'It uses MATLAB''s satelliteScenario for orbits and a DTN engine for bundles, TTL,'
                'routing, PHY-aware contacts, and per-bundle release times.'
                ''
                'TABS'
                '----'
                '1. Nodes & Ping:'
                '   - Add/remove satellites and ground stations.'
                '   - Open the satelliteScenarioViewer.'
                '   - Manually ping between nodes using PHY + packet size from the Scenario tab.'
                '   - Reset Simulation: re-creates the default constellation and viewer.'
                ''
                '2. Settings & Scenario:'
                '   - Choose routing (Epidemic / PRoPHET / Spray-and-Wait).'
                '   - Choose PHY profile (SBand / KaBand / SatelliteRF).'
                '   - Set bundle TTL (minutes, 0 disables expiry).'
                '   - Set bundle packet size (bytes, affects PHY serialization delay).'
                '   - Set simulation start offset (minutes from scenario start).'
                '   - Set playback speed (x real-time), where 0 = run as fast as possible.'
                '   - Run Scenario / Reset Simulation.'
                ''
                '3. Packets:'
                '   - Each row = one bundle:'
                '       * Bundle ID (auto-assigned, after sorting by time).'
                '       * Release offset (min) = when the bundle is injected at its Source.'
                '       * Source = node name for this bundle''s origin.'
                '       * Destination = node name for this bundle''s destination.'
                '   - Add Packet / Remove Selected Packet.'
                '   - When you run, the table is sorted by time and IDs reset to 1..N.'
                ''
                '4. Info:'
                '   - Explanations of routing modes and PHY models used in this simulator.'
                ''
                '5. Help:'
                '   - This manual.'
                ''
                'SIMULATION TIMING'
                '-----------------'
                '   - The satelliteScenario defines a start and end time.'
                '   - "Simulation start offset" chooses when the DTN engine starts stepping within'
                '     that window (e.g. +60 minutes).'
                '   - Each bundle has a release offset (min from scenario start). Its releaseTime'
                '     = startTime + offset.'
                '   - TTL is measured from the bundle''s releaseTime, not from t=0.'
                ''
                'CONSTRAINTS ENFORCED BY THE GUI'
                '--------------------------------'
                '   - All bundle release times must lie within the satelliteScenario window.'
                '   - Simulation start offset must be <= earliest bundle release offset.'
                '   - During a scenario run, node editing, scenario settings, and packet schedule'
                '     are frozen; only Reset is allowed.'
                ''
                'LOG INTERPRETATION'
                '------------------'
                '   - "RELEASED at X": bundle was created at node X at its releaseTime.'
                '   - "forwarded A -> B": bundle propagated from A to B during that time step.'
                '   - "DELIVERED at Y": bundle reached its per-bundle Destination Y.'
                '   - "EXPIRED (TTL=...)": bundle timed out after TTL (from releaseTime).'
                '   - "NOT simulated": releaseTime > simulation end; never injected.'
                '   - "NOT delivered within horizon": injected but didn''t reach destination or expire'
                '     before the scenario end time.'
                ''
                'BUNDLE SUMMARY LINES'
                '---------------------'
                '   - At the end of the run, each bundle prints:'
                '       * Total delivery delay (from releaseTime).'
                '       * Path delay (simulation time from release to delivered).'
                '       * PHY-extra delay (per-hop PHY serialization/handshake * hops).'
                '       * Hops count and PHY profile.'
                '       * Release and delivered timestamps.'
                '';
            };
            
            app.helpManualTextArea.Value = txt;
        end
        
        function postInitSetup(app)
            % Spawn 12 satellites in a ring + one ground station
            % and initialize a default packet schedule
            
            app.logLines = {};
            app.updateLogText();
            
            % new empty scenario
            app.scenarioManager.nodes    = struct('name',{},'type',{},'handle',{}, ...
                                                  'latDeg',{},'lonDeg',{},'altM',{});
            app.scenarioManager.accesses = struct('nodeA',{},'nodeB',{},'handle',{});
            
            % 12 LEO sats with different RAANs
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
            app.updatePacketTableNodeLists();
            app.initDefaultPackets();
        end
        
        function initDefaultPackets(app)
            % Initialize default 3 packets at 0, 6, and 20 minutes
            
            if isempty(app.packetTable) || ~isvalid(app.packetTable)
                return;
            end
            
            names = app.scenarioManager.getNodeNames();
            if numel(names) < 2
                % fallback
                srcDefault = '';
                dstDefault = '';
            else
                srcDefault = names{1};
                dstDefault = names{2};
            end
            
            offsets = [0; 6; 20];
            n = numel(offsets);
            data = cell(n,4);
            for i = 1:n
                data{i,1} = i;             % Bundle ID
                data{i,2} = offsets(i);    % Release offset (min)
                data{i,3} = srcDefault;    % Source
                data{i,4} = dstDefault;    % Destination
            end
            app.packetTable.Data = data;
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
        
        %% Packet schedule helpers
        
        function onAddPacketButton(app)
            data = app.packetTable.Data;
            if isempty(data)
                nextId = 1;
            else
                ids = cell2mat(data(:,1));
                nextId = max(ids) + 1;
            end
            
            names = app.scenarioManager.getNodeNames();
            if numel(names) < 2
                srcDefault = '';
                dstDefault = '';
            else
                srcDefault = names{1};
                dstDefault = names{2};
            end
            
            newRow = {nextId, 0, srcDefault, dstDefault};
            app.packetTable.Data = [data; newRow];
        end
        
        function onRemovePacketButton(app)
            idx = app.packetTable.Selection;
            if isempty(idx)
                uialert(app.fig, 'Select a packet row to remove.', 'Info');
                return;
            end
            row = idx(1);
            data = app.packetTable.Data;
            if row >= 1 && row <= size(data,1)
                data(row,:) = [];
            end
            app.packetTable.Data = data;
        end
        
        function [releaseOffsetsMinutes, srcNames, dstNames, numBundles] = getPacketSchedule(app)
            % Extract and sort the packet schedule from packetTable.
            % Returns:
            %   releaseOffsetsMinutes - row vector of offsets (min), sorted ascending
            %   srcNames, dstNames    - 1xN cell arrays of strings, same sorted order
            %   numBundles            - number of bundles
            
            data = app.packetTable.Data;
            names = app.scenarioManager.getNodeNames();
            
            if isempty(data)
                % If empty: create a single default bundle at t=0 between first two nodes
                if numel(names) < 2
                    uialert(app.fig, 'Need at least 2 nodes to create a packet.', 'Error');
                    releaseOffsetsMinutes = [];
                    srcNames = {};
                    dstNames = {};
                    numBundles = 0;
                    return;
                end
                srcDefault = names{1};
                dstDefault = names{2};
                data = {1, 0, srcDefault, dstDefault};
                app.packetTable.Data = data;
            end
            
            nRows = size(data,1);
            offsets = zeros(nRows,1);
            srcNames = cell(1,nRows);
            dstNames = cell(1,nRows);
            
            for i = 1:nRows
                % Release offset
                val = data{i,2};
                if isempty(val)
                    offsets(i) = 0;
                else
                    offsets(i) = double(val);
                end
                
                % Force everything to char (uitable likes char, not string objects)
                srcNames{i} = strtrim(char(data{i,3}));
                dstNames{i} = strtrim(char(data{i,4}));
            end

            % Validate sources/dests
            for i = 1:nRows
                s = srcNames{i};
                d = dstNames{i};
                
                if isempty(s) || isempty(d)
                    uialert(app.fig, sprintf('Packet row %d: Source and Destination must be set.', i), 'Error');
                    releaseOffsetsMinutes = [];
                    srcNames = {};
                    dstNames = {};
                    numBundles = 0;
                    return;
                end
                if strcmp(s, d)
                    uialert(app.fig, sprintf('Packet row %d: Source and Destination must be different.', i), 'Error');
                    releaseOffsetsMinutes = [];
                    srcNames = {};
                    dstNames = {};
                    numBundles = 0;
                    return;
                end
                if ~any(strcmp(names, s))
                    uialert(app.fig, sprintf('Packet row %d: Source "%s" is not a valid node.', i, s), 'Error');
                    releaseOffsetsMinutes = [];
                    srcNames = {};
                    dstNames = {};
                    numBundles = 0;
                    return;
                end
                if ~any(strcmp(names, d))
                    uialert(app.fig, sprintf('Packet row %d: Destination "%s" is not a valid node.', i, d), 'Error');
                    releaseOffsetsMinutes = [];
                    srcNames = {};
                    dstNames = {};
                    numBundles = 0;
                    return;
                end
            end
            
            % Sort by offset ascending
            [offsetsSorted, idx] = sort(offsets);
            n = numel(offsetsSorted);
            releaseOffsetsMinutes = offsetsSorted(:).';  % row vector
            
            srcNames = srcNames(idx);
            dstNames = dstNames(idx);
            numBundles = n;
            
            % Rebuild table with IDs 1..n in sorted order
            newData = cell(n,4);
            for i = 1:n
                newData{i,1} = i;                    % Bundle ID
                newData{i,2} = offsetsSorted(i);     % Release offset
                newData{i,3} = srcNames{i};          % Source
                newData{i,4} = dstNames{i};          % Dest
            end
            app.packetTable.Data = newData;
        end
        
        %% Callbacks
        
        function onOpenViewerButton(app)
            % Open Satellite Viewer, ensuring only one is open or opening
            
            % If a viewer exists but was closed manually, clear it
            if ~isempty(app.viewer) && ~isvalid(app.viewer)
                app.viewer = [];
            end
            
            % If we are already in the process of opening one, block
            if app.viewerOpening
                uialert(app.fig, ...
                    'Satellite viewer is currently being opened. Please wait.', ...
                    'Viewer Opening');
                return;
            end
            
            % If a valid viewer is already open, just bring it forward
            if ~isempty(app.viewer) && isvalid(app.viewer)
                try
                    figure(app.viewer.Figure);
                catch
                end
                uialert(app.fig, 'Satellite viewer is already open.', 'Info');
                return;
            end
            
            % Otherwise, open a new viewer with a lock
            app.viewerOpening = true;
            try
                app.viewer = satelliteScenarioViewer(app.scenarioManager.sc);
            catch ME
                app.viewerOpening = false;
                rethrow(ME);
            end
            app.viewerOpening = false;
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
            app.updatePacketTableNodeLists();
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
            app.updatePacketTableNodeLists();
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
            
            % LOS test
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
            
            % Range check vs PHY (from Scenario tab)
            dKm = norm(p1 - p2);
            phyMode = app.scenarioPHYDropDown.Value;
            profile = dtn.PHYProfiles.getProfile(phyMode);
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
            
            % RTT model using Scenario packet size
            dM  = dKm * 1e3;
            c   = 3e8; % speed of light m/s
            prop_s = 2 * dM / c;    % there & back
            
            packetBytes = app.scenarioPacketSizeField.Value;
            packetBits  = packetBytes * 8;
            txOneWay_s  = packetBits / profile.dataRate_bps;
            
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
                profile.name, packetBytes);
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
            
            % Close existing viewer if present
            if ~isempty(app.viewer) && isvalid(app.viewer)
                try
                    delete(app.viewer);
                catch
                end
            end
            app.viewer = [];
            
            % Recreate ScenarioManager with same time window
            startTime  = app.scenarioManager.startTime;
            stopTime   = app.scenarioManager.stopTime;
            sampleTime = app.scenarioManager.sampleTime;
            app.scenarioManager = dtn.ScenarioManager(startTime, stopTime, sampleTime);
            
            % Reset internal state & UI
            app.scenarioRunning  = false;
            app.currentSimulator = [];
            app.runScenarioButton.Enable = 'on';
            
            % Recreate default satellites / GS, repopulate dropdowns, etc.
            app.postInitSetup();
            
            % Open a new viewer using the same guarded logic
            app.viewerOpening = true;
            try
                app.viewer = satelliteScenarioViewer(app.scenarioManager.sc);
            catch
                app.viewerOpening = false;
                rethrow;
            end
            app.viewerOpening = false;
            
            % Re-enable controls after reset
            app.unlockUIAfterScenario();
            
            % Log reset
            app.logLines{end+1} = '[INFO] Scenario reset. Default satellites and GS-1 re-created, new viewer opened.';
            app.updateLogText();
        end
        
        function onRunScenarioButton(app)
            % Run DTN scenario: uses dtn.DTNSimulator

            % Require a satellite viewer
            if isempty(app.viewer) || ~isvalid(app.viewer)
                uialert(app.fig, ...
                    'Open the Satellite Viewer before running a scenario.', ...
                    'Viewer Required');
                return;
            end

            % Prevent multiple runs without reset
            if app.scenarioRunning
                uialert(app.fig, ...
                    'A scenario is already running or has just finished. Click "Reset Simulation" to set up and run a new scenario.', ...
                    'Scenario Running');
                return;
            end

            % Get packet schedule (per-bundle src/dst + release times)
            [releaseOffsetsMinutes, srcNames, dstNames, numBundles] = app.getPacketSchedule();
            if numBundles == 0
                return;
            end
            
            % Simulation window from satelliteScenario
            startTime = app.scenarioManager.startTime;
            stopTime  = app.scenarioManager.stopTime;
            horizonMinutes = minutes(stopTime - startTime);
            
            % Read sim start offset
            simStartOffsetMinutes = app.scenarioStartOffsetField.Value;
            if simStartOffsetMinutes < 0 || simStartOffsetMinutes > horizonMinutes
                uialert(app.fig, sprintf(['Simulation start offset %.2f min is outside the ' ...
                                          'scenario window (0..%.2f min).'], ...
                                          simStartOffsetMinutes, horizonMinutes), ...
                        'Invalid Start Offset');
                return;
            end
            
            % Check that all release times lie within scenario window
            releaseTimes = startTime + minutes(releaseOffsetsMinutes);
            if any(releaseTimes > stopTime)
                badIdx = find(releaseTimes > stopTime, 1, 'first');
                msg = sprintf(['Packet %d has release time %s, which is after the ' ...
                               'scenario end %s.'], ...
                               badIdx, datestr(releaseTimes(badIdx)), datestr(stopTime));
                uialert(app.fig, msg, 'Release Time Outside Scenario');
                return;
            end
            
            % Ensure sim start offset is not after earliest bundle
            if ~isempty(releaseOffsetsMinutes)
                earliestOffset = min(releaseOffsetsMinutes);
                if simStartOffsetMinutes > earliestOffset
                    msg = sprintf(['Earliest packet is scheduled at %.2f min; ' ...
                                   'simulation start offset (%.2f min) must be <= that.'], ...
                                   earliestOffset, simStartOffsetMinutes);
                    uialert(app.fig, msg, 'Invalid Start Offset vs Packet Times');
                    return;
                end
            end

            % Build config struct for DTNSimulator
            cfg.srcName        = 'mixed';
            cfg.dstName        = 'mixed';
            cfg.numBundles     = numBundles;
            cfg.routing        = app.scenarioRoutingDropDown.Value;
            cfg.phyMode        = app.scenarioPHYDropDown.Value;
            cfg.startTime      = startTime;
            cfg.horizonMinutes = horizonMinutes;
            cfg.stepSeconds    = 1;        % 1-second simulation steps

            % Real-time playback speed (0 => as fast as possible)
            cfg.realTimeSpeed  = app.scenarioSpeedField.Value;

            % TTL + packet size from Scenario tab
            cfg.ttlMinutes      = app.scenarioTTLField.Value;
            cfg.packetSizeBytes = app.scenarioPacketSizeField.Value;
            
            % Bundle release schedule + sim start offset + per-bundle src/dst
            cfg.bundleReleaseOffsetsMinutes = releaseOffsetsMinutes;
            cfg.bundleSrcNames              = srcNames;
            cfg.bundleDstNames              = dstNames;
            cfg.simStartOffsetMinutes       = simStartOffsetMinutes;

            % Create simulator
            sim = dtn.DTNSimulator(cfg);

            % *** CLEAR LOG at the start of every run ***
            app.logLines = {};
            app.updateLogText();

            % Stream messages live from simulator
            sim.logCallback = @(msg) app.appendLogFromSim(msg);

            % Track simulator + lock run button
            app.currentSimulator         = sim;
            app.scenarioRunning          = true;
            app.runScenarioButton.Enable = 'off';

            % Freeze UI while scenario is running
            app.lockUIForScenario();

            % Run simulation (logs will appear as it runs)
            try
                sim.run(app.scenarioManager, app.viewer);
            catch ME
                app.scenarioRunning          = false;
                app.runScenarioButton.Enable = 'on';
                app.currentSimulator         = [];
                app.unlockUIAfterScenario();
                rethrow(ME);
            end

            % Scenario finished; keep scenarioRunning=true so user must Reset
            app.currentSimulator = [];
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
        
        function updatePacketTableNodeLists(app)
            % Update the allowed node names for the Source/Destination columns
            if isempty(app.packetTable) || ~isvalid(app.packetTable)
                return;
            end
            
            names = app.scenarioManager.getNodeNames();
            if isempty(names)
                names = {''};
            end
            
            cf = app.packetTable.ColumnFormat;
            if numel(cf) ~= 4
                cf = {'numeric','numeric',names,names};
            else
                cf{3} = names;
                cf{4} = names;
            end
            app.packetTable.ColumnFormat = cf;
        end
    end
end
