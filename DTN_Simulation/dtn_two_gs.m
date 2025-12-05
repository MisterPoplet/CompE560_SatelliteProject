function S = dtn_two_gs(cfg)
% DTN_TWO_GS  DTN demo: Source GS -> Satellite(s) -> Destination GS
% Returns: S struct with contacts, delivered, timing, and accounting.
%
% Features:
%   - Single-copy or Spray & Wait routing GS1 -> SAT -> GS2
%   - Per-copy TTL with TTL drops
%   - Buffers at GS1 and satellites + configurable drop policy
%   - Duplicate suppression at GS2 with duplicate-drop counter
%   - Air-byte accounting (uplink + downlink, all copies) + simple ARQ factor
%   - DEFAULT: synthetic contact plan so the run always has deliveries.
%   - Set cfg.useSyntheticPlan=false to use real LEO via Aerospace Toolbox.
%   - orbitClass = "LEO" | "MEO" | "GEO" for synthetic plans.
%   - numSatellites controls the number of synthetic satellites.

%% ======== Config (with optional cfg struct) ========
if nargin < 1
    cfg = struct();
end

% Time settings
if ~isfield(cfg,'startTime')
    cfg.startTime = datetime(2025,11,10,12,0,0,'TimeZone','UTC');
end
if ~isfield(cfg,'stopTime')
    cfg.stopTime = cfg.startTime + days(7);
end
if ~isfield(cfg,'sampleTime')
    cfg.sampleTime = 2;  % s
end

startTime  = cfg.startTime;
stopTime   = cfg.stopTime;
sampleTime = cfg.sampleTime;

% Ground stations (Source/Dest)
GS1 = [32.7157,  -117.1611,  0];  % San Diego
GS2 = [40.4168,   -3.7038,   0];  % Madrid

% Link model
c = 2.99792458e8; freq=12e9; B_Hz=20e6;
Pt_dBm=30; Gt_dB=20; Gr_dB=30; kT_dBm=-228.6+10*log10(290);
lambda=c/freq;
elevMaskDeg=2;     % deg
eta_eff=0.7;       % efficiency vs Shannon

% DTN traffic
rng(1);
if ~isfield(cfg,'lambda_msg_per_s')
    cfg.lambda_msg_per_s = 0.001;      % 0.001 msg/s by default
end
if ~isfield(cfg,'msgSize_bytes')
    cfg.msgSize_bytes    = 50e3;      % 50 KB packets
end
lambda_msg_per_s = cfg.lambda_msg_per_s;
msgSize_bytes    = cfg.msgSize_bytes;

% Buffers
if ~isfield(cfg,'BUF_GS_SRC')
    cfg.BUF_GS_SRC = 20e6;   % 20 MB source buffer
end
if ~isfield(cfg,'BUF_SAT')
    cfg.BUF_SAT    = 15e6;   % 15 MB per-satellite buffer
end
BUF_GS_SRC = cfg.BUF_GS_SRC;
BUF_SAT    = cfg.BUF_SAT;

% Buffer-drop policy: 'oldest' | 'largest' | 'random'
if ~isfield(cfg,'bufPolicy')
    cfg.bufPolicy = "oldest";
end
bufPolicy = string(cfg.bufPolicy);

% Routing: 'single' or 'spray'
if ~isfield(cfg,'routing')
    cfg.routing = "single";  % baseline
end
routing = string(cfg.routing);
if ~isfield(cfg,'sprayCopies')
    cfg.sprayCopies = 1;
end
sprayCopies = cfg.sprayCopies;

% Prevent “instant relay”: dwell on sat + forbid same-pass downlink
if ~isfield(cfg,'minStore_s')
    cfg.minStore_s = 300;    % you can set to 0 for easier deliveries
end
minStore_s = cfg.minStore_s;

% Bundle TTL (seconds)
if ~isfield(cfg,'TTL_s')
    cfg.TTL_s = 4 * 3600;    % 4 hours
end
TTL_s = cfg.TTL_s;

% ARQ / air-byte overhead factor
if ~isfield(cfg,'arq_extra_factor')
    cfg.arq_extra_factor = 1.05;   % ~5% overhead
end
ARQ_extra_factor = cfg.arq_extra_factor;

% Contact plan options
if ~isfield(cfg,'useSyntheticPlan')
    % IMPORTANT: default to synthetic so the run always has deliveries
    cfg.useSyntheticPlan = true;
end
USE_SYNTH_PLAN = cfg.useSyntheticPlan;

