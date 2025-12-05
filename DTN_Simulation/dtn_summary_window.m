function dtn_summary_window(S)
%DTN_SUMMARY_WINDOW  Horizontal DTN summary dashboard (no scrolling).

%% ========== CREATE WINDOW ==========
f = uifigure('Name','DTN Summary','Position',[200 100 1000 600]);
defaultFont = 11;   % small-ish so everything fits

% Top-level grid: 2 rows x 2 columns
mainGrid = uigridlayout(f,[2,2]);
mainGrid.RowHeight   = {'1x','1x'};
mainGrid.ColumnWidth = {'1x','1x'};

%% ========== EXTRACT VALUES FROM S ==========
lat = getLatency(S);

total_created   = S.total_created;
total_delivered = S.total_delivered;
delivery_ratio  = total_delivered / max(1,total_created);

droppedTTL  = S.bundles_droppedTTL;
dupSupp     = S.bundles_dupSupp;

mean_lat = mean(lat,'omitnan');
med_lat  = median(lat,'omitnan');
p95_lat  = prctile(lat,95);

offered_bytes  = S.total_offered_bytes;
payload_bytes  = S.payload_bytes_deliv;
air_bytes      = S.air_bytes_total;
overhead_ratio = S.overhead_ratio;

src_drop = S.Qsrc_bytes_dropped;
sat_drop = sum(S.Qsat_bytes_drop);

bufPolicy = S.bufPolicy;
bufGS     = S.BUF_GS_SRC;
bufSAT    = S.BUF_SAT;
routing   = S.routing;
sprayC    = S.sprayCopies;
TTL_hours = S.TTL_s / 3600;

numGS  = S.numGroundStations;
numSat = S.numSatellites;

packetSize_bytes = S.cfg.msgSize_bytes;
packetSize_KB    = packetSize_bytes / 1024;

TTL_pct = droppedTTL / max(1,total_created) * 100;

remainingCopies = (S.Qsrc_bytes_in + sum(S.Qsat_bytes_in)) / packetSize_bytes;

% Duration
sim_days  = days(S.stopTime - S.startTime);
sim_hours = hours(S.stopTime - S.startTime);

packets_per_hour = total_created / sim_hours;
packets_per_day  = total_created / sim_days;

% Bandwidth from contacts
C = S.contacts;
uplinkRows   = strcmp(C.Link,"GS1");
downlinkRows = strcmp(C.Link,"GS2");

avg_up_Mbps   = mean(C.MeanRate_Mbps(uplinkRows),'omitnan');
avg_down_Mbps = mean(C.MeanRate_Mbps(downlinkRows),'omitnan');

total_up_bytes   = sum(C.Cap_bytes(uplinkRows));
total_down_bytes = sum(C.Cap_bytes(downlinkRows));

%% ========== PANEL 1 (TOP-LEFT): TRAFFIC ==========
p1 = uipanel(mainGrid,'Title','Traffic Statistics','FontSize',defaultFont+1);
g1 = uigridlayout(p1,[9,2]);
g1.RowHeight   = repmat({'fit'},1,9);
g1.ColumnWidth = {'1x','1x'};

addRow(g1,"Simulation Duration (days):", sprintf('%.2f',sim_days),defaultFont);
addRow(g1,"Packets Created:",            total_created,defaultFont);
addRow(g1,"Packets Delivered:",          total_delivered,defaultFont);
addRow(g1,"Delivery Ratio:",             sprintf('%.3f',delivery_ratio),defaultFont);
addRow(g1,"Packets per Hour:",           sprintf('%.2f',packets_per_hour),defaultFont);
addRow(g1,"Packets per Day:",            sprintf('%.2f',packets_per_day),defaultFont);
addRow(g1,"TTL Packet Drops:",           droppedTTL,defaultFont);
addRow(g1,"TTL Drop %:",                 sprintf('%.1f%%',TTL_pct),defaultFont);
addRow(g1,"Copies in Buffers (approx):", remainingCopies,defaultFont);

