function dtn_control_panel()
%DTN_CONTROL_PANEL  GUI to run DTN simulation only.

%% ---- Main figure ----
f = uifigure('Name','DTN Control Panel', ...
             'Position',[200 200 480 360]);   % <-- shorter height

grid = uigridlayout(f,[11 2]);
grid.RowHeight   = repmat({'fit'},1,11);
grid.ColumnWidth = {150, 300};
grid.RowSpacing  = 3;
grid.Padding     = [10 10 10 10];

%% ---- Row 1: Orbit Class ----
uilabel(grid, 'Text','Orbit Class:', 'HorizontalAlignment','right');
ddOrbit = uidropdown(grid, ...
    'Items',{'LEO','MEO','GEO'}, ...
    'Value','LEO');

%% ---- Row 2: Number of Satellites (synthetic only) ----
uilabel(grid, 'Text','# Satellites (synthetic):', 'HorizontalAlignment','right');
efNumSat = uieditfield(grid,'numeric', ...
    'Value',3, ...
    'Limits',[1 Inf], ...
    'RoundFractionalValues',true);

%% ---- Row 3: Simulation Days ----
uilabel(grid, 'Text','Simulation Length (days):', 'HorizontalAlignment','right');
efDays = uieditfield(grid,'numeric', ...
    'Value',7, ...
    'Limits',[0.1 Inf]);

%% ---- Row 4: GS Buffer (MB) ----
uilabel(grid, 'Text','GS Buffer (MB):', 'HorizontalAlignment','right');
efBufGS = uieditfield(grid,'numeric', ...
    'Value',20, ...
    'Limits',[1 Inf]);

%% ---- Row 5: Sat Buffer (MB) ----
uilabel(grid, 'Text','Sat Buffer (MB):', 'HorizontalAlignment','right');
efBufSat = uieditfield(grid,'numeric', ...
    'Value',15, ...
    'Limits',[1 Inf]);

%% ---- Row 6: Traffic Rate (packets/s) ----
uilabel(grid, 'Text','Traffic λ (pkts/s):', 'HorizontalAlignment','right');
efLambda = uieditfield(grid,'numeric', ...
    'Value',0.001, ...
    'Limits',[0 Inf]);

%% ---- Row 7: Packet Size (KB) ----
uilabel(grid, 'Text','Packet Size (KB):', 'HorizontalAlignment','right');
efPktKB = uieditfield(grid,'numeric', ...
    'Value',50, ...
    'Limits',[1 Inf]);

%% ---- Row 8: TTL (hours) ----
uilabel(grid, 'Text','TTL (hours):', 'HorizontalAlignment','right');
efTTLh = uieditfield(grid,'numeric', ...
    'Value',4, ...
    'Limits',[0.01 Inf]);

%% ---- Row 9: Routing & Spray ----
uilabel(grid, 'Text','Routing Protocol:', 'HorizontalAlignment','right');
ddRouting = uidropdown(grid, ...
    'Items',{'single','spray'}, ...
    'Value','single');

uilabel(grid, 'Text','Spray Copies (L):', 'HorizontalAlignment','right');
efSpray = uieditfield(grid,'numeric', ...
    'Value',1, ...
    'Limits',[1 Inf], ...
    'RoundFractionalValues',true);

%% ---- Row 10: Min Store (s) ----
uilabel(grid, 'Text','Min Store on Sat (s):', 'HorizontalAlignment','right');
efMinStore = uieditfield(grid,'numeric', ...
    'Value',300, ...
    'Limits',[0 Inf], ...
    'RoundFractionalValues',true);

%% ---- Row 11: Run Simulation Button (full width) ----
pBtns = uipanel(grid);
pBtns.Layout.Row    = 11;
pBtns.Layout.Column = [1 2];

btnGrid = uigridlayout(pBtns,[1 1]);
btnGrid.RowHeight   = {'fit'};
btnGrid.ColumnWidth = {'1x'};

uibutton(btnGrid,'Text','Run Simulation', ...
    'ButtonPushedFcn', @onRunSimulation);

%% ====== Callbacks ======
    function cfg = buildCfgFromUI()
        cfg = struct();
        cfg.startTime  = datetime(2025,11,10,12,0,0,'TimeZone','UTC');
        cfg.stopTime   = cfg.startTime + days(efDays.Value);
        cfg.sampleTime = 2;

        cfg.useSyntheticPlan = true;
        cfg.orbitClass       = ddOrbit.Value;
        cfg.numSatellites    = efNumSat.Value;

        cfg.BUF_GS_SRC = efBufGS.Value * 1e6;
        cfg.BUF_SAT    = efBufSat.Value * 1e6;
        cfg.bufPolicy  = "oldest";

        cfg.lambda_msg_per_s = efLambda.Value;
        cfg.msgSize_bytes    = efPktKB.Value * 1024;

        cfg.routing     = string(ddRouting.Value);
        cfg.sprayCopies = efSpray.Value;

        cfg.TTL_s      = efTTLh.Value * 3600;
        cfg.minStore_s = efMinStore.Value;

        cfg.arq_extra_factor = 1.05;
        cfg.USE_VIEWER       = false;
    end

    function onRunSimulation(~,~)
        cfg = buildCfgFromUI();
        fprintf('Running simulation with config:\n');
        disp(cfg);

        S = dtn_two_gs(cfg);

        if exist('dtn_summary_window','file') == 2
            dtn_summary_window(S);
        else
            uialert(f,'dtn_summary_window.m not found.','Missing File');
        end

        if exist('dtn_globe_viewer','file') == 2
            dtn_globe_viewer(S);
        else
            uialert(f,'dtn_globe_viewer.m not found.','Missing File');
        end
    end

end
