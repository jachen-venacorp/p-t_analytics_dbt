{{ config(materialized='table') }}

with prod_tenant_list as 
(
select distinct
tenant_id,
TENANT_NM, 
eff_from_dt,
account_id,
data_cntr_cd
from PROD_HARMONIZED.PRODUCT.TENANT_PROF
where CRNT_RCRD_IND = 'Y'
and tenant_typ_nm in ('PRODUCTION')
and organization_typ_nm = 'CUSTOMER'
and tenant_enbld_status_nm = 'ENABLED'
),

arr as 
(
select
dc_tenant_id,
arr_usd
from PROD_HARMONIZED.PRODUCT.VW_ENBLD_PRODUCTION_TENANTS
),

acc as 
(
select 
account_id,
became_customer_dt,
indstry_nm,
territory_sgmnt_nm,
renewal_dt
from PROD_HARMONIZED.SALES.VW_ACCOUNT_PROF
),

cont as 

(
SELECT distinct
substr(tenant_dc,charindex('.', tenant_dc)+1,len(tenant_dc)) as tenant_id,
user_id
FROM PROD_HARMONIZED.PRODUCT.VW_USER_PROF
where crnt_rcrd_ind = 'Y'
--and actvtn_status_nm = 'ACTIVE'
and cntrbtr_access_ind = 'Y'
--and admin_access_ind = 'N'
and last_impersonation_login_dt is null 
and ntfctn_email is null
order by user_id
),

hydra as 
(
select 
    hydra.tenant_id,
--    tenant_nm,
    max(session_start_dts) as latest_desktop_ts

from PROD_HARMONIZED.PRODUCT.HYDRA_UI_ACTIONS hydra
inner join cont on cont.tenant_id = hydra.tenant_id and cont.user_id = hydra.user_id

where hydra.event_nm ilike '%simplerefresh%'   
and hydra.timing_ctgry_nm = 'DesktopAddin'
--and to_date(session_start_dts) < '2024-05-01'
group by hydra.tenant_id--,tenant_nm
),


v as 
(
select 
region,
customer_id as tenant_id,
--tenant_nm,
max(etl_load_date) as latest_365_ts

from PROD_RAW.PROD_TEAM_SANDBOX.VENALYTICS_RUM_DATA_STAGING staging
--inner join prod_tenant_list on staging.customer_id = prod_tenant_list.tenant_id and staging.region = prod_tenant_list.data_cntr_cd
inner join cont on cont.tenant_id = staging.customer_id and staging.user_id =staging.user_id
where file_id is not null 
and total_duration is not null
--and etl_load_date < '2024-05-01'
and is_initial_load = 'True'
group by region,customer_id--, tenant_nm
),

v9 as
(
select 
v9.sf_account_id,
predict_proba_1 as churn_probability 
from PROD_PRESENTATION.CHURN_PREDICTION.VW_CHURN_PREDICTION_MONTHLY__MODEL_V9 v9
inner join 
(
select 
sf_account_id,
max(fiscal_month) as maxdate
from PROD_PRESENTATION.CHURN_PREDICTION.VW_CHURN_PREDICTION_MONTHLY__MODEL_V9
group by sf_account_id
)maxdate
on v9.sf_account_id = maxdate.sf_account_id and v9.fiscal_month = maxdate.maxdate
),

legacy_connector as 
(
select 
track.account_id,
sum(num_events) as total_events,
sum(num_minutes) as total_minutes,
max(_fivetran_synced) as latest_usage
from PROD_RAW.PENDO.TRACK_TYPE_EVENT track 
where track_type_id = 'm6dr7UFzH5cEzVPeyHcm-dKK3_4'
group by 
track.account_id
)

select 
prod_tenant_list.tenant_id,
prod_tenant_list.tenant_nm,
prod_tenant_list.account_id,
arr_usd,
churn_probability,
eff_from_dt,
latest_desktop_ts,
latest_365_ts,
case 
when latest_desktop_ts > (current_date()-30) and latest_365_ts > (current_date()-30) then 'Used Both Addins Recently'
when latest_desktop_ts > (current_date()-30) and latest_365_ts is null then 'Used Desktop Addin Recently'
when latest_desktop_ts is null  and latest_365_ts > (current_date()-30) then 'Used 365 Addin Recently'
end as which_addin,
case 
when latest_desktop_ts > (current_date()-365) and latest_365_ts > (current_date()-365) then 'Refreshed Templates for Both Addins Past Year'
when latest_desktop_ts > (current_date()-365) and latest_365_ts is null then 'Refreshed Templates for Desktop Addin Past Year'
when latest_desktop_ts is null  and latest_365_ts > (current_date()-365) then 'Refreshed Templates for 365 Addin Past Year'
end as which_addin_LTM,
total_events as initializations_legacy_connector,
latest_usage as most_recent_legacy_connector_usage,
case 
when latest_usage > (current_date()-365) then 'Legacy Connector Used LTM'
else null end as legacy_connector_usage_status
from prod_tenant_list
left join v on prod_tenant_list.tenant_id = v.tenant_id and prod_tenant_list.data_cntr_cd = v.region
left join v9 on prod_tenant_list.account_id = left(v9.sf_account_id,15)
left join legacy_connector on concat(data_cntr_cd,'.',prod_tenant_list.tenant_id) = legacy_connector.account_id
left join arr on arr.dc_tenant_id = concat(data_cntr_cd,'.',prod_tenant_list.tenant_id)
left join hydra on prod_tenant_list.tenant_id = hydra.tenant_id
--tough to deal with in relationships, exists in aws and azure
where prod_tenant_list.tenant_id <> '1497761032260681728'