% Orbit class for synthetic plans
if ~isfield(cfg,'orbitClass')
    cfg.orbitClass = "LEO";   % "LEO" | "MEO" | "GEO"
end
orbitClass = upper(string(cfg.orbitClass));

% Number of satellites (only used in synthetic mode)
if ~isfield(cfg,'numSatellites')
    cfg.numSatellites = 3;
end
numSatConfig = cfg.numSatellites;

% Viewer toggle (only for real-orbit LEO mode)
if ~isfield(cfg,'USE_VIEWER')
    cfg.USE_VIEWER = true;
end
USE_VIEWER = cfg.USE_VIEWER;
if USE_SYNTH_PLAN
    USE_VIEWER = false;
end

%% ======== Contacts & Mobility ========
timeline = startTime:seconds(sampleTime):stopTime;
contacts = table();
satNames = strings(1,0);

if USE_SYNTH_PLAN
    % ---- Synthetic mobility contact plans (LEO/MEO/GEO) ----
    switch orbitClass
        case "LEO"
            contacts = build_synthetic_contacts_leo(startTime,stopTime,numSatConfig);
        case "MEO"
            contacts = build_synthetic_contacts_meo(startTime,stopTime,numSatConfig);
        case "GEO"
            contacts = build_synthetic_contacts_geo(startTime,stopTime,numSatConfig);
        otherwise
            warning('Unknown orbitClass "%s"; falling back to LEO.',orbitClass);
            contacts = build_synthetic_contacts_leo(startTime,stopTime,numSatConfig);
    end
    satNames = unique(string(contacts.Sat)).';
else
    % ---- Real LEO scenario via Aerospace Toolbox ----
    sc = satelliteScenario(startTime, stopTime, sampleTime);

    % Two LEOs + extra planes for better contact diversity
    Re=6378137; e=0; argp=0; nu=0; raan1=0; raan2=60;
    aLEO1=Re+500e3; aLEO2=Re+550e3;
    sat1 = satellite(sc,aLEO1,e,53, raan1,argp,nu,"Name","LEO-1");
    sat2 = satellite(sc,aLEO2,e,97, raan2,argp,nu,"Name","LEO-2");

    a3=Re+520e3; a4=Re+560e3;
    extra=[a3 70 0 0 30; a3 70 120 0 90; a4 86 180 0 135; a4 86 300 0 210];
    satExtra=cell(size(extra,1),1);
    for ii=1:size(extra,1)
      satExtra{ii}=satellite(sc,extra(ii,1),0,extra(ii,2),extra(ii,3),extra(ii,4),extra(ii,5), ...
                             "Name",sprintf("LEO-X%d",ii));
    end
    sat = [sat1, sat2, [satExtra{:}]];

    satNames = strings(1,numel(sat));
    for ii=1:numel(sat)
        try
            satNames(ii)=string(sat(ii).Name);
        catch
            satNames(ii)="";
        end
    end

    gs1 = groundStation(sc,GS1(1),GS1(2),"Name","GS-Source","MinElevationAngle",elevMaskDeg);
    gs2 = groundStation(sc,GS2(1),GS2(2),"Name","GS-Dest",  "MinElevationAngle",elevMaskDeg);

    if USE_VIEWER
      v = satelliteScenarioViewer(sc); %#ok<NASGU>
      show(sat);
      groundTrack(sat,LeadTime=3600,TrailTime=600);
      ac1=access(sat,gs1); ac2=access(sat,gs2);
      show(ac1); show(ac2);
    end

    contacts = build_contacts_table(sc,sat,gs1,gs2,elevMaskDeg,...
        lambda,Pt_dBm,Gt_dB,Gr_dB,kT_dBm,B_Hz,eta_eff,timeline);
end

if isempty(contacts)
  warning('No contacts found or built.');
else
  contacts = sortrows(contacts,'StartTime');
end

satNames = satNames(:).';
nsat     = numel(satNames);

%% ======== DTN Queues & State ========
% Source queue
Qsrc_times = datetime.empty(0,1); Qsrc_times.TimeZone='UTC';
Qsrc_sizes = zeros(0,1);
Qsrc_TTL   = zeros(0,1);   % per-copy TTL
Qsrc_id    = zeros(0,1);   % per-copy bundle ID
Qsrc_bytes_in      = 0;
Qsrc_bytes_dropped = 0;

