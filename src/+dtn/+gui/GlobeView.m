classdef GlobeView < handle
    % GLOBEVIEW Wrapper for satelliteScenarioViewer with DTN Controls.
    %   Uses the native Aerospace Toolbox viewer for 3D visualization.
    %   Provides a separate Control Panel for DTN-specific actions.
    
    properties
        Sim         % Reference to Simulation object
        Scenario    % Reference to satelliteScenario object
        Viewer      % Handle to satelliteScenarioViewer
        
        % Control Panel Figure
        CtrlFig
        
        % UI Elements
        NodeList
        InputName
        InputLatAlt
        InputLonInc
        TypeSelector
    end
    
    methods
        function obj = GlobeView(sim)
            % GLOBEVIEW Constructor
            obj.Sim = sim;
            
            % Extract Scenario from the first node
            if ~isempty(sim.Nodes)
                obj.Scenario = sim.Nodes(1).Mobility.Scenario;
            else
                error('GlobeView requires at least one node to find the Scenario.');
            end
            
            % 1. Launch Native Viewer
            obj.Viewer = satelliteScenarioViewer(obj.Scenario); 
            drawnow; % Give it a moment to appear
            
            % 2. Create Separate Control Panel
            obj.createControlPanel();
            
            % Subscribe to Simulation updates
            addlistener(sim, 'StepComplete', @obj.onStep);
        end
        
        function createControlPanel(obj)
            % CREATECONTROLPANEL Embed controls into the Viewer's figure.
            
            % Robustly find the figure
            figHandle = [];
            
            % 1. Try undocumented property
            try
                if isprop(obj.Viewer, 'Figure')
                    figHandle = obj.Viewer.Figure;
                end
            catch
            end
            
            % 2. Search for standard figures (Visible only)
            if isempty(figHandle)
                figHandle = findall(0, 'Type', 'figure', 'Name', 'Satellite Scenario Viewer', 'Visible', 'on');
            end
            
            % 3. Search for uifigures (Visible only)
            if isempty(figHandle)
                figHandle = findall(0, 'Type', 'uifigure', 'Name', 'Satellite Scenario Viewer', 'Visible', 'on');
            end
            
            if isempty(figHandle)
                warning('Could not find Satellite Scenario Viewer figure. Creating separate window.');
                obj.CtrlFig = figure('Name', 'DTN Controls', 'NumberTitle', 'off', 'MenuBar', 'none');
                % Fallback to simple layout
                grid = uigridlayout(obj.CtrlFig, [1 1]);
                panel = uipanel(grid, 'Title', 'DTN Controls', 'BackgroundColor', [0.1 0.1 0.1], 'ForegroundColor', 'w');
            else
                obj.CtrlFig = figHandle(1); % Use the first match
                disp(['Found Viewer Figure! Type: ' obj.CtrlFig.Type]);
                
                % --- Resize Strategy (Less Invasive) ---
                % Instead of reparenting (which breaks internal listeners), we just resize the canvas.
                children = obj.CtrlFig.Children;
                
                % Identify the Canvas (usually the one that isn't our panel)
                % For now, assume all existing children are part of the viewer.
                
                % Create our Panel first
                panel = uipanel('Parent', obj.CtrlFig, ...
                    'Units', 'normalized', ...
                    'Position', [0.75, 0.0, 0.25, 1.0], ...
                    'BackgroundColor', [0.1 0.1 0.1], ...
                    'ForegroundColor', 'w', ...
                    'Title', 'DTN Controls');
                
                % Resize existing children to left 75%
                for i = 1:length(children)
                    child = children(i);
                    try
                        if isprop(child, 'Units')
                            child.Units = 'normalized';
                        end
                        if isprop(child, 'Position')
                            child.Position = [0, 0, 0.75, 1.0];
                        end
                        % If it's a GeographicGlobe, it might not have standard Position/Units in the same way,
                        % but usually in a figure it does.
                    catch
                        % Ignore if property doesn't exist
                    end
                end
                
                % Add a resize listener to enforce this
                obj.CtrlFig.SizeChangedFcn = @(src, ~) obj.enforceLayout(src, panel);
            end
            
            textColor = 'w';
            bgColor = [0.1 0.1 0.1];
            
            textColor = 'w';
            bgColor = [0.1 0.1 0.1];
            
            % --- Add Controls to the Panel ---
            
            % Node List
            uicontrol('Parent', panel, 'Style', 'text', ...
                'String', 'Active Nodes:', ...
                'Units', 'normalized', ...
                'Position', [0.05, 0.85, 0.9, 0.05], ...
                'BackgroundColor', bgColor, 'ForegroundColor', textColor, ...
                'HorizontalAlignment', 'left');
            
            obj.NodeList = uicontrol('Parent', panel, 'Style', 'listbox', ...
                'Units', 'normalized', ...
                'Position', [0.05, 0.45, 0.9, 0.4], ...
                'BackgroundColor', [0.2 0.2 0.2], 'ForegroundColor', textColor);
            
            % Remove Button
            uicontrol('Parent', panel, 'Style', 'pushbutton', ...
                'String', 'REMOVE AGENT', ...
                'Units', 'normalized', ...
                'Position', [0.05, 0.40, 0.9, 0.04], ...
                'Callback', @obj.onRemoveNode, ...
                'BackgroundColor', [0.6 0 0], 'ForegroundColor', 'w', 'FontWeight', 'bold');
            
            % Add Node Controls
            uicontrol('Parent', panel, 'Style', 'text', ...
                'String', 'Add New Agent:', ...
                'Units', 'normalized', ...
                'Position', [0.05, 0.35, 0.9, 0.05], ...
                'BackgroundColor', bgColor, 'ForegroundColor', textColor, ...
                'HorizontalAlignment', 'left', 'FontWeight', 'bold');
            
            obj.TypeSelector = uicontrol('Parent', panel, 'Style', 'popupmenu', ...
                'String', {'Ground Station', 'Satellite'}, ...
                'Units', 'normalized', ...
                'Position', [0.05, 0.28, 0.9, 0.05], ...
                'Callback', @obj.onTypeChange);
            
            uicontrol('Parent', panel, 'Style', 'text', ...
                'String', 'Name:', ...
                'Units', 'normalized', ...
                'Position', [0.05, 0.22, 0.2, 0.04], ...
                'BackgroundColor', bgColor, 'ForegroundColor', textColor, 'HorizontalAlignment', 'left');
            obj.InputName = uicontrol('Parent', panel, 'Style', 'edit', ...
                'String', 'Sat-X', ...
                'Units', 'normalized', ...
                'Position', [0.3, 0.22, 0.65, 0.04]);
            
            uicontrol('Parent', panel, 'Style', 'text', ...
                'String', 'Param 1:', ...
                'Tag', 'Lbl1', ...
                'Units', 'normalized', ...
                'Position', [0.05, 0.16, 0.2, 0.04], ...
                'BackgroundColor', bgColor, 'ForegroundColor', textColor, 'HorizontalAlignment', 'left');
            obj.InputLatAlt = uicontrol('Parent', panel, 'Style', 'edit', ...
                'String', '500', ...
                'Units', 'normalized', ...
                'Position', [0.3, 0.16, 0.65, 0.04]);
            
            uicontrol('Parent', panel, 'Style', 'text', ...
                'String', 'Param 2:', ...
                'Tag', 'Lbl2', ...
                'Units', 'normalized', ...
                'Position', [0.05, 0.10, 0.2, 0.04], ...
                'BackgroundColor', bgColor, 'ForegroundColor', textColor, 'HorizontalAlignment', 'left');
            obj.InputLonInc = uicontrol('Parent', panel, 'Style', 'edit', ...
                'String', '53', ...
                'Units', 'normalized', ...
                'Position', [0.3, 0.10, 0.65, 0.04]);
            
            uicontrol('Parent', panel, 'Style', 'pushbutton', ...
                'String', 'DEPLOY AGENT', ...
                'Units', 'normalized', ...
                'Position', [0.05, 0.02, 0.9, 0.06], ...
                'Callback', @obj.onAddNode, ...
                'BackgroundColor', [0 0.6 0], 'ForegroundColor', 'w', 'FontWeight', 'bold');
            
            % Initial Update
            obj.updateNodeList();
            obj.onTypeChange(obj.TypeSelector, []);
        end
        
        function onTypeChange(obj, src, ~)
            idx = src.Value;
            % Find labels within the parent panel of the source object
            panel = src.Parent;
            lbl1 = findobj(panel, 'Tag', 'Lbl1');
            lbl2 = findobj(panel, 'Tag', 'Lbl2');
            
            if idx == 1 % Ground Station
                lbl1.String = 'Lat:';
                lbl2.String = 'Lon:';
                obj.InputLatAlt.String = '32.7';
                obj.InputLonInc.String = '-117.1';
                obj.InputName.String = 'GS-New';
            else % Satellite
                lbl1.String = 'Alt (km):';
                lbl2.String = 'Inc (deg):';
                obj.InputLatAlt.String = '500';
                obj.InputLonInc.String = '53';
                obj.InputName.String = 'Sat-New';
            end
        end
        
        function onAddNode(obj, ~, ~)
            name = obj.InputName.String;
            val1 = str2double(obj.InputLatAlt.String);
            val2 = str2double(obj.InputLonInc.String);
            typeIdx = obj.TypeSelector.Value;
            
            % Check Duplicate
            for i = 1:length(obj.Sim.Nodes)
                if strcmp(obj.Sim.Nodes(i).Name, name)
                    errordlg('Name already exists!'); return;
                end
            end
            
            newId = length(obj.Sim.Nodes) + 100 + randi(900);
            
            try
                if typeIdx == 1 % Ground Station
                    asset = groundStation(obj.Scenario, val1, val2, 'Name', name);
                    mob = dtn.core.AerospaceMobility(asset, obj.Scenario);
                    node = dtn.core.Node(newId, name, 'GroundStation', 1e9, 'S-Band', 'Epidemic', mob, obj.Sim);
                else % Satellite
                    Re = 6378137;
                    sma = Re + (val1 * 1000);
                    inc = val2;
                    asset = satellite(obj.Scenario, sma, 0, inc, 0, 0, 0, 'Name', name);
                    % show(asset); % Ensure visible
                    mob = dtn.core.AerospaceMobility(asset, obj.Scenario);
                    node = dtn.core.Node(newId, name, 'Satellite', 1e6, 'S-Band', 'Epidemic', mob, obj.Sim);
                end
                
                obj.Sim.addNode(node);
                obj.updateNodeList();
                
                % Feedback
                disp(['Deployed agent: ' name]);
                
            catch e
                errordlg(['Failed to deploy agent: ' e.message]);
            end
        end
        
        function onRemoveNode(obj, ~, ~)
            idx = obj.NodeList.Value;
            if isempty(idx) || idx < 1 || idx > length(obj.Sim.Nodes)
                return;
            end
            
            node = obj.Sim.Nodes(idx);
            name = node.Name;
            
            try
                % 1. Remove from Scenario (Visual)
                if ~isempty(node.Mobility) && ~isempty(node.Mobility.Asset)
                    % Try to remove the asset from the scenario
                    % Note: 'remove' might not be available on all asset objects directly,
                    % but 'delete' usually works for handles.
                    delete(node.Mobility.Asset);
                end
                
                % 2. Remove from Simulation (Logic)
                obj.Sim.Nodes(idx) = [];
                
                % 3. Update UI
                obj.updateNodeList();
                
                % Reset selection if out of bounds
                if obj.NodeList.Value > length(obj.Sim.Nodes)
                    obj.NodeList.Value = max(1, length(obj.Sim.Nodes));
                end
                
                disp(['Removed agent: ' name]);
                
            catch e
                errordlg(['Failed to remove agent: ' e.message]);
            end
        end
        
        function updateNodeList(obj)
            names = {};
            for i = 1:length(obj.Sim.Nodes)
                names{end+1} = obj.Sim.Nodes(i).Name;
            end
            obj.NodeList.String = names;
        end
        
        function onStep(obj, ~, ~)
            % No-op for now, as Viewer handles itself.
            % We could update a time label if we had one, but the Viewer has one.
        end
        
        function enforceLayout(obj, fig, panel)
            % ENFORCELAYOUT Ensure the panel stays on the right and canvas on the left.
            try
                children = fig.Children;
                for i = 1:length(children)
                    child = children(i);
                    if child == panel
                        child.Position = [0.75, 0.0, 0.25, 1.0];
                    elseif isprop(child, 'Position') && isprop(child, 'Units')
                        child.Units = 'normalized';
                        child.Position = [0.0, 0.0, 0.75, 1.0];
                    end
                end
            catch
                % Ignore errors during resize
            end
        end
    end
end
