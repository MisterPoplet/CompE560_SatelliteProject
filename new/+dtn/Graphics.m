classdef Graphics
    % Graphics - static helpers for drawing Earth & nodes
    
    methods (Static)
        function setupOrbitAxes(ax)
            % Draw Earth sphere
            radiusKm = 6371; % Earth radius
            [x,y,z] = sphere(50);
            surf(ax, radiusKm*x, radiusKm*y, radiusKm*z, ...
                'EdgeColor', 'none', 'FaceAlpha', 0.3);
            colormap(ax, 'parula');
            axis(ax, 'equal');
            grid(ax, 'on');
            hold(ax, 'on');
            view(ax, 45, 20);
            hold(ax, 'off');
        end
        
        function [x,y,z] = latLonAltToXYZ(latDeg, lonDeg, altM)
            % Convert geodetic lat/lon/alt to simple Cartesian in km
            ReKm = 6371;
            rKm  = ReKm + altM/1000;
            
            latRad = deg2rad(latDeg);
            lonRad = deg2rad(lonDeg);
            
            x = rKm * cos(latRad) * cos(lonRad);
            y = rKm * cos(latRad) * sin(lonRad);
            z = rKm * sin(latRad);
        end
        
        function updateNodes(ax, scenarioManager, t)
            % Clear axes and redraw Earth + all nodes at time t
            cla(ax);
            dtn.Graphics.setupOrbitAxes(ax);
            hold(ax, 'on');
            
            nodes = scenarioManager.nodes;
            for k = 1:numel(nodes)
                node = nodes(k);
                [lat, lon, altM] = scenarioManager.getLatLonAlt(node.name, t);
                [x,y,z] = dtn.Graphics.latLonAltToXYZ(lat, lon, altM);
                
                if strcmp(node.type, 'sat')
                    plot3(ax, x, y, z, 'o', 'MarkerSize', 8, 'LineWidth', 1.5);
                    text(ax, x, y, z, [' ' node.name], 'FontSize', 10);
                else
                    plot3(ax, x, y, z, '^', 'MarkerSize', 8, 'LineWidth', 1.5);
                    text(ax, x, y, z, [' ' node.name], 'FontSize', 10);
                end
            end
            
            hold(ax, 'off');
        end
    end
end