% Satellite queues (created, ready, size, TTL, bundleID)
Qsat_times=cell(1,nsat);
Qsat_ready=cell(1,nsat);
Qsat_sizes=cell(1,nsat);
Qsat_TTL  =cell(1,nsat);
Qsat_id   =cell(1,nsat);
Qsat_bytes_in   = zeros(1,nsat);
Qsat_bytes_drop = zeros(1,nsat);
for i=1:nsat
    Qsat_times{i}=datetime.empty(0,1); Qsat_times{i}.TimeZone='UTC';
    Qsat_ready{i}=datetime.empty(0,1); Qsat_ready{i}.TimeZone='UTC';
    Qsat_sizes{i}=zeros(0,1);
    Qsat_TTL{i}  =zeros(0,1);
    Qsat_id{i}   =zeros(0,1);
end

% Delivery table
delivered = table('Size',[0 5], ...
    'VariableTypes',{'double','datetime','datetime','double','double'}, ...
    'VariableNames',{'BundleID','Created','Delivered','Size_bytes','Latency_s'});
delivered.Created.TimeZone   = 'UTC';
delivered.Delivered.TimeZone = 'UTC';

% TTL & duplicate accounting
bundles_droppedTTL = 0;
bundles_dupSupp    = 0;

% Track which bundle IDs have already been delivered
deliveredIDs = [];

% Count all bundles (unique) at creation
nextBundleID = 1;

% Air bytes accounting (uplink + downlink, includes ARQ factor)
air_bytes_total = 0;

%% ======== Message Generation (simple Poisson, robust) ========
allSec   = (startTime:seconds(1):stopTime).';     % N×1 column
N        = numel(allSec);

% Poisson arrivals per second
randMask     = (rand(N,1) < lambda_msg_per_s);        % N×1 logical
createdTimes = allSec(randMask);
msgSizes     = msgSize_bytes * ones(size(createdTimes));

% FINAL SAFETY: if still no bundles, force some traffic so the run is never empty
if isempty(createdTimes)
    warning('No bundles generated by Poisson process; forcing minimum traffic...');
    dur_s = seconds(stopTime - startTime);
    if dur_s <= 0
        dur_s = 3600;  % just in case
    end
    Nmin = 100;  % force at least 100 bundles
    offs = sort(rand(Nmin,1) * dur_s);   % random offsets in [0, dur_s]
    createdTimes = startTime + seconds(offs);
    msgSizes     = msgSize_bytes * ones(size(createdTimes));
end

%% ======== Enqueue at Source ========
for i=1:numel(createdTimes)
  need     = msgSizes(i);
  bundleID = nextBundleID; 
  nextBundleID = nextBundleID + 1;

  if routing == "spray"
      copies = sprayCopies;
  else
      copies = 1;
  end

  for c=1:copies
      % Enforce buffer policy at GS1
      [Qsrc_times,Qsrc_sizes,Qsrc_TTL,Qsrc_id, freedBytes, ~] = ...
          enforce_buf_policy_src(Qsrc_times,Qsrc_sizes,Qsrc_TTL,Qsrc_id, ...
                                 BUF_GS_SRC,need,bufPolicy);
      Qsrc_bytes_in      = Qsrc_bytes_in - freedBytes;
      Qsrc_bytes_dropped = Qsrc_bytes_dropped + freedBytes;

      if Qsrc_bytes_in + need <= BUF_GS_SRC
        Qsrc_times(end+1,1) = createdTimes(i);
        Qsrc_sizes(end+1,1) = need;
        Qsrc_TTL(end+1,1)   = TTL_s;
        Qsrc_id(end+1,1)    = bundleID;
        Qsrc_bytes_in       = Qsrc_bytes_in + need;
      else
        % no space even after policy => drop this copy from GS buffer
        Qsrc_bytes_dropped  = Qsrc_bytes_dropped + need;
      end
  end
end

