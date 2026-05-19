{{ config(materialized='view') }}

with maxdate as
(
select 
id, 
max(last_updated_at) as maxdate
from PROD_RAW.PENDO.FEATURE_HISTORY
group by id
)

select 
history.id as feature_id,
page_id,
is_core_event,
history.name as feature_name,
to_date(last_updated_at) as update_date
from PROD_RAW.PENDO.FEATURE_HISTORY history
inner join maxdate on history.id = maxdate.id and history.last_updated_at = maxdate.maxdate
where current_date()>=to_date(valid_through)
