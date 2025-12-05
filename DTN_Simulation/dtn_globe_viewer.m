function sc = dtn_globe_viewer(S)
%DTN_GLOBE_VIEWER  Globe viewer driven by DTN base implementation.
%   sc = dtn_globe_viewer(S) creates a satelliteScenario whose:
%     - start/stop times are based on S.startTime / S.stopTime
%     - number of satellites comes from S.numSatellites
%     - ground stations match the DTN GS locations (GS-Source, GS-Dest)
%     - orbitClass from S.orbitClass ("LEO"|"MEO"|"GEO") sets altitudes
%
%   Call this AFTER running:
%       S = dtn_two_gs(cfg);
%
%   This viewer is ONLY for visualization. It does not affect the DTN
%   results. To keep it fast, it:
%     - shows only a 1-day slice of the scenario
%     - uses a 60 s visualization sample time
%
%   Requires: Aerospace Toolbox.

%% ---- Basic checks ----
if nargin < 1
    error('Usage: dtn_globe_viewer(S) where S is from dtn_two_gs.');
end

% Pull times out of S (with safe defaults)
startTime_sim = getfield_if(S,"startTime", ...
    datetime(2025,11,10,12,0,0,'TimeZone','UTC'));
stopTime_sim  = getfield_if(S,"stopTime",  ...
    startTime_sim + days(7));

% Visualization window: limit to first day for speed
visDays = 1;   % change to 2/3/etc if you want more shown
viewStart = startTime_sim;
viewStop  = min(stopTime_sim, startTime_sim + days(visDays));

% Number of satellites / GS (info only; we still use 2 GS)
numSat = getfield_if(S,"numSatellites",3);
orbitClass = upper(string(getfield_if(S,"orbitClass","LEO")));
numGS  = getfield_if(S,"numGroundStations",2); %#ok<NASGU> % currently fixed at 2

% Visualization sample time (coarser than DTN sim)
sampleTimeVis = 60;  % seconds (bigger => faster)

%% ---- Create satelliteScenario for visualization ----
sc = satelliteScenario(viewStart, viewStop, sampleTimeVis);

%% ---- Ground stations (match DTN code) ----
% GS1: San Diego (Source)
GS1_lat = 32.7157;
GS1_lon = -117.1611;

% GS2: Madrid (Dest)
GS2_lat = 40.4168;
GS2_lon = -3.7038;

gs1 = groundStation(sc, GS1_lat, GS1_lon, ...
    "Name","GS-Source", "MinElevationAngle", 2);
gs2 = groundStation(sc, GS2_lat, GS2_lon, ...
    "Name","GS-Dest",   "MinElevationAngle", 2);

%% ---- Satellites: create numSat orbits based on orbitClass ----
Re   = 6378137;   % Earth radius (m)
e    = 0;
argp = 0;
nu0  = 0;

% Choose altitude set based on orbit class
switch orbitClass
    case "MEO"
        alts_km = [10000 12000 15000 18000];   % rough MEO altitudes
    case "GEO"
        alts_km = [35786 35786 35786 35786];   % GEO belt ~35,786 km
    otherwise % "LEO" or unknown
        alts_km = [500 520 540 560];           % your original LEO-ish set
        orbitClass = "LEO";                    % normalize
end

% Inclinations: just spread them to look nice
incs_deg   = [53 70 86 97];
% RAAN spread: wrap around 0–300 deg
raans_deg  = linspace(0, 300, max(2,numSat));

satCells = cell(numSat,1);
for k = 1:numSat
    alt_km = alts_km( mod(k-1, numel(alts_km)) + 1 );
    a      = Re + 1000 * alt_km; % meters
    inc    = incs_deg( mod(k-1, numel(incs_deg)) + 1 );
    raan   = raans_deg(k);
    name   = sprintf("%s-%d", orbitClass, k);

    satCells{k} = satellite(sc, a, e, inc, raan, argp, nu0, "Name", name);
end

sats = vertcat(satCells{:});   % cell array -> Satellite array

%% ---- Viewer setup ----
v = satelliteScenarioViewer(sc); %#ok<NASGU>

% Show satellites
show(sats);

% Ground tracks (shorter lead/trail for speed)
groundTrack(sats, "LeadTime", 1800, "TrailTime", 600); % 30 min lead, 10 min trail

% Access links to each GS
ac1 = access(sats, gs1);
ac2 = access(sats, gs2);
show(ac1);
show(ac2);

fprintf(['Globe viewer: orbitClass=%s, %d satellites, 2 ground stations,\n' ...
         '             visualized window: %s to %s (sampleTime=%ds).\n'], ...
        orbitClass, numSat, string(viewStart), string(viewStop), sampleTimeVis);

end

%% ===== Helper: safe getfield =====
function v = getfield_if(S, field, defaultVal)
    if isstruct(S) && isfield(S,field)
        v = S.(field);
    else
        v = defaultVal;
    end
end