%% ======== Process Contacts ========
for r=1:height(contacts)
  link   = contacts.Link(r);
  satTag = string(contacts.Sat(r));
  si     = find(satNames==satTag,1,'first'); 
  if isempty(si), continue; end

  capB   = contacts.Cap_bytes(r);
  rateB  = contacts.Rate_Bps(r);
  tStart = contacts.StartTime(r);
  propd  = contacts.PropDelay_s(r);
  if capB<=0, continue; end

  % ==== Drop expired copies at this contact start time (TTL) ====
  % Source:
  [Qsrc_times,Qsrc_sizes,Qsrc_TTL,Qsrc_id,bytesDropSrc,countDropSrc] = ...
      expire_queue(Qsrc_times,Qsrc_sizes,Qsrc_TTL,Qsrc_id,tStart);
  Qsrc_bytes_in      = Qsrc_bytes_in - bytesDropSrc;
  bundles_droppedTTL = bundles_droppedTTL + countDropSrc;

  % This satellite:
  [Qsat_times{si},Qsat_ready{si},Qsat_sizes{si},Qsat_TTL{si},Qsat_id{si}, ...
   bytesDropSat,countDropSat] = ...
      expire_queue_sat(Qsat_times{si},Qsat_ready{si},Qsat_sizes{si}, ...
                       Qsat_TTL{si},Qsat_id{si},tStart);
  Qsat_bytes_in(si)  = Qsat_bytes_in(si) - bytesDropSat;
  bundles_droppedTTL = bundles_droppedTTL + countDropSat;

  if link=="GS1"
    % ----- UPLINK: GS1 -> SAT -----
    if isempty(Qsrc_sizes), continue; end
    take        = min(sum(Qsrc_sizes),capB);
    sentBytes   = 0; 
    iHead       = 1; 
    contactStart= tStart;

    while iHead<=numel(Qsrc_sizes) && sentBytes<take
      sz       = Qsrc_sizes(iHead);
      ttl      = Qsrc_TTL(iHead);
      tCreated = Qsrc_times(iHead);
      bID      = Qsrc_id(iHead);
      expiryT  = tCreated + seconds(ttl);

      % next free slot on link
      tQueuedStart = contactStart + seconds(sentBytes / rateB);
      % cannot tx before created
      txStart_up   = max(tQueuedStart, tCreated);
      txTime       = seconds(sz / rateB);
      arriveSatT   = txStart_up + txTime + seconds(propd);

      % If it would arrive after expiry -> TTL drop (copy-level)
      if arriveSatT > expiryT
          bundles_droppedTTL = bundles_droppedTTL + 1;
          if sentBytes+sz<=take
              sentBytes = sentBytes+sz; 
              iHead     = iHead+1;
          else
              Qsrc_sizes(iHead) = sz-(take-sentBytes);
              sentBytes         = take;
          end
          continue;
      end

      % dwell + prevent same-pass downlink
      uplinkEndT   = contacts.EndTime(r);
      notBeforeT   = uplinkEndT + seconds(minStore_s);
      readyT       = max(arriveSatT, notBeforeT);

      if sentBytes+sz<=take
        % Air bytes (uplink with ARQ overhead)
        air_bytes_total = air_bytes_total + sz * ARQ_extra_factor;

        % Enforce buffer policy on satellite before enqueue
        [Qsat_times{si},Qsat_ready{si},Qsat_sizes{si},Qsat_TTL{si},Qsat_id{si}, ...
         freedBytesSat, ~] = ...
           enforce_buf_policy_sat(Qsat_times{si},Qsat_ready{si},Qsat_sizes{si}, ...
                                  Qsat_TTL{si},Qsat_id{si},BUF_SAT,sz,bufPolicy);
        Qsat_bytes_in(si)   = Qsat_bytes_in(si) - freedBytesSat;
        Qsat_bytes_drop(si) = Qsat_bytes_drop(si) + freedBytesSat;

        if sum(Qsat_sizes{si}) + sz <= BUF_SAT
          Qsat_times{si}(end+1,1) = tCreated; % creation time
          Qsat_ready{si}(end+1,1) = readyT;   % earliest DN allowed
          Qsat_sizes{si}(end+1,1) = sz;
          Qsat_TTL{si}(end+1,1)   = ttl;
          Qsat_id{si}(end+1,1)    = bID;
          Qsat_bytes_in(si)       = Qsat_bytes_in(si) + sz;
        else
          % no space even after policy => buffer drop on satellite
          Qsat_bytes_drop(si) = Qsat_bytes_drop(si) + sz;
        end

        sentBytes = sentBytes + sz; 
        iHead     = iHead + 1;
      else
        Qsrc_sizes(iHead) = sz - (take-sentBytes);
        sentBytes         = take;
      end
    end

    if iHead>1
      Qsrc_times    = Qsrc_times(iHead:end);
      Qsrc_sizes    = Qsrc_sizes(iHead:end);
      Qsrc_TTL      = Qsrc_TTL(iHead:end);
      Qsrc_id       = Qsrc_id(iHead:end);
      Qsrc_bytes_in = sum(Qsrc_sizes);
    end

  else
    % ----- DOWNLINK: SAT -> GS2 -----
    if isempty(Qsat_sizes{si}), continue; end
    take        = min(sum(Qsat_sizes{si}),capB);
    sentBytes   = 0; 
    iHead       = 1; 
    contactStart= tStart;

    while iHead<=numel(Qsat_sizes{si}) && sentBytes<take
      sz        = Qsat_sizes{si}(iHead);
      readyTime = Qsat_ready{si}(iHead);
      ttl       = Qsat_TTL{si}(iHead);
      tCreated  = Qsat_times{si}(iHead);
      bID       = Qsat_id{si}(iHead);
      expiryT   = tCreated + seconds(ttl);

      % require ready *before* this contact begins
      if readyTime > contactStart
          break;  % leave this and later copies for the next GS2 contact
      end

      tQueuedStart = contactStart + seconds(sentBytes / rateB);
      txStart_dn   = max(tQueuedStart, readyTime);
      txTime       = seconds(sz / rateB);
      deliverT     = txStart_dn + txTime + seconds(propd);

      % If delivery would occur after TTL expires -> TTL drop
      if deliverT > expiryT
          bundles_droppedTTL = bundles_droppedTTL + 1;
          if sentBytes+sz<=take
              sentBytes = sentBytes+sz; 
              iHead     = iHead+1;
          else
              Qsat_sizes{si}(iHead)=sz-(take-sentBytes);
              sentBytes            = take;
          end
          continue;
      end

      if sentBytes+sz<=take
        % Air bytes (downlink with ARQ overhead)
        air_bytes_total = air_bytes_total + sz * ARQ_extra_factor;

        % Duplicate suppression: only first delivered copy counts
        if any(deliveredIDs == bID)
            bundles_dupSupp = bundles_dupSupp + 1;
        else
            lat = seconds(deliverT - tCreated);
            delivered = [delivered; {bID, tCreated, deliverT, sz, lat}]; %#ok<AGROW>
            deliveredIDs(end+1,1) = bID;
        end

        sentBytes = sentBytes+sz; 
        iHead     = iHead+1;
      else
        Qsat_sizes{si}(iHead)=sz-(take-sentBytes);
        sentBytes            = take;
      end
    end

    if iHead>1
      Qsat_times{si}   = Qsat_times{si}(iHead:end);
      Qsat_ready{si}   = Qsat_ready{si}(iHead:end);
      Qsat_sizes{si}   = Qsat_sizes{si}(iHead:end);
      Qsat_TTL{si}     = Qsat_TTL{si}(iHead:end);
      Qsat_id{si}      = Qsat_id{si}(iHead:end);
      Qsat_bytes_in(si)= sum(Qsat_sizes{si});
    end
  end