%% ========== PANEL 2 (TOP-RIGHT): LATENCY ==========
p2 = uipanel(mainGrid,'Title','Latency Statistics','FontSize',defaultFont+1);
g2 = uigridlayout(p2,[4,2]);
g2.RowHeight   = repmat({'fit'},1,4);
g2.ColumnWidth = {'1x','1x'};

addRow(g2,"Mean Latency (s):",    sprintf('%.2f',mean_lat),defaultFont);
addRow(g2,"Median Latency (s):",  sprintf('%.2f',med_lat),defaultFont);
addRow(g2,"95th Percentile (s):", sprintf('%.2f',p95_lat),defaultFont);

%% ========== PANEL 3 (BOTTOM-LEFT): BUFFERS / ROUTING / TOPOLOGY ==========
p3 = uipanel(mainGrid,'Title','Buffers, Routing & Topology','FontSize',defaultFont+1);
g3 = uigridlayout(p3,[10,2]);
g3.RowHeight   = repmat({'fit'},1,10);
g3.ColumnWidth = {'1x','1x'};

addRow(g3,"Buffer Policy:",          bufPolicy,defaultFont);
addRow(g3,"GS Buffer Size:",         readable(bufGS),defaultFont);
addRow(g3,"Satellite Buffer Size:",  readable(bufSAT),defaultFont);
addRow(g3,"Routing Mode:",           routing,defaultFont);
addRow(g3,"Spray Copies:",           sprayC,defaultFont);
addRow(g3,"TTL (hours):",            sprintf('%.2f',TTL_hours),defaultFont);
addRow(g3,"# Ground Stations:",      numGS,defaultFont);
addRow(g3,"# Satellites:",           numSat,defaultFont);
addRow(g3,"Packet Size (KB):",       sprintf('%.1f',packetSize_KB),defaultFont);
addRow(g3,"Duplicate Drops:",        dupSupp,defaultFont);

%% ========== PANEL 4 (BOTTOM-RIGHT): BYTES / BANDWIDTH / DROPS ==========
p4 = uipanel(mainGrid,'Title','Bytes, Bandwidth & Buffer Drops','FontSize',defaultFont+1);
g4 = uigridlayout(p4,[10,2]);
g4.RowHeight   = repmat({'fit'},1,10);
g4.ColumnWidth = {'1x','1x'};

addRow(g4,"Offered Bytes:",         readable(offered_bytes),defaultFont);
addRow(g4,"Delivered Payload:",     readable(payload_bytes),defaultFont);
addRow(g4,"Air Bytes (incl. ARQ):", readable(air_bytes),defaultFont);
addRow(g4,"Overhead Ratio:",        sprintf('%.2f×',overhead_ratio),defaultFont);

addRow(g4,"Avg Uplink BW (Mbps):",   sprintf('%.2f',avg_up_Mbps),defaultFont);
addRow(g4,"Avg Downlink BW (Mbps):", sprintf('%.2f',avg_down_Mbps),defaultFont);
addRow(g4,"Total Uplink Capacity:",  readable(total_up_bytes),defaultFont);
addRow(g4,"Total Downlink Capacity:",readable(total_down_bytes),defaultFont);

addRow(g4,"GS Source Drops:", readable(src_drop),defaultFont);
addRow(g4,"Satellite Drops:", readable(sat_drop),defaultFont);

end

%% ----------- HELPERS ------------
function addRow(grid,label,value,font)
    uilabel(grid,'Text',label,'FontWeight','bold','FontSize',font);
    uilabel(grid,'Text',string(value),'FontSize',font);
end

function s = readable(x)
    if isnumeric(x)
        if isnan(x)
            s = "NaN";
        elseif x > 1e9
            s = sprintf('%.2f GB',x/1e9);
        elseif x > 1e6
            s = sprintf('%.2f MB',x/1e6);
        elseif x > 1e3
            s = sprintf('%.2f KB',x/1e3);
        else
            s = sprintf('%.0f bytes',x);
        end
    else
        s = string(x);
    end
end

function lat = getLatency(S)
    if ~isfield(S,"delivered") || isempty(S.delivered)
        lat = NaN;
        return;
    end
    if ismember("Latency_s", S.delivered.Properties.VariableNames)
        lat = S.delivered.Latency_s;
    else
        lat = NaN;
    end
end
