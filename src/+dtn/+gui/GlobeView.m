
classdef GlobeView < handle
    % GLOBEVIEW 3D Visualization of the Satellite Network.
    %   Draws the Earth, Satellites, Ground Stations, and Links.
    %   Matches the aesthetic of satelliteScenarioViewer (Stars, No Axes).
    
    properties
        Sim         % Reference to Simulation object
        Figure      % MATLAB Figure handle
        Ax          % Axes handle
        
        % Graphics Handles
        NodePlots   % Map: NodeID -> Scatter/Plot handle
        LinkPlots   % Map: "ID1-ID2" -> Line handle
        EarthObj    % Handle to the Earth surface
    end
    
    methods
        function obj = GlobeView(sim)
            % GLOBEVIEW Constructor
            obj.Sim = sim;
            obj.NodePlots = containers.Map('KeyType', 'double', 'ValueType', 'any');
            obj.LinkPlots = containers.Map('KeyType', 'char', 'ValueType', 'any');
            
            obj.createWindow();
            obj.drawOrbitPaths(); % Pre-calculate and draw orbits
            
            % Subscribe to Simulation updates
            addlistener(sim, 'StepComplete', @obj.onStep);
        end
        
        function createWindow(obj)
            % CREATEWINDOW Setup the figure and 3D Earth.
            obj.Figure = figure('Name', 'DTN Satellite Simulation', ...
                'Color', 'k', 'NumberTitle', 'off', ...
                'Position', [100, 100, 1200, 900], ... % Larger window
                'MenuBar', 'none', 'ToolBar', 'figure');
            
            obj.Ax = axes('Parent', obj.Figure, 'Color', 'k', ...
                'XColor', 'none', 'YColor', 'none', 'ZColor', 'none'); % Hide axis colors
            axis(obj.Ax, 'equal');
            axis(obj.Ax, 'off'); % Turn off axes completely
            hold(obj.Ax, 'on');
            
            % Draw Stars (Background)
            obj.drawStars();
            
            % Draw Earth (Radius ~6371 km)
            R_earth = 6371;
            [x, y, z] = sphere(100); % Higher res sphere
            
            % Try to load topographic data for texture
            try
                earth_data = load('topo.mat');
                % topo is 180x360. We need to flip it to match sphere mapping
                props.FaceColor = 'texture';
                props.EdgeColor = 'none';
                props.CData = earth_data.topo;
                props.FaceLighting = 'gouraud';
                props.SpecularStrength = 0.2; % Less shiny
                
                obj.EarthObj = surface(obj.Ax, x*R_earth, y*R_earth, z*R_earth, props);
                rotate(obj.EarthObj, [0 0 1], 180); 
            catch
                % Fallback
                obj.EarthObj = surf(obj.Ax, x*R_earth, y*R_earth, z*R_earth, ...
                    'FaceColor', [0, 0.5, 1], 'EdgeColor', 'none', 'FaceAlpha', 1.0);
            end
            
            % Add Lighting (Sun-like)
            light('Position', [10000, 10000, 10000], 'Style', 'local', 'Parent', obj.Ax);
            material(obj.EarthObj, 'dull');
            
            view(3);
            rotate3d(obj.Ax, 'on');
            
            % Set zoom limits
            limit = R_earth * 1.5; % Zoom in closer (was 3.0)
            xlim(obj.Ax, [-limit limit]);
            ylim(obj.Ax, [-limit limit]);
            zlim(obj.Ax, [-limit limit]);
        end
        
        function drawStars(obj)
            % DRAWSTARS Create a starfield background.
            rng(42); % Fixed seed for consistent stars
            numStars = 2000;
            dist = 50000; % Far away
            
            % Random spherical coordinates
            theta = 2 * pi * rand(numStars, 1);
            phi = acos(2 * rand(numStars, 1) - 1);
            
            sx = dist * sin(phi) .* cos(theta);
            sy = dist * sin(phi) .* sin(theta);
            sz = dist * cos(phi);
            
            plot3(obj.Ax, sx, sy, sz, '.', 'Color', [0.8 0.8 0.8], 'MarkerSize', 1);
        end
        
        function drawOrbitPaths(obj)
            % DRAWORBITPATHS Draw the trajectory of all satellites.
            nodes = obj.Sim.Nodes;
            duration = obj.Sim.Duration;
            dt = 60; % Step size for orbit drawing (1 min)
            
            times = 0:dt:duration;
            
            for i = 1:length(nodes)
                node = nodes(i);
                if strcmp(node.Type, 'Satellite') && ~isempty(node.Mobility)
                    % Calculate path
                    path = zeros(length(times), 3);
                    for t_idx = 1:length(times)
                        path(t_idx, :) = node.Mobility.getPosition(times(t_idx));
                    end
                    
                    % Draw Line (Cyan, like the toolbox)
                    plot3(obj.Ax, path(:,1), path(:,2), path(:,3), ...
                        'Color', [0, 1, 1, 0.5], 'LineWidth', 1);
                end
            end
        end
        
        function onStep(obj, ~, ~)
            % ONSTEP Called every simulation frame.
            if ~isvalid(obj.Figure), return; end
            
            obj.drawNodes();
            obj.drawLinks();
            
            title(obj.Ax, sprintf('Time: %.1f s', obj.Sim.Time), ...
                'Color', 'w', 'FontSize', 14, 'FontWeight', 'bold');
            drawnow limitrate; 
        end
        
        function drawNodes(obj)
            % DRAWNODES Update positions of all nodes.
            nodes = obj.Sim.Nodes;
            for i = 1:length(nodes)
                node = nodes(i);
                pos = node.Position;
                
                if ~isKey(obj.NodePlots, node.Id)
                    % First time setup
                    if strcmp(node.Type, 'GroundStation')
                        % Ground Station: Red Triangle
                        h = plot3(obj.Ax, pos(1), pos(2), pos(3), ...
                            'Marker', '^', 'MarkerSize', 8, ...
                            'MarkerFaceColor', 'r', 'Color', 'w');
                        
                        % Label
                        text(obj.Ax, pos(1)*1.05, pos(2)*1.05, pos(3)*1.05, ['  ' node.Name], ...
                            'Color', 'w', 'FontSize', 10, 'FontWeight', 'bold');
                    else
                        % Satellite: Cyan/White Dot with Label
                        h = plot3(obj.Ax, pos(1), pos(2), pos(3), ...
                            'Marker', 'o', 'MarkerSize', 6, ...
                            'MarkerFaceColor', 'c', 'Color', 'w');
                        
                        % Label (floating slightly above)
                        text(obj.Ax, pos(1), pos(2), pos(3)+500, ['  ' node.Name], ...
                            'Color', 'c', 'FontSize', 9);
                    end
                    
                    obj.NodePlots(node.Id) = h;
                else
                    % Update position
                    h = obj.NodePlots(node.Id);
                    set(h, 'XData', pos(1), 'YData', pos(2), 'ZData', pos(3));
                end
            end
        end
        
        function drawLinks(obj)
            % DRAWLINKS Draw lines between connected neighbors.
            nodes = obj.Sim.Nodes;
            currentLinks = {};
            
            for i = 1:length(nodes)
                node = nodes(i);
                neighbors = node.Link.Neighbors;
                keys = neighbors.keys;
                
                for k = 1:length(keys)
                    peerId = keys{k};
                    state = neighbors(peerId);
                    
                    if strcmp(state.Status, 'CONNECTED')
                        id1 = min(node.Id, peerId);
                        id2 = max(node.Id, peerId);
                        linkKey = sprintf('%d-%d', id1, id2);
                        currentLinks{end+1} = linkKey;
                        
                        peer = node.getPeer(peerId);
                        p1 = node.Position;
                        p2 = peer.Position;
                        
                        if ~isKey(obj.LinkPlots, linkKey)
                            % Create Line (Yellow, Dashed)
                            h = plot3(obj.Ax, [p1(1) p2(1)], [p1(2) p2(2)], [p1(3) p2(3)], ...
                                'Color', 'y', 'LineWidth', 2, 'LineStyle', ':');
                            obj.LinkPlots(linkKey) = h;
                        else
                            % Update Line
                            h = obj.LinkPlots(linkKey);
                            set(h, 'XData', [p1(1) p2(1)], 'YData', [p1(2) p2(2)], 'ZData', [p1(3) p2(3)]);
                        end
                    end
                end
            end
            
            % Remove stale links
            allKeys = obj.LinkPlots.keys;
            for k = 1:length(allKeys)
                key = allKeys{k};
                if ~ismember(key, currentLinks)
                    delete(obj.LinkPlots(key));
                    remove(obj.LinkPlots, key);
                end
            end
        end
    end
end