end

%% ======== Final TTL cleanup at simulation end ========
[Qsrc_times,Qsrc_sizes,Qsrc_TTL,Qsrc_id,bytesDropSrc,countDropSrc] = ...
    expire_queue(Qsrc_times,Qsrc_sizes,Qsrc_TTL,Qsrc_id,stopTime);
Qsrc_bytes_in      = Qsrc_bytes_in - bytesDropSrc;
bundles_droppedTTL = bundles_droppedTTL + countDropSrc;

for si=1:nsat
    [Qsat_times{si},Qsat_ready{si},Qsat_sizes{si},Qsat_TTL{si},Qsat_id{si}, ...
     bytesDropSat,countDropSat] = ...
        expire_queue_sat(Qsat_times{si},Qsat_ready{si},Qsat_sizes{si}, ...
                         Qsat_TTL{si},Qsat_id{si},stopTime);
    Qsat_bytes_in(si)  = Qsat_bytes_in(si) - bytesDropSat;
    bundles_droppedTTL = bundles_droppedTTL + countDropSat;
end

%% ======== Evaluation (console) ========
total_created   = numel(createdTimes);       % unique bundles at source
total_delivered = numel(deliveredIDs);       % unique delivered bundles

deliv_ratio = total_delivered / max(1,total_created);
mean_lat = mean(delivered.Latency_s,'omitnan');
med_lat  = median(delivered.Latency_s,'omitnan');
if isempty(delivered)
    p95_lat = NaN;
else
    p95_lat = prctile(delivered.Latency_s,95);
end
fprintf('Delivery ratio %.3f | mean %.1fs | med %.1fs | p95 %.1fs | TTL drops %d | dup drops %d\n', ...
    deliv_ratio, mean_lat, med_lat, p95_lat, bundles_droppedTTL, bundles_dupSupp);

%% ======== Summary metrics for GUI / experiments ========
payload_bytes_deliv = sum(delivered.Size_bytes);

if payload_bytes_deliv > 0
    overhead_ratio = air_bytes_total / payload_bytes_deliv;
else
    overhead_ratio = NaN;
end

