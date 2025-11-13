function S = dtn_leo_two_gs
% LEO-only DTN demo: Source GS -> Satellite(s) -> Destination GS
% Requires: Aerospace Toolbox
% Returns: S struct with contacts, delivered, timing, and accounting.

%% ======== Config ========
startTime  = datetime(2025,11,10,12,0,0,'TimeZone','UTC');
stopTime   = datetime(2025,11,11,12,0,0,'TimeZone','UTC');
sampleTime = 2;  % s

% Ground stations (Source/Dest)
GS1 = [32.7157,  -117.1611,  0];  % San Diego
GS2 = [40.4168,   -3.7038,   0];  % Madrid

% Link model
c = 2.99792458e8; freq=12e9; B_Hz=20e6;
Pt_dBm=30; Gt_dB=20; Gr_dB=30; kT_dBm=-228.6+10*log10(290);
lambda=c/freq;
elevMaskDeg=2;     % deg
eta_eff=0.7;       % efficiency vs Shannon

% DTN traffic / buffers
rng(1);
lambda_msg_per_s=0.01;
msgSize_bytes=50e3;
BUF_GS_SRC=50e6;   % 50 MB
BUF_SAT   =50e6;   % per-satellite

% Prevent “instant relay”: dwell on sat + forbid same-pass downlink
minStore_s = 300;  % try 300–900 s for larger medians

USE_VIEWER = true; % keep headless here (dashboard is in separate file)

%% ======== Scenario ========
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

% Names
satNames = strings(1,numel(sat));
for ii=1:numel(sat)
    try, satNames(ii)=string(sat(ii).Name); catch, satNames(ii)=""; end
end

% Ground stations
gs1 = groundStation(sc,GS1(1),GS1(2),"Name","GS-Source","MinElevationAngle",elevMaskDeg);
gs2 = groundStation(sc,GS2(1),GS2(2),"Name","GS-Dest",  "MinElevationAngle",elevMaskDeg);

% Viewer (off by default)
if USE_VIEWER
  v = satelliteScenarioViewer(sc); %#ok<NASGU>
  show(sat);
  groundTrack(sat,LeadTime=3600,TrailTime=600);
  ac1=access(sat,gs1); ac2=access(sat,gs2);
  show(ac1); show(ac2);
end

%% ======== Contacts ========
timeline = startTime:seconds(sampleTime):stopTime;

contacts = build_contacts_table(sc,sat,gs1,gs2,elevMaskDeg,...
    lambda,Pt_dBm,Gt_dB,Gr_dB,kT_dBm,B_Hz,eta_eff,timeline);

if isempty(contacts)
  warning('No contacts found. Retrying with mask=0°...');
  contacts = build_contacts_table(sc,sat,gs1,gs2,0,...
      lambda,Pt_dBm,Gt_dB,Gr_dB,kT_dBm,B_Hz,eta_eff,timeline);
end
if ~isempty(contacts)
  contacts = sortrows(contacts,'StartTime');
else
  warning('Still no contacts—try longer window or other GS/planes.');
end

%% ======== DTN Queues ========
% Source queue
Qsrc_times = datetime.empty(0,1); Qsrc_times.TimeZone='UTC';
Qsrc_sizes = zeros(0,1);
Qsrc_bytes_in = 0; Qsrc_bytes_dropped = 0;

% Satellite queues (created, ready, size)
Qsat_times=cell(1,numel(sat));
Qsat_ready=cell(1,numel(sat));
Qsat_sizes=cell(1,numel(sat));
Qsat_bytes_in = zeros(1,numel(sat));
Qsat_bytes_drop = zeros(1,numel(sat));
for i=1:numel(sat)
    Qsat_times{i}=datetime.empty(0,1); Qsat_times{i}.TimeZone='UTC';
    Qsat_ready{i}=datetime.empty(0,1); Qsat_ready{i}.TimeZone='UTC';
    Qsat_sizes{i}=zeros(0,1);
end

%% ======== Message Generation (column-safe, off-contact) ========
allSec   = (startTime:seconds(1):stopTime).';     % N×1 column
N        = numel(allSec);
uplinkBusy = in_contact_col(allSec, contacts, "GS1");   % N×1 logical
randMask   = (rand(N,1) < lambda_msg_per_s);            % N×1 logical
genMask    = randMask & ~uplinkBusy;                    % N×1 logical

