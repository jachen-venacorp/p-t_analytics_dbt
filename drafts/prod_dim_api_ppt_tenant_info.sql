{{ config(materialized='table') }}

WITH PROD_TENANT_INFO AS
(
select
tenant_id,
tenant_nm,
data_cntr_cd
from PROD_HARMONIZED.PRODUCT.TENANT_PROF
where CRNT_RCRD_IND = 'Y'
and tenant_enbld_status_nm = 'ENABLED'
and tenant_typ_nm in ('PRODUCTION')
),

Refreshes as 
(
select 
API.tenant_id,
tenant_nm,
user_id,
request_start_dts,
request_end_dts,
request_endpoint_nm,
case 
when (request_endpoint_nm ilike '/api/manager/globalFiles%data%' AND QUERY_STRING LIKE '%POWERPOINT_V365%') then 'PPT file download'
when (request_method_cd = 'PUT' AND request_endpoint_nm LIKE '/api/globalFiles/%/enrolledTemplates/%') then 'Enrolled with Template'
when (request_method_cd = 'POST' AND request_endpoint_nm LIKE '/api/manager/globalFiles/%/presentable/images%') then 'Initiated Refresh'
end as endpoint_action,
request_url,
query_string,
request_method_cd,
request_status_cd
from  PROD_HARMONIZED.PRODUCT.USER_API_ACTIVITY API
inner join prod_tenant_info on API.data_cntr_cd = prod_tenant_info.data_cntr_cd and API.tenant_id = prod_tenant_info.tenant_id
where to_date(request_end_dts) > '2023-11-13'
and request_status_cd in ('200','204')

and 
(
--download
(request_endpoint_nm ilike '/api/manager/globalFiles%data%' AND QUERY_STRING LIKE '%POWERPOINT_V365%')

OR

-- enrollment
(request_method_cd = 'PUT' AND request_endpoint_nm LIKE '/api/globalFiles/%/enrolledTemplates/%')

OR

--shows 1 refresh
(request_method_cd = 'POST' AND request_endpoint_nm LIKE '/api/manager/globalFiles/%/presentable/images%')
)
),

past_90 as 
(
select 
tenant_id,
tenant_nm,
count(request_start_dts) as last_90_day_refreshes
from Refreshes
where to_date(request_end_dts) >= (current_date()-90)
and endpoint_action = 'Initiated Refresh'
group by tenant_id, tenant_nm
),

all_time as 
(
select 
tenant_id,
tenant_nm,
count(case when (request_endpoint_nm ilike '/api/manager/globalFiles%data%' AND QUERY_STRING LIKE '%POWERPOINT_V365%')then 1 else null end) as all_time_downloads,
count(case when (request_method_cd = 'PUT' AND request_endpoint_nm LIKE '/api/globalFiles/%/enrolledTemplates/%') then 1 else null end) as all_time_template_enrollments,
count(case when (request_method_cd = 'POST' AND request_endpoint_nm LIKE '/api/manager/globalFiles/%/presentable/images%') then 1 else null end) as all_time_refreshes
from Refreshes
group by tenant_id, tenant_nm
),

specfic_refresh as 
(
select 
tenant_id,
tenant_nm,
to_date(max(request_end_dts)) as latest_refresh,
to_date(min(request_end_dts)) as first_refresh,
datediff(day,to_date(min(request_end_dts)), to_date(max(request_end_dts))) as gap_between_first_refresh
from Refreshes
where endpoint_action = 'Initiated Refresh'
group by tenant_id, tenant_nm
)

select
A.tenant_id,
A.tenant_nm,
all_time_downloads,
all_time_template_enrollments,
all_time_refreshes,
last_90_day_refreshes,
latest_refresh,
first_refresh,
gap_between_first_refresh
from Refreshes A 
left join specfic_refresh on A.tenant_id = specfic_refresh.tenant_id
left join past_90 on A.tenant_id = past_90.tenant_id
left join all_time on A.tenant_id = all_time.tenant_id
group by 
A.tenant_id, 
A.tenant_nm, 
all_time_downloads,
all_time_template_enrollments,
all_time_refreshes,
last_90_day_refreshes,
latest_refresh,
first_refresh,
gap_between_first_refresh