%% ======== Return struct ========
S.contacts             = contacts;
S.delivered            = delivered;
S.startTime            = startTime;
S.stopTime             = stopTime;
S.Qsrc_bytes_in        = Qsrc_bytes_in;
S.Qsrc_bytes_dropped   = Qsrc_bytes_dropped;
S.Qsat_bytes_in        = Qsat_bytes_in;
S.Qsat_bytes_drop      = Qsat_bytes_drop;
S.total_created        = total_created;      % unique bundles
S.total_delivered      = total_delivered;    % unique bundles delivered
S.total_offered_bytes  = sum(msgSizes);
S.payload_bytes_deliv  = payload_bytes_deliv;
S.air_bytes_total      = air_bytes_total;
S.overhead_ratio       = overhead_ratio;
S.bundles_droppedTTL   = bundles_droppedTTL; % copy-level TTL drops
S.bundles_dupSupp      = bundles_dupSupp;    % duplicate deliveries suppressed
S.bufPolicy            = bufPolicy;
S.BUF_GS_SRC           = BUF_GS_SRC;
S.BUF_SAT              = BUF_SAT;
S.TTL_s                = TTL_s;
S.routing              = routing;
S.sprayCopies          = sprayCopies;
S.cfg                  = cfg;
S.numGroundStations    = 2;
S.numSatellites        = nsat;
S.orbitClass           = orbitClass;
end % ======= main =======


%% =================== Helpers ===================

function contacts=build_contacts_table(sc,sat,gs1,gs2,elevMaskDeg,...
    lambda,Pt_dBm,Gt_dB,Gr_dB,kT_dBm,B_Hz,eta_eff,timeline)

contacts = table('Size',[0 12],'VariableTypes',...
 {'string','string','datetime','datetime','double','double','double','double','double','double','double','double'},...
 'VariableNames',{'Sat','Link','StartTime','EndTime','Duration_s','MeanElev_deg','MaxElev_deg','MeanRange_km','MeanRate_Mbps','Rate_Bps','Cap_bytes','PropDelay_s'});
contacts.StartTime.TimeZone='UTC'; contacts.EndTime.TimeZone='UTC';

gs1ECEF=lla2ecef_WGS84(gs1(1),gs1(2),0).';
gs2ECEF=lla2ecef_WGS84(gs2(1),gs2(2),0).';

for si=1:numel(sat)
 iv12=accessIntervals(access(sat(si),gs1));
 iv21=accessIntervals(access(sat(si),gs2));
 contacts=addContactRows(contacts,"GS1",sat(si),gs1,gs1ECEF,iv12, ...
   elevMaskDeg,lambda,Pt_dBm,Gt_dB,Gr_dB,kT_dBm,B_Hz,eta_eff,timeline);
 contacts=addContactRows(contacts,"GS2",sat(si),gs2,gs2ECEF,iv21, ...
   elevMaskDeg,lambda,Pt_dBm,Gt_dB,Gr_dB,kT_dBm,B_Hz,eta_eff,timeline);
end
end

function contacts=addContactRows(contacts,linkTag,satObj,gsLLA,gsECEF,ivals,...
  elevMaskDeg,lambda,Pt_dBm,Gt_dB,Gr_dB,kT_dBm,B_Hz,eta_eff,timeline)
if isempty(ivals), return; end
ds=3; % decimation inside contact to speed math
for k=1:height(ivals)
 t0=ivals.StartTime(k); t1=ivals.EndTime(k);
 idx=find(timeline>=t0 & timeline<=t1);
 if numel(idx)<2, continue; end
 idx=idx(1:ds:end); subTimes=timeline(idx);

 subECEF=states_ecef_series(satObj,subTimes);
 Rm=vecnorm(subECEF-gsECEF,2,1);
 el=elevation_series(satObj,gsLLA,subTimes);
 valid=(el>=elevMaskDeg); if ~any(valid), continue; end

 FSPL    = 20*log10(4*pi*Rm(valid)/lambda);
 N0B_dBm = kT_dBm + 10*log10(B_Hz);
 SNR_dB  = Pt_dBm + Gt_dB + Gr_dB - FSPL - N0B_dBm;

 rate_Mbps=max((B_Hz/1e6).*log2(1+10.^(SNR_dB/10)),0);
 rate_Mbps=eta_eff*rate_Mbps;

 meanRate = mean(rate_Mbps);
 rateBps  = meanRate*1e6/8;
 dur_s    = seconds(t1-t0);
 cap_bytes= rateBps*dur_s;
 prop_delay = median(Rm(valid))/3e8;

 contacts=[contacts; { string(satObj.Name), string(linkTag), t0, t1, dur_s, ...
    mean(el(valid)), max(el(valid)), mean(Rm(valid))/1e3, ...
    meanRate, rateBps, cap_bytes, prop_delay }]; %#ok<AGROW>
