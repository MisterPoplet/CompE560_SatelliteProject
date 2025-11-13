function show_dtn_dashboard(varargin)
% SHOW_DTN_DASHBOARD  Interactive results dashboard for DTN simulation.
%
% Usage:
%   show_dtn_dashboard(S)
%   show_dtn_dashboard(contacts, delivered, startTime, stopTime, ...
%                      Qsrc_bytes_in, Qsrc_bytes_dropped, Qsat_bytes_in, Qsat_bytes_drop)

%% --------- Normalize inputs ---------
if nargin == 1
    S = varargin{1};
    required = ["contacts","delivered","startTime","stopTime", ...
                "Qsrc_bytes_in","Qsrc_bytes_dropped","Qsat_bytes_in","Qsat_bytes_drop"];
    for k = 1:numel(required)
        if ~isfield(S, required(k))
            error('Struct input missing field: %s', required(k));
        end
    end
elseif nargin == 8
    S.contacts           = varargin{1};
    S.delivered          = varargin{2};
    S.startTime          = varargin{3};
    S.stopTime           = varargin{4};
    S.Qsrc_bytes_in      = varargin{5};
    S.Qsrc_bytes_dropped = varargin{6};
    S.Qsat_bytes_in      = varargin{7};
    S.Qsat_bytes_drop    = varargin{8};
else
    error(['Usage:\n  show_dtn_dashboard(S)\n' ...
           '  or\n  show_dtn_dashboard(contacts, delivered, startTime, stopTime, Qsrc_in, Qsrc_drop, Qsat_in, Qsat_drop)']);
end

%% --------- Compute key metrics ----------
durHrs = hours(S.stopTime - S.startTime);

nContacts = height(S.contacts);
avgDur_s  = safe_mean(S.contacts,'Duration_s');
medDur_s  = safe_median(S.contacts,'Duration_s');
avgRate   = safe_mean(S.contacts,'MeanRate_Mbps');
capBytes  = safe_sum(S.contacts,'Cap_bytes');

nDelivered = height(S.delivered);
lat_mean   = safe_mean(S.delivered,'Latency_s');
lat_median = safe_median(S.delivered,'Latency_s');
lat_p95    = safe_prctile(S.delivered,'Latency_s',95);

src_in_MB   = S.Qsrc_bytes_in/1e6;
src_drop_MB = S.Qsrc_bytes_dropped/1e6;
sat_in_MB   = sum(S.Qsat_bytes_in)/1e6;
sat_drop_MB = sum(S.Qsat_bytes_drop)/1e6;

contacts_per_hr = nContacts / max(durHrs, eps);

% --- NEW: real delivery ratio from the simulation ---
if isfield(S,'total_created') && S.total_created > 0
    deliv_ratio = S.total_delivered / S.total_created;
else
    deliv_ratio = NaN;  % unknown
end

%% --------- Build UI ----------
fig = uifigure('Name','DTN Results Dashboard','Color','w','Position',[100 100 1100 720]);
tg  = uitabgroup(fig,'Position',[1 1 fig.Position(3) fig.Position(4)]);

tab1 = uitab(tg,'Title','Summary');
tab2 = uitab(tg,'Title','Contacts');
tab3 = uitab(tg,'Title','Delivered');
tab4 = uitab(tg,'Title','Plots');

% ===== Summary Tab =====
g = uigridlayout(tab1,[6,4]); g.ColumnSpacing=12; g.RowSpacing=8; g.Padding=[14 14 14 14];
g.ColumnWidth = {'1x','1x','1x','1x'};
header = uilabel(g,'Text','DTN Summary','FontSize',18,'FontWeight','bold');
header.Layout.Column=[1 4]; header.Layout.Row=1;

mkKPI(g,2,1,'Window (UTC)',sprintf('%s → %s', string(S.startTime), string(S.stopTime)));
mkKPI(g,2,2,'Sim Duration (h)',fmtnum(durHrs,1));
mkKPI(g,2,3,'Contacts',fmtnum(nContacts));
mkKPI(g,2,4,'Contacts / hour',fmtnum(contacts_per_hr,2));

mkKPI(g,3,1,'Avg Contact Dur (s)',fmtnum(avgDur_s,1));
mkKPI(g,3,2,'Median Contact Dur (s)',fmtnum(medDur_s,1));
mkKPI(g,3,3,'Avg Rate (Mb/s)',fmtnum(avgRate,2));
mkKPI(g,3,4,'Total Capacity (MB)',fmtnum(capBytes/1e6,1));

