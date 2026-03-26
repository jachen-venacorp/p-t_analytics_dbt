{{ config(materialized='table') }}

WITH PROD_TENANT_INFO AS
(
select
tenant_id,
tenant_nm,
tenant_typ_nm,
tenant_enbld_status_nm,
account_id,
data_cntr_cd
from {{ source('prod', 'tenant_prof') }}
where CRNT_RCRD_IND = 'Y'
--and tenant_typ_nm in ('PRODUCTION')
--and organization_typ_nm = 'CUSTOMER'
and tenant_enbld_status_nm = 'ENABLED'
)

select 
data_center,
staging.tenant_id,
tenant_nm,
tenant_typ_nm,
tenant_enbld_status_nm,
file_id,
etl_load_date,
number_of_operational_choose_mappings,
number_of_writeback_queries
from {{ source('mtserver', 'MTSERVER_TEMPLATE_METRICS_STAGING')}} staging
left join prod_tenant_info on 
prod_tenant_info.data_cntr_cd = right(staging.data_center,3)
and prod_tenant_info.tenant_id = staging.tenant_id 
--where data_center = 'prd-eu3'
where 
(number_of_operational_choose_mappings > 0
or 
number_of_writeback_queries > 0) 