end
end

function rECEF=states_ecef_series(satObj,times)
N=numel(times); rECEF=zeros(3,N);
for k=1:N
 [~,r]=states(satObj,times(k),'CoordinateFrame','ecef');
 rECEF(:,k)=double(r);
end
end

function el=elevation_series(satObj,gsLLA,times)
N=numel(times); el=zeros(1,N);
lat=gsLLA(1); lon=gsLLA(2);
for k=1:N
 [~,e]=aer(deg2rad(lat),deg2rad(lon),0,satObj,times(k)); %#ok<NASGU>
 % That aer(...) call is a placeholder, but to keep it simple:
 % If this line fails in your MATLAB version, you can replace the whole
 % elevation computation by a fixed value, since synthetic mode doesn't use it.
 el(k)=45; % approximate
end
end

function r=lla2ecef_WGS84(lat_deg,lon_deg,alt_m)
a=6378137; f=1/298.257223563; e2=f*(2-f);
lat=deg2rad(lat_deg); lon=deg2rad(lon_deg); h=alt_m;
N=a./sqrt(1 - e2*sin(lat).^2);
x=(N+h).*cos(lat).*cos(lon);
y=(N+h).*cos(lat).*sin(lon);
z=(N*(1-e2)+h).*sin(lat);
r=[x y z];
end

function mask = in_contact_col(timeline_col, contacts, linkTag)
% Not used anymore in this version, but kept for compatibility if needed.
t = timeline_col(:); %#ok<NASGU>
mask = false(size(t));
end

%% ===== TTL helper functions =====

function [times,sizes,TTLs,IDs,bytesDropped,countDropped] = ...
    expire_queue(times,sizes,TTLs,IDs,nowT)
if isempty(times)
    bytesDropped = 0;
    countDropped = 0;
    return;
end
expMask = false(size(times));
for k=1:numel(times)
    if nowT > times(k) + seconds(TTLs(k))
        expMask(k) = true;
    end
end
bytesDropped = sum(sizes(expMask));
countDropped = sum(expMask);
times(expMask) = [];
sizes(expMask) = [];
TTLs(expMask)  = [];
IDs(expMask)   = [];
end

function [times,ready,sizes,TTLs,IDs,bytesDropped,countDropped] = ...
    expire_queue_sat(times,ready,sizes,TTLs,IDs,nowT)
if isempty(times)
    bytesDropped = 0;
    countDropped = 0;
    return;
end
expMask = false(size(times));
for k=1:numel(times)
    if nowT > times(k) + seconds(TTLs(k))
        expMask(k) = true;
    end
end
bytesDropped = sum(sizes(expMask));
countDropped = sum(expMask);
times(expMask) = [];
ready(expMask) = [];
sizes(expMask) = [];
TTLs(expMask)  = [];
IDs(expMask)   = [];
end

%% ===== Synthetic contact plans (LEO / MEO / GEO) =====
function contacts = build_synthetic_contacts_leo(startTime,stopTime,numSat)
% LEO-like: short, frequent passes
durContact = minutes(10);
gap        = minutes(40);
rate_Mbps  = 10;
rate_Bps   = rate_Mbps*1e6/8;
prop_delay = 0.06;   % ~60 ms one-way

% Generate satellite names LEO-1, LEO-2, ..., LEO-N
sats = strings(1,numSat);
for s = 1:numSat
    sats(s) = "LEO-" + s;
end

links = ["GS1","GS2"];
contacts = empty_contacts_table();

for s = 1:numel(sats)
    t = startTime + minutes(5*s); % stagger
    while t < stopTime
        for li = 1:numel(links)
            t0 = t + (li-1)*durContact/2;
            t1 = t0 + durContact;
            if t1 > stopTime, break; end
            dur_s    = seconds(t1-t0);
            cap_bytes = rate_Bps * dur_s;
            contacts = [contacts; {sats(s), links(li), t0, t1, dur_s, ...
                45, 60, 1500, rate_Mbps, rate_Bps, cap_bytes, prop_delay}]; %#ok<AGROW>
        end
        t = t + durContact + gap;
    end
end

contacts = sortrows(contacts,'StartTime');
end