createdTimes = allSec(genMask);
msgSizes     = msgSize_bytes * ones(size(createdTimes));

% Enqueue at source respecting buffer
for i=1:numel(createdTimes)
  need=msgSizes(i);
  if Qsrc_bytes_in+need<=BUF_GS_SRC
    Qsrc_times(end+1,1)=createdTimes(i);
    Qsrc_sizes(end+1,1)=need;
    Qsrc_bytes_in=Qsrc_bytes_in+need;
  else
    Qsrc_bytes_dropped=Qsrc_bytes_dropped+need;
  end
end

% Delivery table
delivered = table('Size',[0 4],'VariableTypes',{'datetime','datetime','double','double'}, ...
 'VariableNames',{'Created','Delivered','Size_bytes','Latency_s'});
delivered.Created.TimeZone='UTC'; delivered.Delivered.TimeZone='UTC';

%% ======== Process Contacts (uplink/downlink) ========
for r=1:height(contacts)
  link   = contacts.Link(r);
  satTag = string(contacts.Sat(r));
  si     = find(satNames==satTag,1,'first'); if isempty(si), continue; end

  capB   = contacts.Cap_bytes(r);
  rateB  = contacts.Rate_Bps(r);
  tStart = contacts.StartTime(r);
  propd  = contacts.PropDelay_s(r);
  if capB<=0, continue; end

  if link=="GS1"
    % ----- UPLINK: GS1 -> SAT (respect creation time; add dwell to ready time) -----
    if isempty(Qsrc_sizes), continue; end
    take=min(sum(Qsrc_sizes),capB);
    sentBytes=0; iHead=1; contactStart=tStart;

    while iHead<=numel(Qsrc_sizes) && sentBytes<take
      sz=Qsrc_sizes(iHead);
      % next free slot on link
      tQueuedStart = contactStart + seconds(sentBytes / rateB);
      % cannot tx before created
      txStart_up   = max(tQueuedStart, Qsrc_times(iHead));
      txTime       = seconds(sz / rateB);
      arriveSatT   = txStart_up + txTime + seconds(propd);

      % dwell + prevent same-pass downlink
      uplinkEndT   = contacts.EndTime(r);
      notBeforeT   = uplinkEndT + seconds(minStore_s);
      readyT       = max(arriveSatT, notBeforeT);

      if sentBytes+sz<=take
        if sum(Qsat_sizes{si}) + sz <= BUF_SAT
          Qsat_times{si}(end+1,1) = Qsrc_times(iHead); % creation time
          Qsat_ready{si}(end+1,1) = readyT;            % earliest DN allowed
          Qsat_sizes{si}(end+1,1) = sz;
          Qsat_bytes_in(si) = Qsat_bytes_in(si) + sz;
        else
          Qsat_bytes_drop(si) = Qsat_bytes_drop(si) + sz;
        end
        sentBytes=sentBytes+sz; iHead=iHead+1;
      else
        Qsrc_sizes(iHead) = sz - (take-sentBytes);
        sentBytes=take;
      end
    end
    if iHead>1
      Qsrc_times=Qsrc_times(iHead:end);
      Qsrc_sizes=Qsrc_sizes(iHead:end);
    end

  else
    % ----- DOWNLINK: SAT -> GS2 (must be ready BEFORE this contact begins) -----
    if isempty(Qsat_sizes{si}), continue; end
    take=min(sum(Qsat_sizes{si}),capB);
    sentBytes=0; iHead=1; contactStart=tStart;

    while iHead<=numel(Qsat_sizes{si}) && sentBytes<take
      sz        = Qsat_sizes{si}(iHead);
      readyTime = Qsat_ready{si}(iHead);

      % require a *future* GS2 pass; if not ready before this contact, defer
      if readyTime > contactStart
          break;  % leave this and later messages for the next GS2 contact
      end

      tQueuedStart = contactStart + seconds(sentBytes / rateB);
      txStart_dn   = max(tQueuedStart, readyTime);
      txTime       = seconds(sz / rateB);
      deliverT     = txStart_dn + txTime + seconds(propd);

      if sentBytes+sz<=take
        lat = seconds(deliverT - Qsat_times{si}(iHead));  % Created -> Delivered
        delivered = [delivered; {Qsat_times{si}(iHead), deliverT, sz, lat}]; %#ok<AGROW>
        sentBytes=sentBytes+sz; iHead=iHead+1;
      else
        Qsat_sizes{si}(iHead)=sz-(take-sentBytes);
        sentBytes=take;
      end
    end

    if iHead>1
      Qsat_times{si}=Qsat_times{si}(iHead:end);
      Qsat_ready{si}=Qsat_ready{si}(iHead:end);
      Qsat_sizes{si}=Qsat_sizes{si}(iHead:end);
    end
  end
