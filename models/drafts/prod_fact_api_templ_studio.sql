{{ config(materialized='table') }}

WITH PROD_TENANT_INFO AS
(
select
tenant_id,
tenant_nm,
account_id,
data_cntr_cd,
tenant_typ_nm
from PROD_HARMONIZED.PRODUCT.TENANT_PROF
where CRNT_RCRD_IND = 'Y'
and tenant_typ_nm in ('PRODUCTION')
and organization_typ_nm = 'CUSTOMER'
and tenant_enbld_status_nm = 'ENABLED'
)

select 
API.data_cntr_cd,
API.tenant_id,
tenant_nm,
account_id,
user_id,
request_end_dts,
request_endpoint_nm,
request_url,
request_status_cd,
request_size_b,
response_size_b,
user_imprsntd_ind
from PROD_HARMONIZED.PRODUCT.USER_API_ACTIVITY API
inner join prod_tenant_info on prod_tenant_info.data_cntr_cd = API.data_cntr_cd and prod_tenant_info.tenant_id = API.tenant_id
where request_url ilike '%/api/templateStudio/remapFile%'
and request_method_cd = 'POST'
-- need to be able to calculate error rates 
--and request_status_cd = '200'
and to_date(request_end_dts) >= '2025-02-01'