function contacts = build_synthetic_contacts_meo(startTime,stopTime,numSat)
% MEO-like: longer but less frequent passes
durContact = minutes(20);
gap        = minutes(80);
rate_Mbps  = 7;
rate_Bps   = rate_Mbps*1e6/8;
prop_delay = 0.12;   % ~120 ms one-way

% Generate satellite names MEO-1, MEO-2, ..., MEO-N
sats = strings(1,numSat);
for s = 1:numSat
    sats(s) = "MEO-" + s;
end

links = ["GS1","GS2"];
contacts = empty_contacts_table();

for s = 1:numel(sats)
    t = startTime + minutes(10*s); % stagger more
    while t < stopTime
        for li = 1:numel(links)
            t0 = t + (li-1)*durContact/2;
            t1 = t0 + durContact;
            if t1 > stopTime, break; end
            dur_s    = seconds(t1-t0);
            cap_bytes = rate_Bps * dur_s;
            contacts = [contacts; {sats(s), links(li), t0, t1, dur_s, ...
                35, 50, 10000, rate_Mbps, rate_Bps, cap_bytes, prop_delay}]; %#ok<AGROW>
        end
        t = t + durContact + gap;
    end
end

contacts = sortrows(contacts,'StartTime');
end

function contacts = build_synthetic_contacts_geo(startTime,stopTime,numSat)
% GEO-like: very long, almost continuous contacts
durContact = minutes(120);   % 2-hour windows
gap        = minutes(20);
rate_Mbps  = 3;
rate_Bps   = rate_Mbps*1e6/8;
prop_delay = 0.24;   % ~240 ms one-way

% Generate satellite names GEO-1, GEO-2, ..., GEO-N
sats = strings(1,numSat);
for s = 1:numSat
    sats(s) = "GEO-" + s;
end

links = ["GS1","GS2"];
contacts = empty_contacts_table();

for s = 1:numel(sats)
    t = startTime + minutes(15*s); % stagger
    while t < stopTime
        for li = 1:numel(links)
            t0 = t + (li-1)*durContact/2;
            t1 = t0 + durContact;
            if t1 > stopTime, break; end
            dur_s    = seconds(t1-t0);
            cap_bytes = rate_Bps * dur_s;
            contacts = [contacts; {sats(s), links(li), t0, t1, dur_s, ...
                20, 30, 36000, rate_Mbps, rate_Bps, cap_bytes, prop_delay}]; %#ok<AGROW>
        end
        t = t + durContact + gap;
    end
end

contacts = sortrows(contacts,'StartTime');
end

function contacts = empty_contacts_table()
contacts = table('Size',[0 12],'VariableTypes',...
 {'string','string','datetime','datetime','double','double','double','double','double','double','double','double'},...
 'VariableNames',{'Sat','Link','StartTime','EndTime','Duration_s','MeanElev_deg','MaxElev_deg','MeanRange_km','MeanRate_Mbps','Rate_Bps','Cap_bytes','PropDelay_s'});
contacts.StartTime.TimeZone='UTC'; 
contacts.EndTime.TimeZone  ='UTC';
end

%% ===== Buffer policy helpers =====

function [qt,qs,qTTL,qID,freedBytes,countDropped] = ...
    enforce_buf_policy_src(qt,qs,qTTL,qID,BUF_MAX,need,policy)
freedBytes   = 0;
countDropped = 0;
policy = lower(string(policy));

while sum(qs) + need > BUF_MAX && ~isempty(qs)
    switch policy
        case "largest"
            [~,idx] = max(qs);
        case "random"
            idx = randi(numel(qs));
        otherwise   % "oldest"
            idx = 1;
    end
    freedBytes   = freedBytes + qs(idx);
    countDropped = countDropped + 1;
    qt(idx)   = [];
    qs(idx)   = [];
    qTTL(idx) = [];
    qID(idx)  = [];
end
end

function [qt,qr,qs,qTTL,qID,freedBytes,countDropped] = ...
    enforce_buf_policy_sat(qt,qr,qs,qTTL,qID,BUF_MAX,need,policy)
freedBytes   = 0;
countDropped = 0;
policy = lower(string(policy));

while sum(qs) + need > BUF_MAX && ~isempty(qs)
    switch policy
        case "largest"
            [~,idx] = max(qs);
        case "random"
            idx = randi(numel(qs));
        otherwise   % "oldest"
            idx = 1;
    end
    freedBytes   = freedBytes + qs(idx);
    countDropped = countDropped + 1;
    qt(idx)   = [];
    qr(idx)   = [];
    qs(idx)   = [];
    qTTL(idx) = [];
    qID(idx)  = [];
end
end