end

%% ======== Evaluation (console) ========
deliv_ratio = height(delivered)/max(1,numel(createdTimes));
mean_lat = mean(delivered.Latency_s,'omitnan');
med_lat  = median(delivered.Latency_s,'omitnan');
p95_lat  = iif(~isempty(delivered), prctile(delivered.Latency_s,95), NaN);
fprintf('Delivery ratio %.3f | mean %.1fs | med %.1fs | p95 %.1fs\n', ...
    deliv_ratio, mean_lat, med_lat, p95_lat);

%% ======== Return struct for dashboard ========
S.contacts            = contacts;
S.delivered           = delivered;
S.startTime           = startTime;
S.stopTime            = stopTime;
S.Qsrc_bytes_in       = Qsrc_bytes_in;
S.Qsrc_bytes_dropped  = Qsrc_bytes_dropped;
S.Qsat_bytes_in       = Qsat_bytes_in;
S.Qsat_bytes_drop     = Qsat_bytes_drop;
S.total_created        = numel(createdTimes);
S.total_delivered      = height(delivered);
S.total_offered_bytes  = sum(msgSizes);

end % ======= main =======


%% =================== Helpers (local to this file) ===================
function contacts=build_contacts_table(sc,sat,gs1,gs2,elevMaskDeg,...
    lambda,Pt_dBm,Gt_dB,Gr_dB,kT_dBm,B_Hz,eta_eff,timeline)

contacts = table('Size',[0 12],'VariableTypes',...
 {'string','string','datetime','datetime','double','double','double','double','double','double','double','double'},...
 'VariableNames',{'Sat','Link','StartTime','EndTime','Duration_s','MeanElev_deg','MaxElev_deg','MeanRange_km','MeanRate_Mbps','Rate_Bps','Cap_bytes','PropDelay_s'});
contacts.StartTime.TimeZone='UTC'; contacts.EndTime.TimeZone='UTC';

gs1ECEF=lla2ecef_WGS84(gs1.Latitude,gs1.Longitude,0).';
gs2ECEF=lla2ecef_WGS84(gs2.Latitude,gs2.Longitude,0).';

for si=1:numel(sat)
 iv12=accessIntervals(access(sat(si),gs1));
 iv21=accessIntervals(access(sat(si),gs2));
 contacts=addContactRows(contacts,"GS1",sat(si),gs1,gs1ECEF,iv12, ...
   elevMaskDeg,lambda,Pt_dBm,Gt_dB,Gr_dB,kT_dBm,B_Hz,eta_eff,timeline);
 contacts=addContactRows(contacts,"GS2",sat(si),gs2,gs2ECEF,iv21, ...
   elevMaskDeg,lambda,Pt_dBm,Gt_dB,Gr_dB,kT_dBm,B_Hz,eta_eff,timeline);
end
end

function contacts=addContactRows(contacts,linkTag,satObj,gsObj,gsECEF,ivals,...
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
 el=elevation_series(satObj,gsObj,subTimes);
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

function el=elevation_series(satObj,gsObj,times)
N=numel(times); el=zeros(1,N);
for k=1:N
 [~,e]=aer(gsObj,satObj,times(k)); % ground -> sat (correct)
 el(k)=double(e);
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

function y=iif(cond,a,b)
if cond, y=a; else, y=b; end
end

function mask = in_contact_col(timeline_col, contacts, linkTag)
% Return N×1 mask where any sat has the given link ("GS1"/"GS2")
t = timeline_col(:); N=numel(t);
mask = false(N,1);
if isempty(contacts), return; end
rows = strcmp(contacts.Link, string(linkTag));
if ~any(rows), return; end
for r = find(rows).'
    mask = mask | ((t >= contacts.StartTime(r)) & (t <= contacts.EndTime(r)));
end
end
