function sc = dtn_globe_viewer(S)
%DTN_GLOBE_VIEWER_FROM_S  Globe viewer driven by DTN base implementation.
%   sc = dtn_globe_viewer_from_S(S) creates a satelliteScenario whose:
%     - start/stop times come from S.startTime / S.stopTime
%     - number of satellites comes from S.numSatellites
%     - ground stations match the DTN GS locations (GS-Source, GS-Dest)
%     - orbit geometry depends on S.orbitClass = 'LEO' | 'MEO' | 'GEO'
%
%   Call this AFTER running:
%       S = dtn_leo_two_gs(cfg);
%
%   Requires: Aerospace Toolbox.

%% ---- Basic checks ----
if nargin < 1
    error('Usage: dtn_globe_viewer_from_S(S) where S is from dtn_leo_two_gs.');
end

startTime = getfield_if(S,"startTime", ...
    datetime(2025,11,10,12,0,0,'TimeZone','UTC'));
stopTime  = getfield_if(S,"stopTime",  ...
    startTime + days(7));

% Number of satellites / GS (for info; we still place 2 GS)
numSat = getfield_if(S,"numSatellites",3);
numGS  = getfield_if(S,"numGroundStations",2); %#ok<NASGU> % currently fixed at 2

% Orbit class (must match what you use in dtn_leo_two_gs)
orbitClass = upper(string(getfield_if(S,"orbitClass","LEO")));

% Sampling interval for visualization (not DTN sampleTime)
sampleTime = 10;  % seconds

%% ---- Create scenario ----
sc = satelliteScenario(startTime, stopTime, sampleTime);

%% ---- Ground stations (match your DTN code) ----
% GS1: San Diego (Source)
GS1_lat = 32.7157;
GS1_lon = -117.1611;

% GS2: Madrid (Dest)
GS2_lat = 40.4168;
GS2_lon = -3.7038;

gs1 = groundStation(sc, GS1_lat, GS1_lon, "Name","GS-Source", ...
    "MinElevationAngle", 2);
gs2 = groundStation(sc, GS2_lat, GS2_lon, "Name","GS-Dest", ...
    "MinElevationAngle", 2);

%% ---- Satellites: geometry depends on orbitClass ----
Re   = 6378137;   % Earth radius (m)
e    = 0;
argp = 0;
nu0  = 0;

switch orbitClass
    case "LEO"
        % Low Earth Orbit – few hundred km, varied inclinations
        alts_km   = [500 520 540 560];                  % altitudes
        incs_deg  = [53 70 86 97];                      % inclinations
        namePref  = "LEO-";
    case "MEO"
        % Medium Earth Orbit – ~10,000–20,000 km
        alts_km   = [10000 12000 15000 20000];
        incs_deg  = [56 63 70 75];
        namePref  = "MEO-";
    case "GEO"
        % Geostationary-like – ~35,786 km, near-equatorial
        alts_km   = [35786 35786 35786 35786];
        incs_deg  = [0 2 3 1];   % small inclinations
        namePref  = "GEO-";
    otherwise
        warning('Unknown orbitClass "%s"; using LEO visualization.', orbitClass);
        alts_km   = [500 520 540 560];
        incs_deg  = [53 70 86 97];
        namePref  = "LEO-";
end

% Spread RAANs around the planet
raans_deg = linspace(0, 300, max(2,numSat));

satCells = cell(numSat,1);
for k = 1:numSat
    alt_km = alts_km( mod(k-1, numel(alts_km)) + 1 );
    inc    = incs_deg( mod(k-1, numel(incs_deg)) + 1 );
    raan   = raans_deg(k);

    a   = Re + 1000 * alt_km;  % semi-major axis (m)
    name = sprintf("%s%d",namePref,k);

    satCells{k} = satellite(sc, a, e, inc, raan, argp, nu0, "Name", name);
end

sats = vertcat(satCells{:});   % convert cell array -> Satellite array

%% ---- Viewer setup ----
v = satelliteScenarioViewer(sc); %#ok<NASGU>

% Show satellites
show(sats);

% Ground tracks (1 hour lead, 20 minutes trail)
groundTrack(sats, "LeadTime", 3600, "TrailTime", 1200);

% Access links to each GS
ac1 = access(sats, gs1);
ac2 = access(sats, gs2);
show(ac1);
show(ac2);

fprintf('Globe viewer: %d satellites (%s), 2 ground stations, %s to %s.\n', ...
    numSat, orbitClass, string(startTime), string(stopTime));

end

%% ===== Helper: safe getfield =====
function v = getfield_if(S, field, defaultVal)
    if isstruct(S) && isfield(S,field)
        v = S.(field);
    else
        v = defaultVal;
    end
end