% Delivered/Created and correct Delivery Ratio
mkKPI(g,4,1,'Delivered',fmtnum(nDelivered));
if isfield(S,'total_created')
    mkKPI(g,4,2,'Created', fmtnum(S.total_created));
    mkKPI(g,4,3,'Delivery Ratio', sprintf('%.1f %%', 100*deliv_ratio));
else
    mkKPI(g,4,2,'Delivery Ratio', '–');
end
mkKPI(g,4,4,'Latency mean (s)',fmtnum(lat_mean,1));

mkKPI(g,5,1,'Latency median (s)',fmtnum(lat_median,1));
mkKPI(g,5,2,'Latency p95 (s)',fmtnum(lat_p95,1));
mkKPI(g,5,3,'Src Buffer In (MB)',fmtnum(src_in_MB,1));
mkKPI(g,5,4,'Src Drops (MB)',fmtnum(src_drop_MB,1));

mkKPI(g,6,1,'Sat In (MB)',fmtnum(sat_in_MB,1));
mkKPI(g,6,2,'Sat Drops (MB)',fmtnum(sat_drop_MB,1));

% ===== Contacts Table =====
p2 = uipanel(tab2,'Title','Contacts','FontWeight','bold','Position',[10 10 1080 670]);
if isempty(S.contacts)
    uilabel(p2,'Text','No contacts found for this window.','Position',[20 610 400 24],'FontWeight','bold');
else
    uitable(p2,'Data',S.contacts,'Position',[10 10 1060 620]);
end

% ===== Delivered Table =====
p3 = uipanel(tab3,'Title','Delivered Messages','FontWeight','bold','Position',[10 10 1080 670]);
if isempty(S.delivered)
    uilabel(p3,'Text','No delivered messages in this run.','Position',[20 610 400 24],'FontWeight','bold');
else
    uitable(p3,'Data',S.delivered,'Position',[10 10 1060 620]);
end

% ===== Plots =====
g4 = uigridlayout(tab4,[1,2]); g4.RowSpacing=8; g4.ColumnSpacing=8; g4.Padding=[10 10 10 10];
ax1 = uiaxes(g4); title(ax1,'Latency CDF'); grid(ax1,'on'); xlabel(ax1,'Latency (s)'); ylabel(ax1,'CDF');
ax2 = uiaxes(g4); title(ax2,'Contact Duration vs Mean Rate'); grid(ax2,'on'); xlabel(ax2,'Duration (s)'); ylabel(ax2,'Mean Rate (Mb/s)');

if ~isempty(S.delivered)
    L = sort(S.delivered.Latency_s); F = (1:numel(L))/max(1,numel(L));
    plot(ax1,L,F,'LineWidth',1.5);
else
    text(ax1,0.5,0.5,'No delivered messages','HorizontalAlignment','center');
end
if ~isempty(S.contacts)
    scatter(ax2,S.contacts.Duration_s,S.contacts.MeanRate_Mbps,20,'filled');
else
    text(ax2,0.5,0.5,'No contacts','HorizontalAlignment','center');
end

end % ==== main ====

%% ======= Local UI helpers =======
function mkKPI(grid,row,col,label,value)
p = uipanel(grid); p.Layout.Row=row; p.Layout.Column=col; p.BorderType='none';
uilabel(p,'Text',label,'FontSize',11,'FontColor',[0.3 0.3 0.3],'Position',[5 26 200 22]);
uilabel(p,'Text',value,'FontSize',16,'FontWeight','bold','Position',[5 2 260 26]);
end

function s=fmtnum(x,prec)
% Optional precision; default 0 decimals
if nargin < 2 || isempty(prec), prec = 0; end
if isempty(x) || (isscalar(x) && isnan(x))
    s = '–';
else
    if ~isscalar(x), x = x(1); end
    s = num2str(x, ['%0.' num2str(prec) 'f']);
end
end

function v=safe_mean(T,f)
if isempty(T)||~ismember(f,T.Properties.VariableNames), v=NaN;
else, v=mean(T.(f),'omitnan'); end
end

function v=safe_median(T,f)
if isempty(T)||~ismember(f,T.Properties.VariableNames), v=NaN;
else, v=median(T.(f),'omitnan'); end
end

function v=safe_sum(T,f)
if isempty(T)||~ismember(f,T.Properties.VariableNames), v=0;
else, v=nansum(T.(f)); end
end

function v=safe_prctile(T,f,p)
if isempty(T)||~ismember(f,T.Properties.VariableNames)||isempty(T.(f)), v=NaN;
else, v=prctile(T.(f),p); end
end

function r=safe_ratio(a,b)
if b<=0, r=0; else, r=a/b; end
end
